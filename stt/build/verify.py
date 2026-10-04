"""
The gates the Parakeet export must clear before anything is allowed to ship.

Build-time only. Nothing here reaches the runtime image. Every gate runs OUR
runtime code (app/features.py, decode.py, vad.py, server.py), so what is
verified is what the container will execute, not a stand-in.

  G0 — STRUCTURE. The three int8 models load; their input/output names and ranks
       match the fp32 export and the positional order app/decode.py relies on; a
       probe run proves the decoder state shape and that the joiner scores exactly
       vocab + blank + one logit per TDT duration.
  G1 — PARITY WITH NeMo on the fixture: encoder output (fp32 ONNX, fed by our
       log-mel) vs NeMo's own encoder at SNR >= 50 dB; our fp32 decode must give
       NeMo's transcribe() text word for word; the int8 trio within 5 % WER of it.
  G2 — REAL SPEECH. WER against LibriSpeech's own transcript of the clip, through
       server.transcribe() (VAD trim -> features -> decode): the int8 trio <= 15 %,
       and NeMo itself <= 10 % (which proves the reference text is the right one,
       so the first number means something). There is no fp32 fallback.
  G3 — SILENCE. Digital silence and low white noise must come back as
       no_speech with empty text through server.transcribe(); the first 3 s of
       the clip plus 1 s of silence must still give >= 5 words. Louder noise
       (about -35 dBFS) is reported, never failed.
  G4 — LATENCY. Informational only: int8 vs fp32 on a 10 s clip with a per-stage
       breakdown, and int8 on a 120 s clip with peak RSS.
  G5 — ARTEFACT. server.Parakeet loaded from --out exactly as the container
       loads /models must transcribe the fixture as G2 did.
  G6 — HTTP SURFACE. read_wav rejects every malformed input; the handler returns
       the right status for each request shape (stub model, loopback socket).

WER is word-level edit distance over lowercase words with punctuation removed.
"""
from __future__ import annotations

import http.client
import io
import json
import math
import re
import resource
import threading
import time
import wave
from http.server import ThreadingHTTPServer
from typing import TYPE_CHECKING

import numpy as np
import onnxruntime as ort

import server
from decode import Transducer, feed

if TYPE_CHECKING:
    import pathlib

    from features import LogMel
    from vad import Vad

SAMPLE_RATE = 16_000
# LibriSpeech test-clean 2086-149220-0033 (CC-BY-4.0, build-time only), LibriSpeech's own transcript.
FIXTURE_TRUTH = (
    "well i don't wish to see it any more observed phoebe turning away her eyes "
    "it is certainly very like the old portrait"
)
G1_MIN_SNR_DB = 50.0
G1_MAX_INT8_WER = 0.05
G2_MAX_ONNX_WER = 0.15
G2_MAX_NEMO_WER = 0.10
G3_CLIP_S = 2                 # length of the silence and noise clips
G3_HEAD_S = 3
G3_MAX_PREFIX_WER = 0.25
G3_MIN_HEAD_WORDS = 5
G3_NOISE_STD = 0.003          # about -50 dBFS
G3_LOUD_NOISE_STD = 0.018     # about -35 dBFS, informational
G4_RUNS = 3
G4_CLIP_S = 10
G6_TIMEOUT_S = 10
# (input ranks, output ranks) in the positional order app/decode.py feeds and reads.
EXPECTED_RANKS = {
    "encoder": ([3, 1], [3, 1]),                # features, length -> enc (1, D, T), enc length
    "decoder": ([2, 1, 3, 3], [3, 1, 3, 3]),    # token, length, h, c -> out, length, h, c
    "joiner": ([3, 3], [4]),                    # enc frame, decoder out -> logits
}


class GateFailed(Exception):
    """Raised when a verification gate rejects the export."""


# --- measurement helpers ----------------------------------------------------
def snr_db(ref: np.ndarray, test: np.ndarray) -> float:
    """10*log10(signal power / error power); +inf when identical."""
    err = float(np.sum((ref.astype(np.float64) - test.astype(np.float64)) ** 2))
    if err == 0.0:
        return math.inf
    return 10.0 * math.log10(float(np.sum(ref.astype(np.float64) ** 2)) / err)


