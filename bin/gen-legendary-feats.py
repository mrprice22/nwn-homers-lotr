#!/usr/bin/env python3
"""gen-legendary-feats.py — own the legendary feat rows in hak_2da/feat.2da.

Phase 2 of the Legendary Feats build order (CLAUDE-legendary-feats.md).

THE ARCHITECTURE, IN ONE LINE
-----------------------------
**A legendary feat row carries name, description and icon only.** It has no
engine mechanic. Every effect is applied server-side by script — ability bonuses
as item properties on the PC's skin, other effects as permanent supernatural
effects re-applied at login, spell changes as a branch on GetHasFeat(). That is
what makes "NWN can't express that in a 2DA" entries tractable, and it means
**feat.2da gates nothing**: prerequisites, class restrictions and the level-60
allotment all live in the picker (phase 3), in script, where they can be
arbitrarily expressive.

THE EASIEST BUG TO SHIP
-----------------------
**The engine must never offer a legendary feat on its own level-up feat page.**
The picker is the only grant path; a feat reachable from both is a double-grant.
Every row here therefore sets `ALLCLASSESCANUSE = 0` and is listed in no
`cls_feat_*.2da`, which is what keeps it off every class's selection list.
tests/check_legendary_feats.py asserts that column on every owned row.

THE BASE TABLE
--------------
The module resolves the **stock** feat.2da: **1116 rows (0-1115, last
PLAYER_TOOL_10) and 43 columns**. It does NOT resolve hak_2da/feat.2da's former
contents, which were a byte-identical copy of the table inside
`cep2_add_feats.hak` — **a hak Mod_HakList does not load** (24,771 rows, 44
columns). Building on that copy would have silently added ~23,000 CEP
weapon-of-choice feats and changed the column count. It was a reference extract
and is recoverable from cep2_add_feats.hak if it is ever wanted again.

So: **our rows append at 1116**, rows 0-1115 stay byte-identical, and the gate
asserts both. Re-extracting feat.2da from the game data over the generated file
silently drops every legendary row — seed a fresh base with --from-stock
instead, which preserves our rows and swaps only the base underneath them.

SINGLE SOURCE OF TRUTH
----------------------
FEATS below drives both the 2DA rows and the TLK strings: bin/build-lotr-tlk
imports `tlk_strings()` from this module and appends them to its own block, so a
feat name is typed exactly once. The strref each row points at is derived from
where build-lotr-tlk actually places that string, not from a number written down
twice.

Usage:
    python3 bin/gen-legendary-feats.py                    # dry run
    python3 bin/gen-legendary-feats.py --apply            # write hak_2da/feat.2da
    python3 bin/gen-legendary-feats.py --apply --from-stock /tmp/feat.2da
                                                          # ... reseeding the base

Extract a fresh stock base with (see README.md "Rebuild from scratch"):
    NWN="$HOME/.local/share/Steam/steamapps/common/Neverwinter Nights"
    ~/.nimble/bin/nwn_resman_cat --root "$NWN" \\
      --userdirectory "$HOME/.local/share/Neverwinter Nights" feat.2da > /tmp/feat.2da

Idempotent: a second --apply run reports no changes. Publishing needs the hak
AND the TLK, because the rows point at strrefs that only exist in ours:

    bin/build-lotr-tlk --apply --install
    python3 bin/gen-legendary-feats.py --apply
    bin/build-lotr-rules-hak --install
    bin/refresh-nwsync
    nwn-manager repack
    bin/server-restart
"""
import argparse
import importlib.machinery
import importlib.util
import sys
from dataclasses import dataclass
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
FEAT_2DA = REPO / "hak_2da" / "feat.2da"
TLK_GENERATOR = REPO / "bin" / "build-lotr-tlk"
# Generated: the script-side view of the same table. Scripts must never hand-type
# a feat row number — a renumbered row would silently become a different feat.
IDS_INC = REPO / "unpacked" / "legfeat_ids_inc.nss"

