#!/usr/bin/env python3
"""audit-character-drift - find items in players' .bic files that no longer
match their blueprint, and say WHY.

The forge's contraband law only applies its caps to items a player actually
forged, which it knows from an item-local stamp (FORGE_TOUCHED, or the older
FORGE_GP_INVESTED / FORGE_CEIL). Items forged before those stamps existed carry
none of them, so the live check can no longer judge them. This script closes that gap from
outside the game: it reads the character vault directly and decides drift by
comparing properties, not by trusting a stamp.

The key trick is that "differs from the blueprint" is NOT the same as "a player
modified it" - a blueprint rebalance makes every copy already in circulation
differ through no act of the player. So when an item does not match the CURRENT
blueprint, this script replays that blueprint's git history and checks whether
the item matches any PAST version. If it does, the drift is explained by an
edit we made, and the item is innocent.

Verdicts, worst first:
  SUSPECT      no match against any blueprint version, and no forge stamp.
               The one case that needs a human: either forged before stamps
               existed, or modified by something other than the forge.
  FORGED       no match, but carries a forge stamp. Expected - a player
               enchanted it. Check props/value against the caps.
  PLACED_VARIANT matches a variant the module itself places (store stock,
               creature loot, container contents). Legally obtainable - the
               live check allows these too, via ForgeIsKnownLegalVariant.
  REBALANCED   matches a HISTORICAL blueprint version. Benign: we changed the
               blueprint under them. Shows which commit did it.
  CLEAN        matches the current blueprint.
  UNKNOWN_BP   resref is not in unpacked/ (stock Bioware/CEP item) - cannot be
               judged offline.

Usage:
  bin/audit-character-drift.py                    # audit the dev vault
  bin/audit-character-drift.py --vault PATH
  bin/audit-character-drift.py --verdict SUSPECT FORGED
  bin/audit-character-drift.py --json out.json
"""
import argparse
import json
import os
import subprocess
import sys
from collections import Counter

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UNPACKED = os.path.join(REPO, "unpacked")
# REPO/UNPACKED/LEGAL_INC are rebound by --repo so a vault can be audited
# against ITS OWN module tree. Auditing the season-2 vault against the dev
# tree would compare live gear to blueprints that only exist on dev, and every
# difference between the two module versions would read as drift.
NWN_GFF = os.path.expanduser("~/.nimble/bin/nwn_gff")

# Mirrors forge_inc.nss ForgePropInSet(FORGE_SEL_PRICED): permanent, non-cosmetic,
# restrictions INCLUDED. Cosmetics are excluded because the forge never counts,
# compares or fingerprints them (Bree appearance station effects, Light).
ITEM_PROPERTY_LIGHT = 44
ITEM_PROPERTY_VISUALEFFECT = 83
COSMETIC = {ITEM_PROPERTY_LIGHT, ITEM_PROPERTY_VISUALEFFECT}

FORGE_MARKERS = ("FORGE_TOUCHED", "FORGE_GP_INVESTED", "FORGE_CEIL",
                 "FORGE_EXTRA_SLOTS", "FORGE_CLEAN")
# Variables that only a forge ever writes, i.e. proof a player changed the item.
# FORGE_CLEAN is NOT one of them - the contraband scan stamps that on everything
# it clears, forged or not.
PROOF_OF_FORGING = ("FORGE_TOUCHED", "FORGE_GP_INVESTED", "FORGE_CEIL")

LEGAL_INC = os.path.join(REPO, "unpacked", "forge_legal_inc.nss")

# The live caps (forge_inc.nss ForgeLegalMaxProps / ForgeLegalMaxValue) - the
# MAXIMUM achievable, including the top boss-kill bonus.
LEGAL_MAX_PROPS = 7
LEGAL_MAX_VALUE = 900000


def gval(node, default=None):
    """Unwrap a {"type":..,"value":..} GFF node."""
    if isinstance(node, dict) and "value" in node:
        return node["value"]
    return default


def prop_sig(p):
    """(type, subtype, costvalue, param1value), matching ForgePropSig.

    Subtype 65535 is the other encoding of "blank" (see the AB/Enhancement
    subtype blind spot) and is normalised to 0 so the two encodings of the same
    property cannot read as drift.
    """
    sub = gval(p.get("Subtype"), 0) or 0
    if sub == 65535:
        sub = 0
    return (
        gval(p.get("PropertyName"), -1),
        sub,
        gval(p.get("CostValue"), 0) or 0,
        gval(p.get("Param1Value"), 0) or 0,
    )


def priced_props(props):
    """Multiset of PRICED property signatures."""
    out = Counter()
    for p in props or []:
        if gval(p.get("PropertyName"), -1) in COSMETIC:
            continue
        out[prop_sig(p)] += 1
    return out


def bp_props_from_json(text):
    try:
        d = json.loads(text)
    except Exception:
        return None
    return priced_props(gval(d.get("PropertiesList"), []))


