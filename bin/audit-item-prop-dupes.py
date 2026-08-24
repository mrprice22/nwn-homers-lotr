#!/usr/bin/env python3
"""Find (and repair) player items whose item properties were duplicated by the
polymorph item-merge race.

WHY THIS EXISTS
    Until 58c4384c918, five of the six polymorph scripts ran ShapeMergeAll() in
    the same script tick that applied EffectPolymorph. When the engine had not
    yet stripped the caster's gear, GetItemInSlot(INVENTORY_SLOT_RIGHTHAND)
    still returned the caster's OWN weapon, and the merge then ran

        IPWildShapeCopyItemProperties(oWeapon, oWeapon)

    which copies every property of an item onto ITSELF as
    DURATION_TYPE_PERMANENT. The weapon is a real, saved object, so the
    duplicates persist in the player's .bic - and each further bad cast doubles
    the list again (2x, 4x, 8x ...). Only the right-hand weapon could be hit:
    with an empty hand the merge source is the gloves and the targets are the
    form's claws, never the gloves themselves.

    The code path is closed. This closes the damage it already did.

WHAT COUNTS AS DUPLICATED
    The whole property list is an exact k-fold repetition of a smaller multiset
    (k >= 2): every distinct property appears a multiple of k times. That is the
    shape a self-copy leaves and nothing else does - a forge enchant adds ONE
    property, it does not multiply the list. k is the greatest common divisor of
    the property counts, so a 4x weapon is detected as 4x and repaired in one
    pass.

    An item whose properties are all distinct can never match (gcd would be 1),
    so a normal weapon is never touched. The residual false-positive shape is an
    item that legitimately carries every one of its properties exactly k times;
    --require-weapon (the default) keeps the sweep to weapons, and --blueprint
    cross-checks the collapsed list against the module blueprint when the item
    still carries its TemplateResRef.

USAGE
    python3 bin/audit-item-prop-dupes.py                     # this realm
    python3 bin/audit-item-prop-dupes.py --vault DIR ...     # other realms' vaults
    python3 bin/audit-item-prop-dupes.py --all-items         # not just weapons
    python3 bin/audit-item-prop-dupes.py --fix               # repair in place

    A character's gear is only half of it: a weapon corrupted before it was
    banked sits in a bank box or player-house chest, which are CPDB-compressed
    serialized objects in bankdb/housechest rather than in the .bic. Both are
    scanned by default for whichever realms are being audited.

    --fix backs up every changed .bic and every changed campaign DB to
    <realm>/bic-backup-<stamp>/ first, and refuses to run while that realm's
    server is up: nwserver rewrites characters on save and holds the campaign
    DBs open, so a repair now would be overwritten or fought.
"""

import argparse
import json
import math
import os
import shutil
import subprocess
import sys
import tempfile
import time
from collections import Counter
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
STAMP = time.strftime("%Y%m%d_%H%M%S")
NWN_GFF = os.environ.get("NWN_GFF", str(Path.home() / ".nimble" / "bin" / "nwn_gff"))

# Weapon base-item rows, read from hak_2da/baseitems.2da (WeaponType != 0) so
# the module's own custom weapons are covered without a hand-maintained list.
def weapon_base_items() -> set:
    import shlex
    path = REPO / "hak_2da" / "baseitems.2da"
    try:
        lines = path.read_text(errors="replace").splitlines()
    except OSError:
        return set()
    header = lines[2].split()
    col = header.index("WeaponType")
    rows = set()
    for line in lines[3:]:
        cells = shlex.split(line)
        if len(cells) < len(header) + 1:
            continue
        if cells[1 + col] not in ("****", "0"):
            rows.add(int(cells[0]))
    return rows


# The property fields that make one property distinct from another.
PROP_KEYS = ("PropertyName", "Subtype", "CostTable", "CostValue",
             "Param1", "Param1Value", "ChanceAppear", "UsesPerDay", "Useable")
# The subset a .uti blueprint actually stores. An item created in game carries
# Useable/UsesPerDay (and CustomTag) that the blueprint leaves to the engine
# defaults, so a blueprint comparison has to ignore them or every item looks
# changed. Defaults fill in fields a blueprint may omit entirely.
BP_KEYS = PROP_KEYS[:-2]
BP_DEFAULTS = {"Subtype": 0, "CostTable": 0, "CostValue": 0,
               "Param1": 255, "Param1Value": 0, "ChanceAppear": 100}


def gff_to_json(path: Path) -> dict:
    out = subprocess.run([NWN_GFF, "-i", str(path), "-k", "json"],
                         check=True, capture_output=True)
    return json.loads(out.stdout)


