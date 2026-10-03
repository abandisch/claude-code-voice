# syntax=docker/dockerfile:1.7
#
# Parakeet TDT 0.6B v2 speech-to-text in a hardened container.
# Build context is stt/ (see `make build-stt`).
#
#   Stage "convert"  – THROWAWAY. NeMo + NVIDIA's original .nemo -> ONNX
#                      (encoder / decoder / joiner), dynamic int8, then the gates.
#                      Nothing from this stage except the exported model files
#                      reaches the runtime image.
#   Stage "deps"     – Python packages (Microsoft onnxruntime, NumPy) installed
#                      into /pylibs, plus Silero VAD's ONNX pinned by sha256.
#   Stage "harvest"  – libstdc++ for onnxruntime and the /etc/machine-id
#                      placeholder, taken from Debian's own package archive.
#   Stage "runtime"  – Docker Hardened Image: non-root, no shell, no package
#                      manager. Only our ~290 lines of Python run here.
#
# Override PY_DEV / PY_RUN at build time if you do not want to log in to dhi.io
# (e.g. make build-stt STT_BUILD_ARGS="--build-arg PY_RUN=python:3.12-slim-bookworm"),
# at the cost of hardening.

ARG PY_DEV=dhi.io/python:3.12-debian13-dev
ARG PY_RUN=dhi.io/python:3.12-debian13
ARG DEBIAN=debian:13-slim

############################################################################
FROM ${PY_DEV} AS deps
USER 0
ENV PIP_NO_CACHE_DIR=1
COPY build/fetch.py /tmp/fetch.py
# Silero VAD (MIT) at a pinned tag; fetch.py refuses any other bytes.
ARG SILERO_TAG=v5.1.2
ARG SILERO_SHA256=2623a2953f6ff3d2c1e61740c6cdb7168133479b267dfef114a4a3cc5bdd788f
RUN python /tmp/fetch.py \
      "https://raw.githubusercontent.com/snakers4/silero-vad/${SILERO_TAG}/src/silero_vad/data/silero_vad.onnx" \
      "${SILERO_SHA256}" /vad/silero_vad.onnx
COPY app/requirements.txt /tmp/requirements.txt
# pip enforces hashes only once `make lock-stt` has written --hash lines into the file.
RUN pip install --target /pylibs --no-compile -r /tmp/requirements.txt \
 && find /pylibs -name '__pycache__' -prune -exec rm -rf {} + \
 && rm -rf /pylibs/bin

############################################################################
FROM ${PY_DEV} AS convert
USER 0
WORKDIR /work
ENV PIP_NO_CACHE_DIR=1 HF_HUB_DISABLE_TELEMETRY=1
COPY build/fetch.py .
# NVIDIA's model-card clip, LibriSpeech 2086-149220-0033 (CC-BY-4.0; test fixture only,
# never shipped). Fetched before the NeMo install so a hash mismatch fails in seconds.
ARG FIXTURE_SHA256=5fceacff0315d49cb59fcc505bcecf1ed5f2f35c2897b1e65a59f30e5d922150
RUN python fetch.py https://dldata-public.s3.us-east-2.amazonaws.com/2086-149220-0033.wav \
      "${FIXTURE_SHA256}" /work/fixture.wav
COPY build/requirements-convert.txt .
# torch first from PyTorch's CPU-only index (an --extra-index-url resolve can pick
# PyPI's multi-GB CUDA build), then everything else from PyPI.
RUN pip install --index-url https://download.pytorch.org/whl/cpu "torch>=2.6,<2.9" \
 && pip install -r requirements-convert.txt
COPY --from=deps /vad/silero_vad.onnx /work/silero_vad.onnx
# app/ too: the gates run the runtime's own code.
COPY build/*.py app/*.py ./
# nvidia/parakeet-tdt-0.6b-v2 pinned by commit and by the .nemo's sha256; export_onnx.py refuses other bytes.
ARG PARAKEET_REVISION=ae9ad07059c7c739ffaf932226a8fe64ae2620b0
ARG PARAKEET_SHA256=d99e39955c9d3d0350d8fb7c75e40c64a2b2eaeb003883d7c941fd2e8747b28c
RUN python export_onnx.py --revision "${PARAKEET_REVISION}" --weights-sha256 "${PARAKEET_SHA256}" \
      --fixture fixture.wav --vad silero_vad.onnx --out /out

############################################################################
FROM ${DEBIAN} AS harvest
# Mirrors the root build/harvest.sh; cannot reuse it because the build context is stt/.
RUN apt-get update \
 && apt-get install -y --no-install-recommends libstdc++6 \
 && rm -rf /var/lib/apt/lists/*
# onnxruntime's wheel needs the C++ runtime. /etc/machine-id: see the root build/harvest.sh
# (onnxruntime telemetry fclose()s a NULL without it; never transmitted).
RUN for lib in /usr/lib/*-linux-gnu/libstdc++.so.6* /usr/lib/*-linux-gnu/libgcc_s.so.1; do \
      mkdir -p "/stage$(dirname "$lib")" && cp -a "$lib" "/stage$lib" || exit 1; \
    done \
 && mkdir -p /stage/etc \
 && printf '%s\n' 00000000000000000000000000000000 > /stage/etc/machine-id \
 && find /stage | sort

############################################################################
FROM ${PY_RUN} AS runtime
COPY --from=harvest /stage/ /
COPY --from=deps    --chown=65532:65532 /pylibs /pylibs
COPY --from=convert --chown=65532:65532 /out    /models
COPY --chown=65532:65532 app/server.py app/features.py app/decode.py app/vad.py /app/
ENV PYTHONPATH=/pylibs \
    PYTHONDONTWRITEBYTECODE=1 \
    HOME=/tmp \
    OMP_NUM_THREADS=4 \
    STT_MODEL_DIR=/models \
    STT_PORT=8881
USER 65532:65532
EXPOSE 8881
ENTRYPOINT ["python", "/app/server.py"]
