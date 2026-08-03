#!/usr/bin/env python3
"""Build gate: no UTF-8 typographic characters in unpacked/*.nss.

NWN reads script text as windows-1252, one byte per character. A UTF-8 em dash
in a string literal is three bytes there and reaches the player as garbage --
"Your account a<EUR>" 10 most recent tests" on the Hall of Champions sign is the
one that got caught by eye. In a comment the same bytes are a known compile trap
(CLAUDE-gotchas.md). Neither is visible in a diff, and both are a recurring slip
in machine-written scripts, so the build refuses them.

The rule is deliberately NOT "any byte over 127": NWN colour tags are literal
high bytes (COLOR_RED in unpacked/color.nss is "<c\\xfe\\x20\\x20>", and scripts
embed the same thing inline everywhere). Those bytes are data. So this checks
for the UTF-8 encodings of a fixed list of typographic characters, and ignores
any match that sits inside a well-formed <cRGB> tag.

Fix a failure with:  python3 bin/ascii-clean-nss.py --apply
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "bin"))

import importlib.util

spec = importlib.util.spec_from_file_location(
    "ascii_clean_nss", ROOT / "bin" / "ascii-clean-nss.py")
ascii_clean = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ascii_clean)

errors = []

for path in sorted((ROOT / "unpacked").glob("*.nss")):
    raw = path.read_bytes()
    if all(byte < 128 for byte in raw):
        continue
    for offset, needle, replacement in ascii_clean.find_hits(raw):
        errors.append(
            f"{path.name}:{ascii_clean.line_of(raw, offset)}: "
            f"{needle.decode('utf-8')!r} (write {replacement.decode()!r})")

if errors:
    print("check_ascii_nss: FAIL")
    for err in errors[:40]:
        print("  - " + err)
    if len(errors) > 40:
        print(f"  ... and {len(errors) - 40} more")
    print("  Fix all of them with: python3 bin/ascii-clean-nss.py --apply")
    sys.exit(1)

print("check_ascii_nss: ok (no UTF-8 typography in any script)")
sys.exit(0)
