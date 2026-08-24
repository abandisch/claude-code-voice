# syntax=docker/dockerfile:1.7
#
# Kokoro-82M text-to-speech in a hardened container.
#
#   Stage "convert"  – THROWAWAY. PyTorch + hexgrad's original weights -> ONNX.
#                      Nothing from this stage except the exported model files
#                      reaches the runtime image.
#   Stage "deps"     – Python packages (Microsoft onnxruntime, NumPy) installed
#                      into /pylibs with pip's hash checking.
#   Stage "harvest"  – espeak-ng and its shared libraries taken from Debian's
#                      own package archive (no third-party wheels).
#   Stage "runtime"  – Docker Hardened Image: non-root, no shell, no package
#                      manager. Only our ~150 lines of Python run here.
#
# Override PY_DEV / PY_RUN at build time if you do not want to log in to dhi.io
# (e.g. --build-arg PY_RUN=python:3.12-slim-bookworm), at the cost of hardening.

ARG PY_DEV=dhi.io/python:3.12-debian13-dev
ARG PY_RUN=dhi.io/python:3.12-debian13
ARG DEBIAN=debian:13-slim

############################################################################
FROM ${PY_DEV} AS convert
USER 0
WORKDIR /work
ENV PIP_NO_CACHE_DIR=1 HF_HUB_DISABLE_TELEMETRY=1
COPY build/requirements-convert.txt .
# torch first from PyTorch's CPU-only index (an --extra-index-url resolve can pick
# PyPI's multi-GB CUDA build), then everything else from PyPI.
RUN pip install --index-url https://download.pytorch.org/whl/cpu "torch>=2.6,<2.9" \
 && pip install -r requirements-convert.txt
COPY build/*.py .
# Pin to a specific commit of hexgrad/Kokoro-82M once you have recorded one.
ARG KOKORO_REVISION=main
ARG VOICES="bf_emma bm_fable bm_daniel am_adam am_liam am_fenrir"
RUN python export_onnx.py --revision "${KOKORO_REVISION}" --voices ${VOICES} --out /out

############################################################################
FROM ${PY_DEV} AS deps
USER 0
ENV PIP_NO_CACHE_DIR=1
COPY app/requirements.txt /tmp/requirements.txt
# --require-hashes is enforced automatically by pip when the file has --hash lines.
RUN pip install --target /pylibs --no-compile -r /tmp/requirements.txt \
 && find /pylibs -name '__pycache__' -prune -exec rm -rf {} + \
 && rm -rf /pylibs/bin

############################################################################
FROM ${DEBIAN} AS harvest
RUN apt-get update \
 && apt-get install -y --no-install-recommends espeak-ng libstdc++6 \
 && rm -rf /var/lib/apt/lists/*
COPY build/harvest.sh /tmp/harvest.sh
RUN sh /tmp/harvest.sh /stage

############################################################################
FROM ${PY_RUN} AS runtime
COPY --from=harvest /stage/ /
COPY --from=deps    --chown=65532:65532 /pylibs /pylibs
COPY --from=convert --chown=65532:65532 /out    /models
COPY --chown=65532:65532 app/server.py app/phonemize.py /app/
ENV PYTHONPATH=/pylibs \
    PYTHONDONTWRITEBYTECODE=1 \
    HOME=/tmp \
    OMP_NUM_THREADS=4 \
    KOKORO_MODEL_DIR=/models \
    KOKORO_DEFAULT_VOICE=bf_emma \
    PORT=8880
USER 65532:65532
EXPOSE 8880
ENTRYPOINT ["python", "/app/server.py"]
