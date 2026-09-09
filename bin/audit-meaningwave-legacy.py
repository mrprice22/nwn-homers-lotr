#!/usr/bin/env python3
"""audit-meaningwave-legacy - resolve legacy Meaningwave campaign-DB rows
(playerid -> account -> character) using the SAME identity bridge
GIT/nwn_manager's wiki build already relies on for player pages
(nwn_wiki.players.identity/bicreader), instead of guessing offline.

Earlier attempts at this script assumed servervault's folder name (the
literal CD key on disk) could be matched against the playerid strings the
old GetCampaignInt/SetCampaignInt("meaningwave", key, oPC) scheme wrote.
That's wrong on two counts:

  * servervault/<X>/ is an opaque engine hash of the CD key, unrelated to
    the human-readable string ("ray", "-Methonash-", "szescian82"...)
    embedded in the playerid.
  * The embedded string is actually GetPCPlayerName() (the account's chosen
    display name), not GetPCPublicCDKey() at all - see
    nwn_wiki/players/identity.py's module docstring, which already
    documents this exact "playerid string" ID space as ID space #2 of
    three the wiki's player pages have to bridge.

nwn_manager's identity.Roster already solves this by cross-referencing
activity-sessions.json (which records account name <-> CD key together)
with the character roster from the vault, so THIS script reuses it rather
than re-deriving something worse. See CLAUDE.md's Meaningwave section and
roadmap item mw-mixtape-per-character for why the migration exists at all.

This is a REPORT, not a writer with a hidden side effect: it never touches
the old "meaningwave" DB, and it only writes the new "meaningwavedb" when
--apply-safe or --apply-approved is passed. The in-game MW_MigrateLegacy()
(unpacked/mw_unlock_inc.nss) still runs independently at each character's
first login and remains the authoritative, self-healing path - this script
exists to give the admin a head start / second source for reviewing
mw_legacy_pending rows, with account names and sibling characters attached
instead of a bare UUID.

Usage:
  bin/audit-meaningwave-legacy.py                 # report only
  bin/audit-meaningwave-legacy.py --realm dev      # by SEASON_ROLE, repeatable
  bin/audit-meaningwave-legacy.py --apply-safe     # write unambiguous u_*/jq_* matches
  bin/audit-meaningwave-legacy.py --json out.json
"""
import argparse
import json
import os
import re
import sqlite3
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
NWN_MANAGER_BIN = REPO.parent / "nwn_manager" / "bin"

SAFE_PREFIXES = ("u_", "jq_")
SENSITIVE_FLAGS = {"finale", "mixtape_consumed"}


def env_get(text, key):
    m = re.search(rf'^{key}=["\']?(.*?)["\']?\s*(?:#.*)?$', text, re.M)
    return m.group(1).strip() if m else ""


def expand(path_str):
    return Path(os.path.expandvars(path_str.replace("$HOME", str(Path.home())))).expanduser()


def realms(wanted):
    out = []
    for repo in sorted(REPO.parent.glob("nwn_homers_lotr*")):
        env_file = repo / "server.env"
        try:
            text = env_file.read_text(encoding="utf-8")
        except OSError:
            continue
        role = env_get(text, "SEASON_ROLE") or "?"
        if wanted and role not in wanted:
            continue
        home = env_get(text, "NWN_HOME_DIR") or "$HOME/.local/share/Neverwinter Nights"
        run = env_get(text, "NWN_RUN_DIR") or "$HOME/.local/state/nwnxee-homer"
        out.append({
            "role": role, "repo": repo.name,
            "vault": expand(home) / "servervault",
            "db_dir": expand(home) / "database",
            "log_dir": expand(run),
        })
    return out


def audit_realm(bicreader, identity, sources, realm):
    vault, db_dir, log_dir = realm["vault"], realm["db_dir"], realm["log_dir"]
    old_db = db_dir / "meaningwave.sqlite3"
    new_db = db_dir / "meaningwavedb.sqlite3"
    if not vault.is_dir():
        return None, f"{realm['repo']}: no servervault at {vault}"
    if not old_db.exists():
        return None, f"{realm['repo']}: no legacy meaningwave.sqlite3 (nothing to migrate)"

    cache_path = log_dir / "vault-characters.json"
    chars = bicreader.load_vault(vault, cache_path=cache_path)
    sessions = sources.load_sessions(log_dir / "activity-sessions.json")

    kills = []
    bes = sources.open_ro(db_dir / "bestiarydb.sqlite3")
    if bes is not None:
        kills = sources.load_kills(bes)

    identity.configure()
    roster = identity.build_roster(sessions, kills, chars)
    pid_map = roster.build_playerid_map()

    # name -> full char record, per cdkey, straight from the vault parse (not
    # just the roster's name set) so we can report UUID + mw_mixtape holding.
    by_cdkey = {}
    for c in chars:
        by_cdkey.setdefault(c["cdkey"], []).append(c)

    # Player-chosen character names are not reliably UTF-8 (same trap
    # sources.open_ro guards against for the wiki's own DB reads).
    conn = sqlite3.connect(f"file:{old_db}?mode=ro", uri=True)
    conn.text_factory = lambda b: b.decode("utf-8", "replace")
    rows = list(conn.execute("SELECT varname, playerid FROM db"))
    conn.close()

    safe, sensitive, unmatched = [], [], []
    for varname, playerid in rows:
        is_sensitive = varname in SENSITIVE_FLAGS
        is_safe = varname == "jq_intro" or any(varname.startswith(p) for p in SAFE_PREFIXES)
        if not is_sensitive and not is_safe:
            continue

        cdkey = roster.resolve_playerid(playerid, pid_map)
        if cdkey is None:
            unmatched.append({"varname": varname, "playerid": playerid})
            continue

        # Narrow to characters whose own (account + name) is actually
        # consistent with THIS row's playerid -- same prefix logic
        # identity.build_playerid_map() uses, but applied per-row instead of
        # collapsed into one global map, so "rayFireberry" correctly rules
        # out ray's other character "Maneticore" instead of listing both.
        acct = roster.account(cdkey)
        candidates = []
        for c in by_cdkey.get(cdkey, []):
            candidate_key = f"{acct}{c['name']}"
            if playerid.startswith(candidate_key) or candidate_key.startswith(playerid):
                candidates.append({
                    "name": c["name"], "uuid": c["uuid"],
                    "has_mixtape": any(i["resref"] == "mw_mixtape" for i in c.get("items", []))})
        entry = {
            "realm": realm["role"], "repo": realm["repo"], "cdkey": cdkey,
            "account": roster.account(cdkey), "flag": varname, "playerid": playerid,
            "candidates": candidates,
        }

        if is_sensitive:
            sensitive.append(entry)
        else:
            if len(candidates) == 1:
                entry["action"] = "migrate"
                entry["uuid"] = candidates[0]["uuid"]
            else:
                entry["action"] = "ambiguous" if candidates else "no-live-character"
            safe.append(entry)

    if roster.unmatched:
        for pid in roster.unmatched:
            unmatched.append({"varname": "?", "playerid": pid, "note": "roster could not place this playerid at all"})

    return {"safe": safe, "sensitive": sensitive, "unmatched": unmatched, "new_db": new_db}, None


