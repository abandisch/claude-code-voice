#!/bin/bash
# Install the Claude Code voice hook on this Mac. Idempotent; safe to re-run.
#
#   1. checks prerequisites (Apple Silicon, docker, jq, running container)
#   2. installs hook/speak-kokoro.sh as ~/.claude/hooks/speak.sh (backs up any old one)
#   3. adds the Stop hook to ~/.claude/settings.json (backs it up first)
#   4. appends hook/CLAUDE-snippet.md to ~/.claude/CLAUDE.md if the 🔊 rule is absent
#
# Run from the repo root:  ./install.sh   (or: make install)
set -euo pipefail
cd "$(dirname "$0")"

CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
HOOK_DST="$CLAUDE_DIR/hooks/speak.sh"
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
  warn "container not answering — run 'make build && make run' first; hook will fall back to 'say' until it is up"
fi
[ -d "$CLAUDE_DIR" ] || die "$CLAUDE_DIR not found — install Claude Code and run it once"

echo "Hook"
mkdir -p "$CLAUDE_DIR/hooks"
if [ -f "$HOOK_DST" ] && ! cmp -s hook/speak-kokoro.sh "$HOOK_DST"; then
  cp "$HOOK_DST" "$HOOK_DST.bak.$(date +%Y%m%d%H%M%S)"
  warn "existing speak.sh backed up"
fi
cp hook/speak-kokoro.sh "$HOOK_DST" && chmod +x "$HOOK_DST"
ok "installed $HOOK_DST"

echo "settings.json"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
if "$JQ" -e '.hooks.Stop[]?.hooks[]? | select(.command | test("hooks/speak\\.sh"))' "$SETTINGS" >/dev/null; then
  ok "Stop hook already registered"
else
  cp "$SETTINGS" "$SETTINGS.bak.$(date +%Y%m%d%H%M%S)"
  "$JQ" '.hooks.Stop = ((.hooks.Stop // []) + [{"hooks":[{"type":"command","command":"bash ~/.claude/hooks/speak.sh","timeout":30}]}])' \
    "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
  ok "Stop hook added (backup kept alongside)"
fi

echo "Global CLAUDE.md"
if [ -f "$GLOBAL_MD" ] && grep -q '🔊' "$GLOBAL_MD"; then
  ok "🔊 rule already present in $GLOBAL_MD"
else
  { [ -f "$GLOBAL_MD" ] && [ -s "$GLOBAL_MD" ] && printf '\n'; cat hook/CLAUDE-snippet.md; } >> "$GLOBAL_MD"
  ok "appended hook/CLAUDE-snippet.md to $GLOBAL_MD (edit the optional persona line as you like)"
fi

echo
echo "Done. Start a new Claude Code session and ask it anything — you should hear the 🔊 line."
