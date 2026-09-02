#!/usr/bin/env python3
"""Manage roadmap-editor accounts, roles and sessions.

This is the ONLY way accounts are created or changed. The editor deliberately
has no signup page, no password-reset flow and no in-browser user admin: the
web surface is reachable from the public internet, and a management UI there is
a much bigger thing to get right than a script that only runs on this box.

    python3 bin/roadmap-users.py setup            # interactive: the easy way
    python3 bin/roadmap-users.py add jane --role dm --name "Jane (DM)"
    python3 bin/roadmap-users.py passwd jane
    python3 bin/roadmap-users.py list
    python3 bin/roadmap-users.py roles
    python3 bin/roadmap-users.py audit --limit 40

Passwords are never taken from the command line (that would put them in your
shell history and in `ps`): the commands prompt, or read one line from stdin
with --stdin, or mint one with --random.

`setup` is the recommended way to create an account: it picks the in-game
player off the roadmap's own roster, proves the name resolves in meritdb before
it is bound, and asks for the login and password. Every account MUST end up with
a player name -- the editor refuses a UAT claim or result from an unbound
account whatever its role, admin included.

The database lives outside the repo -- see bin/roadmap_auth.py.
"""
from __future__ import annotations

import argparse
import getpass
import re
import secrets
import string
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import roadmap_auth as A   # noqa: E402
import roadmap_merit as M  # noqa: E402  (meritdb, shared with the editor)

REPO = Path(__file__).resolve().parent.parent
YAML_PATH = REPO / "roadmap.yaml"
# The editor hoists these to the top of its player picker and never means them
# as a person; they can't be bound to a login. Mirrors RESERVED_PLAYERS in
# bin/roadmap-editor.py.
RESERVED_PLAYERS = ("community",)


def _stamp(ts) -> str:
    if not ts:
        return "-"
    return (datetime.fromtimestamp(int(ts), timezone.utc).astimezone()
            .strftime("%Y-%m-%d %H:%M"))


def _read_password(args, *, who: str) -> str:
    """Get a new password: --random, --stdin, or two matching prompts."""
    if getattr(args, "random", False):
        alphabet = string.ascii_letters + string.digits
        pw = "".join(secrets.choice(alphabet) for _ in range(20))
        print(f"Generated password for {who}: {pw}")
        print("Copy it now — it is not stored anywhere in recoverable form.")
        return pw
    if getattr(args, "stdin", False):
        pw = sys.stdin.readline().rstrip("\n")
        if not pw:
            sys.exit("error: no password on stdin")
        return pw
    pw = getpass.getpass(f"New password for {who}: ")
    if not pw:
        sys.exit("error: password must not be empty")
    if len(pw) < 8:
        sys.exit("error: password must be at least 8 characters")
    if pw != getpass.getpass("Repeat: "):
        sys.exit("error: passwords did not match")
    return pw


def cmd_list(conn, args) -> int:
    users = A.list_users(conn)
    if not users:
        print(A.bootstrap_hint())
        return 0
    w = max(len(u["username"]) for u in users)
    print(f"{'USER'.ljust(w)}  {'ROLE':<6} {'STATE':<8} {'LAST LOGIN':<16}  "
          f"{'NAME':<24}  PLAYER")
    for u in users:
        state = "disabled" if u["disabled"] else "active"
        # A tester with no player_name cannot record a UAT result at all, so
        # say so here rather than leaving a blank column to puzzle over.
        player = u["player_name"] or ("(unbound)" if u["role"] == "tester" else "")
        print(f"{u['username'].ljust(w)}  {u['role']:<6} {state:<8} "
              f"{_stamp(u['last_login']):<16}  {u['display_name']:<24}  {player}")
    return 0


def cmd_add(conn, args) -> int:
    pw = _read_password(args, who=args.username)
    user = A.add_user(conn, args.username, pw, args.role, args.name or "",
                      args.player or "")
    A.audit(conn, "user.add", detail=f"{user.username} role={user.role}",
            username="(cli)")
    print(f"Created {user.username} with role {user.role} "
          f"({len(user.caps)} capabilities).")
    if user.role == "tester" and not user.player_name:
        print(f"Note: no in-game player name bound, so {user.username} cannot "
              f"record a UAT result yet. Set one with:\n"
              f"  roadmap-users.py player {user.username} \"Their Player Name\"")
    return 0


def cmd_passwd(conn, args) -> int:
    A.set_password(conn, args.username, _read_password(args, who=args.username))
    A.audit(conn, "user.passwd", detail=args.username, username="(cli)")
    print(f"Password changed for {args.username}; their sessions were revoked.")
    return 0


