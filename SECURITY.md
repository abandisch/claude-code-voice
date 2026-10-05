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
- The container (`app/`, `Dockerfile`) — it binds to `127.0.0.1`
  only, runs read-only, non-root, all capabilities dropped; anything that
  weakens that is a bug.
- The speech-to-text container (`stt/`) — loopback only (`127.0.0.1:8881`),
  the same hardening; its weights are pinned by commit and sha256 and its
  build is gated in the same way.
- `compose.yaml` — the runtime hardening flags for both containers; anything
  that weakens them is a bug.
- The build pipeline (`build/`) — it downloads and converts the model weights;
  the verification gates exist to catch tampering.
- The Pardon app (`ptt/`) — holds Microphone and Accessibility permission, sends audio
  only to `127.0.0.1:8881`, and posts synthetic keystrokes (Cmd-V, optionally
  Return) into the focused window. Its only other requests are a health check on
  `127.0.0.1:8881` and, on `127.0.0.1:8880`, the health check, the voice list and a fixed
  test sentence; every reply is size-capped and voice ids are validated before use.
  It writes two files under `~/.claude/hooks/`: `mute` and `pardon.conf`. The hooks read `pardon.conf` by
  strict whole-line pattern and never execute it. Pardon does not start or stop
  containers and spawns no processes. Its floating pet is a second trigger under
  the same rules and needs no further permission. The optional self-signed `Pardon` signing
  identity (`make ptt-cert`) could be used by any program running as the user
  to sign something that inherits those permissions; see `ptt/README.md`.
- `scripts/release.sh` — creates and pushes a version tag.
- `.github/workflows/codeql.yml` — runs only GitHub-owned actions pinned by commit;
  read-only except uploading the scan results.

## Supported versions

Only the latest commit on `main` is supported. Tags mark versions; no binary
releases are published.
