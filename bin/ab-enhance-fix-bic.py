#!/usr/bin/env python3
"""ab-enhance-fix-bic.py -- repair stale ab-enhance items in player .bic files.

Phase 2 of the ab-enhance-stack-bug fix. The module blueprints + placed instances
were fixed by bin/ab-enhance-apply.py, but items players already carry live in
their .bic character files (independent GFF snapshots) and are untouched. This
tool finds weapons in the server vault that still carry BOTH a generic Attack
Bonus (56) and Enhancement Bonus (6) and collapses them to the single Enhancement
Bonus value recorded in ab-enhance-audit.csv -- matching the updated blueprints.

SAFETY (read the runbook in BIC-EDITING.md):
  * Dry-run by default; pass --apply to write.
  * Never touches a logged-in character. Exclude live players by FirstName with
    --exclude "Name" (repeatable). Aborts if an exclude name matches no .bic.
    Best-effort: also skips .bic files held open by a process or modified in the
    last --recent-min minutes.
  * Before writing, every .bic is backed up under --backup-dir (mirrors vault
    layout) AND copied alongside as <name>.bic.pre-abfix.
  * After writing, the new .bic is re-converted to JSON and compared against the
    intended edit; on any mismatch it is restored from backup and the run aborts.
  * Idempotent: a second run finds nothing to change.

Conservative match: only an item node carrying BOTH generic (Subtype 0) AB and
ENH whose TemplateResRef is in the plan is repaired. Customized/single-prop items
are left alone.
"""
import argparse
import csv
import datetime
import glob
import json
import os
import shutil
import subprocess
import sys
import tempfile

PROP_ENHANCEMENT = 6
PROP_ATTACK_BONUS = 56
COST_TABLE = 2

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CSV = os.path.join(REPO, "ab-enhance-audit.csv")
DEFAULT_VAULT = os.path.expanduser(
    "~/.local/share/Neverwinter Nights/servervault"
)
DEFAULT_GFF = os.path.expanduser(
    "~/.nimble/pkgs2/neverwinter-2.1.2-5952d15f313299678f541b10957ec8c475ed880c/nwn_gff"
)
DEFAULT_BACKUP_ROOT = os.path.expanduser("~/nwn-bic-backups")
CHANGES_CSV = os.path.join(REPO, "ab-enhance-bic-changes.csv")


# --- property transform (same semantics as bin/ab-enhance-apply.py) -----------

def is_generic(p, prop_name):
    return (
        isinstance(p, dict)
        and p.get("PropertyName", {}).get("value") == prop_name
        and p.get("Subtype", {}).get("value", 0) == 0
    )


def make_prop(prop_name, value):
    return {
        "__struct_id": 0,
        "ChanceAppear": {"type": "byte", "value": 100},
        "CostTable": {"type": "byte", "value": COST_TABLE},
        "CostValue": {"type": "word", "value": value},
        "Param1": {"type": "byte", "value": 255},
        "Param1Value": {"type": "byte", "value": 0},
        "PropertyName": {"type": "word", "value": prop_name},
        "Subtype": {"type": "word", "value": 0},
    }


def generic_vals(props, prop_name):
    return [
        p["CostValue"]["value"]
        for p in props
        if is_generic(p, prop_name)
    ]


def has_both_generic(item):
    pl = item.get("PropertiesList", {})
    props = pl.get("value", []) if isinstance(pl, dict) else []
    return bool(generic_vals(props, PROP_ATTACK_BONUS)) and bool(
        generic_vals(props, PROP_ENHANCEMENT)
    )


def transform_to_enh(item, value):
    """Collapse generic AB/ENH to a single ENH=value in place. Return True if changed."""
    pl = item["PropertiesList"]
    props = pl["value"]
    new = [p for p in props if not is_generic(p, PROP_ATTACK_BONUS)]
    if any(is_generic(p, PROP_ENHANCEMENT) for p in new):
        for p in new:
            if is_generic(p, PROP_ENHANCEMENT):
                p["CostValue"]["value"] = value
    else:
        new.append(make_prop(PROP_ENHANCEMENT, value))
    if new != props:
        pl["value"] = new
        return True
    return False


