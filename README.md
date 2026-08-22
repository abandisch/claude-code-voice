# claude-code-voice — Claude Code talks back

Give Claude Code a voice. Every response ends with a one-line spoken summary
(marked `🔊`); a Stop hook sends that line to a local neural text-to-speech
server and plays it, so you hear what Claude did without reading the
terminal — handy when you're across the room, mid-build, or just prefer to
listen.

```
🔊 Build is green, the hook is installed, and the voice is yours to choose.
```

The voice is [Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M) (open
weights, Apache-2.0), running entirely on your Mac in a hardened Docker
container on `127.0.0.1`. No cloud, no API keys, nothing leaves the machine.
If the container is down, the hook falls back to macOS `say`, so it never
goes silent.

## Quick start

Requires macOS on Apple Silicon, Docker Desktop, and a (free) Docker ID for
the hardened base image.

```sh
docker login dhi.io    # once
make build             # 5-10 min first time: downloads weights, converts, verifies
make run               # container "kokoro" on 127.0.0.1:8880
make test              # speaks a test sentence
```

Then install the hook — [SETUP.md](SETUP.md) walks through it (and is written
so a Claude Code session can do most of it for you).

## Configure

- **Voice / speed:** `VOICE=` and `SPEED=` at the top of the hook
  (`hook/speak-kokoro.sh`). Baked in: `bm_lewis` (British male, default) and
  `bf_emma` (British female). Any other Kokoro voice: add it to `VOICES` in the
  Dockerfile and `make build`.
- **Port:** `PORT=8881 make run`, and update `URL=` in the hook.
- **Stop / logs:** `make stop`, `make logs`.

## API

```
GET  /health   -> {"ok": true}
GET  /voices   -> ["bf_emma", "bm_lewis"]
POST /speak    -> audio/wav   body: {"text": "...", "voice": "bm_lewis", "speed": 1.0}
```

## How it's built, and why you can trust it

Every ingredient comes from a source you can name — Docker Hardened Images,
Microsoft's onnxruntime, numpy, Debian's espeak-ng, hexgrad's weights — and
the only individually-authored code is ~170 lines of Python in `app/`. The
model is converted to ONNX by this repo's own build, which refuses to produce
an image unless the conversion is verified against the original PyTorch model.
The container runs read-only, non-root, with all capabilities dropped.

Details, including the verification gates and the pinning procedure:
[docs/DESIGN.md](docs/DESIGN.md). Project history and decisions: [`wiki/`](wiki/index.md).

## Licence

Kokoro-82M weights are Apache-2.0 (hexgrad). Everything in this repo: MIT.
