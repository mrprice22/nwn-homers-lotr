#!/usr/bin/env python3
"""Sync _inc_donations.nss with module-index accessibility data.

Usage:  python3 bin/sync_donations.py [--dry-run]

What it does:
  1. Parses unpacked/_inc_donations.nss to extract the current bonus pool
     and illicit list.
  2. Reads module-index/inaccessible_items.json for the current set of items
     players cannot obtain.
  3. Reads module-index/item_index.json for human-readable item names.
  4. Finds "graduates": illicit items that are now accessible (absent from
     inaccessible_items.json).
  5. Removes graduates from the illicit list and appends them to the bonus
     pool (stack size defaults to 1; ammo must be flagged manually).
  6. Rewrites unpacked/_inc_donations.nss with the updated lists.

The illicit list can only shrink — this script never adds new items to it.
Run from the repository root. Re-run the wiki builder first if module-index
files are stale.
"""

import argparse
import json
import re
import sys
from pathlib import Path

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
REPO_ROOT     = Path(__file__).resolve().parent.parent
UNPACKED      = REPO_ROOT / "unpacked"
INC_FILE      = UNPACKED / "_inc_donations.nss"
INACC_FILE    = REPO_ROOT / "module-index" / "inaccessible_items.json"
ITEM_IDX_FILE = REPO_ROOT / "module-index" / "item_index.json"

# ---------------------------------------------------------------------------
# Regexes — scoped to extracted function bodies
# ---------------------------------------------------------------------------
RE_POOL_SIZE    = re.compile(r'^const int BONUS_POOL_SIZE\s*=\s*(\d+);', re.MULTILINE)
RE_RESREF_FUNC  = re.compile(r'string GetBonusItemResref\(int n\)\s*\{(.*?)\n\}', re.DOTALL)
RE_RESREF_CASE  = re.compile(r'^\s+case\s+(\d+):\s+return\s+"([^"]+)";\s*//\s*(.+?)\s*$', re.MULTILINE)
RE_STACK_FUNC   = re.compile(r'int GetBonusItemStackSize\(int n\)\s*\{(.*?)\n\}', re.DOTALL)
RE_AMMO_CASE    = re.compile(r'^\s+case\s+(\d+):', re.MULTILINE)
RE_ILLICIT_FUNC = re.compile(r'int IsIllicitDonationsItem\(string sResRef\)\s*\{(.*?)\n\}', re.DOTALL)
RE_ILLICIT_LINE = re.compile(r'^\s+if\s*\(sResRef\s*==\s*"([^"]+)"\s*\)', re.MULTILINE)

# ---------------------------------------------------------------------------
# Parsing
# ---------------------------------------------------------------------------

def parse_inc(text: str) -> dict:
    """Extract all managed data from _inc_donations.nss.

    Returns:
      pool_size   int
      bonus_pool  list of (resref, name) ordered by case index
      ammo_set    set of resrefs that get stack size 99
      illicit     list of resrefs (in declaration order)
    """
    # --- BONUS_POOL_SIZE ---
    m = RE_POOL_SIZE.search(text)
    if not m:
        sys.exit("ERROR: BONUS_POOL_SIZE constant not found in _inc_donations.nss")
    pool_size = int(m.group(1))

    # --- GetBonusItemResref ---
    m = RE_RESREF_FUNC.search(text)
    if not m:
        sys.exit("ERROR: GetBonusItemResref not found in _inc_donations.nss")
    resref_body = m.group(1)
    raw_cases = RE_RESREF_CASE.findall(resref_body)  # list of (n_str, resref, name)
    if not raw_cases:
        sys.exit("ERROR: no case entries found in GetBonusItemResref")
    raw_cases.sort(key=lambda c: int(c[0]))
    for i, (n_str, _, _) in enumerate(raw_cases):
        if int(n_str) != i:
            sys.exit(f"ERROR: GetBonusItemResref has non-contiguous cases "
                     f"(expected {i}, got {n_str}) — fix manually before running sync")
    bonus_pool = [(resref, name.strip()) for _, resref, name in raw_cases]
    if len(bonus_pool) != pool_size:
        print(f"WARNING: BONUS_POOL_SIZE={pool_size} but found {len(bonus_pool)} cases — "
              f"using actual count")
        pool_size = len(bonus_pool)

    # --- GetBonusItemStackSize (ammo) ---
    # Parse by case *index*, cross-reference against bonus_pool position
    m = RE_STACK_FUNC.search(text)
    if not m:
        sys.exit("ERROR: GetBonusItemStackSize not found in _inc_donations.nss")
    stack_body = m.group(1)
    ammo_indices = {int(n) for n in RE_AMMO_CASE.findall(stack_body)}
    ammo_set = set()
    for idx in ammo_indices:
        if 0 <= idx < len(bonus_pool):
            ammo_set.add(bonus_pool[idx][0])
        else:
            print(f"WARNING: ammo case {idx} is out of range for bonus pool (size {len(bonus_pool)})")

    # --- IsIllicitDonationsItem ---
    m = RE_ILLICIT_FUNC.search(text)
    if not m:
        sys.exit("ERROR: IsIllicitDonationsItem not found in _inc_donations.nss")
    illicit = RE_ILLICIT_LINE.findall(m.group(1))

    return {
        "pool_size":  pool_size,
        "bonus_pool": bonus_pool,
        "ammo_set":   ammo_set,
        "illicit":    illicit,
    }

