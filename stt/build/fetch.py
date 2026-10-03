"""
Download one pinned file and refuse it unless its SHA-256 matches. Build-time only.

  python fetch.py URL SHA256 DEST

Standard library only, so no stage needs curl. On a mismatch the build stops and
prints the hash it got: check the file by hand before pinning that value.
"""
import hashlib
import pathlib
import sys
import urllib.request

MAX_BYTES = 64 << 20


def main() -> None:
    url, want, dest = sys.argv[1], sys.argv[2], pathlib.Path(sys.argv[3])
    with urllib.request.urlopen(url, timeout=120) as resp:
        if not resp.geturl().startswith("https://"):
            sys.exit(f"[fetch] FAIL {url} ended at a non-https URL: {resp.geturl()}")
        data = resp.read(MAX_BYTES + 1)
    if len(data) > MAX_BYTES:
        sys.exit(f"[fetch] FAIL {url} is larger than {MAX_BYTES >> 20} MB")
    got = hashlib.sha256(data).hexdigest()
    if got != want:
        sys.exit(f"[fetch] FAIL {url}\n[fetch] sha256 got {got}\n[fetch] sha256 expected {want}\n"
                 "[fetch] if the upstream file legitimately changed, verify it and update the matching "
                 "*_SHA256 ARG in stt/Dockerfile")
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_bytes(data)
    print(f"[fetch] {dest.name} {len(data)} bytes sha256 {got}")


if __name__ == "__main__":
    main()
