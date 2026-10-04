IMAGE ?= kokoro-tts:local
PLATFORM ?= linux/arm64
VOICE ?= bf_emma
SPEED ?= 1.0
APP_DIR ?= app

.PHONY: build run stop logs test say mute unmute install scan digest lock sbom clean

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

## Regenerate $(APP_DIR)/requirements.txt with exact versions + sha256 hashes
lock:
	docker run --rm -v "$(PWD)/$(APP_DIR):/app" -w /tmp dhi.io/python:3.12-debian13-dev sh -c '\
		pip download -q --only-binary=:all: --platform manylinux_2_28_aarch64 \
			--python-version 3.12 -d wheels -r /app/requirements.txt && \
		for w in wheels/*.whl; do n=$$(basename $$w); \
			printf "%s==%s --hash=sha256:%s\n" \
				"$$(echo $$n | cut -d- -f1 | tr _ -)" "$$(echo $$n | cut -d- -f2)" \
				"$$(sha256sum $$w | cut -d" " -f1)"; done | sort > /app/requirements.txt' \
	&& cat $(APP_DIR)/requirements.txt

sbom:
	docker sbom $(IMAGE) 2>/dev/null || docker buildx imagetools inspect $(IMAGE) --format '{{json .SBOM}}'

clean: stop
	docker rmi $(IMAGE) 2>/dev/null || true

## Install the Claude Code hook, settings entry and global CLAUDE.md rule (idempotent)
install:
	./install.sh

## Speak anything: make say TEXT="Good evening" [VOICE=bm_fable] [SPEED=1.2]
say:
	@[ -n "$(TEXT)" ] || { echo 'usage: make say TEXT="hello there" [VOICE=bf_emma] [SPEED=1.0]'; exit 1; }
	@wav=$$(mktemp -t kokoro); \
	/usr/bin/jq -cn --arg t "$(TEXT)" --arg v "$(VOICE)" --argjson s "$(SPEED)" \
		'{text:$$t, voice:$$v, speed:$$s}' \
	| curl -sf --max-time 30 -X POST http://127.0.0.1:8880/speak \
		-H 'Content-Type: application/json' -d @- -o "$$wav" \
	&& afplay "$$wav"; rm -f "$$wav"

## Silence both hooks until further notice
mute:
	@mkdir -p $(HOME)/.claude/hooks && touch $(HOME)/.claude/hooks/mute
	@echo "muted — make unmute to restore"

## Remove the mute flag (confirms audibly)
unmute:
	@rm -f $(HOME)/.claude/hooks/mute
	@$(MAKE) --no-print-directory say TEXT="Voice restored."

# --- Speech-to-text: Parakeet in its own container (stt/, 127.0.0.1:8881) ---
STT_IMAGE ?= parakeet-stt:local
STT_BUILD_ARGS ?=

.PHONY: build-stt run-stt stop-stt logs-stt test-stt clean-stt lock-stt

## Build the STT image (context stt/; first build runs NeMo export + gates)
build-stt:
	docker buildx build --platform $(PLATFORM) --sbom=true --provenance=true \
		$(STT_BUILD_ARGS) --load -t $(STT_IMAGE) -f stt/Dockerfile stt

run-stt:
	IMAGE=$(STT_IMAGE) ./stt/run-stt.sh

stop-stt:
	docker rm -f parakeet 2>/dev/null || true

logs-stt:
	docker logs -f parakeet