_bp_cache = {}


def current_blueprint(resref):
    if resref in _bp_cache:
        return _bp_cache[resref]
    path = os.path.join(UNPACKED, resref + ".uti.json")
    val = None
    if os.path.isfile(path):
        with open(path) as f:
            val = bp_props_from_json(f.read())
    _bp_cache[resref] = val
    return val


_hist_cache = {}


def historical_blueprints(resref):
    """[(commit, date, subject, propmultiset)] oldest last, for this blueprint."""
    if resref in _hist_cache:
        return _hist_cache[resref]
    rel = "unpacked/%s.uti.json" % resref
    try:
        log = subprocess.run(
            ["git", "log", "--format=%H\t%ad\t%s", "--date=short", "--", rel],
            cwd=REPO, capture_output=True, text=True, check=True).stdout
    except subprocess.CalledProcessError:
        _hist_cache[resref] = []
        return []
    out = []
    for line in log.splitlines():
        if not line.strip():
            continue
        sha, date, subject = line.split("\t", 2)
        try:
            blob = subprocess.run(
                ["git", "show", "%s:%s" % (sha, rel)],
                cwd=REPO, capture_output=True, text=True, check=True).stdout
        except subprocess.CalledProcessError:
            continue
        props = bp_props_from_json(blob)
        if props is not None:
            out.append((sha[:11], date, subject, props))
    _hist_cache[resref] = out
    return out


def legal_fingerprint(resref, props):
    """Replicates ForgeLegalFingerprint (forge_legal_inc.nss): resref, then the
    permanent non-cosmetic property tuples zero-padded to 5 and sorted."""
    tuples = []
    for p in props or []:
        if gval(p.get("PropertyName"), -1) in COSMETIC:
            continue
        p1 = gval(p.get("Param1"), 255)
        pv = 65535 if (p1 is None or p1 < 0 or p1 == 255) \
            else (gval(p.get("Param1Value"), 0) or 0)
        tuples.append("%05d:%05d:%05d:%05d" % (
            gval(p.get("PropertyName"), 0) or 0,
            gval(p.get("Subtype"), 0) or 0,
            gval(p.get("CostValue"), 0) or 0,
            pv))
    return "%s|%s" % (resref, ",".join(sorted(tuples)))


_legal_set = None


def legal_variants():
    """Every fingerprint the module itself places (store stock, creature loot,
    container contents), as baked into forge_legal_inc.nss by gen-forge-legal.py.
    An item matching one of these is legally obtainable, not player-forged - the
    live check consults the same list via ForgeIsKnownLegalVariant."""
    global _legal_set
    if _legal_set is None:
        _legal_set = set()
        if os.path.isfile(LEGAL_INC):
            import re
            with open(LEGAL_INC) as fh:
                for mo in re.finditer(r'sFP == "([^"]*)"', fh.read()):
                    _legal_set.add(mo.group(1))
    return _legal_set


def read_vars(item):
    """Item-local variables as {name: value}."""
    out = {}
    for v in gval(item.get("VarTable"), []) or []:
        name = gval(v.get("Name"), "")
        if name:
            out[name] = gval(v.get("Value"), None)
    return out


def item_name(item):
    n = gval(item.get("LocalizedName"), {})
    if isinstance(n, dict) and n:
        return list(n.values())[0]
    return gval(item.get("Tag"), "") or ""


def walk_items(bic):
    """Equipped, inventory, and one level into containers (bags can't nest)."""
    for slot in gval(bic.get("Equip_ItemList"), []) or []:
        yield ("equipped", slot)
    for it in gval(bic.get("ItemList"), []) or []:
        yield ("inventory", it)
        for sub in gval(it.get("ItemList"), []) or []:
            yield ("in container", sub)


def audit_item(where, item):
    resref = (gval(item.get("TemplateResRef"), "") or "").lower()
    props = priced_props(gval(item.get("PropertiesList"), []))
    variables = read_vars(item)
    stamps = {k: variables[k] for k in FORGE_MARKERS if k in variables}
    forged_stamp = any((variables.get(k) or 0) for k in PROOF_OF_FORGING)

    rec = {
        "where": where,
        "resref": resref,
        "name": item_name(item),
        "props": sum(props.values()),
        "cost": gval(item.get("Cost"), 0) or 0,
        "stamps": stamps,
        "forged_stamp": forged_stamp,
        "matched_commit": None,
        "matched_subject": None,
    }
    rec["over_caps"] = rec["props"] > LEGAL_MAX_PROPS or rec["cost"] > LEGAL_MAX_VALUE

    cur = current_blueprint(resref)
    if cur is None:
        rec["verdict"] = "UNKNOWN_BP"
        return rec
    if props == cur:
        rec["verdict"] = "CLEAN"
        return rec
    for sha, date, subject, hprops in historical_blueprints(resref):
        if props == hprops:
            rec["verdict"] = "REBALANCED"
            rec["matched_commit"] = sha
            rec["matched_subject"] = "%s %s" % (date, subject)
            return rec
    # Deviating is fine when the deviation matches an item the module itself
    # places - the live check allows these too (ForgeIsKnownLegalVariant), which
    # is why several of them carry a FORGE_CLEAN stamp despite the drift.
    if legal_fingerprint(resref, gval(item.get("PropertiesList"), [])) \
            in legal_variants():
        rec["verdict"] = "PLACED_VARIANT"
        return rec
    rec["verdict"] = "FORGED" if forged_stamp else "SUSPECT"
    return rec


