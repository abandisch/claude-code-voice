#!/bin/bash
# Claude Code Notification hook: speak the notification message (e.g. "Claude
# needs your permission to use Bash") through the local Kokoro container, so
# you hear when a session is waiting on you. Falls back to macOS `say`.
# Reads the hook's JSON on stdin; settings are the variables below, which
# VOICE= / SPEED= lines in ~/.claude/hooks/pardon.conf override.
# No set -e, and every path exits 0: a hook must never break the Claude Code session.
VOICE="bf_emma"
SPEED="1.0"
FALLBACK_SAY_VOICE="Daniel (Enhanced)"
URL="http://127.0.0.1:8880/speak"

# Muted? (make mute / make unmute)
[ -f "$HOME/.claude/hooks/mute" ] && exit 0

# Voice and speed chosen in Pardon's menu. Matched by whole-line pattern, never executed.
# Pattern, 512-byte cap and byte rules must match ptt/Sources/PardonKit/Speech/SpeechConf.swift.
conf="$HOME/.claude/hooks/pardon.conf"
if [ -f "$conf" ]; then
  # A NUL, or a line cut by the cap (marked Z), spoils its line; C locale so no byte stops sed.
  cut=; [ "$(head -c 513 "$conf" 2>/dev/null | wc -c)" -gt 512 ] && cut=Z
  v=$({ head -c 512 "$conf" 2>/dev/null; printf '%s' "$cut"; } | LC_ALL=C tr '\000' '#' \
    | LC_ALL=C sed -nE '/^VOICE=[a-z]{2}_[a-z]{1,20}$/{s/^VOICE=//p;q;}')
  s=$({ head -c 512 "$conf" 2>/dev/null; printf '%s' "$cut"; } | LC_ALL=C tr '\000' '#' \
    | LC_ALL=C sed -nE '/^SPEED=[0-9]\.[0-9]$/{s/^SPEED=//p;q;}')
  [ -n "$v" ] && VOICE="$v"
  [ -n "$s" ] && SPEED="$s"
fi

input=$(cat)
msg=$(printf '%s' "$input" | /usr/bin/jq -r '.message // empty')
[ -n "$msg" ] || exit 0

# Skip the ~60s idle reminder ("Claude is waiting for your input"), it fires
# whenever you pause to think. Permission requests are the announcements worth
# hearing.
case "$msg" in *"waiting for your input"*) exit 0;; esac

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