# The stock table's shape. Both are asserted before anything is written: a base
# with a different row count or column count is not the table the module
# resolves, and appending to it would put our rows at the wrong feat IDs.
BASE_ROWS = 1116               # stock rows 0..1115
BASE_COLUMNS = 43              # header columns, excluding the row-index column
FIRST_ROW = BASE_ROWS          # our first feat ID

BLANK = "****"


@dataclass
class Feat:
    """One legendary feat. `effect` is documentation for now — phase 3's picker
    and the per-category behaviour scripts are what read it."""
    label: str                 # 2DA LABEL and nwscript Constant (minus FEAT_)
    name: str                  # TLK string, shown in the feat list
    description: str           # TLK string, shown in the tooltip
    icon: str                  # existing icon resref; we ship no new art yet
    effect: str = ""           # human-readable summary of what the script does
    category: str = ""         # draft section this came from
    # Ability-score feats only: the ABILITY_* constant this boosts and by how
    # much. Generated into legfeat_ids_inc.nss so the picker applies the bonus
    # from the same table that names the feat. -1 = not an ability feat.
    ability: int = -1
    bonus: int = 0


# ---------------------------------------------------------------------------
# The feat table. APPEND ONLY, for the same reason bin/build-lotr-tlk's string
# table is: a feat's row index is its FEAT_* id, baked into save games the
# moment a character takes it, and its strings sit at a fixed TLK index.
# Inserting or removing an entry renumbers every feat after it and silently
# turns granted feats into different feats.
# ---------------------------------------------------------------------------
FEATS: list[Feat] = [
    Feat("LEGENDARY_STRENGTH", "Legendary Strength",
         "Your might has passed out of the merely mortal. You gain a permanent "
         "+6 bonus to Strength.",
         "ife_X2GrStr1", effect="+6 STR",
         category="Ability Scores", ability=0, bonus=6),
    Feat("LEGENDARY_DEXTERITY", "Legendary Dexterity",
         "You move as the wind through grass. You gain a permanent +6 bonus to "
         "Dexterity.",
         "ife_X2GrDex1", effect="+6 DEX",
         category="Ability Scores", ability=1, bonus=6),
    Feat("LEGENDARY_CONSTITUTION", "Legendary Constitution",
         "Hurt cannot find purchase in you. You gain a permanent +6 bonus to "
         "Constitution.",
         "ife_X2GrCon1", effect="+6 CON",
         category="Ability Scores", ability=2, bonus=6),
    Feat("LEGENDARY_INTELLIGENCE", "Legendary Intelligence",
         "Lore long lost lies open to you. You gain a permanent +6 bonus to "
         "Intelligence.",
         "ife_X2GrInt1", effect="+6 INT",
         category="Ability Scores", ability=3, bonus=6),
    Feat("LEGENDARY_WISDOM", "Legendary Wisdom",
         "You see the shape of things as they truly are. You gain a permanent "
         "+6 bonus to Wisdom.",
         "ife_X2GrWis1", effect="+6 WIS",
         category="Ability Scores", ability=4, bonus=6),
    Feat("LEGENDARY_CHARISMA", "Legendary Charisma",
         "Others follow where you lead, and are glad of it. You gain a "
         "permanent +6 bonus to Charisma.",
         "ife_X2GrCha1", effect="+6 CHA",
         category="Ability Scores", ability=5, bonus=6),
]


def tlk_strings():
    """The strings bin/build-lotr-tlk appends to its block, in index order.

    Two per feat, name then description. build-lotr-tlk imports this; it does
    not get its own copy of the text.
    """
    out = []
    for feat in FEATS:
        out.append(feat.name)
        out.append(feat.description)
    return out


