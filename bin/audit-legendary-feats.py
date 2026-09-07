#!/usr/bin/env python3
"""audit-legendary-feats - find characters holding legendary feats their realm
has no pick record for, or more than their allotment allows.

A legendary feat lives in two places at once, and only one of them travels:

  * the FEAT itself is written into the character's .bic by
    NWNX_Creature_AddFeat, and a RAW feat (Legendary Strength and the other
    five ability feats) also writes +6 into the .bic's BASE ability score;
  * the PICK RECORD lives in `legfeatdb`, which is a campaign DB and therefore
    PER REALM.

`bin/sync-vault-from-prod` copies .bic files one way, live season -> dev realm,
and deliberately does not bring campaign DBs with them. So a character that
crosses realms arrives holding feats the receiving realm has never heard of.
That desync is what this script measures, from outside the game, by parsing
every .bic and joining it to that realm's legfeatdb.

Why it matters (roadmap legfeat-double-grant-cross-realm, reported by Rajmund
on the dev realm 2026-09-06): with no pick record, LegFeat_EnsureAllotment took
its "first grant at 60" branch and offered a full allotment to a character that
had already spent it - a four-class character entitled to one legendary feat
was handed a second. And because LegFeat_RevokeAll iterates pick RECORDS, an
unrecorded feat is invisible to the respec, to the class-change revoke and to
the level-drop revoke, stranding a RAW feat's +6 with nothing recording that it
was ever granted.

`LegFeat_AdoptHeldFeats` now closes the gap in game: it records what a character
already holds before any allotment decision is made. This script stays useful
either way - as the before/after check on that fix, and as the standing audit
for any future path that writes a feat into a .bic.

Verdicts, worst first:
  OVER        holds MORE legendary feats than its class makeup allows. The one
              that is unambiguously wrong and needs a respec to clear.
  UNRECORDED  holds a feat with no pick record in this realm's legfeatdb. Not
              over allotment yet, but one Force Rest away from OVER before the
              adoption fix, and unrevokable by any in-game path.
  STALE       a pick record for a feat the character does NOT hold. The
              harmless reverse - a level drop or a vault restore. Self-heals at
              the next login.
  MISMATCH    holds and records the same COUNT but not the same feats.

The allotment rule mirrors LegFeat_Allotment in unpacked/legfeat_inc.nss:
level 60 is required; anything in a second/third/fourth class slot gives 1;
a pure Fighter gives 3; any other pure class gives 2.

Usage:
  bin/audit-legendary-feats.py                 # every realm found beside this repo
  bin/audit-legendary-feats.py --realm dev     # by SEASON_ROLE, repeatable
  bin/audit-legendary-feats.py --all           # list clean characters too
  bin/audit-legendary-feats.py --json out.json

Exit status is 1 when any OVER or UNRECORDED character is found, 0 otherwise -
so it can be used as a check. STALE and MISMATCH alone do not fail it.
"""
import argparse
import json
import os
import re
import shutil
import sqlite3
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
IDS_INC = REPO / "unpacked" / "legfeat_ids_inc.nss"

# CLASS_TYPE_FIGHTER, the one class whose pure allotment differs. Kept as a
# named constant rather than a bare 4 so the rule below reads like the NWScript
# it mirrors.
CLASS_TYPE_FIGHTER = 4
LEGFEAT_LEVEL = 60


def find_nwn_gff():
    """nwn_gff, from PATH or the nimble install. ~/.nimble/bin/nwn_gff is a
    symlink into whichever package version was installed last, so resolve it
    rather than assuming a version directory."""
    found = shutil.which("nwn_gff")
    if found:
        return found
    nimble = Path.home() / ".nimble" / "bin" / "nwn_gff"
    if nimble.exists():
        return str(nimble.resolve())
    for pkg in sorted((Path.home() / ".nimble" / "pkgs2").glob("neverwinter-*"),
                      reverse=True):
        if (pkg / "nwn_gff").exists():
            return str(pkg / "nwn_gff")
    return None


def feat_range():
    """The legendary feat id block, read from the GENERATED include rather than
    hardcoded. bin/gen-legendary-feats.py owns those two constants; a copy here
    would silently stop covering feats added after this script was written."""
    text = IDS_INC.read_text(encoding="latin-1")

    def const(name):
        m = re.search(rf"^const int {name}\s*=\s*(\d+);", text, re.M)
        if not m:
            sys.exit(f"error: {IDS_INC} has no {name} - cannot bound the audit")
        return int(m.group(1))

    first = const("LEGFEAT_FIRST")
    return first, first + const("LEGFEAT_COUNT")


def env_get(text, key):
    m = re.search(rf'^{key}=["\']?(.*?)["\']?\s*(?:#.*)?$', text, re.M)
    return m.group(1).strip() if m else ""


def realms(wanted):
    """Every sibling nwn_homers_lotr* checkout with a server.env, as
    (role, name, home_dir). Same discovery rule as bin/watch-all-servers and
    the roadmap editor - a realm IS a sibling repo whose server.env names one."""
    out = []
    for repo in sorted(REPO.parent.glob("nwn_homers_lotr*")):
        env_file = repo / "server.env"
        try:
            text = env_file.read_text(encoding="utf-8")
        except OSError:
            continue
        role = env_get(text, "SEASON_ROLE") or "?"
        home = env_get(text, "NWN_HOME_DIR")
        if not home:
            continue
        home = Path(os.path.expandvars(home.replace("$HOME", str(Path.home()))))
        if wanted and role not in wanted:
            continue
        out.append((role, repo.name, home))
    return out


def gff_json(nwn_gff, path):
    out = subprocess.run([nwn_gff, "-i", str(path), "-k", "json"],
                         capture_output=True)
    if out.returncode != 0:
        return None
    try:
        return json.loads(out.stdout)
    except json.JSONDecodeError:
        return None