def walk_items(o):
    if isinstance(o, dict):
        if "TemplateResRef" in o and "PropertiesList" in o:
            yield o
        for v in o.values():
            yield from walk_items(v)
    elif isinstance(o, list):
        for v in o:
            yield from walk_items(v)


# --- plan map (resref -> enhancement value) -----------------------------------

def load_plan():
    plan = {}
    for r in csv.DictReader(open(CSV, encoding="utf-8")):
        keep = (r.get("keep") or "").strip().lower()
        val = (r.get("value") or "").strip().lstrip("+")
        if keep == "enhancement" and val.isdigit():
            plan[r["resref"]] = int(val)
        # (Phase 1 resolved every row to enhancement; an 'attack' keep would
        #  need its own branch here -- none exist, so we keep this strict.)
    return plan


# --- gff helpers --------------------------------------------------------------

def gff_to_obj(gff, path):
    r = subprocess.run(
        [gff, "-i", path, "-o", "-", "-k", "json"],
        capture_output=True, text=True,
    )
    if r.returncode != 0:
        raise RuntimeError(f"gff->json failed for {path}: {r.stderr.strip()}")
    return json.loads(r.stdout)


def obj_to_gff(gff, obj, out_path):
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as tf:
        json.dump(obj, tf)
        tmp = tf.name
    try:
        r = subprocess.run(
            [gff, "-i", tmp, "-l", "json", "-o", out_path],
            capture_output=True, text=True,
        )
        if r.returncode != 0:
            raise RuntimeError(f"json->gff failed for {out_path}: {r.stderr.strip()}")
    finally:
        os.unlink(tmp)


def locstr(field):
    v = field.get("value") if isinstance(field, dict) else None
    if isinstance(v, dict):
        return v.get("0") or (next(iter(v.values())) if v else "")
    return v or ""


