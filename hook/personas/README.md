# Personas

A persona changes how Claude *writes* the 🔊 line — the voice model just reads
it. Pick one, copy its block into your global `~/.claude/CLAUDE.md` (replace
the optional persona comment that `make install` added), start a new session.

Mix freely: edit the wording, swap the suggested voice (`VOICE=` in
`~/.claude/hooks/speak.sh` and `notify.sh`), or write your own — it's one
paragraph of instructions, nothing more.

| Persona | Flavour | Suggested voice |
|---|---|---|
| [butler](butler.md) | unflappable British valet | `bm_fable` or `bm_daniel` |
| [ships-computer](ships-computer.md) | calm starship status reports | `bf_emma` |
| [laconic-sysadmin](laconic-sysadmin.md) | dry, seen-it-all, minimal | `am_adam` |
| [noir-detective](noir-detective.md) | hard-boiled case notes | `am_fenrir` |
