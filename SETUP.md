# Setting up on a new machine

Goal: Claude Code speaks its `🔊` summary line through a local Kokoro container.

## Prerequisites

- macOS on Apple Silicon (image is `linux/arm64`; the hook uses `afplay` and `say`).
- Docker Desktop, running. Turn on *Settings → General → Start Docker Desktop when
  you sign in* so the container returns after a reboot (it runs with
  `--restart unless-stopped`).
- A free Docker ID, logged in to Docker Hardened Images: `docker login dhi.io`.
  No account? Build with stock Python images instead — see `docs/DESIGN.md`.
- `jq` — `/usr/bin/jq` ships with macOS 15+; otherwise `brew install jq`.
- Claude Code installed and run at least once (so `~/.claude` exists).
- Network access during `make build` to dhi.io, Docker Hub, PyPI,
  download.pytorch.org and huggingface.co. On a managed work machine, a proxy
  or firewall is the most likely snag.

## Steps

```sh
git clone https://github.com/abandisch/claude-code-voice.git
cd claude-code-voice
docker login dhi.io
make build      # 5-10 min first time: downloads weights, converts to ONNX, runs the gates
make run        # container "kokoro" on 127.0.0.1:8880
make test       # /health, /voices, then speaks a sentence
make install    # hooks (speak + notify) + settings.json entries + 🔊 rule in ~/.claude/CLAUDE.md
```

`make install` is idempotent and backs up anything it changes
(`~/.claude/settings.json.bak.*`, `~/.claude/hooks/speak.sh.bak.*`). What it
adds to your global CLAUDE.md is `hook/CLAUDE-snippet.md`; the persona line in
it is optional — edit it, delete it, or pick a ready-made one from `hook/personas/`.

## Verify

Open a **new** Claude Code session anywhere, ask anything, and listen.

- Hear a voice → done.
- Hear the macOS `say` voice → hook works, container unreachable. `docker ps`
  should show `kokoro`; `curl -s http://127.0.0.1:8880/health` should answer.
- Hear nothing → the response had no `🔊` line (check the rule landed in
  `~/.claude/CLAUDE.md`), or the Stop hook isn't registered (check
  `~/.claude/settings.json` → `hooks.Stop`).

## Optional: speech-to-text and Pardon (push-to-talk)

Hold right Option, speak, release: the transcript is pasted into the focused
window. Parakeet runs in a second container on `127.0.0.1:8881`; Pardon is the
menu bar app that records and pastes, and its floating orb can be pressed instead
of the key. Audio never leaves the Mac.

Extra prerequisites:

- Docker memory of at least 8 GB (Docker Desktop → Settings → Resources) and
  several GB of free build cache; the first build downloads ~2.4 GB of weights
  from huggingface.co.
- Xcode Command Line Tools (`xcode-select --install`); Pardon builds with `/usr/bin/swift` (a Swift 6 toolchain).

```sh
make build-stt   # 15-30 min first time: downloads weights, exports to ONNX, runs the gates
make run-stt     # container "parakeet" on 127.0.0.1:8881; ready once make logs-stt shows "parakeet ready:"
make test-stt    # needs Kokoro running too (make run): it speaks the sentence Parakeet must transcribe
make test-ptt    # Pardon's tests (macOS 14 or later; no GUI, microphone or network)
make ptt-cert    # optional, once: signing identity so rebuilds keep their permissions
make ptt         # builds Pardon, installs it in ~/Applications and starts it
```

`make ptt-cert` creates a self-signed code-signing identity named `Pardon` in your
login keychain; read the caveat in `ptt/README.md` before you create it.

**Permissions.** On first launch allow the microphone, then in the Accessibility
dialog choose Open System Settings and switch Pardon on. The menu bar icon changes
from a slashed microphone to a plain one.

**Verify.** Click into a text field, hold right Option, say a sentence, release:
Tink when recording starts, Pop when the text is pasted. A slashed icon means a
permission is missing or the speech server is down; open Pardon's menu to see which.
Everything else: `ptt/README.md` → Troubleshooting.

`docker compose up -d` starts both containers together (`compose.yaml`); Docker
Desktop shows them as one `claude-code-voice` group.

## Upgrading from an earlier clone

`make run` and `make run-stt` now replace containers started by the old scripts by
themselves. Remove the old network once with `docker network rm kokoro-net`. No image
rebuild is needed.

## Options

- **Voice / speed:** `VOICE=` and `SPEED=` at the top of `~/.claude/hooks/speak.sh`
  and `~/.claude/hooks/notify.sh` (the waiting-on-you announcer).
  Baked in: `bf_emma` (default), `bm_fable`, `bm_daniel`, `am_adam`, `am_liam`, `am_fenrir`. Others: add to `VOICES` in the
  Dockerfile and `make build` (ids: hexgrad/Kokoro-82M `voices/`).
- **Port:** `PORT=8890 make run`, then change `URL=` in the hook. Speech-to-text:
  `PORT=… make run-stt`; Pardon always uses `127.0.0.1:8881`.
- **Stop / restart / logs:** `make stop`, `make run`, `make logs`.
- **Mute / unmute:** `make mute`, `make unmute` (flag file `~/.claude/hooks/mute`).
- **Supply-chain pinning** (optional): `docs/DESIGN.md`.

## Uninstall

`docker compose down` (removes both containers and their network), then
`docker rmi kokoro-tts:local` (and `docker rmi parakeet-stt:local` if you built it); remove
the `hooks.Stop` and `hooks.Notification` entries from `~/.claude/settings.json` (or restore the `.bak`), delete
`~/.claude/hooks/speak.sh` and `~/.claude/hooks/notify.sh`, the mute flag `~/.claude/hooks/mute`
if present and the `*.bak.*` backups `make install` left in `~/.claude` and `~/.claude/hooks`, and remove the "Spoken summary" section from
`~/.claude/CLAUDE.md`.

Pardon: `make clean-ptt` (stops it, removes `ptt/build` and `~/Applications/Pardon.app`);
remove Pardon from System Settings → Privacy & Security → Microphone and
Accessibility, and from System Settings → General → Login Items; optionally delete
the "Pardon" certificate in Keychain Access → login → My Certificates.

## Doing this with Claude Code

Open Claude Code in the repo and say "set this up". `CLAUDE.md` tells it which
steps it can run and which to hand back to you (anything touching Docker, audio,
or `~/.claude`).
