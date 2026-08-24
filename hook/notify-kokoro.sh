#!/bin/bash
# Claude Code Notification hook: speak the notification message (e.g. "Claude
# needs your permission to use Bash") through the local Kokoro container, so
# you hear when a session is waiting on you. Falls back to macOS `say`.
VOICE="bf_emma"
SPEED="1.0"
FALLBACK_SAY_VOICE="Daniel (Enhanced)"
URL="http://127.0.0.1:8880/speak"

# Muted? (make mute / make unmute)
[ -f "$HOME/.claude/hooks/mute" ] && exit 0

input=$(cat)
msg=$(printf '%s' "$input" | /usr/bin/jq -r '.message // empty')
[ -n "$msg" ] || exit 0

# Kokoro garbles prosody around em/en dashes; speak them as commas instead.
msg=$(printf '%s' "$msg" | sed 's/[[:space:]]*[—–][[:space:]]*/, /g')

wav=$(mktemp -t kokoro)  # afplay sniffs the format; no .wav suffix needed
body=$(/usr/bin/jq -cn --arg t "$msg" --arg v "$VOICE" --argjson s "$SPEED" '{text:$t, voice:$v, speed:$s}')
if curl -sf --max-time 15 -X POST "$URL" -H 'Content-Type: application/json' -d "$body" -o "$wav"; then
  afplay "$wav"
else
  say -v "$FALLBACK_SAY_VOICE" -r 165 "$msg"
fi
rm -f "$wav"
exit 0