def apply_safe(result, dry):
    to_write = [e for e in result["safe"] if e.get("action") == "migrate"]
    if not to_write or dry:
        return len(to_write)
    new_db = result["new_db"]
    conn = sqlite3.connect(new_db)
    conn.execute("CREATE TABLE IF NOT EXISTS mw_flag ("
                 "pid TEXT NOT NULL, flag TEXT NOT NULL, cdkey TEXT,"
                 "set_at TEXT DEFAULT CURRENT_TIMESTAMP,"
                 "PRIMARY KEY(pid, flag))")
    for e in to_write:
        conn.execute(
            "INSERT OR IGNORE INTO mw_flag(pid, flag, cdkey) VALUES(?, ?, ?)",
            (e["uuid"], e["flag"], e["cdkey"]))
    conn.commit()
    conn.close()
    return len(to_write)


def main():
    ap = argparse.ArgumentParser(
        description="Resolve legacy Meaningwave rows to accounts/characters "
                    "using nwn_manager's own identity bridge.")
    ap.add_argument("--realm", action="append", default=[], metavar="ROLE")
    ap.add_argument("--apply-safe", action="store_true",
                    help="write unambiguous u_*/jq_* matches to the new DB")
    ap.add_argument("--json", metavar="PATH")
    args = ap.parse_args()

    if not NWN_MANAGER_BIN.is_dir():
        sys.exit(f"error: {NWN_MANAGER_BIN} not found - this script needs "
                 "GIT/nwn_manager checked out beside this repo")
    sys.path.insert(0, str(NWN_MANAGER_BIN))
    from nwn_wiki.players import bicreader, identity, sources  # noqa: E402

    targets = realms(args.realm)
    if not targets:
        sys.exit("error: no realm found beside this repo"
                 + (f" with SEASON_ROLE in {args.realm}" if args.realm else ""))

    results, warnings = {}, []
    for realm in targets:
        result, warn = audit_realm(bicreader, identity, sources, realm)
        if warn:
            warnings.append(warn)
            continue
        results[realm["role"]] = result

    if args.json:
        Path(args.json).write_text(
            json.dumps({r: {k: v for k, v in res.items() if k != "new_db"}
                        for r, res in results.items()}, indent=2),
            encoding="utf-8")

    for w in warnings:
        print(f"warning: {w}")

    for role, result in results.items():
        migrate = [e for e in result["safe"] if e.get("action") == "migrate"]
        other = [e for e in result["safe"] if e.get("action") != "migrate"]
        print(f"\n=== {role} ===")
        print(f"u_*/jq_*: {len(migrate)} unambiguous match(es), "
              f"{len(other)} ambiguous/no-live-character")
        for e in other:
            names = ", ".join(f"{c['name']}({c['uuid'][:8]})" for c in e["candidates"]) or "(none live)"
            print(f"  {e['action']:16} flag={e['flag']:12} account={e['account']!r:20} "
                  f"cdkey={e['cdkey']:10} candidates={names}")

        print(f"finale/mixtape_consumed: {len(result['sensitive'])} row(s) "
              "- always admin-reviewed:")
        for e in result["sensitive"]:
            if len(e["candidates"]) == 1:
                tag = "SINGLE LIVE CHARACTER on this account - low-risk to approve"
            elif not e["candidates"]:
                tag = "NO LIVE CHARACTER on this account - deleted? check backups"
            else:
                tag = "MULTIPLE live characters - true collision, needs a real decision"
            names = ", ".join(f"{c['name']}({c['uuid'][:8]}, holds_mixtape={c['has_mixtape']})"
                              for c in e["candidates"]) or "-"
            print(f"  flag={e['flag']:16} account={e['account']!r:20} cdkey={e['cdkey']:10}")
            print(f"    {tag}")
            print(f"    candidates: {names}")

        if result["unmatched"]:
            print(f"unmatched/unresolved rows: {len(result['unmatched'])}")

        if args.apply_safe:
            n = apply_safe(result, dry=False)
            if n:
                print(f"applied {n} u_*/jq_* row(s) to {role}'s meaningwavedb.sqlite3")
        else:
            if migrate:
                print(f"{len(migrate)} u_*/jq_* row(s) ready - rerun with --apply-safe to write them")

    return 0


if __name__ == "__main__":
    sys.exit(main())
