#!/usr/bin/env python3
"""ascii-clean-nss.py - replace UTF-8 typographic characters in unpacked/*.nss.

WHY
---
NWN reads script text as windows-1252, one byte per character. A UTF-8 em dash
written into a string literal is three bytes there, and the game renders it as
the three-character garbage the admin caught on the Hall of Champions sign:

    "Your account - 10 most recent tests"   written with an em dash
    "Your account a<EUR>" 10 most recent tests"   what the player actually reads

It is a recurring slip in machine-written scripts (798 em dashes across 406
files at the time this was written), it is invisible in a diff, and in comments
it is also a known compile trap (CLAUDE-gotchas.md). So it gets purged and
gated rather than fixed one string at a time.

WHAT IT DOES *NOT* TOUCH - read this before widening the rule
------------------------------------------------------------
NWN colour tags are literal high bytes: COLOR_RED in unpacked/color.nss is
`"<c\\xfe\\x20\\x20>"`, and scripts all over the module embed the same thing
inline. Those bytes are DATA, not text - rewriting them changes the colour or
breaks the tag. Which is why this tool (and tests/check_ascii_nss.py) works on
a curated list of UTF-8 SEQUENCES for known typographic characters instead of
"any byte over 127", and additionally skips any match sitting inside a `<c...>`
tag. A blanket high-byte rule would corrupt every coloured string in the module.

USAGE
-----
    python3 bin/ascii-clean-nss.py            # dry run: list every hit
    python3 bin/ascii-clean-nss.py --apply    # rewrite the files
"""
import argparse
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
UNPACKED = REPO / "unpacked"

# The characters that actually turn up, plus the rest of the usual machine-text
# set so a future slip is caught the first time rather than the second.
REPLACEMENTS = {
    "—": "-",      # em dash
    "–": "-",      # en dash
    "‘": "'",      # left single quote
    "’": "'",      # right single quote / apostrophe
    "‚": ",",      # single low quote
    "“": '"',      # left double quote
    "”": '"',      # right double quote
    "„": '"',      # double low quote
    "…": "...",    # ellipsis
    "•": "*",      # bullet
    "→": "->",     # right arrow
    "←": "<-",     # left arrow
    "⇒": "=>",     # double right arrow
    " ": " ",      # non-breaking space
    "°": " degrees",
    "×": "x",      # multiplication sign
    "≠": "!=",
    "≤": "<=",
    "≥": ">=",
    "½": "1/2",
    "¼": "1/4",
    "¾": "3/4",
    "™": "(TM)",
    "®": "(R)",
    "©": "(C)",
}
# NOT in the list, deliberately: U+FFFD. Its UTF-8 bytes (EF BF BD) also occur
# as the three raw colour bytes inside real <c...> tags in this module
# (deathalert.nss and friends), and there is no way to tell a mangled character
# from a colour from the bytes alone. Leave them.


def protected_ranges(raw):
    """Byte ranges that are colour data, not text: the three bytes of a
    well-formed `<cRGB>` tag. Any of the three can coincidentally be part of a
    valid UTF-8 sequence, and rewriting it changes the colour or breaks the
    tag."""
    spans = []
    at = raw.find(b"<c")
    while at >= 0:
        if raw[at + 5:at + 6] == b">":
            spans.append((at + 2, at + 5))
        at = raw.find(b"<c", at + 1)
    return spans


def find_hits(raw):
    """[(offset, utf8 bytes, replacement)] for every rewritable sequence."""
    spans = protected_ranges(raw)
    hits = []
    for char, ascii_text in REPLACEMENTS.items():
        needle = char.encode("utf-8")
        start = 0
        while True:
            at = raw.find(needle, start)
            if at < 0:
                break
            start = at + 1
            end = at + len(needle)
            if any(lo < end and at < hi for lo, hi in spans):
                continue        # colour data, leave it alone
            hits.append((at, needle, ascii_text.encode("ascii")))
    return sorted(hits)


def clean(raw, hits):
    out = bytearray()
    at = 0
    for offset, needle, ascii_bytes in hits:
        out += raw[at:offset]
        out += ascii_bytes
        at = offset + len(needle)
    out += raw[at:]
    return bytes(out)


def line_of(raw, offset):
    return raw.count(b"\n", 0, offset) + 1


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--apply", action="store_true",
                    help="rewrite the files (default is a dry run)")
    args = ap.parse_args()

    files = 0
    total = 0
    for path in sorted(UNPACKED.glob("*.nss")):
        raw = path.read_bytes()
        if all(byte < 128 for byte in raw):
            continue
        hits = find_hits(raw)
        if not hits:
            continue
        files += 1
        total += len(hits)
        if not args.apply:
            shown = hits[:3]
            where = ", ".join(f"line {line_of(raw, off)}" for off, _, _ in shown)
            more = "" if len(hits) <= 3 else f", +{len(hits) - 3} more"
            print(f"  {path.name}: {len(hits)} hit(s) ({where}{more})")
        else:
            path.write_bytes(clean(raw, hits))

    print(f"[ascii] {total} character(s) in {files} file(s)")
    if not args.apply:
        print("[ascii] dry run - nothing written (use --apply)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
