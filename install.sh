#!/bin/bash
# Install the Claude Code voice hooks on this Mac. Idempotent; safe to re-run.
#
#   1. checks prerequisites (Apple Silicon, docker, jq, running container)
#   2. installs hook/speak-kokoro.sh  as ~/.claude/hooks/speak.sh   (Stop: 🔊 line)
#      and     hook/notify-kokoro.sh as ~/.claude/hooks/notify.sh  (Notification:
#      announces when Claude is waiting on you); backs up any old copies
#   3. registers both hooks in ~/.claude/settings.json (backs it up first)
#   4. appends hook/CLAUDE-snippet.md to ~/.claude/CLAUDE.md if the 🔊 rule is absent
#
# Run from the repo root:  ./install.sh   (or: make install)
set -euo pipefail
cd "$(dirname "$0")"

CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
SETTINGS="$CLAUDE_DIR/settings.json"
GLOBAL_MD="$CLAUDE_DIR/CLAUDE.md"
JQ="${JQ:-/usr/bin/jq}"
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
die()  { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

echo "Prerequisites"
[ "$(uname -s)" = Darwin ] && [ "$(uname -m)" = arm64 ] || die "needs macOS on Apple Silicon (image is linux/arm64; hook uses afplay/say)"
ok "macOS arm64"
[ -x "$JQ" ] || { [ -x /opt/homebrew/bin/jq ] && JQ=/opt/homebrew/bin/jq; } || die "jq not found (/usr/bin/jq on macOS 15+, or: brew install jq)"
ok "jq at $JQ"
command -v docker >/dev/null || die "docker not found — install Docker Desktop"
ok "docker"
if curl -sf --max-time 2 http://127.0.0.1:8880/health >/dev/null; then
  ok "kokoro container answering on 127.0.0.1:8880"
else
  warn "container not answering — run 'make build && make run' first; hooks will fall back to 'say' until it is up"
fi
[ -d "$CLAUDE_DIR" ] || die "$CLAUDE_DIR not found — install Claude Code and run it once"

echo "Hooks"
mkdir -p "$CLAUDE_DIR/hooks"
install_hook() {  # $1 = repo source, $2 = installed name
  local src="hook/$1" dst="$CLAUDE_DIR/hooks/$2"
  if [ -f "$dst" ] && ! cmp -s "$src" "$dst"; then
    cp "$dst" "$dst.bak.$(date +%Y%m%d%H%M%S)"
    warn "existing $2 backed up (your VOICE/SPEED edits live in the .bak)"
  fi
  cp "$src" "$dst" && chmod +x "$dst"
  ok "installed $dst"
}
install_hook speak-kokoro.sh speak.sh
install_hook notify-kokoro.sh notify.sh

echo "settings.json"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
SETTINGS_BACKED_UP=""
register_hook() {  # $1 = event name, $2 = installed script name
  local event="$1" script="$2"
  if "$JQ" -e --arg e "$event" --arg s "hooks/$script" \
      '.hooks[$e][]?.hooks[]? | select(.command | contains($s))' "$SETTINGS" >/dev/null; then
    ok "$event hook already registered"
  else
    if [ -z "$SETTINGS_BACKED_UP" ]; then
      cp "$SETTINGS" "$SETTINGS.bak.$(date +%Y%m%d%H%M%S)"
      SETTINGS_BACKED_UP=1
    fi
    "$JQ" --arg e "$event" --arg c "bash ~/.claude/hooks/$script" \
      '.hooks[$e] = ((.hooks[$e] // []) + [{"hooks":[{"type":"command","command":$c,"timeout":30}]}])' \
      "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
    ok "$event hook added (backup kept alongside)"
  fi
}
register_hook Stop speak.sh
register_hook Notification notify.sh

echo "Global CLAUDE.md"
if [ -f "$GLOBAL_MD" ] && grep -q '🔊' "$GLOBAL_MD"; then
  ok "🔊 rule already present in $GLOBAL_MD"
else
  { [ -f "$GLOBAL_MD" ] && [ -s "$GLOBAL_MD" ] && printf '\n'; cat hook/CLAUDE-snippet.md; } >> "$GLOBAL_MD"
  ok "appended hook/CLAUDE-snippet.md to $GLOBAL_MD (edit the optional persona line as you like)"
fi

echo
echo "Done. Start a new Claude Code session and ask it anything — you should hear the 🔊 line."
