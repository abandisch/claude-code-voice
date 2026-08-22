# Setting up on a new machine

Goal: Claude Code speaks its `🔊` summary line through a local Kokoro container.
This guide is written so you can hand it to a Claude Code session in this repo
("read SETUP.md and set things up") — steps marked **[you]** need a human
terminal (Docker socket, audio, and `~/.claude/hooks` are out of Claude's sandbox
reach); the rest Claude can do.

## 0. Prerequisites

- macOS on Apple Silicon (the image is `linux/arm64`; `afplay` and `say` are used).
- Docker Desktop, running. Enable *Settings → General → Start Docker Desktop when
  you sign in* so the container comes back after a reboot (it is started with
  `--restart unless-stopped`).
- A free Docker ID, logged in to Docker Hardened Images: **[you]** `docker login dhi.io`.
  (No account? Build with the stock Python images instead — see README → Build.)
- `/usr/bin/jq` — ships with macOS 15+. Check: `/usr/bin/jq --version`.
- Claude Code installed, with a global `~/.claude/CLAUDE.md`.

## 1. Build and run

**[you]**, in the repo root:

```sh
make build      # 5-10 min first time: downloads torch + weights, converts, runs the gates
make run        # container "kokoro" on 127.0.0.1:8880
make test       # prints /health and /voices, then speaks a sentence
```

If `make test` prints `{"ok": true}` and you hear a voice, the server side is done.

## 2. Install the hook

1. Copy `hook/speak-kokoro.sh` to `~/.claude/hooks/speak.sh` and make it executable.
   (If Claude is doing this: the directory may be write-denied for Bash — use the
   Write tool.) If an older `speak.sh` exists, keep a copy as `speak-say.sh`.
2. Register it as a Stop hook in `~/.claude/settings.json`:

   ```json
   "hooks": {
     "Stop": [
       { "hooks": [ { "type": "command", "command": "bash ~/.claude/hooks/speak.sh", "timeout": 30 } ] }
     ]
   }
   ```

3. Make sure the global `~/.claude/CLAUDE.md` tells Claude to end every response
   with a line starting `🔊 ` followed by a one-sentence spoken summary. That
   marker is what the hook extracts; without it nothing is spoken.

## 3. Verify

Start a Claude Code session anywhere and ask it anything. You should hear the
`🔊` line in the configured voice. If you hear macOS `say` instead, the hook ran
but could not reach the container: check `docker ps` shows `kokoro`, and
`curl -s http://127.0.0.1:8880/health`.

## 4. Options

- **Voice / speed:** `VOICE=` and `SPEED=` at the top of `~/.claude/hooks/speak.sh`.
  Baked-in voices: `bm_lewis` (default), `bf_emma`. Others need the `VOICES` arg in
  the Dockerfile changed and `make build` (voice ids: hexgrad/Kokoro-82M `voices/`).
- **Port:** `PORT=8881 make run` and change `URL=` in the hook.
- **Stop / restart:** `make stop`, `make run`. Logs: `make logs`.
- **Supply-chain pinning** (optional, recommended once happy): README →
  *After the first successful build*.

## 5. Uninstall

`make stop`, `docker rmi kokoro-tts:local`, `docker network rm kokoro-net`, restore
`~/.claude/hooks/speak-say.sh` as `speak.sh` (or remove the Stop hook entry).

## For Claude sessions

Read `CLAUDE.md` and `wiki/index.md` first; `wiki/hook-integration.md` and
`wiki/debugging-containers-playbook.md` cover the failure modes already met.