# ---------------------------------------------------------------------------
# NWScript generation
# ---------------------------------------------------------------------------

def _case_line(n: int, resref: str, name: str) -> str:
    case_str   = f"case {n}:".ljust(10)
    resref_col = f'"{resref}";'.ljust(26)
    return f"        {case_str} return {resref_col}  // {name}"


def _gen_stack_func(bonus_pool: list, ammo_set: set) -> str:
    lines = ["int GetBonusItemStackSize(int n)", "{", "    switch (n)", "    {"]
    for i, (resref, _) in enumerate(bonus_pool):
        if resref in ammo_set:
            lines.append(f"        case {i}: // {resref}")
    lines += ["            return 99;", "    }", "    return 1;", "}"]
    return "\n".join(lines)


def _gen_resref_func(bonus_pool: list) -> str:
    lines = ["string GetBonusItemResref(int n)", "{", "    switch (n)", "    {"]
    for i, (resref, name) in enumerate(bonus_pool):
        lines.append(_case_line(i, resref, name))
    lines += ["    }", '    return "";', "}"]
    return "\n".join(lines)


def _gen_illicit_func(illicit: list) -> str:
    lines = [
        "// Returns TRUE if the resref was removed from the bonus pool",
        "// because it was not legitimately obtainable by players.",
        "int IsIllicitDonationsItem(string sResRef)",
        "{",
    ]
    for resref in illicit:
        lines.append(f'    if (sResRef == "{resref}")   return TRUE;')
    lines += ["    return FALSE;", "}"]
    return "\n".join(lines)


def generate_inc(bonus_pool: list, ammo_set: set, illicit: list) -> str:
    pool_size = len(bonus_pool)
    parts = [
        "// _inc_donations.nss",
        "// Donations Chest data: bonus item pool, stack sizes, and illicit quarantine list.",
        "// AUTO-MANAGED by bin/sync_donations.py - do not hand-edit the generated sections.",
        "",
        "// Number of items in the bonus pool (cases 0..BONUS_POOL_SIZE-1).",
        f"const int BONUS_POOL_SIZE = {pool_size};",
        "",
        "// Returns 99 for ammunition items, 1 for everything else.",
        _gen_stack_func(bonus_pool, ammo_set),
        "",
        _gen_resref_func(bonus_pool),
        "",
        _gen_illicit_func(illicit),
    ]
    return "\n".join(parts) + "\n"

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

AMMO_HINTS = ("arrow", "bolt", "bullet", "quiver")


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dry-run", action="store_true",
                    help="Print what would change without writing any files")
    args = ap.parse_args()

    # Pre-flight checks
    for p in (INACC_FILE, ITEM_IDX_FILE):
        if not p.exists():
            print(f"ERROR: {p} not found — run the wiki builder first (nwn-manager wiki).")
            sys.exit(1)
    if not INC_FILE.exists():
        print(f"ERROR: {INC_FILE} not found — create it before running sync.")
        sys.exit(1)

    # Parse current state
    text  = INC_FILE.read_text(encoding="utf-8")
    state = parse_inc(text)

    # Load module-index
    inacc_data = json.loads(INACC_FILE.read_text(encoding="utf-8"))
    inacc_set  = {item["resref"] for item in inacc_data["items"]}

    idx_data = json.loads(ITEM_IDX_FILE.read_text(encoding="utf-8"))
    name_map = {item["resref"]: item["name"] for item in idx_data["items"]}

    # Compute graduates: illicit items now accessible
    illicit_set = set(state["illicit"])
    bonus_set   = {r for r, _ in state["bonus_pool"]}
    graduates   = []
    for resref in state["illicit"]:
        if resref not in inacc_set:
            name = name_map.get(resref, resref)
            graduates.append((resref, name))

    # Summary
    print(f"Bonus pool:    {state['pool_size']} items")
    print(f"Illicit list:  {len(state['illicit'])} items")
    print(f"Inaccessible:  {len(inacc_set)} items (module-index)")
    print()

    if not graduates:
        print("No graduates — illicit list is already up to date.")
        return

    print(f"Graduates ({len(graduates)} items now accessible → moving to bonus pool):")
    ammo_warnings = []
    for resref, name in graduates:
        print(f"  + {resref:<26}  // {name}")
        if any(hint in name.lower() or hint in resref.lower() for hint in AMMO_HINTS):
            ammo_warnings.append(resref)

    if ammo_warnings:
        print()
        print("NOTE: the following graduates may be ammunition (stack size defaults to 1).")
        print("      If they should give 99 per stack, add their case numbers to")
        print("      GetBonusItemStackSize in _inc_donations.nss after this run:")
        for r in ammo_warnings:
            print(f"  {r}")

    grad_set       = {r for r, _ in graduates}
    new_illicit    = [r for r in state["illicit"] if r not in grad_set]
    new_bonus_pool = list(state["bonus_pool"]) + graduates
    new_pool_size  = len(new_bonus_pool)

    print()
    print(f"New bonus pool size: {new_pool_size}  (was {state['pool_size']})")
    print(f"New illicit count:   {len(new_illicit)}  (was {len(state['illicit'])})")

    if args.dry_run:
        print("\n[dry-run] No files written.")
        return

    new_text = generate_inc(new_bonus_pool, state["ammo_set"], new_illicit)
    INC_FILE.write_text(new_text, encoding="utf-8")
    print(f"\nWrote {INC_FILE.relative_to(REPO_ROOT)}")


if __name__ == "__main__":
    main()
