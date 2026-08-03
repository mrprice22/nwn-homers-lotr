#!/usr/bin/env python3
"""gen-devcrit-map.py — disable the engine's Devastating Critical at its source.

Roadmap: devcrit-roll.

THE PROBLEM
-----------
The first attempt at the rework left the engine's save-or-die in place and tried
to refuse the kill afterwards, from NWNX (devcrit_eff.nss, on
NWNX_ON_EFFECT_APPLIED_BEFORE, discriminated on the internal Death effect type).
UAT proved it does not work: a devastating critical rolled its Fortitude save
and instantly killed the Combat Dummy — which also carries a permanent
EffectImmunity(IMMUNITY_TYPE_DEATH). Two independent death defences failing on
the same hit says the engine's devastating-critical kill is not an ordinary
applied death effect, so nothing downstream of it can be trusted to stop it.

THE FIX
-------
Stop it upstream instead. The engine only considers a devastating critical when
the wielder has the feat named in the weapon's baseitems.2da row, column
`EpicWeaponDevastatingCriticalFeat` (CNWSCreatureStats::GetEpicWeaponDevastating
Critical). Blank that column for every base item in our own hak_2da/baseitems.2da
and the check can never succeed: no save is rolled, no kill happens, for players
and NPCs alike. Nothing else in the row changes — Overwhelming Critical, weapon
focus/specialisation and improved critical live in their own columns and are
untouched, so ordinary critical hits still work exactly as before.

Blanking the column also destroys the base-item -> feat mapping the module needs
to know WHO should get the replacement bonus dice. So this script moves that
mapping into a generated NWScript include, unpacked/devcrit_map_inc.nss, which
devcrit_atk.nss uses to grant the dice on an ordinary critical instead.

IDEMPOTENCE
-----------
After the first --apply the 2DA column is blank, so the mapping can no longer be
read from it. From then on the generated include IS the source of truth and this
script reads the mapping back out of it. Re-running is therefore safe and a
no-op. tests/check_devcrit.py gates both halves: the column stays blank and the
include stays populated.

USAGE
-----
    python3 bin/gen-devcrit-map.py             # dry run (default)
    python3 bin/gen-devcrit-map.py --apply     # write both files

AFTER APPLYING the hak must be rebuilt and republished, or the change is not in
the game at all:

    bin/build-lotr-rules-hak --install
    bin/refresh-nwsync            # so clients get the same table
    restart the server
"""
import argparse
import re
import shlex
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
BASEITEMS = REPO / "hak_2da" / "baseitems.2da"
INCLUDE = REPO / "unpacked" / "devcrit_map_inc.nss"

COLUMN = "EpicWeaponDevastatingCriticalFeat"
BLANK = "****"


def read_2da(path):
    """(preamble lines, header fields, [(raw line, fields)], newline)."""
    # Bytes, not read_text: universal-newline translation would hide the CRLF
    # endings this file has, and rewriting a 2DA with LF endings is a 513-line
    # diff that buries the four cells we actually changed.
    text = path.read_bytes().decode("latin-1")
    newline = "\r\n" if "\r\n" in text else "\n"
    lines = text.replace("\r\n", "\n").split("\n")

    header_at = next(i for i, ln in enumerate(lines) if ln.split()[:1] == ["Name"]
                     or COLUMN in ln)
    header = lines[header_at].split()
    body = [(ln, shlex.split(ln)) for ln in lines[header_at + 1:] if ln.strip()]
    return lines[:header_at + 1], header, body, newline


def mapping_from_2da(header, body):
    """{base item row: feat id} for every row that still names a feat."""
    col = header.index(COLUMN) + 1     # +1: the row number is not in the header
    out = {}
    for _, fields in body:
        if len(fields) <= col:
            continue
        value = fields[col]
        if value == BLANK or not value.isdigit():
            continue
        out[int(fields[0])] = int(value)
    return out


def mapping_from_include():
    """Read the mapping back out of the generated include."""
    if not INCLUDE.is_file():
        return {}
    text = INCLUDE.read_text(encoding="latin-1")
    return {int(item): int(feat) for item, feat in
            re.findall(r"case\s+(\d+):\s*return\s+(\d+);", text)}


