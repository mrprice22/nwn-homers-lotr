#!/usr/bin/env python3
"""grant-feats.py — hand a character feats it is owed, offline, in its .bic.

WHY THIS EXISTS
---------------
`bin/audit-devcrit-lost.py` found characters that spent feat picks on Devastating
Critical (Unarmed) and got nothing: the feat was stripped and written out of the
.bic, so the level-up screen offered it again at the next feat level (roadmap
buged-dev-crit). The feat itself is restored in game at the next login. The SPARE
picks cannot be: a second pick on the same feat bought a feat the player never
received, and only they can say what they would have taken instead.

There is no DM console on this server, so "log in as a DM and grant it" is not
available. The character file is, and it is the same route `bin/ab-enhance-fix-bic.py`
already takes.

THE ONE RULE: THE PLAYER MUST BE OFFLINE.
The server holds an open character in memory and writes it back on logout or
export, so an edit made under a logged-in player is silently overwritten by their
own session. This refuses to run against a realm whose server is up unless you
confirm the player is offline.

Every run backs the .bic up first and appends a line to the grant ledger
(~/.local/share/nwn-feat-grants.jsonl), so what was handed out is auditable long
after the conversation that agreed it.

Usage:
  bin/grant-feats.py --bic PATH --feat EpicWeaponFocusUnarmed --feat 891
  bin/grant-feats.py --realm live --character "PiC Finger of Death" \\
      --feat ArmourSkinEpic --feat GreatStrength1 --apply

  --feat takes a feat.2da LABEL, a FEAT_* Constant, or a row id; repeat it once
  per feat. Dry run unless --apply.
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
FEAT_2DA = REPO / "hak_2da" / "feat.2da"
NWN_GFF = os.environ.get("NWN_GFF", os.path.expanduser("~/.nimble/bin/nwn_gff"))
LEDGER = Path(os.path.expanduser("~/.local/share/nwn-feat-grants.jsonl"))


def die(msg):
    print(f"grant-feats: error: {msg}", file=sys.stderr)
    sys.exit(1)


def env_get(text, key):
    m = re.search(rf'^{key}=["\']?(.*?)["\']?\s*(?:#.*)?$', text, re.M)
    return m.group(1).strip() if m else ""


def realms():
    """(role, repo, home_dir) for every sibling realm — the same discovery rule
    as bin/audit-devcrit-lost.py."""
    out = []
    for repo in sorted(REPO.parent.glob("nwn_homers_lotr*")):
        try:
            text = (repo / "server.env").read_text(encoding="utf-8")
        except OSError:
            continue
        home = env_get(text, "NWN_HOME_DIR")
        if not home:
            continue
        out.append((env_get(text, "SEASON_ROLE") or "?", repo,
                    Path(os.path.expandvars(home.replace("$HOME", str(Path.home()))))))
    return out


def load_feats():
    """{label.lower(): row, constant.lower(): row, str(row): row} from feat.2da."""
    table = {}
    names = {}
    lines = FEAT_2DA.read_bytes().decode("latin-1").splitlines()
    header = lines[2].split()
    const_i = 1 + header.index("Constant") if "Constant" in header else None
    for line in lines[3:]:
        cells = line.split()
        if not cells or not cells[0].isdigit():
            continue
        row = int(cells[0])
        label = cells[1]
        names[row] = label
        table[label.lower()] = row
        table[str(row)] = row
        if const_i and len(cells) > const_i and cells[const_i] not in ("****", ""):
            table[cells[const_i].lower()] = row
    return table, names


def gff_json(path):
    out = subprocess.run([NWN_GFF, "-i", str(path), "-k", "json"], capture_output=True)
    if out.returncode != 0:
        die(f"nwn_gff could not read {path}: {out.stderr.decode(errors='replace')[:200]}")
    return json.loads(out.stdout)


def gff_write(data, path):
    """json -> gff, the same invocation bin/ab-enhance-fix-bic.py uses.

    The output format is inferred from the OUTPUT FILE's extension, so there is
    no -k here; passing one ("-k bic") fails with "Not a supported file format",
    because -k names the json/gff container, not the resource type. Writing
    through a temp file rather than stdin for the same reason: nwn_gff needs a
    real path to infer from.
    """
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as tf:
        json.dump(data, tf)
        tmp = tf.name
    try:
        out = subprocess.run([NWN_GFF, "-i", tmp, "-l", "json", "-o", str(path)],
                             capture_output=True)
        if out.returncode != 0:
            die(f"nwn_gff could not write {path}: "
                f"{out.stderr.decode(errors='replace')[:200]}")
    finally:
        os.unlink(tmp)


def server_running(repo):
    inst = repo.name
    r = subprocess.run(["systemctl", "--user", "is-active",
                        f"nwn-season-server@{inst}.service"], capture_output=True)
    return r.stdout.decode().strip() == "active"


def main():
    ap = argparse.ArgumentParser(description="Grant feats to a character's .bic.")
    ap.add_argument("--bic", type=Path, help="path to the character file")
    ap.add_argument("--realm", help="SEASON_ROLE (live/dev/archive) — with --character")
    ap.add_argument("--character", help="character name, as the audit prints it")
    ap.add_argument("--feat", action="append", default=[], metavar="FEAT",
                    help="feat.2da LABEL, FEAT_* constant, or row id; repeatable")
    ap.add_argument("--apply", action="store_true", help="write (default is a dry run)")
    ap.add_argument("--player-is-offline", action="store_true",
                    help="confirm the player is not logged in; required when the "
                         "realm's server is running")
    ap.add_argument("--note", default="", help="why, recorded in the ledger")
    args = ap.parse_args()

    if not os.path.exists(NWN_GFF):
        die(f"nwn_gff not found at {NWN_GFF} — set NWN_GFF")
    if not args.feat:
        die("no --feat given")

    repo = None
    bic = args.bic
    if bic is None:
        if not (args.realm and args.character):
            die("give --bic, or --realm and --character")
        for role, r, home in realms():
            if role != args.realm:
                continue
            repo = r
            for cand in sorted((home / "servervault").glob("*/*.bic")):
                data = gff_json(cand)
                first = (data.get("FirstName", {}).get("value") or {}).get("0", "")
                last = (data.get("LastName", {}).get("value") or {}).get("0", "")
                if " ".join(x for x in (first, last) if x).strip() == args.character:
                    bic = cand
                    break
            break
        if bic is None:
            die(f"no character named {args.character!r} in the {args.realm} vault")
    else:
        for role, r, home in realms():
            if str(bic).startswith(str(home)):
                repo = r
                break

    # Only a WRITE is dangerous under a live player; a dry run reads and reports,
    # so refusing it would just make the safe step harder than the unsafe one.
    if args.apply and repo is not None and server_running(repo) \
            and not args.player_is_offline:
        die(f"{repo.name}'s server is RUNNING. An edit made while the player is "
            "logged in is overwritten by their own session on logout. Confirm "
            "they are offline and re-run with --player-is-offline.")

    table, names = load_feats()
    wanted = []
    for f in args.feat:
        row = table.get(f.lower())
        if row is None:
            die(f"unknown feat {f!r} — not a label, constant or row id in hak_2da/feat.2da")
        wanted.append(row)

    data = gff_json(bic)
    feat_list = data.setdefault("FeatList", {"type": "list", "value": []})
    held = {f["Feat"]["value"] for f in feat_list["value"]}

    print(f"character : {bic}")
    print(f"realm     : {repo.name if repo else '<unknown>'}")
    print(f"feats held: {len(held)}")
    to_add = []
    for row in wanted:
        if row in held:
            print(f"  skip {row:5} {names.get(row, '?')} — already held")
        else:
            to_add.append(row)
            print(f"  add  {row:5} {names.get(row, '?')}")
    if not to_add:
        print("nothing to do.")
        return 0

    if not args.apply:
        print(f"\nDry run. Re-run with --apply to write {len(to_add)} feat(s).")
        return 0

    backup = bic.with_suffix(f".bic.bak-{time.strftime('%Y%m%d-%H%M%S')}")
    shutil.copy2(bic, backup)
    print(f"backed up -> {backup}")

    for row in to_add:
        feat_list["value"].append({"__struct_id": 1, "Feat": {"type": "word", "value": row}})
    # Keep the list ordered the way the engine writes it; nothing depends on it,
    # but a diff against a later export stays readable.
    feat_list["value"].sort(key=lambda f: f["Feat"]["value"])
    gff_write(data, bic)

    # Read it back rather than trust the write — a .bic that will not parse is a
    # character that will not load.
    reread = gff_json(bic)
    now_held = {f["Feat"]["value"] for f in reread["FeatList"]["value"]}
    missing = [r for r in to_add if r not in now_held]
    if missing:
        shutil.copy2(backup, bic)
        die(f"verification failed (missing {missing}); restored from {backup}")
    print(f"verified: {len(now_held)} feats held, {len(to_add)} added")

    try:
        LEDGER.parent.mkdir(parents=True, exist_ok=True)
        with LEDGER.open("a", encoding="utf-8") as fh:
            fh.write(json.dumps({
                "when": datetime.now(timezone.utc).isoformat(),
                "bic": str(bic), "realm": repo.name if repo else None,
                "feats": [{"id": r, "label": names.get(r)} for r in to_add],
                "backup": str(backup), "note": args.note,
            }) + "\n")
        print(f"recorded in {LEDGER}")
    except OSError as exc:
        print(f"warning: could not write the ledger: {exc}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