## Transcribe a sentence spoken by the running Kokoro container (needs `make run`)
test-stt:
	@for i in $$(seq 60); do curl -sf http://127.0.0.1:8881/health >/dev/null && break; sleep 1; done; \
	curl -sf http://127.0.0.1:8881/health >/dev/null || { echo "parakeet is not answering on 127.0.0.1:8881 — make run-stt first, then check make logs-stt (it may still be loading or restart-looping)"; exit 1; }; \
	curl -sf http://127.0.0.1:8880/health >/dev/null || { echo "kokoro is not answering on 127.0.0.1:8880 — make run first (it speaks the test sentence)"; exit 1; }; \
	tmp=$$(mktemp -d -t parakeet); trap 'rm -rf "$$tmp"' EXIT; \
	curl -sf --max-time 30 -X POST http://127.0.0.1:8880/speak \
		-H 'Content-Type: application/json' \
		-d '{"text":"The quick brown fox jumps over the lazy dog near the riverbank."}' \
		-o "$$tmp/stt-src.wav" || { echo "FAIL: Kokoro /speak failed"; exit 1; }; \
	/usr/bin/afconvert -f WAVE -d LEI16@16000 -c 1 "$$tmp/stt-src.wav" "$$tmp/stt-16k.wav" \
		|| { echo "FAIL: afconvert could not make a 16 kHz mono WAV"; exit 1; }; \
	out=$$(curl -s --fail-with-body --max-time 60 -X POST http://127.0.0.1:8881/transcribe \
		-H 'Content-Type: audio/wav' --data-binary @"$$tmp/stt-16k.wav" -w '\n%{time_total}'); rc=$$?; \
	json=$$(printf '%s\n' "$$out" | sed '$$d'); \
	printf '%s\n' "$$json"; echo "wall time $$(printf '%s\n' "$$out" | tail -n 1) s"; \
	[ $$rc -eq 0 ] || { echo "FAIL: parakeet /transcribe failed (curl exit $$rc)"; exit 1; }; \
	printf '%s' "$$json" | /usr/bin/jq -e '.no_speech == false and (.text | ascii_downcase | contains("quick brown fox"))' >/dev/null \
		|| { echo "FAIL: expected speech containing \"quick brown fox\""; exit 1; }

## Regenerate stt/app/requirements.txt with exact versions + sha256 hashes
lock-stt:
	@$(MAKE) --no-print-directory lock APP_DIR=stt/app

clean-stt: stop-stt
	docker rmi $(STT_IMAGE) 2>/dev/null || true

# --- Push-to-talk: Pardon, the menu bar app (ptt/) ---
PTT_APP ?= $(HOME)/Applications/Pardon.app
# Refuse to rm -rf anything that is not an .app bundle path.
PTT_APP_GUARD = case "$(PTT_APP)" in *?.app) ;; *) echo "PTT_APP must end in .app: $(PTT_APP)"; exit 1;; esac

.PHONY: ptt test-ptt ptt-cert stop-ptt clean-ptt

## Build Pardon, replace the installed copy in $(PTT_APP) and start it
ptt:
	@$(PTT_APP_GUARD)
	./ptt/build.sh
	@/usr/bin/pkill -x Pardon || true; \
	for i in 1 2 3 4 5 6 7 8 9 10; do /usr/bin/pgrep -x Pardon >/dev/null || break; sleep 0.5; done; \
	if /usr/bin/pgrep -x Pardon >/dev/null; then echo "Pardon did not quit within 5 s; quit it from its menu and run make ptt again"; exit 1; fi
	@mkdir -p "$$(dirname "$(PTT_APP)")" && rm -rf "$(PTT_APP)" && \
	/usr/bin/ditto ptt/build/Pardon.app "$(PTT_APP)" && /usr/bin/open "$(PTT_APP)"
	@echo "Pardon installed at $(PTT_APP); its mic icon is in the menu bar; grant Microphone and Accessibility when asked (see ptt/README.md)"

## Compile Pardon unsigned into a temp dir and run its self-test (no GUI, mic or network)
test-ptt:
	@tmp=$$(mktemp -d -t pardon) || exit 1; trap 'rm -rf "$$tmp"' EXIT; \
	BUILD_DIR="$$tmp" SIGN=0 ./ptt/build.sh && "$$tmp/Pardon.app/Contents/MacOS/Pardon" --self-test

## One-time self-signed "Pardon" signing identity, so rebuilds keep their permissions
ptt-cert:
	./ptt/make-cert.sh

stop-ptt:
	@/usr/bin/pkill -x Pardon || true

## Stop Pardon; remove ptt/build and the installed app (not the certificate or the macOS permission entries)
clean-ptt: stop-ptt
	@$(PTT_APP_GUARD)
	rm -rf ptt/build "$(PTT_APP)"