def blank_column(header, body, newline, preamble):
    """The 2DA with COLUMN set to **** on every row. Column widths are not
    preserved verbatim (2DA is whitespace-delimited); the file stays aligned
    enough to read, and the engine does not care."""
    col = header.index(COLUMN) + 1
    changed = 0
    out = list(preamble)
    for raw, fields in body:
        if len(fields) > col and fields[col] != BLANK:
            # Substitute in place in the RAW line so every other cell — including
            # any quoted string with spaces in it — is byte-for-byte untouched.
            pattern = re.compile(
                r"^((?:\s*(?:\"[^\"]*\"|\S+)){%d}\s+)(\"[^\"]*\"|\S+)" % col)
            match = pattern.match(raw)
            if not match:
                print(f"error: cannot locate column {col} in row {fields[0]}",
                      file=sys.stderr)
                sys.exit(1)
            tail = raw[match.end(2):]
            # Keep the column alignment: give back (or borrow) the width
            # difference from the run of spaces that follows the cell.
            pad = len(match.group(2)) - len(BLANK)
            if pad > 0:
                tail = " " * pad + tail
            elif pad < 0:
                strip = min(-pad, len(tail) - len(tail.lstrip(" ")))
                tail = tail[strip:]
            raw = match.group(1) + BLANK + tail
            changed += 1
        out.append(raw)
    return newline.join(out) + newline, changed


def render_include(mapping):
    lines = [
        # ASCII only: NWScript source with non-ASCII bytes in a comment is a
        # known compile trap in this module (see CLAUDE-gotchas.md).
        "// devcrit_map_inc.nss - GENERATED by bin/gen-devcrit-map.py. Do not edit.",
        "//",
        "// The base item -> Devastating Critical feat mapping that USED to live in",
        "// baseitems.2da's EpicWeaponDevastatingCriticalFeat column. That column is",
        "// blanked in hak_2da/baseitems.2da so the engine can never roll its",
        "// save-or-die (roadmap devcrit-roll); this table is what is left of it, and",
        "// it is how devcrit_atk.nss knows whose critical hit earns the bonus dice",
        "// that replaced the instant kill.",
        "//",
        "// Regenerate with:  python3 bin/gen-devcrit-map.py --apply",
        "",
        "// The feat that grants Devastating Critical with nBaseItem, or -1 for a",
        "// base item that never had one (every non-weapon, and a few weapons).",
        "int DevCrit_WeaponFeat(int nBaseItem);",
        "",
        "int DevCrit_WeaponFeat(int nBaseItem)",
        "{",
        "    switch (nBaseItem)",
        "    {",
    ]
    for item in sorted(mapping):
        lines.append(f"        case {item}: return {mapping[item]};")
    lines += [
        "    }",
        "    return -1;",
        "}",
        "",
    ]
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--apply", action="store_true",
                    help="write the files (default is a dry run)")
    args = ap.parse_args()

    preamble, header, body, newline = read_2da(BASEITEMS)
    if COLUMN not in header:
        print(f"error: {BASEITEMS} has no {COLUMN} column", file=sys.stderr)
        return 1

    from_2da = mapping_from_2da(header, body)
    from_include = mapping_from_include()

    # After the first apply the 2DA is blank and the include is the record.
    mapping = dict(from_include)
    mapping.update(from_2da)

    if not mapping:
        print("error: no mapping in either hak_2da/baseitems.2da or "
              f"{INCLUDE.name} — refusing to write an empty table, which would "
              "silently disable the bonus dice for every weapon.",
              file=sys.stderr)
        return 1

    text, changed = blank_column(header, body, newline, preamble)
    include = render_include(mapping)

    print(f"[devcrit] {len(mapping)} base item(s) map to a devastating "
          f"critical feat ({len(from_2da)} still in the 2DA, "
          f"{len(from_include)} already in the include)")
    print(f"[devcrit] baseitems.2da: {changed} row(s) to blank")

    if not args.apply:
        print("[devcrit] dry run — nothing written (use --apply)")
        return 0

    BASEITEMS.write_bytes(text.encode("latin-1"))
    INCLUDE.write_bytes(include.encode("ascii"))
    print(f"[devcrit] wrote {BASEITEMS.relative_to(REPO)} and "
          f"{INCLUDE.relative_to(REPO)}")
    print("[devcrit] NOW REBUILD THE HAK: bin/build-lotr-rules-hak --install "
          "(then bin/refresh-nwsync and restart) — the 2DA change is not in the "
          "game until the hak clients and server load is rebuilt.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