def cmd_role(conn, args) -> int:
    A.set_role(conn, args.username, args.role)
    A.audit(conn, "user.role", detail=f"{args.username} -> {args.role}",
            username="(cli)")
    print(f"{args.username} is now {args.role}; their sessions were revoked "
          f"so the change takes effect immediately.")
    return 0


def cmd_name(conn, args) -> int:
    A.set_display_name(conn, args.username, args.name)
    print(f"Display name for {args.username} set to {args.name!r}.")
    return 0


def cmd_player(conn, args) -> int:
    A.set_player_name(conn, args.username, args.name)
    A.audit(conn, "user.player", detail=f"{args.username} -> {args.name or '(none)'}",
            username="(cli)")
    if args.name:
        print(f"{args.username} now credits UAT work to player {args.name!r}. "
              f"It must match a meritdb account (or an entry in "
              f"roadmap-merit-aliases.json) for the Award +1 button to resolve it.")
    else:
        print(f"{args.username} is no longer bound to a player name; they can "
              f"still browse, but not claim or record UAT work.")
    return 0


# --------------------------------------------------------------------------
# `setup` -- the interactive account wizard
# --------------------------------------------------------------------------
# Everything below exists because `add --player "Exactly The Right String"` is
# a trap. The editor stamps claimed_by / tested_by / uat_credits[].player from
# users.player_name and refuses the write when it is empty (roadmap-editor.py
# _need_actor), so an account created without one is half-built; and a name
# that does not resolve in meritdb looks fine for weeks and then fails at the
# moment you press Award +1. The wizard closes both by construction: you pick
# the player off the roadmap roster, and the binding is proved against meritdb
# through M.resolve_with_alias -- the very function the award path calls --
# before anything is written.


def _ask(prompt: str, default: str = "") -> str:
    """One line of input, with a shown default. EOF/^C aborts the wizard."""
    suffix = f" [{default}]" if default else ""
    try:
        got = input(f"{prompt}{suffix}: ").strip()
    except (EOFError, KeyboardInterrupt):
        print()
        sys.exit("Aborted.")
    return got or default


def _ask_yes(prompt: str, default: bool = False) -> bool:
    got = _ask(f"{prompt} [{'Y/n' if default else 'y/N'}]").lower()
    if not got:
        return default
    return got.startswith("y")


def _roadmap_players() -> list[str]:
    """The roster the editor offers, in the same union it builds.

    roadmap.yaml's top-level `players:` list, plus any idea.player already in
    use that never made it into the roster, minus the reserved pseudo-players.
    Read with a plain yaml.safe_load -- the wizard must not take the editor's
    file lock or pull in gen-roadmap.py.
    """
    try:
        import yaml  # noqa: PLC0415  (only `setup` needs it)
        data = yaml.safe_load(YAML_PATH.read_text(encoding="utf-8")) or {}
    except Exception as exc:  # noqa: BLE001
        print(f"[warn] could not read {YAML_PATH}: {exc}", file=sys.stderr)
        return []
    out: list[str] = []
    for n in (data.get("players") or []):
        n = str(n).strip()
        if n and n not in out and n not in RESERVED_PLAYERS:
            out.append(n)
    for idea in (data.get("ideas") or []):
        n = str((idea or {}).get("player") or "").strip()
        if n and n not in out and n not in RESERVED_PLAYERS:
            out.append(n)
    return out


def _merit_label(con, name: str) -> str:
    """How the award path would resolve `name`, rendered for the picker."""
    if con is None:
        return "meritdb unreadable"
    row = M.resolve_with_alias(con, name)
    if row is None:
        return "NO merit match"
    return f"merit: {row['name']}"


def _pick_player(conn, con) -> str:
    """Choose the in-game player name this account will speak for."""
    names = _roadmap_players()
    bound = {}
    for u in A.list_users(conn):
        if u["player_name"]:
            bound.setdefault(u["player_name"], []).append(u["username"])
    print("\nIn-game player (from roadmap.yaml, checked against meritdb):")
    if not names:
        print("  (roadmap.yaml listed none -- type a name)")
    w = max((len(n) for n in names), default=0)
    for i, n in enumerate(names, 1):
        who = bound.get(n)
        tail = f"-> {', '.join(who)}" if who else ""
        print(f"  {i:>3}  {n.ljust(w)}  [{_merit_label(con, n)}]  {tail}")
    while True:
        got = _ask("\nPick a number, or type a player name")
        if not got:
            print("  Give a number or a name.")
            continue
        if got.isdigit() and 1 <= int(got) <= len(names):
            return names[int(got) - 1]
        if got in RESERVED_PLAYERS:
            print(f"  {got!r} is a pseudo-player, not a person -- pick someone else.")
            continue
        if got not in names:
            print(f"  {got!r} is not on the roadmap roster yet. That is fine for a "
                  f"new player; the roster is edited in the editor.")
            if not _ask_yes(f"  Use {got!r} anyway?", True):
                continue
        return got


