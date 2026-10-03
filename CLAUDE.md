# claude-code-voice

Local neural text-to-speech: Kokoro-82M converted to ONNX by us and served from a
hardened, non-root Docker container on `127.0.0.1:8880`. A Claude Code Stop hook
posts the `🔊` summary line to it and plays the WAV, replacing macOS `say`.
Every ingredient is nameable; ~167 lines of our own Python run in the image.
Public repo: https://github.com/abandisch/claude-code-voice

## If the user asks to "set this up" (fresh machine)

Follow `SETUP.md`. Split the work like this:

1. **You check** prerequisites you can see: `uname -m` is `arm64`, `docker` and
   `/usr/bin/jq` exist, `~/.claude` exists, and whether `~/.claude/CLAUDE.md` already
   has a `🔊` rule. Report what's missing.
2. **Hand to the user, one command per fenced block** (your sandbox can't reach the
   Docker socket, play audio, or usually write under `~/.claude`):
   `docker login dhi.io` → `make build` → `make run` → `make test` → `make install`.
   Ask them to paste the output of each; `make build` runs verification gates and
   may take 5-10 minutes the first time.
3. **Verify**: they start a new Claude Code session and hear the `🔊` line. If they
   hear macOS `say` instead, the container isn't reachable; if nothing, the rule or
   the Stop hook didn't land — see SETUP.md → Verify.
4. Do not install the hook by hand-editing `~/.claude/settings.json` when
   `make install` is available; it is idempotent and makes backups.

## Start here (any other task)

`wiki/` is the maintainer's private working memory: gitignored, its own local git repo,
never pushed. Clones will not have it. If it is present:

1. `wiki/index.md` — the catalogue.
2. `wiki/open-tasks.md` — what is in flight.
3. `grep '^## \[' wiki/log.md | tail -5` — recent history.

Only then open source files. Wiki conventions (frontmatter, wikilinks, log format,
ingest/query/lint workflows) live in `wiki/CLAUDE.md` — follow them. If `wiki/` is
absent, start from `README.md` and `docs/DESIGN.md`.

## Maintaining the wiki

Update the wiki at the end of **any session that changes state**: touch the relevant
topic page, append a `log.md` entry, re-sync `open-tasks.md`, and add to
`decisions.md` or a `diagnosis-*` page if a choice was made or a bug was chased.

`HANDOVER.md` (untracked, gitignored) was the original session handover; the wiki
supersedes it. Neither is in the public repo — nothing in them is needed to build or run.

## Working here

- The operator runs `docker` / `make` and pastes the output — the Bash sandbox cannot reach
  the Docker socket. Put commands for the operator one per fenced block in `DEBUG-COMMANDS.md` (local scratch, gitignored).
- `run.sh`'s flags and the build's verification gates are deliberate. Diagnose before
  removing anything.
- The `🔊` line contract lives in `hook/CLAUDE-snippet.md` (what `make install` appends to `~/.claude/CLAUDE.md`).
- Voice persona / address style is a per-user choice: keep it in your global `~/.claude/CLAUDE.md`, not here.
