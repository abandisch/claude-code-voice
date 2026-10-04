#!/bin/sh
# Copy espeak-ng (binary, espeak-ng-data, shared libs), libstdc++ and libgcc_s
# out of a Debian image, plus a placeholder /etc/machine-id, into a staging dir
# that is then layered onto the hardened runtime, which has no package manager.
# glibc itself is NOT copied: the runtime already has its own, and mixing
# loaders across images is unsafe.
#
# Usage (Dockerfile harvest stage):  sh harvest.sh STAGE_DIR
set -eu
[ -n "${1:-}" ] || { echo "usage: sh harvest.sh STAGE_DIR" >&2; exit 2; }
STAGE="$1"
mkdir -p "$STAGE"

copy() {
  # Copy the REAL file (paths resolved: Debian's /lib is a symlink to /usr/lib,
  # and a literal /lib directory would collide with that symlink in the runtime
  # image). If the requested name was a soname symlink, recreate it alongside.
  real="$(readlink -f "$1")"
  mkdir -p "$STAGE$(dirname "$real")"
  cp -a "$real" "$STAGE$real"
  name="$(basename "$1")"
  if [ "$name" != "$(basename "$real")" ]; then
    ln -sfn "$(basename "$real")" "$STAGE$(dirname "$real")/$name"
  fi
}

copy /usr/bin/espeak-ng
ldd /usr/bin/espeak-ng \
  | awk '/=>/ {print $3} /^[[:space:]]*\// {print $1}' \
  | grep -vE 'libc\.so|ld-linux|libm\.so|libpthread|libdl\.so|librt\.so|libresolv' \
  | while read -r lib; do copy "$lib"; done

# onnxruntime's wheel needs the C++ runtime
# A pattern that matches nothing stays literal: skip it rather than fail.
for lib in /usr/lib/*-linux-gnu/libstdc++.so.6* /usr/lib/*-linux-gnu/libgcc_s.so.1; do
  [ -e "$lib" ] || [ -L "$lib" ] || continue
  copy "$lib"
done

# phoneme data
data="$(dpkg -L espeak-ng-data | grep -m1 'espeak-ng-data$')"
mkdir -p "$STAGE$(dirname "$data")"
cp -a "$data" "$STAGE$data"

# onnxruntime's telemetry init fopen()s /etc/machine-id and fclose()s the
# result without a NULL check; the hardened runtime image has no such file,
# so `import onnxruntime` dies with SIGSEGV. Ship a fixed all-zero placeholder
# (never transmitted; the Linux telemetry sink is a no-op).
mkdir -p "$STAGE/etc"
printf '%s\n' 00000000000000000000000000000000 > "$STAGE/etc/machine-id"

echo "harvested:"; find "$STAGE" -type f | head -50