def json_to_gff(data: dict, dest: Path, fmt: str) -> None:
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as fh:
        json.dump(data, fh)
        tmp = Path(fh.name)
    try:
        subprocess.run([NWN_GFF, "-i", str(tmp), "-l", "json",
                        "-o", str(dest), "-k", fmt], check=True,
                       capture_output=True)
    finally:
        tmp.unlink(missing_ok=True)


def val(struct: dict, key: str, default=None):
    node = struct.get(key)
    return node.get("value", default) if isinstance(node, dict) else default


def prop_key(prop: dict) -> tuple:
    return tuple((k, val(prop, k)) for k in PROP_KEYS)


def prop_key_ident(prop: dict) -> tuple:
    """Identity of a property as a blueprint can express it."""
    return tuple((k, val(prop, k, BP_DEFAULTS.get(k))) for k in BP_KEYS)


def walk_items(container: dict, where: str = ""):
    """Yield (item_struct, where) for every item held by a character or a
    stored container, at any bag depth."""
    for field, label in (("Equip_ItemList", "equipped"), ("ItemList", "inventory")):
        node = container.get(field)
        if not isinstance(node, dict):
            continue
        for item in node.get("value", []):
            here = f"{where}/{label}" if where else label
            yield item, here
            yield from walk_items(item, here + "/bag")


def item_name(item: dict) -> str:
    name = item.get("LocalizedName")
    if isinstance(name, dict):
        v = name.get("value")
        if isinstance(v, dict):
            for entry in v.values():
                if entry:
                    return str(entry)
    return val(item, "TemplateResRef", "?") or "?"


def duplication_factor(item: dict) -> int:
    """k >= 2 when the property list is an exact k-fold repetition, else 1."""
    props = item.get("PropertiesList")
    if not isinstance(props, dict):
        return 1
    entries = props.get("value", [])
    if len(entries) < 2:
        return 1
    counts = Counter(prop_key(p) for p in entries)
    k = 0
    for n in counts.values():
        k = math.gcd(k, n)
    return k if k >= 2 else 1


_BLUEPRINTS: dict = {}


def matches_blueprint(item: dict, k: int) -> bool:
    """TRUE if the item's property list is exactly what its blueprint ships.

    The one shape that looks like a k-fold self-copy without being one: a
    blueprint that legitimately repeats each of its properties k times. If the
    item still matches its blueprint property-for-property, nothing was added
    to it and there is nothing to repair.
    """
    resref = (val(item, "TemplateResRef", "") or "").lower()
    if not resref:
        return False
    if resref not in _BLUEPRINTS:
        path = REPO / "unpacked" / f"{resref}.uti.json"
        try:
            blueprint = json.loads(path.read_text())
            props = blueprint.get("PropertiesList", {}).get("value", [])
            _BLUEPRINTS[resref] = Counter(prop_key_ident(p) for p in props)
        except (OSError, ValueError):
            _BLUEPRINTS[resref] = None
    expected = _BLUEPRINTS[resref]
    if expected is None:
        return False
    return Counter(prop_key_ident(p)
                   for p in item["PropertiesList"]["value"]) == expected


def collapse(item: dict, k: int) -> None:
    """Keep 1/k of each distinct property, preserving the original order."""
    entries = item["PropertiesList"]["value"]
    kept, seen = [], Counter()
    quota = Counter()
    for p in entries:
        quota[prop_key(p)] += 1
    for p in entries:
        key = prop_key(p)
        if seen[key] < quota[key] // k:
            kept.append(p)
            seen[key] += 1
    item["PropertiesList"]["value"] = kept


def read_env(path: Path) -> dict:
    env = {}
    try:
        lines = path.read_text().splitlines()
    except OSError:
        return env
    for line in lines:
        if "=" in line and not line.strip().startswith("#"):
            k, _, v = line.partition("=")
            v = v.split("#")[0].strip().strip('"').strip("'")
            env[k.strip()] = v.replace("$HOME", str(Path.home()))
    return env


def realm_module_for_vault(vault: Path) -> str | None:
    """The NWN_MODULE of the realm that owns this vault, if we know it.

    Every season is its own repo with its own server.env, so the owner is found
    by matching NWN_HOME_DIR. A vault that belongs to no known realm (a scratch
    copy, an old backup) returns None and is not guarded - there is no live
    server that could overwrite it.
    """
    home = str(vault.parent.resolve())
    for repo in sorted(REPO.parent.glob("nwn_homers_lotr*")):
        env = read_env(repo / "server.env")
        nwn_home = env.get("NWN_HOME_DIR")
        if nwn_home and str(Path(nwn_home).resolve()) == home:
            return env.get("NWN_MODULE")
    return None


