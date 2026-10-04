"""
Minimal HTTP front-end for the Kokoro ONNX model. Standard library only.

  GET  /health          -> {"ok": true}
  GET  /voices          -> ["bf_emma", ...]
  POST /speak           -> audio/wav (24 kHz, 16-bit mono)
       body: {"text": "...", "voice": "bf_emma", "speed": 1.0}
"""
from __future__ import annotations

import io
import json
import os
import pathlib
import threading
import wave
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import numpy as np
import onnxruntime as ort

from phonemize import phonemize

MODEL_DIR = pathlib.Path(os.environ.get("KOKORO_MODEL_DIR", "/models"))
DEFAULT_VOICE = os.environ.get("KOKORO_DEFAULT_VOICE", "bf_emma")
PORT = int(os.environ.get("PORT", "8880"))
SAMPLE_RATE = 24_000
# Leading silence so a playback device waking from idle (Bluetooth especially)
# does not clip or distort the first word.
LEAD_SILENCE_MS = int(os.environ.get("KOKORO_LEAD_SILENCE_MS", "300"))
MAX_TOKENS = 510        # model context limit
MAX_TEXT = 2_000        # refuse anything longer; this is a sentence-at-a-time service
MAX_BODY = 64_000       # bytes
MIN_SPEED, MAX_SPEED = 0.5, 2.0     # keep in step with the /speak error message
PCM_SCALE = 32767       # float -> int16 multiplies by 32767 so +1.0 fits; the STT side divides by 32768


class Kokoro:
    """The Kokoro ONNX session, its vocabulary and voice packs; one inference at a time."""

    def __init__(self) -> None:
        opts = ort.SessionOptions()
        opts.intra_op_num_threads = int(os.environ.get("OMP_NUM_THREADS", "4"))
        self.session = ort.InferenceSession(
            str(MODEL_DIR / "kokoro.onnx"), opts, providers=["CPUExecutionProvider"]
        )
        self.vocab = json.loads((MODEL_DIR / "vocab.json").read_text(encoding="utf-8"))
        self.voices = {p.stem: np.load(p) for p in sorted((MODEL_DIR / "voices").glob("*.npy"))}
        self.lock = threading.Lock()      # one inference at a time

    def synthesize(self, text: str, voice: str, speed: float) -> np.ndarray:
        """Float audio in [-1, 1] at SAMPLE_RATE; ValueError if the text yields no phonemes."""
        pack = self.voices[voice]
        lang = "en-gb" if voice.startswith("b") else "en-us"
        phonemes = phonemize(text, lang)
        ids = [self.vocab[c] for c in phonemes if c in self.vocab][:MAX_TOKENS]
        if not ids:
            raise ValueError("text produced no phonemes")
        feeds = {
            "input_ids": np.array([[0, *ids, 0]], dtype=np.int64),
            "style": pack[len(ids) - 1].astype(np.float32),
            "speed": np.array([speed], dtype=np.float32),
        }
        with self.lock:
            return self.session.run(None, feeds)[0]


def to_wav(audio: np.ndarray) -> bytes:
    """Float audio -> 16-bit mono WAV bytes, led by LEAD_SILENCE_MS of silence."""
    pcm = (np.clip(audio, -1.0, 1.0) * PCM_SCALE).astype("<i2")
    lead = np.zeros(SAMPLE_RATE * LEAD_SILENCE_MS // 1000, dtype="<i2")
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SAMPLE_RATE)
        w.writeframes(lead.tobytes() + pcm.tobytes())
    return buf.getvalue()


class Handler(BaseHTTPRequestHandler):
    """The HTTP routes in the module docstring."""

    tts: Kokoro | None = None  # set in main()

    def _send(self, status: int, body: bytes, ctype: str = "application/json") -> None:
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _json(self, status: int, obj: object) -> None:
        self._send(status, json.dumps(obj).encode())

    def do_GET(self) -> None:
        """Serve /health and /voices."""
        if self.path == "/health":
            return self._json(200, {"ok": True})
        if self.path == "/voices":
            return self._json(200, sorted(self.tts.voices))
        self._json(404, {"error": "not found"})

    def do_POST(self) -> None:
        """Serve /speak: JSON request in, WAV out; a traceback never reaches the client."""
        if self.path != "/speak":
            return self._json(404, {"error": "not found"})
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if length > MAX_BODY:
                return self._json(413, {"error": "request too large"})
            req = json.loads(self.rfile.read(length) or b"{}")
            text = str(req.get("text", "")).strip()
            voice = str(req.get("voice", DEFAULT_VOICE))
            speed = float(req.get("speed", 1.0))
            if not text or len(text) > MAX_TEXT:
                return self._json(400, {"error": f"text must be 1..{MAX_TEXT} characters"})
            if voice not in self.tts.voices:
                return self._json(400, {"error": f"unknown voice; see /voices"})
            if not MIN_SPEED <= speed <= MAX_SPEED:
                return self._json(400, {"error": "speed must be between 0.5 and 2.0"})
            audio = self.tts.synthesize(text, voice, speed)
            self._send(200, to_wav(audio), "audio/wav")
        except Exception as e:  # never leak a traceback to the client
            self.log_error("speak failed: %s", e)
            self._json(500, {"error": "synthesis failed"})

    def log_message(self, fmt: str, *args: object) -> None:  # quieter access log
        print(f"{self.address_string()} {fmt % args}", flush=True)


def main() -> None:
    """Load the model, then serve on 0.0.0.0:PORT until killed."""
    Handler.tts = Kokoro()
    print(f"kokoro ready: voices={sorted(Handler.tts.voices)} port={PORT}", flush=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