def words(text: str) -> list[str]:
    """Lowercase words with punctuation removed, apostrophes kept."""
    return re.sub(r"[^a-z' ]+", " ", text.lower()).split()


def wer(hyp: list[str], ref: list[str]) -> float:
    """Word edit distance / reference length."""
    row = list(range(len(hyp) + 1))
    for i, r in enumerate(ref, 1):
        prev, row[0] = row[0], i
        for j, h in enumerate(hyp, 1):
            prev, row[j] = row[j], min(row[j] + 1, row[j - 1] + 1, prev + (r != h))
    return row[-1] / max(len(ref), 1)


def describe(session: ort.InferenceSession) -> dict:
    """Input and output [name, rank] pairs in positional order."""
    return {
        "inputs": [[i.name, len(i.shape)] for i in session.get_inputs()],
        "outputs": [[o.name, len(o.shape)] for o in session.get_outputs()],
    }


# --- G0 ---------------------------------------------------------------------
def gate_g0_structure(paths: dict, cfg: dict, vocab: list[str]) -> Transducer:
    """-> the int8 candidates as a Transducer, once their io and probe shapes check out."""
    print("[gate G0] structure of the encoder / decoder / joiner candidates")
    try:
        asr = Transducer(paths, cfg, vocab)
    except Exception as exc:
        raise GateFailed(f"gate G0 (structure): onnxruntime cannot load the candidates: {exc}")
    failures = []
    for part, session in zip(EXPECTED_RANKS, (asr.encoder, asr.decoder, asr.joiner)):
        got = describe(session)
        ranks = ([r for _, r in got["inputs"]], [r for _, r in got["outputs"]])
        print(f"[gate G0] {part}: inputs={got['inputs']} outputs={got['outputs']}")
        if got != cfg["io"][part]:
            failures.append(f"{part}: io {got} differs from the fp32 export {cfg['io'][part]}")
        if ranks != EXPECTED_RANKS[part]:
            failures.append(f"{part}: ranks {ranks}, app/decode.py expects {EXPECTED_RANKS[part]}")
    if failures:
        raise GateFailed("gate G0 (structure): " + "; ".join(failures))

    dec, h, c = asr._predict(asr.blank, asr.zero_state, asr.zero_state)
    enc_frame = np.zeros((1, cfg["enc_dim"], 1), dtype=np.float32)
    logits = asr.joiner.run(None, feed(asr.joiner, enc_frame, dec))[0]
    expected = len(vocab) + 1 + len(cfg["durations"])
    print(f"[gate G0] decoder state {h.shape}, joiner logits {logits.shape[-1]} "
          f"(vocab {len(vocab)} + blank + {len(cfg['durations'])} durations = {expected})")
    if h.shape != asr.zero_state.shape or c.shape != asr.zero_state.shape:
        failures.append(f"decoder state {h.shape}/{c.shape}, config says {asr.zero_state.shape}")
    if logits.shape[-1] != expected:
        failures.append(f"joiner emits {logits.shape[-1]} logits, expected {expected}")
    if failures:
        raise GateFailed("gate G0 (structure): " + "; ".join(failures))
    return asr