def server_running(vault: Path) -> str | None:
    """A live nwserver hosting THIS vault's realm, else None.

    Matching is on the -module argument, because the server runs containerized:
    its -userdirectory is the in-container path and says nothing about which
    host vault it writes.
    """
    module = realm_module_for_vault(vault)
    if not module:
        return None
    try:
        out = subprocess.run(["pgrep", "-af", "nwserver"], capture_output=True,
                             text=True).stdout
    except OSError:
        return None
    for line in out.splitlines():
        if f"-module {module}" in line:
            return f"{module} (pid {line.split()[0]})"
    return None


# Bank boxes and player-house chests are not in the .bic: they are serialized
# objects in a campaign DB (NWNX's db table), one CPDB-compressed GFF per box.
# A weapon corrupted before it was banked is sitting in one of these.
CPDB_MAGIC = "CPDB"
NWN_CBUF = os.environ.get(
    "NWN_COMPRESSEDBUF", str(Path.home() / ".nimble" / "bin" / "nwn_compressedbuf"))


def blob_to_json(payload: bytes) -> dict | None:
    with tempfile.NamedTemporaryFile(suffix=".bin", delete=False) as fh:
        fh.write(payload)
        raw = Path(fh.name)
    gff = raw.with_suffix(".gff")
    try:
        subprocess.run([NWN_CBUF, "-d", CPDB_MAGIC, "-i", str(raw), "-o", str(gff)],
                       check=True, capture_output=True)
        out = subprocess.run([NWN_GFF, "-i", str(gff), "-k", "json"],
                             check=True, capture_output=True)
        return json.loads(out.stdout)
    except (subprocess.CalledProcessError, ValueError):
        return None
    finally:
        raw.unlink(missing_ok=True)
        gff.unlink(missing_ok=True)


def json_to_blob(data: dict) -> bytes:
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as fh:
        json.dump(data, fh)
        js = Path(fh.name)
    gff = js.with_suffix(".gff")
    packed = js.with_suffix(".bin")
    try:
        subprocess.run([NWN_GFF, "-i", str(js), "-l", "json", "-o", str(gff),
                        "-k", "gff"], check=True, capture_output=True)
        subprocess.run([NWN_CBUF, "-c", CPDB_MAGIC, "-i", str(gff), "-o", str(packed)],
                       check=True, capture_output=True)
        return packed.read_bytes()
    finally:
        for f in (js, gff, packed):
            f.unlink(missing_ok=True)


def audit_db(dbfile: Path, args, findings: list) -> None:
    import sqlite3
    uri = f"file:{dbfile}?mode=ro"
    con = sqlite3.connect(uri, uri=True)
    try:
        rows = con.execute(
            "select varname, playerid, payload from db where vartype = 79").fetchall()
    except sqlite3.Error as exc:
        print(f"  [skip] {dbfile.name}: {exc}", file=sys.stderr)
        return
    finally:
        con.close()

    repairs = []
    for varname, playerid, payload in rows:
        data = blob_to_json(bytes(payload))
        if data is None:
            print(f"  [skip] {dbfile.name}:{varname}/{playerid}: not a CPDB object",
                  file=sys.stderr)
            continue
        # The stored object is itself an item (a bank box is a container UTI),
        # so check it as well as everything inside it.
        changed = False
        for item, where in [(data, "box")] + list(walk_items(data, "box")):
            if "PropertiesList" not in item:
                continue
            k = duplication_factor(item)
            if k < 2:
                continue
            base = val(item, "BaseItem", -1)
            if not args.all_items and base not in args.weapons:
                continue
            if matches_blueprint(item, k):
                continue
            total = len(item["PropertiesList"]["value"])
            findings.append({
                "character": playerid or "?", "cdkey": "", "file": str(dbfile),
                "item": item_name(item), "resref": val(item, "TemplateResRef", ""),
                "base_item": base, "where": f"{dbfile.stem}:{varname}/{where}",
                "factor": k, "properties": total, "properties_after": total // k,
            })
            if args.fix:
                collapse(item, k)
                changed = True
        if changed:
            repairs.append((varname, playerid, json_to_blob(data)))

    if repairs and args.fix:
        args.backup_dir.mkdir(parents=True, exist_ok=True)
        shutil.copy2(dbfile, args.backup_dir / dbfile.name)
        con = sqlite3.connect(dbfile)
        with con:
            for varname, playerid, blob in repairs:
                con.execute("update db set payload = ? where varname = ? "
                            "and playerid = ?", (blob, varname, playerid))
        con.close()
        print(f"  [fixed] {dbfile} ({len(repairs)} stored object(s))")