def _confirm_merit(con, player: str) -> None:
    """Prove the name resolves in meritdb; write an alias if it does not.

    Uses the same lookup order as award_merit(): the alias file, then the fuzzy
    name match. Anything this accepts, Award +1 can pay.
    """
    if con is None:
        print(f"[warn] meritdb is unreadable ({M.merit_db_path()}) -- binding "
              f"{player!r} without checking it.")
        return
    row = M.resolve_with_alias(con, player)
    if row is not None:
        print(f"  merit: {player!r} -> {row['cdkey']}  {row['name']}  "
              f"(last login {row['last_login'] or '-'})")
        return
    print(f"\n  {player!r} matches no meritdb player, so Award +1 would not "
          f"find an account to pay.")
    if not _ask_yes("  Pick the meritdb row this player is?", True):
        print("  Left unresolved. Merit for this player will fail until an "
              "alias is set (here, or by hand in the award dialog).")
        return
    uat = ", uat" if M.has_uat_column(con) else ""
    rows = [dict(r) for r in con.execute(
        "SELECT cdkey, name, last_login, bugs, exploits, features"
        f"{uat} FROM players ORDER BY last_login DESC").fetchall()]
    for i, r in enumerate(rows, 1):
        print(f"  {i:>3}  {r['cdkey']:<9} {r['name'][:28]:<28} "
              f"last login {r['last_login'] or '-'}")
    while True:
        got = _ask("\n  Pick a number (or blank to skip)")
        if not got:
            print("  Skipped -- no alias written.")
            return
        if got.isdigit() and 1 <= int(got) <= len(rows):
            r = rows[int(got) - 1]
            M.write_merit_alias(player, r["cdkey"])
            print(f"  Wrote {M.MERIT_ALIAS_PATH.name}: {player!r} -> "
                  f"{r['cdkey']} ({r['name']}).")
            return
        print("  Not a number on the list.")


def _suggest_username(player: str) -> str:
    """A login name from a player name, shaped to satisfy USERNAME_RE."""
    # Prefer the part before a parenthetical -- "Piskan (Alek Cain)" is Piskan.
    base = re.split(r"\s*\(", player.strip())[0]
    slug = re.sub(r"[^a-z0-9._-]+", "", base.lower())
    slug = slug.lstrip("._-")[:32]
    return slug if A.valid_username(slug) else ""


class _PwFlags:
    """The two attributes _read_password() looks for, chosen interactively."""

    def __init__(self, random: bool, stdin: bool = False):
        self.random = random
        self.stdin = stdin


def _choose_password(who: str) -> str:
    while True:
        got = _ask("Password: (g)enerate or (t)ype?", "g").lower()
        if got.startswith("g"):
            return _read_password(_PwFlags(random=True), who=who)
        if got.startswith("t"):
            return _read_password(_PwFlags(random=False), who=who)
        print("  Answer g or t.")


def cmd_setup(conn, args) -> int:
    """Create (or rebind) one account, start to finish."""
    con = M.merit_connect()
    try:
        player = _pick_player(conn, con)
        _confirm_merit(con, player)
    finally:
        if con is not None:
            con.close()

    while True:
        username = _ask("\nLogin name", _suggest_username(player)).lower()
        if A.valid_username(username):
            break
        print("  2-32 chars: lowercase letters, digits, dot, dash or "
              "underscore, starting alphanumeric.")

    existing = A.get_user(conn, username)
    if existing:
        # The rebind path. This is what fixes an account created before the
        # player_name column existed -- it must not look like an error.
        cur = existing.player_name or "(unbound)"
        print(f"\n{username} already exists: role {existing.role}, "
              f"player {cur}.")
        if not _ask_yes(f"Rebind {username} to {player!r}?", True):
            print("Aborted.")
            return 1
        A.set_player_name(conn, username, player)
        A.audit(conn, "user.player", detail=f"{username} -> {player}",
                username="(cli)")
        print(f"{username} now credits UAT work to {player!r}. "
              f"They only need to reload the editor -- no restart, and their "
              f"session is still valid.")
        if args.role and args.role != existing.role:
            A.set_role(conn, username, args.role)
            A.audit(conn, "user.role", detail=f"{username} -> {args.role}",
                    username="(cli)")
            print(f"{username} is now {args.role}; their sessions were revoked.")
        if _ask_yes("Reset their password too?", False):
            A.set_password(conn, username, _choose_password(username))
            A.audit(conn, "user.passwd", detail=username, username="(cli)")
            print(f"Password changed for {username}; sessions revoked.")
        return 0

    roles = sorted(A.ROLES)
    while True:
        role = _ask(f"Role ({', '.join(roles)})", args.role or "tester")
        if role in A.ROLES:
            break
        print(f"  Pick one of: {', '.join(roles)}")
    display = _ask("Display name (shown in the editor)", player)
    password = _choose_password(username)

    print(f"\n  login   {username}\n  role    {role} "
          f"({A.ROLE_LABELS.get(role, role)})\n  name    {display}\n"
          f"  player  {player}")
    if not _ask_yes("\nCreate this account?", True):
        print("Aborted.")
        return 1
    user = A.add_user(conn, username, password, role, display, player)
    A.audit(conn, "user.add", detail=f"{user.username} role={user.role} "
                                     f"player={player}", username="(cli)")
    print(f"Created {user.username} ({len(user.caps)} capabilities), bound to "
          f"{player!r}.")
    return 0


