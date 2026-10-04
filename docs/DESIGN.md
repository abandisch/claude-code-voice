# Design notes — supply chain, verification, hardening

Companion to the [README](../README.md). This is the "why you can trust it"
detail; the README is the "how to use it".

## What is in the box

| Layer | Source | Where it comes from |
|---|---|---|
| Base OS + Python 3.12 | Docker Hardened Images (Docker Inc.) | `dhi.io/python:3.12-debian13` — non-root, no shell, no package manager, signed, SBOM |
| Inference runtime | `onnxruntime` (Microsoft) | PyPI, version + sha256 pinned after `make lock` |
| Maths | `numpy` | PyPI, pinned likewise |
| Phonemiser | `espeak-ng` | Debian 13's own package archive (`build/harvest.sh` copies the binary, data and libs) |
| Model weights | Kokoro-82M, hexgrad, Apache-2.0 | Author's Hugging Face repo, converted to ONNX **by us** in a throwaway build stage |
| Server + phonemizer glue | `app/server.py`, `app/phonemize.py` | This repo. Standard library + the two packages above |

PyTorch and hexgrad's `kokoro` package are used **only** in the throwaway
`convert` build stage to load the original weights and export ONNX. They are
not in the runtime image.

### How the conversion is verified

The weights are published as a PyTorch model; we convert them to ONNX ourselves
and run only onnxruntime in the container. A bad conversion still produces
audio — just subtly wrong audio — so the build compares the ONNX model against
the original PyTorch one and fails (deleting the model) unless they agree.
That comparison is not a simple diff: Kokoro deliberately adds random phase and
noise in its vocoder, so the build first measures how much PyTorch disagrees
with *itself*, checks the deterministic parts strictly, and then requires the
shipped model to sit within that self-disagreement. It also inspects the graph
for the classic export bug of a sequence length baked in as a constant. The
full gate-by-gate description is in the docstring of `build/verify.py`.

**The exported graph is batch-size-1 only.** Removing the LSTM
pack/pad wrappers is what keeps the sequence length dynamic, and that
equivalence only holds when nothing is padded. `app/server.py` sends one
sentence at a time, which is the only shape the graph promises to compute.

## Pinning the supply chain (after the first successful build)

1. `make lock` — rewrites `app/requirements.txt` with exact versions and
   `--hash` lines. Rebuild; pip will now refuse anything that differs.
2. Record the weights hash printed by the build (`[convert] weights sha256 …`)
   and the Hugging Face commit, then pin `KOKORO_REVISION` in the Dockerfile.
   Copy the versions from `/models/convert-freeze.txt` into
   `build/requirements-convert.txt` to make the conversion reproducible too.
3. `make digest` and set `IMAGE=kokoro-tts@sha256:…` for `make run`
   (`KOKORO_IMAGE=` when running `docker compose` directly).
4. `make scan` — Docker Scout CVE report for the final image.

## Runtime hardening (`compose.yaml`)

Both containers (Kokoro, and Parakeet speech-to-text) get the same profile.
No mounts. Port published on 127.0.0.1 only. Read-only root filesystem,
small `noexec` tmpfs for `/tmp`, all capabilities dropped,
`no-new-privileges`, non-root uid 65532, pids/memory/cpu limits. They share
compose's own project bridge network, `pardon_default`.

Why not `--network none`? Docker cannot publish a port from a container with
no network. The image has no shell, no curl, no credentials and nothing that
phones home, so a bridge network with a localhost-only port is the practical
compromise. If you want a zero-egress guarantee, the alternative is a one-shot
`docker run --rm --network none` per sentence (about +1 s latency).