def audit_vault(vault: Path, args, findings: list) -> None:
    for bic in sorted(vault.rglob("*.bic")):
        try:
            data = gff_to_json(bic)
        except subprocess.CalledProcessError as exc:
            print(f"  [skip] {bic.name}: nwn_gff failed ({exc})", file=sys.stderr)
            continue
        hits, changed = [], False
        for item, where in walk_items(data):
            k = duplication_factor(item)
            if k < 2:
                continue
            base = val(item, "BaseItem", -1)
            if not args.all_items and base not in args.weapons:
                continue
            if matches_blueprint(item, k):
                # The blueprint really does carry every property k times (a
                # handful of module items do, e.g. it_mneck002's four
                # regeneration properties). Not this bug.
                continue
            total = len(item["PropertiesList"]["value"])
            hits.append({
                "character": bic.stem, "cdkey": bic.parent.name,
                "file": str(bic), "item": item_name(item),
                "resref": val(item, "TemplateResRef", ""), "base_item": base,
                "where": where, "factor": k,
                "properties": total, "properties_after": total // k,
            })
            if args.fix:
                collapse(item, k)
                changed = True
        findings.extend(hits)
        if changed and args.fix:
            backup = args.backup_dir / bic.parent.name
            backup.mkdir(parents=True, exist_ok=True)
            shutil.copy2(bic, backup / bic.name)
            json_to_gff(data, bic, "gff")
            print(f"  [fixed] {bic} ({len(hits)} item(s))")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--vault", action="append", type=Path, default=None,
                    help="servervault directory (repeatable); default: this repo's realm")
    ap.add_argument("--db", action="append", type=Path, default=None,
                    help="campaign DB holding stored items (bankdb/housechest); "
                         "default: every such DB of this repo's realm")
    ap.add_argument("--all-items", action="store_true",
                    help="check every item, not just weapons")
    ap.add_argument("--fix", action="store_true",
                    help="collapse the duplicates in place (backs up first)")
    ap.add_argument("--force", action="store_true",
                    help="--fix even though a server is running (never do this)")
    ap.add_argument("--json", type=Path, help="write the findings as JSON")
    args = ap.parse_args()

    if not args.vault:
        env = {}
        for line in (REPO / "server.env").read_text().splitlines():
            if "=" in line and not line.strip().startswith("#"):
                k, _, v = line.partition("=")
                env[k.strip()] = v.strip().strip('"').replace("$HOME", str(Path.home()))
        home = env.get("NWN_HOME_DIR")
        if not home:
            ap.error("server.env has no NWN_HOME_DIR; pass --vault")
        args.vault = [Path(home) / "servervault"]

    if args.db is None:
        args.db = []
        for vault in args.vault:
            for name in ("bankdb.sqlite3", "housechest.sqlite3"):
                cand = vault.parent / "database" / name
                if cand.is_file():
                    args.db.append(cand)

    args.weapons = weapon_base_items()
    if not args.weapons and not args.all_items:
        ap.error("could not read hak_2da/baseitems.2da; pass --all-items")
    args.backup_dir = Path(tempfile.gettempdir())  # replaced per vault below
    findings: list = []
    for vault in args.vault:
        if not vault.is_dir():
            print(f"[skip] {vault}: not a directory", file=sys.stderr)
            continue
        print(f"[scan] {vault}")
        if args.fix and not args.force:
            proc = server_running(vault)
            if proc:
                print(f"  [abort] a server is running ({proc}) - a repair now "
                      f"would be overwritten on the next character save.\n"
                      f"          Stop the realm (or wait for a reboot-on-empty "
                      f"cycle) and re-run.", file=sys.stderr)
                return 2
        args.backup_dir = vault.parent / f"bic-backup-{STAMP}"
        audit_vault(vault, args, findings)

    for dbfile in args.db:
        if not dbfile.is_file():
            print(f"[skip] {dbfile}: not a file", file=sys.stderr)
            continue
        print(f"[scan] {dbfile}")
        if args.fix and not args.force:
            proc = server_running(dbfile.parent.parent / "servervault")
            if proc:
                print(f"  [abort] a server is running ({proc}) - it holds this "
                      f"database open and would overwrite the repair.",
                      file=sys.stderr)
                return 2
        args.backup_dir = dbfile.parent.parent / f"bic-backup-{STAMP}"
        audit_db(dbfile, args, findings)

    if not findings:
        print("clean: no duplicated property lists found")
    else:
        print(f"\n{len(findings)} item(s) with duplicated properties:")
        for f in sorted(findings, key=lambda f: -f["factor"]):
            print(f"  {f['factor']}x  {f['properties']:>3} -> {f['properties_after']:<3} "
                  f"{f['character']:<20} {f['where']:<14} {f['item']} "
                  f"[{f['resref']}]")
        if not args.fix:
            print("\nre-run with --fix to collapse them "
                  "(every changed .bic and DB is backed up first)")
    if args.json:
        args.json.write_text(json.dumps(findings, indent=1))
        print(f"wrote {args.json}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