def cmd_disable(conn, args) -> int:
    A.set_disabled(conn, args.username, True)
    A.audit(conn, "user.disable", detail=args.username, username="(cli)")
    print(f"{args.username} disabled and logged out.")
    return 0


def cmd_enable(conn, args) -> int:
    A.set_disabled(conn, args.username, False)
    A.audit(conn, "user.enable", detail=args.username, username="(cli)")
    print(f"{args.username} enabled.")
    return 0


def cmd_delete(conn, args) -> int:
    if not args.yes:
        if input(f"Delete user {args.username}? [y/N] ").strip().lower() != "y":
            print("Aborted.")
            return 1
    A.delete_user(conn, args.username)
    A.audit(conn, "user.delete", detail=args.username, username="(cli)")
    print(f"Deleted {args.username}.")
    return 0


def cmd_sessions(conn, args) -> int:
    A.purge_expired_sessions(conn)
    rows = A.list_sessions(conn, args.user)
    if not rows:
        print("No active sessions.")
        return 0
    print(f"{'USER':<16} {'SINCE':<16} {'EXPIRES':<16} {'IP':<16} AGENT")
    for r in rows:
        print(f"{r['username']:<16} {_stamp(r['created_at']):<16} "
              f"{_stamp(r['expires_at']):<16} {r['ip']:<16} {r['user_agent'][:40]}")
    return 0


def cmd_logout(conn, args) -> int:
    if not args.user and not args.all:
        sys.exit("error: give a username, or --all")
    n = A.revoke_sessions(conn, None if args.all else args.user)
    A.audit(conn, "user.logout", detail=(args.user or "ALL"), username="(cli)")
    print(f"Revoked {n} session(s).")
    return 0


def cmd_roles(conn, args) -> int:
    print("Capabilities:")
    for cap in A.CAPS:
        print(f"  {cap}")
    print()
    for role in sorted(A.ROLES):
        caps = A.ROLES[role]
        print(f"{role} ({A.ROLE_LABELS.get(role, role)}):")
        for cap in A.CAPS:
            print(f"  [{'x' if cap in caps else ' '}] {cap}")
        print()
    print("Statuses only `promote_shipped` may set: "
          + ", ".join(sorted(A.SHIPPED_STATUSES)))
    return 0


def _print_audit_diff(conn, audit_id: int) -> int:
    """The per-field before/after recorded against one audit entry.

    The same data the editor's Recent changes panel shows when you click an
    idea id, for when you are on this box rather than in the browser.
    """
    rows = A.read_audit_diff(conn, audit_id)
    if not rows:
        print(f"No field changes recorded for audit entry {audit_id}. "
              f"(Diffs are kept {A.DIFF_KEEP_DAYS} days, and exist only for "
              f"document writes.)")
        return 0
    idea = None
    for r in rows:
        if r["idea_id"] != idea:
            idea = r["idea_id"]
            print(f"\n{idea or '(note)'}"
                  + (f"  [{r['kind']}]" if r["kind"] not in ("change", "note") else ""))
        print(f"  {r['field']}")
        print(f"    - {r['before'] if r['before'] is not None else '(not set)'}")
        print(f"    + {r['after'] if r['after'] is not None else '(removed)'}")
    return 0


