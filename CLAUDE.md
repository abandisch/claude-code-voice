# claude-code-voice

Local neural text-to-speech: Kokoro-82M converted to ONNX by us and served from a
hardened, non-root Docker container on `127.0.0.1:8880`. A Claude Code Stop hook
posts the `🔊` summary line to it and plays the WAV, replacing macOS `say`.
Every ingredient is nameable; ~167 lines of our own Python run in the image.

## Start here

1. `wiki/index.md` — the catalogue.
2. `wiki/open-tasks.md` — what is in flight.
3. `grep '^## \[' wiki/log.md | tail -5` — recent history.

Only then open source files. Wiki conventions (frontmatter, wikilinks, log format,
ingest/query/lint workflows) live in `wiki/CLAUDE.md` — follow them.

## Maintaining the wiki

Update the wiki at the end of **any session that changes state**: touch the relevant
topic page, append a `log.md` entry, re-sync `open-tasks.md`, and add to
`decisions.md` or a `diagnosis-*` page if a choice was made or a bug was chased.

`HANDOVER.md` (untracked, gitignored) was the original session handover; the wiki
supersedes it. Clones will not have it — nothing in it is needed.

## Working here

- The operator runs `docker` / `make` and pastes the output — the Bash sandbox cannot reach
  the Docker socket. Put commands for the operator one per fenced block in `DEBUG-COMMANDS.md` (local scratch, gitignored).
- `run.sh`'s flags and the build's verification gates are deliberate. Diagnose before
  removing anything.
- See `wiki/operator-workflow.md` for the paste-output workflow and the `🔊` contract.
- Voice persona / address style is a per-user choice: keep it in your global `~/.claude/CLAUDE.md`, not here.
