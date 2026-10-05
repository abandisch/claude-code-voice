#!/bin/bash
# Test both hooks' pardon.conf handling, mute and say fallback without Docker or audio:
# stub curl, afplay and say record their calls; HOME is a fresh temp dir under $TMPDIR.
#
# Run from anywhere:  ./hook/test-hooks.sh   (or: make test-hooks)
set -uo pipefail
cd "$(dirname "$0")"

JQ=/usr/bin/jq
root=$(mktemp -d "${TMPDIR:-/tmp}/test-hooks.XXXXXX") || { echo "FAIL: mktemp"; exit 1; }
trap 'rm -rf "$root"' EXIT

stubs="$root/stubs"
mkdir -p "$stubs"
cat > "$stubs/curl" <<'EOF'
#!/bin/bash
echo called >> "$STUB_LOG/curl"
while [ $# -gt 0 ]; do [ "$1" = -d ] && { printf '%s' "$2" > "$STUB_LOG/body"; shift; }; shift; done
[ -z "${CURL_FAIL:-}" ] || exit 7
EOF
for t in afplay say; do printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "$STUB_LOG/%s"\n' "$t" > "$stubs/$t"; done
chmod +x "$stubs"/*

SPEAK_IN='{"last_assistant_message":"All done.\n🔊 Hello there."}'
NOTIFY_IN='{"message":"Claude needs your permission"}'

pass=0 fail=0 n=0
check() {  # $1 = name, then a command that must succeed
  local name="$1"; shift
  if "$@"; then pass=$((pass + 1)); echo "ok   $name"; else fail=$((fail + 1)); echo "FAIL $name"; fi
}

# run <hook> <mode: none|dir|mute|text|bytes> [conf text, or a printf format for bytes]; sets H and RC
# The hooks run under the usual macOS locale, where sed rejects invalid UTF-8 unless told otherwise.
run() {
  local hook="$1" mode="$2" text="${3:-}" input
  n=$((n + 1)); H="$root/home$n"; mkdir -p "$H/.claude/hooks" "$H/log"
  case "$mode" in
    dir)  mkdir "$H/.claude/hooks/pardon.conf" ;;
    mute) touch "$H/.claude/hooks/mute" ;;
    text) printf '%s' "$text" > "$H/.claude/hooks/pardon.conf" ;;
    bytes) printf "$text" > "$H/.claude/hooks/pardon.conf" ;;
  esac
  [ "$hook" = speak-kokoro.sh ] && input="$SPEAK_IN" || input="$NOTIFY_IN"
  printf '%s' "$input" | env -u LC_ALL -u LC_CTYPE LANG=en_US.UTF-8 HOME="$H" PATH="$stubs:/usr/bin:/bin" STUB_LOG="$H/log" \
    CURL_FAIL="${CURL_FAIL:-}" bash "./$hook" >/dev/null 2>&1
  RC=$?
}

body_is() {  # $1 = voice, $2 = speed
  [ -f "$H/log/body" ] && $JQ -e --arg v "$1" --argjson s "$2" \
    '.voice == $v and (.speed | type) == "number" and .speed == $s' "$H/log/body" >/dev/null
}
exit0()     { [ "$RC" -eq 0 ]; }
no_pwned()  { [ ! -e "$H/pwned" ]; }
not_called() { [ ! -e "$H/log/curl" ] && [ ! -e "$H/log/afplay" ] && [ ! -e "$H/log/say" ]; }
said()      { [ -s "$H/log/say" ] && [ ! -e "$H/log/afplay" ]; }

letters() { printf 'a%.0s' $(seq "$1"); }
pad() { printf '#%0*d' $(($1 - 2)) 0; }  # a comment line of $1 bytes once its newline is added
long="VOICE=bf_$(letters 21)"
junk=$(for b in $(seq 0 255); do printf '\\%03o' "$b"; done)
hostile=(
  'VOICE=$(touch "$HOME/pwned")'
  'VOICE=`touch $HOME/pwned`'
  'VOICE=bf_emma; touch $HOME/pwned'
  'VOICE="bm_fable"'
  $'VOICE=bm_fable\r'
  'VOICE=BM_FABLE'
  "$long"
  'SPEED=1.3; touch $HOME/pwned'
  'SPEED=10'
  'SPEED=1.25'
  'SPEED=abc'
  '  VOICE=bm_fable'
)

for hook in speak-kokoro.sh notify-kokoro.sh; do
  run "$hook" none
  check "$hook: no conf -> bf_emma 1.0" body_is bf_emma 1.0
  check "$hook: no conf exits 0" exit0
  check "$hook: no conf plays the wav" test -s "$H/log/afplay"

  run "$hook" text $'VOICE=bm_fable\nSPEED=1.3\n'
  check "$hook: valid conf -> bm_fable 1.3" body_is bm_fable 1.3
  check "$hook: valid conf exits 0" exit0

  run "$hook" text $'VOICE=am_adam\n'
  check "$hook: voice only -> am_adam 1.0" body_is am_adam 1.0

  run "$hook" text $'SPEED=0.8\n'
  check "$hook: speed only -> bf_emma 0.8" body_is bf_emma 0.8

  run "$hook" text $'VOICE=am_adam\nVOICE=bm_fable\nSPEED=0.9\nSPEED=1.5\n'
  check "$hook: first valid line of each kind wins -> am_adam 0.9" body_is am_adam 0.9

  run "$hook" text $'VOICE=bm_fable\nSPEED=1.3'
  check "$hook: no trailing newline -> bm_fable 1.3" body_is bm_fable 1.3

  run "$hook" text 'VOICE=zz_a'$'\n'
  check "$hook: shortest voice zz_a accepted" body_is zz_a 1.0
  run "$hook" text "VOICE=zz_$(letters 20)"$'\n'
  check "$hook: 20-letter voice name accepted" body_is "zz_$(letters 20)" 1.0
  run "$hook" text "VOICE=zz_$(letters 21)"$'\n'
  check "$hook: 21-letter voice name -> defaults" body_is bf_emma 1.0

  run "$hook" text "$(pad 512)"$'\nVOICE=bm_fable\nSPEED=1.3\n'
  check "$hook: lines past the 512-byte cap -> defaults" body_is bf_emma 1.0
  run "$hook" text "$(pad 497)"$'\nVOICE=bm_fable\nSPEED=1.3\n'
  check "$hook: voice line ending at byte 512 accepted" body_is bm_fable 1.0
  run "$hook" text "$(pad 501)"$'\nVOICE=bm_fable\n'
  check "$hook: voice line cut by the cap -> defaults" body_is bf_emma 1.0
  run "$hook" text "$(pad 498)"$'\nVOICE=bm_fable\n'
  check "$hook: newline just past the cap -> defaults" body_is bf_emma 1.0
  run "$hook" text "$(pad 498)"$'\nVOICE=bm_fable'
  check "$hook: 512-byte file without trailing newline accepted" body_is bm_fable 1.0

  run "$hook" bytes 'X=\377\nVOICE=bm_fable\n'
  check "$hook: invalid UTF-8 line skipped -> bm_fable" body_is bm_fable 1.0
  run "$hook" bytes "$junk"'\nVOICE=am_adam\n'
  check "$hook: binary junk skipped -> am_adam" body_is am_adam 1.0
  check "$hook: binary junk exits 0" exit0
  run "$hook" bytes 'VOICE=bm_fable\000\nSPEED=1.3\n'
  check "$hook: NUL inside a value -> bf_emma, next line still read" body_is bf_emma 1.3
  run "$hook" bytes 'VOICE=\314\201bm_fable\n'
  check "$hook: combining mark after the prefix -> defaults" body_is bf_emma 1.0

  for line in "${hostile[@]}"; do
    label=$(printf '%q' "$line")
    run "$hook" text "$line"$'\n'
    check "$hook: hostile $label -> defaults" body_is bf_emma 1.0
    check "$hook: hostile $label not executed" no_pwned
    check "$hook: hostile $label exits 0" exit0
  done

  run "$hook" dir
  check "$hook: conf is a directory -> defaults" body_is bf_emma 1.0
  check "$hook: conf is a directory exits 0" exit0

  run "$hook" mute
  check "$hook: muted -> curl, afplay, say never called" not_called
  check "$hook: muted exits 0" exit0

  CURL_FAIL=1 run "$hook" text $'VOICE=bm_fable\n'
  check "$hook: curl fails -> say fallback" said
  check "$hook: curl fails exits 0" exit0
done

echo "test-hooks: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