def nss_include():
    """Render unpacked/legfeat_ids_inc.nss — the script-side view of FEATS.

    Scripts read feat ids, names and descriptions from here rather than typing
    row numbers or re-writing the display text, so the 2DA, the TLK and every
    script move together. The names are inlined rather than looked up by strref
    because NUI labels need a string, not a strref.
    """
    lines = [
        "// legfeat_ids_inc.nss — GENERATED by bin/gen-legendary-feats.py. Do not edit.",
        "//",
        "// The script-side view of the legendary feat table. Feat ids are row indices",
        "// in hak_2da/feat.2da; the names and descriptions are the same strings that",
        "// bin/build-lotr-tlk writes into tlk/lotr.tlk, so what a script prints and",
        "// what the character sheet shows cannot drift apart.",
        "//",
        "// Re-run: python3 bin/gen-legendary-feats.py --apply",
        "",
        f"const int LEGFEAT_COUNT = {len(FEATS)};",
        f"const int LEGFEAT_FIRST = {FIRST_ROW};",
        "",
    ]
    for offset, feat in enumerate(FEATS):
        lines.append(f"const int FEAT_{feat.label} = {FIRST_ROW + offset};")
    lines += [
        "",
        "// Feat id at picker index n (0 .. LEGFEAT_COUNT-1), or -1 if out of range.",
        "int LegFeat_IdAt(int n);",
        "// Display name / description for picker index n. Empty string if out of range.",
        "string LegFeat_NameAt(int n);",
        "string LegFeat_DescAt(int n);",
        "",
        "// Ability-score feats: the ABILITY_* constant a pick boosts (-1 if the",
        "// feat is not an ability feat) and the size of the bonus.",
        "int LegFeat_AbilityAt(int n);",
        "int LegFeat_BonusAt(int n);",
        "",
        "int LegFeat_IdAt(int n)",
        "{",
        "    if (n < 0 || n >= LEGFEAT_COUNT) return -1;",
        "    return LEGFEAT_FIRST + n;",
        "}",
        "",
        "string LegFeat_NameAt(int n)",
        "{",
        "    switch (n)",
        "    {",
    ]
    for offset, feat in enumerate(FEATS):
        lines.append(f'        case {offset}: return "{feat.name}";')
    lines += [
        "    }",
        '    return "";',
        "}",
        "",
        "string LegFeat_DescAt(int n)",
        "{",
        "    switch (n)",
        "    {",
    ]
    for offset, feat in enumerate(FEATS):
        text = feat.description.replace('"', "'")
        lines.append(f'        case {offset}: return "{text}";')
    lines += [
        "    }",
        '    return "";',
        "}",
        "",
        "int LegFeat_AbilityAt(int n)",
        "{",
        "    switch (n)",
        "    {",
    ]
    for offset, feat in enumerate(FEATS):
        lines.append(f"        case {offset}: return {feat.ability};")
    lines += [
        "    }",
        "    return -1;",
        "}",
        "",
        "int LegFeat_BonusAt(int n)",
        "{",
        "    switch (n)",
        "    {",
    ]
    for offset, feat in enumerate(FEATS):
        lines.append(f"        case {offset}: return {feat.bonus};")
    lines += [
        "    }",
        "    return 0;",
        "}",
        "",
    ]
    return "\n".join(lines)


def strrefs():
    """Return {label: (name_strref, description_strref)}.

    Derived from where bin/build-lotr-tlk actually places our strings, so the
    2DA cannot drift from the TLK by a transcription error. The import is
    one-directional — build-lotr-tlk pulls tlk_strings() from here inside a
    function, so importing it back at module scope is not a cycle.
    """
    spec = importlib.util.spec_from_file_location(
        "build_lotr_tlk", TLK_GENERATOR,
        loader=importlib.machinery.SourceFileLoader(
            "build_lotr_tlk", str(TLK_GENERATOR)),
    )
    tlk = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(tlk)

    strings = tlk.owned_strings()
    base = tlk.BLOCK_START + tlk.CUSTOM_TLK_OFFSET
    out = {}
    for feat in FEATS:
        try:
            name_pos = strings.index(feat.name)
            desc_pos = strings.index(feat.description)
        except ValueError:  # pragma: no cover - guarded by the gate too
            raise SystemExit(
                f"error: {feat.label}'s strings are not in bin/build-lotr-tlk's "
                "block — it must append tlk_strings() from this module")
        out[feat.label] = (base + name_pos, base + desc_pos)
    return out


