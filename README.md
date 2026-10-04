# Pardon — Claude Code talks back, and listens

Give Claude Code a voice. Every response ends with a one-line spoken summary
(marked `🔊`); a Stop hook sends that line to a local neural text-to-speech
server and plays it, so you hear what Claude did without reading the
terminal — handy when you're across the room, mid-build, or just prefer to
listen. This speech half installs on its own (Quick start below), without
building the Pardon app.

```
🔊 Build is green, the hook is installed, and the voice is yours to choose.
```

The voice is [Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M) (open
weights, Apache-2.0), running entirely on your Mac in a hardened Docker
container on `127.0.0.1`. No cloud, no API keys, nothing leaves the machine.
If the container is down, the hook falls back to macOS `say`, so it never
goes silent.

It works the other way too: an optional second container runs NVIDIA's
Parakeet speech-to-text, and the Pardon app, a small menu bar app, lets you hold the
right Option key (or the small floating pet), speak and let go; the transcript is
pasted into whatever window has focus. Also entirely local: audio never leaves
the Mac.

Pardon is the name of the whole project: local text-to-speech for Claude Code
(Kokoro), local speech-to-text (Parakeet), and the Pardon menu bar app that ties
them together.

Formerly called claude-code-voice. Existing clones keep working through GitHub's
redirect; to point yours at the new name (optional):

```sh
git remote set-url origin git@github.com:abandisch/pardon.git     # SSH
git remote set-url origin https://github.com/abandisch/pardon.git # https
```

If containers from the old name exist, remove them and their network once;
otherwise `docker compose up -d` clashes with their fixed names (`make run`
replaces them itself but leaves the old network behind):

```sh
docker compose -p claude-code-voice down
```

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

## Talk to it (optional)

Needs Docker memory of at least 8 GB (Docker Desktop → Settings → Resources)
and Xcode Command Line Tools (`xcode-select --install`).

```sh
make build-stt         # 15-30 min first time: ~2.4 GB of weights, export, verification gates
make run-stt           # container "parakeet" on 127.0.0.1:8881
make test-stt          # needs Kokoro running too (make run): it speaks the sentence Parakeet transcribes
make ptt-cert          # optional, once: signing identity so rebuilds keep their permissions
make ptt               # builds the Pardon app into ~/Applications and starts it
```

Grant Microphone and Accessibility when macOS asks, then hold right Option,
speak, release. Details: [`stt/README.md`](stt/README.md) (the container and
its API) and [`ptt/README.md`](ptt/README.md) (the Pardon app: settings, permissions,
the signing identity, troubleshooting).

Both containers are defined in [`compose.yaml`](compose.yaml):
`docker compose up -d` starts them together, and Docker Desktop shows them as
one `pardon` group (the compose project name).

## Configure

- **Voice / speed:** `VOICE=` and `SPEED=` at the top of each hook
  (`hook/speak-kokoro.sh`, `hook/notify-kokoro.sh`). Baked in: `bf_emma` (British female, default),
  `bm_fable`, `bm_daniel`, `am_adam`, `am_liam`, `am_fenrir`. Any other Kokoro
  voice: add it to `VOICES` in the Dockerfile and `make build`.
- **Port:** `PORT=8890 make run`, and update `URL=` in the hook.
- **Stop / logs:** `make stop`, `make logs`.
- **Every target:** `make` on its own (or `make help`) lists them.
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
Both containers run read-only, non-root, with all capabilities dropped
(`compose.yaml`).

Speech-to-text follows the same rules: NVIDIA's Parakeet weights, pinned by
commit and sha256, are exported to ONNX and int8-quantised by `stt/`'s own
build, which fails unless the result passes accuracy gates; Silero VAD is
pinned by sha256; ~290 lines of Python in `stt/app/`. The Pardon app is a Swift
package in `ptt/` using Apple system frameworks only, and sends audio nowhere but
`127.0.0.1:8881`.

Details, including the verification gates and the pinning procedure:
[docs/DESIGN.md](docs/DESIGN.md) for Kokoro, [stt/README.md](stt/README.md) for
speech-to-text.

## Licence

Kokoro-82M weights are Apache-2.0 (hexgrad).
[NVIDIA Parakeet TDT 0.6B v2](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2)
weights are CC-BY-4.0; [Silero VAD](https://github.com/snakers4/silero-vad) is
MIT; the ONNX export recipe is adapted from
[sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx/tree/master/scripts/nemo/parakeet-tdt-0.6b-v2)
(Apache-2.0); one [LibriSpeech](https://www.openslr.org/12) clip (CC-BY-4.0) is a
build-time test fixture only, not shipped. Everything in this repo: MIT.

---

Built with [Claude Code](https://claude.com/claude-code) (Claude Fable 5) in
conversation with the maintainer — Claude wrote the code and the docs; the
maintainer set the requirements, ran the commands, and listened
to fifteen voices so you don't have to.
