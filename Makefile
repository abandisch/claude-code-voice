IMAGE ?= kokoro-tts:local
PLATFORM ?= linux/arm64

.PHONY: build run stop logs test install scan digest lock sbom clean

## Build the image (BuildKit; attaches SBOM + provenance attestations)
build:
	docker buildx build --platform $(PLATFORM) --sbom=true --provenance=true \
		--load -t $(IMAGE) .

run:
	IMAGE=$(IMAGE) ./run.sh

stop:
	docker rm -f kokoro 2>/dev/null || true

logs:
	docker logs -f kokoro

## Speak a test sentence through the running container
test:
	curl -sf http://127.0.0.1:8880/health && echo
	curl -sf http://127.0.0.1:8880/voices && echo
	curl -sf -X POST http://127.0.0.1:8880/speak \
		-H 'Content-Type: application/json' \
		-d '{"text":"Text to speech is online and working.","voice":"bf_emma"}' \
		-o /tmp/kokoro-test.wav && afplay /tmp/kokoro-test.wav

## Vulnerability scan of the built image (free, local)
scan:
	docker scout cves $(IMAGE)

## Print the image digest so you can pin IMAGE=kokoro-tts@sha256:... in run.sh
digest:
	docker image inspect --format '{{index .RepoDigests 0}}{{"\n"}}{{.Id}}' $(IMAGE)

## Regenerate app/requirements.txt with exact versions + sha256 hashes
lock:
	docker run --rm -v "$(PWD)/app:/app" -w /tmp dhi.io/python:3.12-debian13-dev sh -c '\
		pip download -q --only-binary=:all: --platform manylinux_2_28_aarch64 \
			--python-version 3.12 -d wheels -r /app/requirements.txt && \
		for w in wheels/*.whl; do n=$$(basename $$w); \
			printf "%s==%s --hash=sha256:%s\n" \
				"$$(echo $$n | cut -d- -f1 | tr _ -)" "$$(echo $$n | cut -d- -f2)" \
				"$$(sha256sum $$w | cut -d" " -f1)"; done | sort > /app/requirements.txt' \
	&& cat app/requirements.txt

sbom:
	docker sbom $(IMAGE) 2>/dev/null || docker buildx imagetools inspect $(IMAGE) --format '{{json .SBOM}}'

clean: stop
	docker rmi $(IMAGE) 2>/dev/null || true

## Install the Claude Code hook, settings entry and global CLAUDE.md rule (idempotent)
install:
	./install.sh
