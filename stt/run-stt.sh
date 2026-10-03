#!/bin/bash
# Start the Parakeet STT container with a locked-down runtime profile.
#
#   --network kokoro-net   user-defined bridge; the ONLY thing published is the
#                          HTTP port, and only on 127.0.0.1 (not your LAN).
#   --read-only            root filesystem is immutable; /tmp is a small tmpfs
#   --cap-drop ALL         no Linux capabilities at all
#   no-new-privileges      setuid/setcap binaries cannot escalate
#   --user 65532           non-root (the image already does this; belt and braces)
#   --pids-limit/--memory  bounded resources; a runaway process cannot starve the Mac
#   --memory 2500m         int8 encoder is ~660 MB; measure with `docker stats` and lower
#   no -v / --mount        the container cannot see any of your files
#
# Tip: after the first run, pin IMAGE to the digest printed by `make digest IMAGE=parakeet-stt:local`.
set -euo pipefail
IMAGE="${IMAGE:-parakeet-stt:local}"
NAME="${NAME:-parakeet}"
PORT="${PORT:-8881}"

docker network inspect kokoro-net >/dev/null 2>&1 || docker network create kokoro-net >/dev/null
docker rm -f "$NAME" >/dev/null 2>&1 || true

exec docker run -d --name "$NAME" \
  --network kokoro-net \
  --publish "127.0.0.1:${PORT}:8881" \
  --read-only --tmpfs /tmp:rw,nosuid,nodev,noexec,size=256m \
  --cap-drop ALL --security-opt no-new-privileges \
  --user 65532:65532 \
  --pids-limit 64 --memory 2500m --memory-swap 2500m --cpus 4 \
  --restart unless-stopped \
  "$IMAGE"