# ---------------------------------------------------------------------------
# 2DA reading and writing
# ---------------------------------------------------------------------------

def read_2da(path):
    """Return (preamble_lines, header_columns, {row_index: raw_line}, newline).

    The newline comes back with the rest: 2DAs from the game data use CRLF, and
    rewriting rows 0-1115 with bare LF would make every one of them differ —
    "byte-identical base rows" has to mean the bytes, not just the tokens.
    """
    raw = path.read_bytes()
    newline = "\r\n" if b"\r\n" in raw else "\n"
    lines = raw.decode("latin-1").splitlines()
    if len(lines) < 3:
        raise SystemExit(f"error: {path} is not a 2DA")
    preamble = lines[:3]
    header = lines[2].split()
    rows = {}
    for line in lines[3:]:
        cells = line.split()
        if not cells or not cells[0].isdigit():
            continue
        rows[int(cells[0])] = line
    return preamble, header, rows, newline


def check_base(path, preamble, header, rows):
    """The base must be the stock table: 1116 rows, 43 columns."""
    problems = []
    if len(header) != BASE_COLUMNS:
        problems.append(
            f"{len(header)} columns, expected {BASE_COLUMNS} — this is not the "
            "stock feat.2da (the CEP cep2_add_feats copy has 44)")
    base_rows = [i for i in rows if i < FIRST_ROW]
    if len(base_rows) != BASE_ROWS or max(base_rows, default=-1) != BASE_ROWS - 1:
        problems.append(
            f"{len(base_rows)} rows below {FIRST_ROW}, expected {BASE_ROWS} "
            "(0-1115, last PLAYER_TOOL_10)")
    if problems:
        raise SystemExit(
            f"error: {path} is not a usable base table:\n"
            + "".join(f"       - {p}\n" for p in problems)
            + "       Seed a fresh stock base with --from-stock; see this "
              "script's docstring for the nwn_resman_cat command.")


def build_cells(index, feat, refs, header):
    """Render one owned row. Everything except name/description/icon is inert."""
    name_ref, desc_ref = refs[feat.label]
    values = {
        "LABEL": feat.label,
        "FEAT": str(name_ref),
        "DESCRIPTION": str(desc_ref),
        "ICON": feat.icon,
        # GAINMULTIPLE 0 / EFFECTSSTACK 0: taken once, no stacking rule for the
        # engine to apply — the script owns the effect.
        "GAINMULTIPLE": "0",
        "EFFECTSSTACK": "0",
        # THE load-bearing column. 0 = only classes whose cls_feat_*.2da lists
        # this feat may select it, and no cls_feat table lists ours, so the
        # engine's level-up page can never offer it. The picker grants it with
        # NWNX_Creature_AddFeat, which does not consult this.
        "ALLCLASSESCANUSE": "0",
        "Constant": f"FEAT_{feat.label}",
        # Toolset category 6 ("special"), so a builder can still hand one to an
        # NPC blueprint. Harmless: the toolset is not the level-up page.
        "TOOLSCATEGORIES": "6",
        # PreReqEpic 0 / ReqAction 0: no epic-page gating, not an activated
        # ability. Both are inert while ALLCLASSESCANUSE is 0; they are set
        # explicitly so a future reader does not read **** as "undecided".
        "PreReqEpic": "0",
        "ReqAction": "0",
    }
    return [str(index)] + [values.get(col, BLANK) for col in header]


def render(cells, widths):
    return "".join(c.ljust(w) for c, w in zip(cells, widths)).rstrip()