def file_in_use(path, recent_min):
    # Held open by any process?
    for tool in (["lsof", "--", path], ["fuser", path]):
        try:
            r = subprocess.run(tool, capture_output=True, text=True)
            if r.returncode == 0 and r.stdout.strip():
                return "open"
        except FileNotFoundError:
            pass
    # Recently modified?
    if recent_min > 0:
        age_min = (datetime.datetime.now().timestamp() - os.path.getmtime(path)) / 60
        if age_min < recent_min:
            return f"modified {age_min:.0f}m ago"
    return None


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--vault", default=DEFAULT_VAULT)
    ap.add_argument("--nwn-gff", default=DEFAULT_GFF)
    ap.add_argument("--backup-dir", default=DEFAULT_BACKUP_ROOT)
    ap.add_argument("--exclude", action="append", default=[],
                    help="character FirstName to skip (repeatable; live players)")
    ap.add_argument("--recent-min", type=int, default=10,
                    help="skip .bic modified within this many minutes (0=off)")
    ap.add_argument("--apply", action="store_true",
                    help="write changes (default is dry-run)")
    args = ap.parse_args()

    if not os.path.exists(args.nwn_gff):
        print(f"nwn_gff not found: {args.nwn_gff}", file=sys.stderr)
        return 2
    plan = load_plan()
    if not plan:
        print(f"no enhancement rows in {CSV}", file=sys.stderr)
        return 2
    exclude = {n.strip().lower() for n in args.exclude}

    bics = sorted(glob.glob(os.path.join(args.vault, "*", "*.bic")))
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    backup_root = os.path.join(args.backup_dir, f"abfix-{stamp}")

    # Validate exclude names match real characters before doing anything.
    if exclude:
        seen = set()
        for b in bics:
            try:
                d = gff_to_obj(args.nwn_gff, b)
            except RuntimeError:
                continue
            seen.add(locstr(d.get("FirstName", {})).strip().lower())
        missing = exclude - seen
        if missing:
            print(f"ABORT: --exclude name(s) match no character FirstName: "
                  f"{sorted(missing)}", file=sys.stderr)
            return 2

    changes = []          # rows for the change log
    skipped_excluded = []
    skipped_inuse = []
    files_changed = 0
    items_changed = 0

    for b in bics:
        rel = os.path.relpath(b, args.vault)
        try:
            d = gff_to_obj(args.nwn_gff, b)
        except RuntimeError as e:
            print(f"  WARN cannot read {rel}: {e}", file=sys.stderr)
            continue
        name = locstr(d.get("FirstName", {})).strip()
        if name.lower() in exclude:
            skipped_excluded.append((rel, name))
            continue

        # Find stale, in-plan items.
        targets = []
        for item in walk_items(d):
            trr = item.get("TemplateResRef", {})
            trr = trr.get("value") if isinstance(trr, dict) else None
            if trr in plan and has_both_generic(item):
                props = item["PropertiesList"]["value"]
                targets.append((
                    item, trr,
                    max(generic_vals(props, PROP_ATTACK_BONUS)),
                    max(generic_vals(props, PROP_ENHANCEMENT)),
                    plan[trr],
                ))
        if not targets:
            continue

        for _, trr, old_ab, old_enh, new_enh in targets:
            changes.append(dict(account=os.path.dirname(rel), bic=os.path.basename(rel),
                                 character=name, resref=trr, old_ab=old_ab,
                                 old_enh=old_enh, new_enh=new_enh))

        if not args.apply:
            files_changed += 1
            items_changed += len(targets)
            print(f"  [dry] {rel} ({name or '?'}): "
                  f"{len(targets)} item(s) -> "
                  + ", ".join(f"{t[1]}(AB{t[2]}/EN{t[3]}->EN{t[4]})" for t in targets))
            continue

        # --- apply path: in-use guard, backup, edit, write, verify ---
        reason = file_in_use(b, args.recent_min)
        if reason:
            skipped_inuse.append((rel, name, reason))
            print(f"  SKIP in-use {rel} ({name}): {reason}", file=sys.stderr)
            continue

        # Backup (mirrored tree + alongside).
        bak = os.path.join(backup_root, rel)
        os.makedirs(os.path.dirname(bak), exist_ok=True)
        shutil.copy2(b, bak)
        shutil.copy2(b, b + ".pre-abfix")

        # Apply edits and compute the intended JSON.
        for item, trr, *_ in targets:
            transform_to_enh(item, plan[trr])
        intended = json.dumps(d, sort_keys=True)

        # Write then verify by re-reading.
        obj_to_gff(args.nwn_gff, d, b)
        reread = gff_to_obj(args.nwn_gff, b)
        if json.dumps(reread, sort_keys=True) != intended:
            shutil.copy2(bak, b)  # restore
            print(f"  ABORT: verify mismatch on {rel}; restored from backup.",
                  file=sys.stderr)
            return 3

        files_changed += 1
        items_changed += len(targets)
        print(f"  fixed {rel} ({name}): {len(targets)} item(s)")

    # Change log.
    if changes:
        with open(CHANGES_CSV, "w", newline="", encoding="utf-8") as fh:
            w = csv.DictWriter(fh, fieldnames=["account", "bic", "character",
                                               "resref", "old_ab", "old_enh", "new_enh"])
            w.writeheader()
            w.writerows(changes)

    mode = "APPLIED" if args.apply else "DRY-RUN"
    print(f"\n{mode}: {items_changed} item(s) across {files_changed} character file(s).")
    if exclude:
        print(f"  excluded (logged-in): {sorted(exclude)} "
              f"-> {len(skipped_excluded)} file(s) skipped")
    if skipped_inuse:
        print(f"  skipped in-use: {len(skipped_inuse)} file(s)")
    if args.apply:
        print(f"  backups: {backup_root}  (+ *.bic.pre-abfix alongside)")
    if changes:
        print(f"  change log: {CHANGES_CSV}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
