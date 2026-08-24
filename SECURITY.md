# Security policy

## Reporting a vulnerability

Please report vulnerabilities privately via GitHub:
**Security → Report a vulnerability** on this repository (private vulnerability
reporting is enabled). Expect an acknowledgement within a few days.

Please do not open public issues for security problems.

## Scope

The interesting attack surface here is small but real:

- `install.sh` and the hooks in `hook/` — they run on users' machines and
  write under `~/.claude/`.
- The container (`app/`, `Dockerfile`, `run.sh`) — it binds to `127.0.0.1`
  only, runs read-only, non-root, all capabilities dropped; anything that
  weakens that is a bug.
- The build pipeline (`build/`) — it downloads and converts the model weights;
  the verification gates exist to catch tampering.

## Supported versions

Only the latest commit on `main` is supported.