def column_widths(header, rows, owned_cells):
    """Match the base table's column alignment so a diff stays readable.

    Measured across every base row, not just the first — the LABEL column is
    sized for the longest feat name in the table, and padding our rows to the
    first row's width instead would run cells together with no separator.
    """
    widths = [6] + [len(c) + 2 for c in header]
    # Base rows only. Measuring our own rows too would make the widths depend on
    # the previous run's output — our long custom strrefs would widen the FEAT
    # column on run 2 and the script would never settle.
    for index, line in rows.items():
        if index >= FIRST_ROW:
            continue
        for i, cell in enumerate(line.split()):
            if i < len(widths):
                widths[i] = max(widths[i], len(cell) + 2)
    # Our own cells too, so a long custom strref still gets a separator after
    # it. Safe for idempotence: those cells come from FEATS, not from the file
    # we are about to overwrite.
    for cells in owned_cells:
        for i, cell in enumerate(cells):
            if i < len(widths):
                widths[i] = max(widths[i], len(cell) + 2)
    return widths


def main():
    ap = argparse.ArgumentParser(
        description="Own the legendary feat rows in hak_2da/feat.2da.")
    ap.add_argument("--apply", action="store_true",
                    help="write the table (default is a dry run)")
    ap.add_argument("--from-stock", metavar="PATH", type=Path,
                    help="reseed rows 0-1115 from a freshly extracted stock "
                         "feat.2da, keeping our rows")
    args = ap.parse_args()

    source = args.from_stock or FEAT_2DA
    if not source.exists():
        print(f"error: {source} is missing", file=sys.stderr)
        return 1

    preamble, header, rows, newline = read_2da(source)
    check_base(source, preamble, header, rows)
    refs = strrefs()
    kept = {i: line for i, line in rows.items() if i < FIRST_ROW}
    owned_cells = {
        FIRST_ROW + offset: build_cells(FIRST_ROW + offset, feat, refs, header)
        for offset, feat in enumerate(FEATS)
    }
    widths = column_widths(header, rows, owned_cells.values())
    owned = {i: render(cells, widths) for i, cells in owned_cells.items()}

    print(f"[feat] base:  {source}  ({len(kept)} rows, {len(header)} columns)")
    print(f"[feat] owned: {len(owned)} row(s) from {FIRST_ROW}")
    for index, feat in zip(sorted(owned), FEATS):
        name_ref, desc_ref = refs[feat.label]
        print(f"        {index}  FEAT_{feat.label}  "
              f"name={name_ref} desc={desc_ref}  {feat.effect}")

    out_lines = preamble + [kept[i] for i in sorted(kept)] \
        + [owned[i] for i in sorted(owned)]
    text = newline.join(out_lines) + newline

    if not args.apply:
        print()
        print(f"Dry run. Nothing written. Re-run with --apply to write {FEAT_2DA}.")
        return 0

    payload = text.encode("latin-1")
    unchanged = FEAT_2DA.exists() and FEAT_2DA.read_bytes() == payload
    FEAT_2DA.write_bytes(payload)
    print()
    print(f"[feat] {'unchanged' if unchanged else 'wrote'} -> {FEAT_2DA}")

    inc = nss_include()
    inc_same = IDS_INC.exists() and IDS_INC.read_text(encoding="utf-8") == inc
    IDS_INC.write_text(inc, encoding="utf-8")
    print(f"[feat] {'unchanged' if inc_same else 'wrote'} -> {IDS_INC}")
    unchanged = unchanged and inc_same
    if not unchanged:
        print()
        print("Next: bin/build-lotr-tlk --apply --install   # the rows point at "
              "strrefs only lotr.tlk has")
        print("      bin/build-lotr-rules-hak --install")
        print("      bin/refresh-nwsync && nwn-manager repack && bin/server-restart")
    return 0


if __name__ == "__main__":
    sys.exit(main())
