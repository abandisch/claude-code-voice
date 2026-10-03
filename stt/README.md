# Parakeet STT (local speech-to-text)

A sibling of the Kokoro container: NVIDIA's Parakeet TDT 0.6B v2, converted to ONNX
and int8-quantised by us at build time, served from a hardened non-root container on
`127.0.0.1:8881`. It receives a WAV over loopback and returns text; it never touches
a microphone, and audio never leaves the machine.

## Before the first build

- Docker Desktop, logged in with `docker login dhi.io` (as in the root README).
- Docker memory of at least 8 GB (Settings → Resources) for the NeMo export, and
  several GB of free build cache.
- The build downloads ~2.4 GB of weights from Hugging Face and takes 15–30 min the
  first time. Build args (e.g. `--build-arg PY_RUN=…`) go through
  `make build-stt STT_BUILD_ARGS="--build-arg NAME=value"`.

## Run and test

`make build-stt`, then `make run-stt`. The port opens only once the model has loaded:
watch `make logs-stt` for the `parakeet ready:` line. `make test-stt` (needs Kokoro
running: it speaks the test sentence) asserts the transcript and prints the latency.
Also `make stop-stt`, `make clean-stt`, `make lock-stt` (hash-pin the runtime packages).

## Endpoints

- `GET /health` → `{"ok": true}`
- `POST /transcribe` — body: WAV, 16 kHz mono 16-bit PCM, ≤ 10 MB and ≤ 120 s →
  `{"text": "...", "duration_s": 3.2, "no_speech": false}`

Any recording works once converted with stock macOS `afconvert`:

```sh
afconvert -f WAVE -d LEI16@16000 -c 1 in.m4a clip.wav
curl -s --data-binary @clip.wav -H 'Content-Type: audio/wav' http://127.0.0.1:8881/transcribe
```

## Every ingredient

- Docker Hardened Image `dhi.io/python:3.12-debian13` (+ libstdc++ from Debian)
- Microsoft onnxruntime and NumPy from PyPI (hash-pinned after `make lock-stt`)
- Parakeet TDT 0.6B v2 weights, exported by `stt/build/export_onnx.py` and gated by
  `stt/build/verify.py`; int8 only, the build fails if int8 misses the accuracy bar.
  Pinned by Hugging Face commit and by the checkpoint's sha256 (`PARAKEET_REVISION`,
  `PARAKEET_SHA256` in `stt/Dockerfile`); the hash is checked before the file is loaded.
- Silero VAD ONNX, pinned by tag and sha256
- ~290 lines of our own Python (`stt/app/`)

**Pinned inputs.** Silero VAD and the test clip are pinned by sha256, recorded on first
use from the official URLs. To move to a new Silero tag: download it, verify it against
a second source, then update `SILERO_TAG` and `SILERO_SHA256` in `stt/Dockerfile`.

## Attribution

- **NVIDIA Parakeet TDT 0.6B v2** — CC-BY-4.0 — https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2
- **Silero VAD** — MIT — https://github.com/snakers4/silero-vad
- **Export recipe** adapted from sherpa-onnx — Apache-2.0 — https://github.com/k2-fsa/sherpa-onnx/tree/master/scripts/nemo/parakeet-tdt-0.6b-v2
- **LibriSpeech** (Panayotov et al., OpenSLR 12) — CC-BY-4.0 — https://www.openslr.org/12 —
  one clip used as a build-time test fixture only; not shipped in the image
