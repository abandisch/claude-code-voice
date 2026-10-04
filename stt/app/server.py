"""
Minimal HTTP front-end for the Parakeet speech-to-text model. Standard library only.

  GET  /health          -> {"ok": true}
  POST /transcribe      -> {"text": "...", "duration_s": 3.2, "no_speech": false}
       body: WAV, 16 kHz mono 16-bit PCM, <= 10 MB and <= 120 s
       (Content-Type audio/wav or application/octet-stream)
"""
from __future__ import annotations

import io
import json
import os
import pathlib
import threading
import time
import urllib.parse
import wave
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import numpy as np

from decode import Transducer
from features import LogMel
from vad import SAMPLE_RATE, Vad

MODEL_DIR = pathlib.Path(os.environ.get("STT_MODEL_DIR", "/models"))
PORT = int(os.environ.get("STT_PORT", "8881"))
MAX_BODY = 10_000_000
MAX_SECONDS = 120
# Doubles as the CORS defence: neither type is safelisted, so browsers preflight; no OPTIONS handler.
CONTENT_TYPES = {"audio/wav", "application/octet-stream"}
HOSTS = {"127.0.0.1", "localhost"}      # hostname only: the published host port is configurable
PCM_SCALE = 32768.0     # int16 -> float divides by 32768 so -32768 maps to -1.0; the TTS side multiplies by 32767


def read_wav(body: bytes) -> np.ndarray:
    """16 kHz mono 16-bit PCM WAV -> float32 in [-1, 1]; ValueError with a one-line reason."""
    try:
        with wave.open(io.BytesIO(body), "rb") as w:
            p = w.getparams()
            if (p.framerate, p.nchannels, p.sampwidth) != (SAMPLE_RATE, 1, 2):
                raise ValueError("audio must be 16 kHz, mono, 16-bit PCM")
            if p.nframes / SAMPLE_RATE > MAX_SECONDS:
                raise ValueError(f"audio longer than {MAX_SECONDS} s")
            pcm = w.readframes(p.nframes)
    except (wave.Error, EOFError):
        raise ValueError("body is not a PCM WAV file") from None
    return np.frombuffer(pcm, dtype="<i2").astype(np.float32) / PCM_SCALE


def transcribe(audio: np.ndarray, vad: Vad, mel: LogMel, asr: Transducer) -> dict:
    """VAD trim -> features -> decode; no_speech with empty text when there is no speech to decode."""
    duration = round(len(audio) / SAMPLE_RATE, 3)
    speech = vad.speech(audio)
    try:
        features = None if speech is None else mel(speech)
    except ValueError:                  # under two feature frames; the VAD's padding normally prevents it
        features = None
    if features is None:
        return {"text": "", "duration_s": duration, "no_speech": True}
    return {"text": asr.decode(*features), "duration_s": duration, "no_speech": False}


class Parakeet:
    """The models in `model_dir`, loaded as config.json describes; one inference at a time."""

    def __init__(self, model_dir: pathlib.Path = MODEL_DIR) -> None:
        cfg = json.loads((model_dir / "config.json").read_text(encoding="utf-8"))
        vocab = (model_dir / "vocab.txt").read_text(encoding="utf-8").split("\n")[: cfg["vocab_size"]]
        self.files = {k: model_dir / name for k, name in cfg["files"].items()}
        self.mel = LogMel(cfg, np.load(model_dir / "mel_basis.npy"), np.load(model_dir / "window.npy"))
        self.asr = Transducer(self.files, cfg, vocab, int(os.environ.get("OMP_NUM_THREADS", "4")))
        self.vad = Vad(model_dir / "silero_vad.onnx")
        self.lock = threading.Lock()      # one inference at a time

    def transcribe(self, audio: np.ndarray) -> dict:
        """Serialised by the lock: the models run one inference at a time."""
        with self.lock:
            return transcribe(audio, self.vad, self.mel, self.asr)


class Handler(BaseHTTPRequestHandler):
    """The HTTP routes in the module docstring, loopback Host names only."""

    stt: Parakeet | None = None  # set in main()
    timeout = 15          # seconds; a stalled client cannot hold a thread

    def _send(self, status: int, body: bytes, ctype: str = "application/json") -> None:
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _json(self, status: int, obj: object) -> None:
        self._send(status, json.dumps(obj).encode())

    def _host_ok(self) -> bool:
        """DNS-rebinding defence: only loopback names in the Host header."""
        try:
            return urllib.parse.urlsplit("//" + self.headers.get("Host", "")).hostname in HOSTS
        except ValueError:
            return False

    def do_GET(self) -> None:
        """Serve /health."""
        if not self._host_ok():
            return self._json(403, {"error": "forbidden"})
        if self.path == "/health":
            return self._json(200, {"ok": True})
        self._json(404, {"error": "not found"})

    def do_POST(self) -> None:
        """Serve /transcribe: WAV in, JSON out; a traceback never reaches the client."""
        if not self._host_ok():
            return self._json(403, {"error": "forbidden"})
        if self.path != "/transcribe":
            return self._json(404, {"error": "not found"})
        try:
            if self.headers.get_content_type() not in CONTENT_TYPES:
                return self._json(415, {"error": "send audio/wav or application/octet-stream"})
            try:
                length = int(self.headers["Content-Length"])
            except (TypeError, ValueError):
                length = 0
            if length <= 0:
                return self._json(400, {"error": "Content-Length required"})
            if length > MAX_BODY:
                return self._json(413, {"error": "request too large"})
            body = self.rfile.read(length)
            if len(body) != length:
                return self._json(400, {"error": "incomplete body"})
            try:
                audio = read_wav(body)
            except ValueError as e:
                return self._json(400, {"error": str(e)})
            self._json(200, self.stt.transcribe(audio))
        except Exception as e:  # never leak a traceback to the client
            self.log_error("transcribe failed: %s", e)
            self._json(500, {"error": "transcription failed"})

    def log_message(self, fmt: str, *args: object) -> None:  # quieter access log
        print(f"{self.address_string()} {fmt % args}", flush=True)


def main() -> None:
    """Load and warm up the models, then serve on 0.0.0.0:PORT until killed."""
    start = time.monotonic()
    Handler.stt = Parakeet()
    Handler.stt.asr.decode(*Handler.stt.mel(np.zeros(SAMPLE_RATE, dtype=np.float32)))   # warm-up
    names = sorted(p.name for p in Handler.stt.files.values())
    print(f"parakeet ready: models={names} load={time.monotonic() - start:.1f}s port={PORT}", flush=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
