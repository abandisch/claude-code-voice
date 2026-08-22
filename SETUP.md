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
make install    # hook + settings.json entry + 🔊 rule in ~/.claude/CLAUDE.md
```

`make install` is idempotent and backs up anything it changes
(`~/.claude/settings.json.bak.*`, `~/.claude/hooks/speak.sh.bak.*`). What it
adds to your global CLAUDE.md is `hook/CLAUDE-snippet.md`; the persona line in
it is optional — edit or delete.

## Verify

Open a **new** Claude Code session anywhere, ask anything, and listen.

- Hear a voice → done.
- Hear the macOS `say` voice → hook works, container unreachable. `docker ps`
  should show `kokoro`; `curl -s http://127.0.0.1:8880/health` should answer.
- Hear nothing → the response had no `🔊` line (check the rule landed in
  `~/.claude/CLAUDE.md`), or the Stop hook isn't registered (check
  `~/.claude/settings.json` → `hooks.Stop`).

## Options

- **Voice / speed:** `VOICE=` and `SPEED=` at the top of `~/.claude/hooks/speak.sh`.
  Baked in: `bm_lewis` (default), `bf_emma`. Others: add to `VOICES` in the
  Dockerfile and `make build` (ids: hexgrad/Kokoro-82M `voices/`).
- **Port:** `PORT=8881 make run`, then change `URL=` in the hook.
- **Stop / restart / logs:** `make stop`, `make run`, `make logs`.
- **Supply-chain pinning** (optional): `docs/DESIGN.md`.

## Uninstall

`make stop`, `docker rmi kokoro-tts:local`, `docker network rm kokoro-net`; remove
the `hooks.Stop` entry from `~/.claude/settings.json` (or restore the `.bak`), delete
`~/.claude/hooks/speak.sh`, and remove the "Spoken summary" section from
`~/.claude/CLAUDE.md`.

## Doing this with Claude Code

Open Claude Code in the repo and say "set this up". `CLAUDE.md` tells it which
steps it can run and which to hand back to you (anything touching Docker, audio,
or `~/.claude`).
