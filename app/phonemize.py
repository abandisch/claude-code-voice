"""
Text -> Kokoro phoneme string, using Debian's espeak-ng binary.

espeak-ng emits IPA. Kokoro was trained on a slightly different phoneme
inventory (it folds diphthongs and affricates into single symbols), so the
table below maps espeak's output onto Kokoro's vocabulary.
"""
import re
import subprocess

# Longest patterns first so e.g. "tʃ" is handled before "t".
_ESPEAK_TO_KOKORO = [
    ("tʃ", "ʧ"), ("dʒ", "ʤ"),
    ("eɪ", "A"), ("aɪ", "I"), ("aʊ", "W"), ("ɔɪ", "Y"), ("oʊ", "O"), ("əʊ", "Q"),
    ("ɚ", "əɹ"), ("r", "ɹ"), ("x", "k"), ("ç", "k"), ("ɐ", "ə"), ("ʔ", "t"), ("ɬ", "l"),
    ("ʲ", ""), ("͡", ""), ("̃", ""),   # tie bar, nasalisation
]

# Keep clause punctuation: Kokoro uses it for pauses and intonation.
_CLAUSE = re.compile(r"([,.;:!?…]+)\s*")

_ESPEAK_TIMEOUT_S = 10


def _espeak(text: str, lang: str) -> str:
    out = subprocess.run(
        ["espeak-ng", "-q", "--ipa=3", "-v", lang, "--", text],
        capture_output=True, text=True, encoding="utf-8", check=True, timeout=_ESPEAK_TIMEOUT_S,
    ).stdout
    # --ipa=3 separates phonemes with "_". Map while still separated, so a
    # multi-char pattern only matches inside ONE espeak phoneme, then join.
    for src, dst in _ESPEAK_TO_KOKORO:
        out = out.replace(src, dst)
    return " ".join(out.replace("_", "").split())


def phonemize(text: str, lang: str = "en-gb") -> str:
    """Text -> Kokoro phoneme string, keeping clause punctuation for prosody."""
    parts = _CLAUSE.split(text.strip())          # [text, punct, text, punct, ...]
    pieces = []
    for i in range(0, len(parts), 2):
        segment = parts[i].strip()
        punct = parts[i + 1] if i + 1 < len(parts) else ""
        if segment:
            pieces.append(_espeak(segment, lang) + punct)
        elif punct:
            pieces.append(punct)
    return " ".join(pieces)