def cmd_audit(conn, args) -> int:
    if args.entry:
        return _print_audit_diff(conn, args.entry)
    since = None
    if args.since:
        try:
            since = int(datetime.strptime(args.since, "%Y-%m-%d")
                        .replace(tzinfo=None).timestamp())
        except ValueError:
            sys.exit("error: --since wants YYYY-MM-DD")
    rows = A.read_audit(conn, username=args.user or "", since=since,
                        limit=args.limit)
    if not rows:
        print("No matching audit entries.")
        return 0
    # The id is what `audit --entry N` takes, so it has to be printed.
    marks = A.audit_diff_ids(conn, [r["id"] for r in rows])
    for r in reversed(rows):
        who = f"{r['username']}/{r['role']}" if r["role"] else r["username"]
        diff = "  *" if marks.get(r["id"]) else ""
        print(f"#{r['id']:<6} {_stamp(r['ts'])}  {who:<20} {r['ip']:<16} "
              f"{r['action']:<22} {r['detail']}{diff}")
    print("\n* has a per-field diff: read it with "
          "`roadmap-users.py audit --entry <id>`.")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__.split("\n\n")[0],
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="Roles: " + ", ".join(sorted(A.ROLES))
               + ".  Run `roles` for the full capability table.")
    ap.add_argument("--db", help="override the auth database path")
    sub = ap.add_subparsers(dest="cmd", required=True)

    def pw_flags(p):
        p.add_argument("--stdin", action="store_true",
                       help="read the password from stdin instead of prompting")
        p.add_argument("--random", action="store_true",
                       help="generate a strong password and print it once")

    sub.add_parser("list", help="list accounts").set_defaults(fn=cmd_list)
    sub.add_parser("roles", help="print the role/capability table").set_defaults(fn=cmd_roles)

    p = sub.add_parser("setup",
                       help="interactive: pick a player, create or rebind an "
                            "account (the recommended way in)")
    p.add_argument("--role", default="", choices=[""] + sorted(A.ROLES),
                   help="skip the role prompt (or change it, when rebinding)")
    p.set_defaults(fn=cmd_setup)

    p = sub.add_parser("add", help="create an account")
    p.add_argument("username")
    p.add_argument("--role", required=True, choices=sorted(A.ROLES))
    p.add_argument("--name", default="", help="display name shown in the editor")
    p.add_argument("--player", default="",
                   help="in-game player name this account credits UAT work to "
                        "(required before a tester can record a result)")
    pw_flags(p)
    p.set_defaults(fn=cmd_add)

    p = sub.add_parser("passwd", help="change a password (revokes their sessions)")
    p.add_argument("username")
    pw_flags(p)
    p.set_defaults(fn=cmd_passwd)

    p = sub.add_parser("role", help="change a role (revokes their sessions)")
    p.add_argument("username")
    p.add_argument("role", choices=sorted(A.ROLES))
    p.set_defaults(fn=cmd_role)

    p = sub.add_parser("name", help="set a display name")
    p.add_argument("username")
    p.add_argument("name")
    p.set_defaults(fn=cmd_name)

    p = sub.add_parser("player",
                       help="bind the in-game player name UAT credit is paid to")
    p.add_argument("username")
    p.add_argument("name", nargs="?", default="",
                   help="omit to unbind")
    p.set_defaults(fn=cmd_player)

    p = sub.add_parser("disable", help="lock an account out")
    p.add_argument("username")
    p.set_defaults(fn=cmd_disable)

    p = sub.add_parser("enable", help="unlock an account")
    p.add_argument("username")
    p.set_defaults(fn=cmd_enable)

    p = sub.add_parser("delete", help="remove an account")
    p.add_argument("username")
    p.add_argument("--yes", action="store_true", help="skip the confirmation")
    p.set_defaults(fn=cmd_delete)

    p = sub.add_parser("sessions", help="list active sessions")
    p.add_argument("--user", default="")
    p.set_defaults(fn=cmd_sessions)

    p = sub.add_parser("logout", help="revoke sessions")
    p.add_argument("user", nargs="?", default="")
    p.add_argument("--all", action="store_true")
    p.set_defaults(fn=cmd_logout)

    p = sub.add_parser("audit", help="read the audit log")
    p.add_argument("--user", default="")
    p.add_argument("--since", default="", metavar="YYYY-MM-DD")
    p.add_argument("--limit", type=int, default=100)
    p.add_argument("--entry", type=int, default=0, metavar="ID",
                   help="show the per-field before/after for one audit entry")
    p.set_defaults(fn=cmd_audit)

    args = ap.parse_args()
    conn = A.connect(Path(args.db) if args.db else None)
    try:
        return args.fn(conn, args)
    except ValueError as e:
        sys.exit(f"error: {e}")


if __name__ == "__main__":
    sys.exit(main())