# --- G1 ---------------------------------------------------------------------
def gate_g1_parity(ref: dict, fp32: Transducer, int8: Transducer, mel: LogMel, audio: np.ndarray) -> None:
    """Our features and fp32 encoder against NeMo's; fp32 text identical, int8 within G1_MAX_INT8_WER."""
    print("[gate G1] parity with NeMo on the fixture (our log-mel and decode)")
    failures = []
    feats, n = mel(audio)
    if feats[:, :, :n].shape != ref["features"].shape:
        raise GateFailed(f"gate G1 (parity): features {feats[:, :, :n].shape} vs NeMo {ref['features'].shape}")
    print(f"[gate G1] log-mel {ref['features'].shape}: SNR={snr_db(ref['features'], feats[:, :, :n]):.1f} dB (info)")

    enc = fp32.encode(feats, n)
    if enc.shape != ref["encoder"].shape:
        failures.append(f"encoder shape onnx={enc.shape} nemo={ref['encoder'].shape}")
    else:
        snr = snr_db(ref["encoder"], enc)
        print(f"[gate G1] fp32 encoder {enc.shape}: SNR={snr:.1f} dB (need >= {G1_MIN_SNR_DB}) "
              f"max|diff|={float(np.max(np.abs(ref['encoder'] - enc))):.2e}")
        if snr < G1_MIN_SNR_DB:
            failures.append(f"encoder SNR={snr:.1f} dB (need >= {G1_MIN_SNR_DB})")

    nemo = words(ref["text"])
    text32 = fp32.decode(feats, n)
    print(f"[gate G1] nemo: {ref['text']!r}")
    print(f"[gate G1] fp32: {text32!r} identical={words(text32) == nemo}")
    if words(text32) != nemo:
        failures.append("fp32 ONNX transcript differs from NeMo's")
    text8 = int8.decode(feats, n)
    w = wer(words(text8), nemo)
    print(f"[gate G1] int8: {text8!r} WER vs NeMo {w:.1%} (need <= {G1_MAX_INT8_WER:.0%})")
    if w > G1_MAX_INT8_WER:
        failures.append(f"int8 WER vs NeMo {w:.1%} > {G1_MAX_INT8_WER:.0%}")
    if failures:
        raise GateFailed("gate G1 (parity): " + "; ".join(failures))


# --- G2 ---------------------------------------------------------------------
def gate_g2_wer(vad: Vad, mel: LogMel, asr: Transducer, audio: np.ndarray, nemo_text: str) -> str:
    """-> the int8 transcript of the full fixture through server.transcribe()."""
    print("[gate G2] real-speech WER against LibriSpeech's transcript (int8, through server.transcribe)")
    truth = words(FIXTURE_TRUTH)
    w_nemo = wer(words(nemo_text), truth)
    result = server.transcribe(audio, vad, mel, asr)
    w = wer(words(result["text"]), truth)
    print(f"[gate G2] int8: {result}")
    print(f"[gate G2] nemo WER {w_nemo:.1%} (need <= {G2_MAX_NEMO_WER:.0%}) | "
          f"int8 WER {w:.1%} (need <= {G2_MAX_ONNX_WER:.0%})")
    failures = []
    if w_nemo > G2_MAX_NEMO_WER:
        failures.append(f"NeMo WER {w_nemo:.1%}: the fixture or its reference text is wrong")
    if result["no_speech"] or w > G2_MAX_ONNX_WER:
        failures.append(f"int8 WER {w:.1%} > {G2_MAX_ONNX_WER:.0%}: int8 missed the accuracy bar; shipping "
                        "fp32 (~2.4 GB encoder) needs a deliberate decision and a higher mem_limit in compose.yaml")
    if failures:
        raise GateFailed("gate G2 (WER): " + "; ".join(failures))
    return result["text"]


# --- G3 ---------------------------------------------------------------------
def gate_g3_silence(vad: Vad, mel: LogMel, asr: Transducer, audio: np.ndarray) -> None:
    """Silence and quiet noise give no_speech; a short utterance before silence still gives text."""
    print("[gate G3] silence and noise -> no speech; short utterance + trailing silence -> text")
    failures = []
    quiet = {
        "silence": np.zeros(G3_CLIP_S * SAMPLE_RATE, dtype=np.float32),
        "noise": np.random.default_rng(0).normal(0.0, G3_NOISE_STD, G3_CLIP_S * SAMPLE_RATE).astype(np.float32),
    }
    for label, clip in quiet.items():
        found = vad.speech(clip) is not None
        result = server.transcribe(clip, vad, mel, asr)
        print(f"[gate G3] {label:>7} 2 s: vad speech={found} -> {result}")
        if found or not result["no_speech"] or result["text"]:
            failures.append(f"{label}: expected no_speech with empty text, got {result}")

    loud = np.random.default_rng(1).normal(0.0, G3_LOUD_NOISE_STD, G3_CLIP_S * SAMPLE_RATE).astype(np.float32)
    result = server.transcribe(loud, vad, mel, asr)
    print(f"[gate G3] loud-noise 2 s (~-35 dBFS): vad speech={vad.speech(loud) is not None} -> {result} (info)")

    head = np.concatenate([audio[: G3_HEAD_S * SAMPLE_RATE], np.zeros(SAMPLE_RATE, dtype=np.float32)])
    result = server.transcribe(head, vad, mel, asr)
    got = words(result["text"])
    w = wer(got, words(FIXTURE_TRUTH)[: len(got)]) if got else 1.0
    print(f"[gate G3] first {G3_HEAD_S} s + 1 s silence -> {result} {len(got)} words "
          f"(need >= {G3_MIN_HEAD_WORDS}), WER vs truth prefix {w:.1%} (need <= {G3_MAX_PREFIX_WER:.0%})")
    if result["no_speech"] or len(got) < G3_MIN_HEAD_WORDS or w > G3_MAX_PREFIX_WER:
        failures.append(f"short utterance: {result}, {len(got)} words, prefix WER {w:.1%}")
    if failures:
        raise GateFailed("gate G3 (silence): " + "; ".join(failures))


