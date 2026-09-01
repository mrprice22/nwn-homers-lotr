#!/usr/bin/env python3
"""Manage roadmap-editor accounts, roles and sessions.

This is the ONLY way accounts are created or changed. The editor deliberately
has no signup page, no password-reset flow and no in-browser user admin: the
web surface is reachable from the public internet, and a management UI there is
a much bigger thing to get right than a script that only runs on this box.

    python3 bin/roadmap-users.py add jane --role dm --name "Jane (DM)"
    python3 bin/roadmap-users.py passwd jane
    python3 bin/roadmap-users.py list
    python3 bin/roadmap-users.py roles
    python3 bin/roadmap-users.py audit --limit 40

Passwords are never taken from the command line (that would put them in your
shell history and in `ps`): the commands prompt, or read one line from stdin
with --stdin, or mint one with --random.

The database lives outside the repo -- see bin/roadmap_auth.py.
"""
from __future__ import annotations

import argparse
import getpass
import secrets
import string
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import roadmap_auth as A   # noqa: E402


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
    print(f"{'USER'.ljust(w)}  {'ROLE':<6} {'STATE':<8} {'LAST LOGIN':<16}  NAME")
    for u in users:
        state = "disabled" if u["disabled"] else "active"
        print(f"{u['username'].ljust(w)}  {u['role']:<6} {state:<8} "
              f"{_stamp(u['last_login']):<16}  {u['display_name']}")
    return 0


def cmd_add(conn, args) -> int:
    pw = _read_password(args, who=args.username)
    user = A.add_user(conn, args.username, pw, args.role, args.name or "")
    A.audit(conn, "user.add", detail=f"{user.username} role={user.role}",
            username="(cli)")
    print(f"Created {user.username} with role {user.role} "
          f"({len(user.caps)} capabilities).")
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


def cmd_audit(conn, args) -> int:
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
    for r in reversed(rows):
        who = f"{r['username']}/{r['role']}" if r["role"] else r["username"]
        print(f"{_stamp(r['ts'])}  {who:<20} {r['ip']:<16} {r['action']:<22} "
              f"{r['detail']}")
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

    p = sub.add_parser("add", help="create an account")
    p.add_argument("username")
    p.add_argument("--role", required=True, choices=sorted(A.ROLES))
    p.add_argument("--name", default="", help="display name shown in the editor")
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
    p.set_defaults(fn=cmd_audit)

    args = ap.parse_args()
    conn = A.connect(Path(args.db) if args.db else None)
    try:
        return args.fn(conn, args)
    except ValueError as e:
        sys.exit(f"error: {e}")


if __name__ == "__main__":
    sys.exit(main())
