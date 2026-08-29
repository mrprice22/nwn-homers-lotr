#!/usr/bin/env python3
"""Push the who's-online roster to the wiki worker.

The live half of the wiki's Players section. Everything else there is static and
ships on the normal git-push cadence; this is the one thing that has to be
current to the minute, so it goes to a Cloudflare KV blob over HTTPS instead --
no commit, no Workers build, no deploy.

    bin/push-online-status.py            # push if the roster changed
    bin/push-online-status.py --dry-run  # print what would be pushed
    bin/push-online-status.py --force    # push even when unchanged

## The game server is not involved

This reads the log files the server already writes and the vault it already
maintains. It makes no connection to the game, runs in its own process, and is
started by a systemd timer rather than by anything in the module. If Cloudflare,
the network or this script is down, the server neither knows nor cares -- the
page just goes stale and says so.

## What it sends

Only what the page renders: account name, character name, level. Never the CD
key -- that is account credentials, and the same rule the wiki's own pages
follow (see nwn_wiki/players/model.py).

The account name comes straight from the log line. The character name does not:
the logs record only "<account> (<CDKEY>) Joined as Player", so the character
being played is inferred from the most recently modified .bic in that account's
vault directory. That is reliable because the module exports the character on
client exit and at level-up, but it is a heuristic -- a player who logs straight
in and does nothing may briefly show their previous character. When the guess is
not confident, the character is left blank and the page shows the account alone.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import urllib.error
import urllib.request
from datetime import datetime
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
# The wiki generator owns the log parser; re-implementing it here is how the
# page and the endpoint would drift apart.
MANAGER_BIN = Path.home() / "GIT" / "nwn_manager" / "bin"
sys.path.insert(0, str(MANAGER_BIN))

# Push at least this often even when nothing changed, so the endpoint can tell
# "nobody is online" from "the pusher died". Must stay well under the worker's
# STALE_AFTER_MS (20 min).
HEARTBEAT_SECONDS = 15 * 60

STATE_PATH_DEFAULT = "online-push-state.json"
USER_AGENT = "homers-lotr-online-push/1.0"
TIMEOUT = 10


def _env(name: str, default: str = "") -> str:
    return os.environ.get(name, default).strip()


def load_server_env() -> dict:
    """Read server.env + server.env.local without executing them.

    Only simple KEY="value" lines are needed here, and shelling out to bash to
    source a file that also runs podman would be a poor trade for a script that
    runs every five minutes.
    """
    out: dict[str, str] = {}
    for name in ("server.env", "server.env.local"):
        p = REPO / name
        if not p.is_file():
            continue
        for line in p.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, _, v = line.partition("=")
            k = k.strip()
            if not k.replace("_", "").isalnum():
                continue
            v = v.split("#", 1)[0].strip().strip('"').strip("'")
            out[k] = os.path.expandvars(v.replace("$HOME", str(Path.home())))
    return out


def online_accounts(log_dirs: list[Path], cache_path: Path) -> list[dict]:
    """Sessions still open, per the same parser the activity page uses."""
    from nwn_wiki.render.activity import parse_nwserver_logs

    activity = parse_nwserver_logs(log_dirs, cache_path=cache_path)
    return [
        s for s in activity["sessions"]
        if s.get("leave") is None and s.get("role") == "Player"
    ]


def character_for(vault: Path, cdkey: str) -> tuple[str, int | None]:
    """Best guess at the character an account is currently playing.

    The newest .bic in the account's vault directory. Returns ("", None) when
    the directory is missing or empty rather than guessing from another account.
    """
    d = vault / cdkey
    if not d.is_dir():
        return "", None
    bics = sorted(d.glob("*.bic"), key=lambda p: p.stat().st_mtime, reverse=True)
    if not bics:
        return "", None

    from nwn_wiki.players import bicreader

    rec = bicreader.parse_bic(bics[0], cdkey)
    if not rec:
        return "", None
    return rec["name"], rec["level"]


def build_roster(cfg: dict) -> list[dict]:
    run_dir = Path(cfg.get("NWN_RUN_DIR", "")).expanduser()
    vault = Path(cfg.get("NWN_HOME_DIR", "")).expanduser() / "servervault"
    if not run_dir.is_dir():
        raise SystemExit(f"NWN_RUN_DIR is not a directory: {run_dir}")

    sessions = online_accounts([run_dir], run_dir / "activity-sessions.json")

    roster = []
    for s in sessions:
        cdkey = s.get("cdkey") or ""
        name, level = character_for(vault, cdkey) if cdkey else ("", None)
        roster.append({
            "player": s.get("player") or "",
            "character": name,
            "level": level,
        })
    roster.sort(key=lambda r: (r["player"].lower(), r["character"].lower()))
    return roster


def fingerprint(roster: list[dict]) -> str:
    return hashlib.sha256(
        json.dumps(roster, sort_keys=True).encode("utf-8")).hexdigest()


def read_state(path: Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}


def push(url: str, token: str, roster: list[dict]) -> None:
    req = urllib.request.Request(
        url,
        data=json.dumps({"players": roster}).encode("utf-8"),
        method="POST",
        headers={
            "content-type": "application/json",
            "authorization": f"Bearer {token}",
            # MUST be set. urllib defaults to "Python-urllib/3.x", which
            # Cloudflare's managed bot rules block with a 403 before the request
            # ever reaches the worker -- verified against the live apex, where
            # the same POST returns 404 under any other agent. A descriptive
            # agent also makes this traffic identifiable in the CF dashboard.
            "user-agent": USER_AGENT,
        },
    )
    with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
        if resp.status not in (200, 204):
            raise urllib.error.HTTPError(
                url, resp.status, "unexpected status", resp.headers, None)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0],
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dry-run", action="store_true",
                    help="print the roster and whether it would push; send nothing")
    ap.add_argument("--force", action="store_true",
                    help="push even when the roster is unchanged")
    ap.add_argument("--state", default=None, metavar="PATH",
                    help=f"where the last-push fingerprint is kept "
                         f"(default: <NWN_RUN_DIR>/{STATE_PATH_DEFAULT})")
    args = ap.parse_args()

    cfg = load_server_env()
    url = cfg.get("SEASON_STATUS_PUSH_URL", "")
    token = cfg.get("SEASON_STATUS_PUSH_TOKEN", "")

    if not url:
        # The normal state for every realm but the live one. Not an error: the
        # timer is installed per-season and this is how a season opts out.
        print("[online-push] SEASON_STATUS_PUSH_URL not set; nothing to do")
        return 0

    roster = build_roster(cfg)
    fp = fingerprint(roster)

    state_path = (Path(args.state) if args.state
                  else Path(cfg["NWN_RUN_DIR"]).expanduser() / STATE_PATH_DEFAULT)
    state = read_state(state_path)
    age = 0.0
    if state.get("pushed_at"):
        age = (datetime.now() - datetime.fromisoformat(state["pushed_at"])).total_seconds()

    changed = state.get("fingerprint") != fp
    stale = age >= HEARTBEAT_SECONDS or not state.get("pushed_at")
    should = args.force or changed or stale

    who = ", ".join(
        f"{r['player']}" + (f" ({r['character']})" if r["character"] else "")
        for r in roster) or "(nobody)"
    reason = ("forced" if args.force else "roster changed" if changed
              else "heartbeat" if stale else "unchanged")
    print(f"[online-push] {len(roster)} online: {who}")
    print(f"[online-push] {reason}; {'would push' if args.dry_run else 'pushing' if should else 'skipping'}")

    if args.dry_run or not should:
        return 0

    if not token:
        print("[online-push] error: SEASON_STATUS_PUSH_TOKEN is not set "
              "(put it in server.env.local, which is gitignored)", file=sys.stderr)
        return 1

    try:
        push(url, token, roster)
    except (urllib.error.URLError, OSError, TimeoutError) as exc:
        # Never retry in-process: the timer comes back in five minutes, and a
        # retry loop here would be the only part of this system that could pile
        # up while the network is down.
        print(f"[online-push] warn: push failed: {exc}", file=sys.stderr)
        return 1

    state_path.write_text(
        json.dumps({"fingerprint": fp, "pushed_at": datetime.now().isoformat()}),
        encoding="utf-8")
    print(f"[online-push] pushed to {url}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