# --- G4 ---------------------------------------------------------------------
def _stage_times(vad: Vad, mel: LogMel, asr: Transducer, clip: np.ndarray) -> dict:
    marks = [time.perf_counter()]
    speech = vad.speech(clip)
    marks.append(time.perf_counter())
    feats, n = mel(clip if speech is None else speech)
    marks.append(time.perf_counter())
    enc = asr.encode(feats, n)
    marks.append(time.perf_counter())
    asr.greedy(enc)
    marks.append(time.perf_counter())
    return dict(zip(("vad", "mel", "encoder", "decode"), np.diff(marks)))


def gate_g4_latency(vad: Vad, mel: LogMel, trios: dict[str, Transducer], audio: np.ndarray) -> None:
    """Never fails: the build host is not the container, so this is a hint only."""
    clip = np.resize(audio, G4_CLIP_S * SAMPLE_RATE)        # fixture repeated/cropped to 10 s
    for label, asr in trios.items():
        _stage_times(vad, mel, asr, clip)             # warm-up, same shape as the timed runs
        runs = sorted((_stage_times(vad, mel, asr, clip) for _ in range(G4_RUNS)), key=lambda r: sum(r.values()))
        mid = runs[len(runs) // 2]
        total = sum(mid.values())
        stages = " ".join(f"{k} {v:.2f}s" for k, v in mid.items())
        print(f"[gate G4] {label} 10 s clip, median of {G4_RUNS}: {total:.2f} s (RTF {total / G4_CLIP_S:.2f}) "
              f"= {stages} (info)")
    long = np.resize(audio, server.MAX_SECONDS * SAMPLE_RATE)
    start = time.perf_counter()
    server.transcribe(long, vad, mel, trios["int8"])
    took = time.perf_counter() - start
    peak_mb = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 1024     # Linux: kilobytes
    print(f"[gate G4] int8 {server.MAX_SECONDS} s clip: {took:.2f} s (RTF {took / server.MAX_SECONDS:.2f}); "
          f"peak RSS {peak_mb:.0f} MB, lifetime of this build process incl. the NeMo restore, "
          f"so an upper bound vs the 2500 MB limit (info)")


# --- G5 ---------------------------------------------------------------------
def gate_g5_artefact(model_dir: pathlib.Path, audio: np.ndarray, full_text: str) -> None:
    """server.Parakeet loaded from `model_dir` must reproduce G2's transcript of the fixture."""
    print(f"[gate G5] the shipped artefact: server.Parakeet loaded from {model_dir}")
    try:
        stt = server.Parakeet(model_dir)
    except Exception as exc:
        raise GateFailed(f"gate G5 (artefact): server.Parakeet cannot load {model_dir}: {exc}")
    result = stt.transcribe(audio)
    w = wer(words(result["text"]), words(FIXTURE_TRUTH))
    same = words(result["text"]) == words(full_text)
    print(f"[gate G5] {result} WER {w:.1%} (need <= {G2_MAX_ONNX_WER:.0%}), same words as G2={same}")
    failures = []
    if result["no_speech"]:
        failures.append("no_speech on the fixture")
    if w > G2_MAX_ONNX_WER:
        failures.append(f"WER {w:.1%} > {G2_MAX_ONNX_WER:.0%}")
    if not same:
        failures.append(f"transcript differs from G2's {full_text!r}")
    if failures:
        raise GateFailed("gate G5 (artefact): " + "; ".join(failures))


# --- G6 ---------------------------------------------------------------------
def _wav(seconds: float, rate: int = SAMPLE_RATE, channels: int = 1, width: int = 2) -> bytes:
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(channels)
        w.setsampwidth(width)
        w.setframerate(rate)
        w.writeframes(bytes(int(seconds * rate) * channels * width))
    return buf.getvalue()


class _StubModel:
    def transcribe(self, audio: np.ndarray) -> dict:
        return {"text": "stub", "duration_s": 1.0, "no_speech": False}


def gate_g6_http() -> None:
    """read_wav rejects malformed input; the handler returns the right status per request shape."""
    print("[gate G6] read_wav rejections and HTTP status codes (stub model)")
    failures = []
    bad = {
        "44.1 kHz": _wav(1, rate=44_100), "stereo": _wav(1, channels=2), "8-bit": _wav(1, width=1),
        "garbage": b"not a wav file at all", "empty": b"",
        f"{server.MAX_SECONDS + 1} s": _wav(server.MAX_SECONDS + 1),
    }
    for label, body in bad.items():
        try:
            server.read_wav(body)
            failures.append(f"read_wav accepted {label}")
        except ValueError as exc:
            print(f"[gate G6] read_wav {label}: rejected ({exc})")
    good = _wav(1)
    if len(server.read_wav(good)) != SAMPLE_RATE:
        failures.append("read_wav did not return 1 s of samples for a valid 1 s file")

    saved = server.Handler.stt
    server.Handler.stt = _StubModel()
    httpd = ThreadingHTTPServer(("127.0.0.1", 0), server.Handler)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    cases = [
        ("GET /health", "GET", "/health", None, {}, 200, {"ok": True}),
        ("GET /nope", "GET", "/nope", None, {}, 404, None),
        ("valid WAV", "POST", "/transcribe", good, {"Content-Type": "audio/wav"}, 200,
         _StubModel().transcribe(None)),
        ("text/plain", "POST", "/transcribe", good, {"Content-Type": "text/plain"}, 415, None),
        ("oversize Content-Length", "POST", "/transcribe", None,
         {"Content-Type": "audio/wav", "Content-Length": str(server.MAX_BODY + 1)}, 413, None),
        ("garbage body", "POST", "/transcribe", b"garbage!", {"Content-Type": "audio/wav"}, 400, None),
        ("no Content-Length", "POST", "/transcribe", None, {"Content-Type": "audio/wav"}, 400, None),
        ("Host: evil.example", "GET", "/health", None, {"Host": "evil.example"}, 403, None),
    ]
    try:
        for label, method, path, body, headers, want_status, want_json in cases:
            conn = http.client.HTTPConnection("127.0.0.1", httpd.server_address[1], timeout=G6_TIMEOUT_S)
            try:
                # putrequest, not request(): request() would add a Content-Length the cases must control
                conn.putrequest(method, path, skip_host="Host" in headers, skip_accept_encoding=True)
                for name, value in headers.items():
                    conn.putheader(name, value)
                if body is not None:
                    conn.putheader("Content-Length", str(len(body)))
                conn.endheaders(body)
                resp = conn.getresponse()
                got = json.loads(resp.read() or b"null")
            finally:
                conn.close()
            ok = resp.status == want_status and (want_json is None or got == want_json)
            print(f"[gate G6] {label}: {resp.status} {got} (want {want_status})")
            if not ok:
                failures.append(f"{label}: got {resp.status} {got}, want {want_status} {want_json or ''}")
    finally:
        httpd.shutdown()
        httpd.server_close()
        server.Handler.stt = saved
    if failures:
        raise GateFailed("gate G6 (HTTP surface): " + "; ".join(failures))
