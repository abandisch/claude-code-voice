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
make install           # installs the Claude Code hook + settings + 🔊 rule (idempotent)
```

Start a new Claude Code session, ask it anything, and listen. `make install`
puts two hooks in `~/.claude/hooks/` — the 🔊 speaker, and a notifier that
announces when Claude is waiting on your permission or input, so you can
wander off during long tasks — registers them in `~/.claude/settings.json`
(backing the file up first) and adds the 🔊 rule to your global
`~/.claude/CLAUDE.md` — see [`hook/CLAUDE-snippet.md`](hook/CLAUDE-snippet.md)
for exactly what it adds. Details and troubleshooting: [SETUP.md](SETUP.md).

**Prefer to let Claude drive?** Open Claude Code in this folder and say
*"set this up"*. It reads `CLAUDE.md`, runs what it can, and hands you the
few commands that need your terminal (Docker login, build, install).

## Configure

- **Voice / speed:** `VOICE=` and `SPEED=` at the top of each hook
  (`hook/speak-kokoro.sh`, `hook/notify-kokoro.sh`). Baked in: `bf_emma` (British female, default),
  `bm_fable`, `bm_daniel`, `am_adam`, `am_liam`, `am_fenrir`. Any other Kokoro
  voice: add it to `VOICES` in the Dockerfile and `make build`.
- **Port:** `PORT=8881 make run`, and update `URL=` in the hook.
- **Stop / logs:** `make stop`, `make logs`.
- **Say anything:** `make say TEXT="Good evening" VOICE=bm_fable SPEED=1.2` —
  handy for auditioning voices or startling the cat.
- **Meetings:** `make mute` silences both hooks; `make unmute` restores the
  voice (and says so).
- **Persona:** the voice reads whatever Claude writes — give it a character
  with a one-paragraph rule in your global CLAUDE.md. Ready-made: butler,
  ship's computer, laconic sysadmin, noir detective in
  [`hook/personas/`](hook/personas/README.md).

## API

```
GET  /health   -> {"ok": true}
GET  /voices   -> ["am_adam", "am_fenrir", "am_liam", "bf_emma", "bm_daniel", "bm_fable"]
POST /speak    -> audio/wav   body: {"text": "...", "voice": "bf_emma", "speed": 1.0}
```

## How it's built, and why you can trust it

Every ingredient comes from a source you can name — Docker Hardened Images,
Microsoft's onnxruntime, numpy, Debian's espeak-ng, hexgrad's weights — and
the only individually-authored code is ~170 lines of Python in `app/`. The
model is converted to ONNX by this repo's own build, which refuses to produce
an image unless the conversion is verified against the original PyTorch model.
The container runs read-only, non-root, with all capabilities dropped.

Details, including the verification gates and the pinning procedure:
[docs/DESIGN.md](docs/DESIGN.md).

## Licence

Kokoro-82M weights are Apache-2.0 (hexgrad). Everything in this repo: MIT.

---

Built with [Claude Code](https://claude.com/claude-code) (Claude Fable 5) in
conversation with the maintainer — Claude wrote the code and the docs; the
maintainer set the requirements, ran the commands, and listened
to fifteen voices so you don't have to.
