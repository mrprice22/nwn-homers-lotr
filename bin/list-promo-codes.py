#!/usr/bin/env python3
"""Print all promo/redemption codes defined in code_redeem.nss."""

import re
import sys
from datetime import date
from pathlib import Path

SCRIPT = Path(__file__).parent.parent / "unpacked" / "code_redeem.nss"

# Descriptions inferred from the ApplyCodeBenefit block.
# Each entry is (pattern-to-match-in-benefit-block, human-readable note).
BENEFIT_PATTERNS = [
    (r'SetXP\(oPC,\s*(\d+)\)',         lambda m: f"Sets XP to {int(m.group(1)):,}"),
    (r'GiveXPToCreature\(oPC,\s*(\d+)\)', lambda m: f"Grants {int(m.group(1)):,} XP"),
    (r'CreateItemOnObject\("([^"]+)",\s*oPC\)', lambda m: f'Creates item "{m.group(1)}"'),
    (r'for.*?CreateItemOnObject\("([^"]+)"', lambda m: f'Creates item "{m.group(1)}" ×3'),
]


def parse_codes(src: str) -> dict[str, dict]:
    """Return {code: {expiry, benefit}} by parsing the two switch-like blocks."""
    codes: dict[str, dict] = {}

    # GetCodeExpiration: if (sCodeLower == "xxx") return "YYYY-MM-DD";
    for m in re.finditer(r'if\s*\(\s*sCodeLower\s*==\s*"([^"]+)"\s*\)\s*return\s*"(\d{4}-\d{2}-\d{2})"', src):
        codes[m.group(1)] = {"expiry": m.group(2), "benefit": ""}

    # ApplyCodeBenefit: find each if-block keyed by code, then the lines inside it.
    benefit_blocks = re.findall(
        r'if\s*\(\s*sCodeLower\s*==\s*"([^"]+)"\s*\)\s*\{([^}]+)\}', src, re.DOTALL
    )
    for code, body in benefit_blocks:
        if code not in codes:
            continue
        note = ""
        for pattern, describe in BENEFIT_PATTERNS:
            m = re.search(pattern, body, re.DOTALL)
            if m:
                note = describe(m)
                break
        if not note:
            note = body.strip().splitlines()[0].strip()
        codes[code]["benefit"] = note

    return codes


def main() -> None:
    if not SCRIPT.exists():
        print(f"ERROR: {SCRIPT} not found", file=sys.stderr)
        sys.exit(1)

    src = SCRIPT.read_text()
    codes = parse_codes(src)
    if not codes:
        print("No codes found.")
        return

    today = date.today().isoformat()
    col_w = max(len(c) for c in codes) + 2

    print(f"{'CODE':<{col_w}}  {'EXPIRES':<12}  {'STATUS':<8}  BENEFIT")
    print("-" * (col_w + 38 + 20))
    for code, info in sorted(codes.items()):
        expiry = info["expiry"]
        status = "EXPIRED" if expiry < today else "active "
        print(f"{code:<{col_w}}  {expiry:<12}  {status:<8}  {info['benefit']}")


if __name__ == "__main__":
    main()