def load_bic(path):
    try:
        out = subprocess.run([NWN_GFF, "-i", path, "-k", "json"],
                             capture_output=True, text=True, check=True).stdout
        return json.loads(out)
    except Exception as e:
        print("  ! could not read %s: %s" % (path, e), file=sys.stderr)
        return None


ORDER = ["SUSPECT", "FORGED", "PLACED_VARIANT", "REBALANCED",
         "UNKNOWN_BP", "CLEAN"]


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--vault", default=os.path.expanduser(
        "~/.local/share/Neverwinter Nights Dev/servervault"))
    ap.add_argument("--repo", help="module repo to compare against "
                    "(default: this one). Use the repo whose module that vault "
                    "actually runs, e.g. --repo ../nwn_homers_lotr_s2 for the "
                    "season-2 vault.")
    ap.add_argument("--verdict", nargs="*", default=["SUSPECT", "FORGED"],
                    help="verdicts to print (default: SUSPECT FORGED); "
                         "use ALL for everything")
    ap.add_argument("--json", help="write the full findings to this file")
    args = ap.parse_args()

    if args.repo:
        global REPO, UNPACKED, LEGAL_INC
        REPO = os.path.abspath(os.path.expanduser(args.repo))
        UNPACKED = os.path.join(REPO, "unpacked")
        LEGAL_INC = os.path.join(UNPACKED, "forge_legal_inc.nss")
        if not os.path.isdir(UNPACKED):
            sys.exit("no unpacked/ in %s" % REPO)
    print("Comparing against module tree: %s" % REPO)

    if not os.path.isfile(NWN_GFF):
        sys.exit("nwn_gff not found at %s (nimble install neverwinter)" % NWN_GFF)
    if not os.path.isdir(args.vault):
        sys.exit("vault not found: %s" % args.vault)

    bics = []
    for root, _dirs, files in os.walk(args.vault):
        for fn in files:
            if fn.endswith(".bic"):
                bics.append(os.path.join(root, fn))
    bics.sort()
    print("Auditing %d character(s) in %s\n" % (len(bics), args.vault))

    findings = []
    totals = Counter()
    for path in bics:
        bic = load_bic(path)
        if bic is None:
            continue
        account = os.path.basename(os.path.dirname(path))
        char = os.path.splitext(os.path.basename(path))[0]
        for where, item in walk_items(bic):
            rec = audit_item(where, item)
            rec["account"] = account
            rec["character"] = char
            totals[rec["verdict"]] += 1
            findings.append(rec)

    show = set(ORDER) if "ALL" in args.verdict else set(args.verdict)
    shown = [f for f in findings if f["verdict"] in show]
    shown.sort(key=lambda f: (ORDER.index(f["verdict"]), -f["props"]))

    for f in shown:
        flag = "  <-- OVER CAPS" if f["over_caps"] else ""
        print("%-10s %-22s %-28s %s/%s" % (
            f["verdict"], f["resref"], f["name"][:28],
            f["account"], f["character"]))
        print("           %d priced props, cost %d, %s%s" % (
            f["props"], f["cost"], f["where"], flag))
        if f["stamps"]:
            print("           stamps: %s" % ", ".join(
                "%s=%s" % (k, v) for k, v in sorted(f["stamps"].items())))
        if f["matched_commit"]:
            print("           matches blueprint as of %s (%s)" % (
                f["matched_commit"], f["matched_subject"]))
        print()

    print("-" * 72)
    print("%d item(s) across %d character(s)" % (len(findings), len(bics)))
    for v in ORDER:
        if totals[v]:
            print("  %-11s %d" % (v, totals[v]))
    susp = [f for f in findings if f["verdict"] == "SUSPECT" and f["over_caps"]]
    print()
    if susp:
        print("%d SUSPECT item(s) are ALSO over the caps - these are the ones that"
              % len(susp))
        print("would have been contraband under the old rule. Review by hand.")
    else:
        print("No SUSPECT item is over the caps: nothing in circulation looks like")
        print("gear forged past the ceiling before the forge stamps existed.")

    if args.json:
        with open(args.json, "w") as fh:
            json.dump(findings, fh, indent=2)
        print("\nwrote %s" % args.json)


if __name__ == "__main__":
    main()