def val(node):
    return node["value"] if isinstance(node, dict) and "value" in node else node


def allotment(classes):
    """LegFeat_Allotment, in Python. classes is [(class_id, level)] in SLOT
    order, which is what the allotment reads - a second slot at all means
    multiclass, whatever the levels in it."""
    if sum(level for _, level in classes) < LEGFEAT_LEVEL:
        return 0
    if len(classes) > 1:
        return 1
    return 3 if classes and classes[0][0] == CLASS_TYPE_FIGHTER else 2


def audit_realm(nwn_gff, role, repo_name, home, leg_ids):
    vault = home / "servervault"
    db_path = home / "database" / "legfeatdb.sqlite3"
    if not vault.is_dir():
        return [], f"{repo_name}: no servervault at {vault}"
    if not db_path.exists():
        return [], f"{repo_name}: no legfeatdb at {db_path}"

    # Read-only: this may run against a realm with players on it, and an audit
    # must never be the thing that locks the server's own writer out.
    db = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    granted = dict(db.execute("select pid, picks from legfeat_alloc"))
    recorded = {}
    for pid, feat in db.execute("select pid, feat from legfeat_pick"):
        recorded.setdefault(pid, set()).add(feat)
    db.close()

    rows, unreadable = [], []
    for bic in sorted(vault.glob("*/*.bic")):
        data = gff_json(nwn_gff, bic)
        if data is None:
            unreadable.append(str(bic.relative_to(vault)))
            continue
        held = {val(f)["Feat"]["value"]
                for f in val(data.get("FeatList", {"value": []}))} & leg_ids
        classes = [(val(c)["Class"]["value"], val(c)["ClassLevel"]["value"])
                   for c in val(data.get("ClassList", {"value": []}))]
        uuid = val(data.get("UUID", {"value": ""}))
        recs = recorded.get(uuid, set())
        allot = allotment(classes)

        if len(held) > allot:
            verdict = "OVER"
        elif held - recs:
            verdict = "UNRECORDED"
        elif recs - held:
            verdict = "STALE"
        elif held != recs:
            verdict = "MISMATCH"
        else:
            verdict = "CLEAN"

        rows.append({
            "realm": role, "repo": repo_name, "cdkey": bic.parent.name,
            "character": bic.stem, "uuid": uuid, "verdict": verdict,
            "level": sum(level for _, level in classes), "classes": classes,
            "allotment": allot, "held": sorted(held), "recorded": sorted(recs),
            "granted": granted.get(uuid),
        })
    warn = ""
    if unreadable:
        warn = (f"{repo_name}: {len(unreadable)} unreadable .bic file(s) - "
                + ", ".join(unreadable[:3]))
    return rows, warn


ORDER = {"OVER": 0, "UNRECORDED": 1, "MISMATCH": 2, "STALE": 3, "CLEAN": 4}
FAIL = {"OVER", "UNRECORDED"}


def main():
    ap = argparse.ArgumentParser(
        description="Audit player vaults for legendary feats with no pick "
                    "record, or more than the allotment allows.")
    ap.add_argument("--realm", action="append", default=[], metavar="ROLE",
                    help="only realms with this SEASON_ROLE (live, dev, ...); "
                         "repeatable. Default: every realm found.")
    ap.add_argument("--all", action="store_true",
                    help="list CLEAN characters too")
    ap.add_argument("--json", metavar="PATH", help="write the full result as JSON")
    args = ap.parse_args()

    nwn_gff = find_nwn_gff()
    if not nwn_gff:
        sys.exit("error: nwn_gff not found (PATH or ~/.nimble) - it is what "
                 "reads a .bic; install neverwinter.nim")

    first, end = feat_range()
    leg_ids = set(range(first, end))
    targets = realms(args.realm)
    if not targets:
        sys.exit("error: no realm found beside this repo"
                 + (f" with SEASON_ROLE in {args.realm}" if args.realm else ""))

    rows, warnings = [], []
    for role, name, home in targets:
        got, warn = audit_realm(nwn_gff, role, name, home, leg_ids)
        rows += got
        if warn:
            warnings.append(warn)

    if args.json:
        Path(args.json).write_text(json.dumps(rows, indent=2), encoding="utf-8")

    shown = [r for r in rows if args.all or r["verdict"] != "CLEAN"]
    shown.sort(key=lambda r: (ORDER[r["verdict"]], r["realm"], r["character"]))

    print(f"legendary feats {first}-{end - 1}; "
          + ", ".join(f"{role}={name}" for role, name, _ in targets))
    print(f"{len(rows)} character(s) audited across {len(targets)} realm(s)\n")
    if shown:
        print(f"{'verdict':11} {'realm':8} {'cdkey':10} {'character':22} "
              f"{'lvl':>3} {'allot':>5} held / recorded")
        for r in shown:
            print(f"{r['verdict']:11} {r['realm']:8} {r['cdkey']:10} "
                  f"{r['character'][:22]:22} {r['level']:>3} {r['allotment']:>5} "
                  f"{r['held']} / {r['recorded']}   classes={r['classes']}")
        print()
    for w in warnings:
        print(f"warning: {w}")

    counts = {}
    for r in rows:
        counts[r["verdict"]] = counts.get(r["verdict"], 0) + 1
    print("  ".join(f"{v}={counts[v]}" for v in sorted(counts, key=ORDER.get)))

    bad = sum(counts.get(v, 0) for v in FAIL)
    if bad:
        print(f"\nFAIL: {bad} character(s) hold a legendary feat their realm "
              "cannot account for.")
        return 1
    print("\nok: every held legendary feat has a matching pick record.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
