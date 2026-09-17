#!/usr/bin/env python3
"""audit-devcrit-lost - who paid for Devastating Critical (Unarmed) and has
nothing to show for it.

Roadmap: buged-dev-crit.

THE DEFECT
----------
`devcrit-unarmed-save-or-die` stops the engine's unarmed save-or-die by TAKING
THE FEAT OFF the character (`DevCrit_ArmNoDevCrit`), because feat 506 is the one
devastating critical the engine resolves without reading the blanked
baseitems.2da column. That removal is written into the .bic. Two things follow,
and both of them cost the player:

  * the level-up wizard offers the feat AGAIN at the next feat level, because
    the character genuinely no longer has it. The reporter bought it at 51, 54
    and 57;
  * the "it had it" record was a local variable, so it died at the logout and
    the replacement bonus dice - and the Legendary Butcher prerequisite - went
    with it.

WHERE THE EVIDENCE IS
---------------------
`NWNX_Creature_RemoveFeat` takes the feat off the creature's stats but does NOT
touch the .bic's PER-LEVEL feat list. So every pick is still recorded against
the level it was made at, on the character's own file, months later. No backup
is needed - which matters, because the picks made after the strip shipped were
stripped within the same second and never reached a backup at all.

The fix hands the feat back in game (`DevCrit_RestoreUnarmed`, from
mod_cliententer). It cannot hand back the SPARE picks: a second or third pick on
the same feat is a feat the player never got. This script is the list of who is
owed how many, so the admin can make those good.

Read-only. It opens .bic files and nothing else.

Usage:
  bin/audit-devcrit-lost.py                 # every realm beside this repo
  bin/audit-devcrit-lost.py --realm live    # by SEASON_ROLE, repeatable
  bin/audit-devcrit-lost.py --json out.json

Exit status is 1 when any character is owed a pick, 0 otherwise.
"""
import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent

# Stock feat ids. The unarmed devastating critical is the one players buy; the
# creature one is on monsters, which never level up and never relog, so a
# recorded pick there is noise rather than a debt. Both are counted, only the
# first is owed.
FEAT_DEVCRIT_UNARMED = 506
FEAT_DEVCRIT_CREATURE = 532

NWN_GFF = os.environ.get(
    "NWN_GFF",
    os.path.expanduser("~/.nimble/bin/nwn_gff"))


def env_get(text, key):
    m = re.search(rf'^{key}=["\']?(.*?)["\']?\s*(?:#.*)?$', text, re.M)
    return m.group(1).strip() if m else ""


def realms(wanted):
    """Every sibling nwn_homers_lotr* checkout with a server.env, as
    (role, name, home_dir) - the same discovery rule as
    bin/audit-legendary-feats.py and the roadmap editor."""
    out = []
    for repo in sorted(REPO.parent.glob("nwn_homers_lotr*")):
        try:
            text = (repo / "server.env").read_text(encoding="utf-8")
        except OSError:
            continue
        role = env_get(text, "SEASON_ROLE") or "?"
        home = env_get(text, "NWN_HOME_DIR")
        if not home:
            continue
        if wanted and role not in wanted:
            continue
        home = Path(os.path.expandvars(home.replace("$HOME", str(Path.home()))))
        out.append((role, repo.name, home))
    return out


def gff_json(path):
    out = subprocess.run([NWN_GFF, "-i", str(path), "-k", "json"],
                         capture_output=True)
    if out.returncode != 0:
        return None
    try:
        return json.loads(out.stdout)
    except json.JSONDecodeError:
        return None


def val(node):
    return node["value"] if isinstance(node, dict) and "value" in node else node


def scan_character(path):
    """{...} for a character with at least one recorded pick, else None."""
    data = gff_json(path)
    if not data:
        return None

    picks = []
    for level, entry in enumerate(val(data.get("LvlStatList", {})) or [], 1):
        for feat in val(entry.get("FeatList", {})) or []:
            if val(feat["Feat"]) in (FEAT_DEVCRIT_UNARMED, FEAT_DEVCRIT_CREATURE):
                picks.append((level, val(feat["Feat"])))
    if not picks:
        return None

    held = {val(f["Feat"]) for f in val(data.get("FeatList", {})) or []}
    classes = [(val(c["Class"]), val(c["ClassLevel"]))
               for c in val(data.get("ClassList", {})) or []]
    name = " ".join(x for x in (val(val(data.get("FirstName", {})) or {}).get("0", ""),
                                val(val(data.get("LastName", {})) or {}).get("0", ""))
                    if x).strip()

    unarmed = [lvl for lvl, feat in picks if feat == FEAT_DEVCRIT_UNARMED]
    return {
        "bic": path.name,
        "cdkey": path.parent.name,
        "name": name,
        "uuid": val(data.get("UUID", {})) or "",
        "level": sum(level for _, level in classes),
        "classes": classes,
        "picks": unarmed,
        "picks_creature": [lvl for lvl, feat in picks
                           if feat == FEAT_DEVCRIT_CREATURE],
        # Held it all along: a single legitimate pick that the strip has not
        # reached yet. Nothing is owed and the login migration converts it.
        "holds_stock": FEAT_DEVCRIT_UNARMED in held,
        # Every pick after the first bought a feat that was taken away again.
        "owed": max(len(unarmed) - 1, 0),
    }


def main():
    ap = argparse.ArgumentParser(
        description="Characters whose Devastating Critical (Unarmed) picks the "
                    "strip ate.")
    ap.add_argument("--realm", action="append", metavar="ROLE",
                    help="only this SEASON_ROLE (live/dev/archive); repeatable")
    ap.add_argument("--json", metavar="PATH", type=Path,
                    help="also write the findings as JSON")
    args = ap.parse_args()

    if not os.path.exists(NWN_GFF):
        sys.exit(f"error: nwn_gff not found at {NWN_GFF} - set NWN_GFF, or "
                 "`nimble install neverwinter`")

    found = []
    for role, repo_name, home in realms(args.realm):
        vault = home / "servervault"
        if not vault.is_dir():
            print(f"[{role:7}] {repo_name}: no servervault at {vault}")
            continue

        rows = []
        for bic in sorted(vault.glob("*/*.bic")):
            row = scan_character(bic)
            if row:
                row["realm"] = repo_name
                row["role"] = role
                rows.append(row)

        owed = sum(r["owed"] for r in rows)
        print(f"[{role:7}] {repo_name}: {len(rows)} character(s) with a "
              f"recorded pick, {owed} pick(s) owed")
        for row in sorted(rows, key=lambda r: -r["owed"]):
            flag = "OWED " if row["owed"] else ("intact" if row["holds_stock"]
                                                else "restored-on-login")
            print(f"            {flag:18} {row['name'] or row['bic']:24} "
                  f"lvl {row['level']:<3} picks at {row['picks']}"
                  + (f"  (+{row['owed']} owed)" if row["owed"] else ""))
        found += rows

    if args.json:
        args.json.write_text(json.dumps(found, indent=2), encoding="utf-8")
        print(f"\nwrote {args.json}")

    total = sum(r["owed"] for r in found)
    if total:
        print(f"\n{total} feat pick(s) are owed to players. The feat itself is "
              "restored at their next login; the spare picks need an admin.")
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main())
