#!/bin/bash
# Claude Code Stop hook: speak the 🔊 summary line through the local Kokoro
# container. Falls back to macOS `say` if the container is not running.
VOICE="bm_lewis"
SPEED="1.0"
FALLBACK_SAY_VOICE="Daniel (Enhanced)"
URL="http://127.0.0.1:8880/speak"

input=$(cat)

# Prefer the message Claude Code hands us directly: the transcript file can lag
# behind the Stop event, which makes a transcript scan speak the previous turn.
line=$(printf '%s' "$input" | /usr/bin/jq -r '.last_assistant_message // empty' \
  | grep '^🔊' | tail -1 | sed 's/^🔊[[:space:]]*//')

if [ -z "$line" ]; then
  transcript=$(printf '%s' "$input" | /usr/bin/jq -r '.transcript_path // empty')
  [ -r "$transcript" ] || exit 0
  line=$(tail -n 200 "$transcript" \
    | /usr/bin/jq -r 'select(.type == "assistant") | .message.content[]? | select(.type == "text") | .text' 2>/dev/null \
    | grep '^🔊' | tail -1 | sed 's/^🔊[[:space:]]*//')
fi
[ -n "$line" ] || exit 0

wav=$(mktemp -t kokoro)  # afplay sniffs the format; no .wav suffix needed
body=$(/usr/bin/jq -cn --arg t "$line" --arg v "$VOICE" --argjson s "$SPEED" '{text:$t, voice:$v, speed:$s}')
if curl -sf --max-time 15 -X POST "$URL" -H 'Content-Type: application/json' -d "$body" -o "$wav"; then
  afplay "$wav"
else
  say -v "$FALLBACK_SAY_VOICE" -r 165 "$line"
fi
rm -f "$wav"
exit 0
