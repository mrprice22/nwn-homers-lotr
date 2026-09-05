#!/usr/bin/env python3
"""Offline checks for the roadmap editor's access control.

Deliberately NOT a repack gate: the gates under tests/ guard module content,
and this guards a web service. Run it by hand after touching bin/roadmap_auth.py
or the permission checks in bin/roadmap-editor.py.

    python3 bin/roadmap-auth-selftest.py

Every check runs against a throwaway database in a temp dir; nothing here reads
or writes the real one, roadmap.yaml, or any server state.
"""
from __future__ import annotations

import sys
import tempfile
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import roadmap_auth as A   # noqa: E402

FAILURES: list[str] = []


def check(label: str, cond, detail: str = "") -> None:
    if cond:
        print(f"  ok    {label}")
    else:
        print(f"  FAIL  {label}" + (f" — {detail}" if detail else ""))
        FAILURES.append(label)


def section(name: str) -> None:
    print(f"\n{name}")


def test_passwords() -> None:
    section("Password hashing")
    # Keep the self-test quick: real logins use SCRYPT_N, but the property being
    # checked here is the round-trip, not the work factor.
    h = A.hash_password("correct horse battery staple", n=2 ** 12)
    check("correct password verifies", A.verify_password("correct horse battery staple", h))
    check("wrong password rejected", not A.verify_password("Correct horse battery staple", h))
    check("empty password rejected", not A.verify_password("", h))
    check("salted: two hashes of one password differ",
          A.hash_password("same", n=2 ** 12) != A.hash_password("same", n=2 ** 12))
    check("malformed hash returns False, does not raise",
          not A.verify_password("x", "not-a-hash"))
    check("unknown scheme rejected", not A.verify_password("x", "md5$1$2$3$4$5"))
    try:
        A.hash_password("")
        check("empty password refused at hash time", False)
    except ValueError:
        check("empty password refused at hash time", True)


def test_roles() -> None:
    section("Roles and capabilities")
    admin = A.User("a", "admin")
    dm = A.User("d", "dm")
    check("admin has every capability", admin.caps == set(A.CAPS))
    check("dm cannot promote to a shipped status", not dm.can("promote_shipped"))
    check("dm cannot award merit", not dm.can("merit"))
    for cap in ("view", "edit", "publish", "llm_review", "palette", "serverlog"):
        check(f"dm can {cap}", dm.can(cap))
    check("unknown role has no capabilities", A.User("x", "nobody").caps == set())
    check("every role's caps are real capabilities",
          all(c in A.CAPS for caps in A.ROLES.values() for c in caps))

    # The tester tier. Its whole security story is that it has no `edit`: the
    # three `uat` endpoints are then the only way it can write roadmap.yaml, so
    # "UAT fields only" needs no per-field filter on /api/save. A later reshuffle
    # of CAPS or ROLES that hands it `edit` (or `merit`) would silently turn it
    # into a DM, so assert the exclusions rather than trusting the table.
    tester = A.User("t", "tester")
    check("tester can browse the backlog", tester.can("view"))
    check("tester can record UAT work", tester.can("uat"))
    check("tester can watch the server monitor", tester.can("serverlog"))
    for cap in sorted(A.TESTER_FORBIDDEN):
        check(f"tester cannot {cap}", not tester.can(cap))
    check("TESTER_FORBIDDEN names only real capabilities",
          A.TESTER_FORBIDDEN <= set(A.CAPS))
    check("tester can read the tester/player release notes",
          tester.can("release_notes"))
    check("tester cannot read the admin audience of the release notes",
          not tester.can("release_notes_admin"))
    # A whitelist, not a blacklist: TESTER_FORBIDDEN catches a cap that gets
    # handed to the tier, but only this catches a NEW capability that nobody
    # remembered to forbid.
    check("tester holds nothing outside view/uat/serverlog/release_notes",
          tester.caps == {"view", "uat", "serverlog", "release_notes"})
    for role in ("admin", "dm"):
        check(f"{role} can read every release-notes audience",
              A.User("u", role).can("release_notes")
              and A.User("u", role).can("release_notes_admin"))
    # Everyone who runs a queue needs `uat`, or the claim/report buttons are
    # dead for the people who do most of the triage.
    check("admin and dm can also record UAT work",
          A.User("a", "admin").can("uat") and A.User("d", "dm").can("uat"))

    # The `bot` tier, asserted exactly like the tester one. nwnbot runs
    # unattended with a password in a file, so what it CANNOT do is the whole
    # security story -- and the server enforces it in
    # enforce_idea_permissions() regardless of what the client believes.
    bot = A.User("b", "bot")
    check("bot can read the roadmap", bot.can("view"))
    check("bot can save ideas", bot.can("edit"))
    check("bot can append an idea comment", bot.can("uat"))
    for cap in sorted(A.BOT_FORBIDDEN):
        check(f"bot cannot {cap}", not bot.can(cap))
    check("BOT_FORBIDDEN names only real capabilities",
          A.BOT_FORBIDDEN <= set(A.CAPS))
    # Same whitelist argument as the tester: BOT_FORBIDDEN catches a cap handed
    # to the role, but only this catches a NEW capability nobody forbade.
    check("bot holds nothing outside view/edit/uat",
          bot.caps == {"view", "edit", "uat"})
    # The two irreversible-in-public things, named explicitly because they are
    # the reason this role exists at all rather than reusing `dm`.
    check("bot cannot ship an item", not bot.can("promote_shipped"))
    check("bot cannot pay merit", not bot.can("merit"))
    # Every capability is either granted or forbidden -- no third bucket that a
    # future CAPS entry could quietly fall into.
    check("bot's granted and forbidden caps partition CAPS",
          bot.caps | A.BOT_FORBIDDEN == set(A.CAPS)
          and not (bot.caps & A.BOT_FORBIDDEN))


def test_users_and_sessions() -> None:
    section("Users and sessions")
    with tempfile.TemporaryDirectory() as td:
        conn = A.connect(Path(td) / "auth.sqlite3")
        check("a fresh database has no users", A.user_count(conn) == 0)
        A.add_user(conn, "jane", "hunter2hunter2", "dm", "Jane")
        check("user created", A.get_user(conn, "jane").role == "dm")
        check("username is case-folded", A.get_user(conn, "JANE") is not None)

        for bad in ("", "a", "Jane", "has space", "-leading", "x" * 40):
            try:
                A.add_user(conn, bad, "hunter2hunter2", "dm")
                check(f"rejects invalid username {bad!r}", False)
            except ValueError:
                check(f"rejects invalid username {bad!r}", True)
        try:
            A.add_user(conn, "bob", "hunter2hunter2", "wizard")
            check("rejects unknown role", False)
        except ValueError:
            check("rejects unknown role", True)
        try:
            A.add_user(conn, "jane", "hunter2hunter2", "dm")
            check("rejects duplicate username", False)
        except ValueError:
            check("rejects duplicate username", True)

        check("authenticate accepts the right password",
              A.authenticate(conn, "jane", "hunter2hunter2") is not None)
        check("authenticate rejects the wrong password",
              A.authenticate(conn, "jane", "hunter2hunter3") is None)
        check("authenticate rejects an unknown user",
              A.authenticate(conn, "nobody", "hunter2hunter2") is None)

        tok = A.create_session(conn, "jane", ip="127.0.0.1", user_agent="test")
        check("session resolves to its user",
              (A.resolve_session(conn, tok) or A.User("", "")).username == "jane")
        check("an unknown token resolves to nothing",
              A.resolve_session(conn, "bogus") is None)
        check("an empty token resolves to nothing", A.resolve_session(conn, "") is None)
        check("listed sessions do not expose the token",
              all("..." in s["token"] for s in A.list_sessions(conn)))

        A.set_disabled(conn, "jane", True)
        check("a disabled user cannot authenticate",
              A.authenticate(conn, "jane", "hunter2hunter2") is None)
        A.set_disabled(conn, "jane", False)

        tok = A.create_session(conn, "jane")
        A.set_password(conn, "jane", "newpassword123")
        check("changing a password revokes existing sessions",
              A.resolve_session(conn, tok) is None)
        check("the new password works",
              A.authenticate(conn, "jane", "newpassword123") is not None)

        tok = A.create_session(conn, "jane")
        A.set_role(conn, "jane", "admin")
        check("changing a role revokes existing sessions",
              A.resolve_session(conn, tok) is None)

        tok = A.create_session(conn, "jane")
        conn.execute("UPDATE sessions SET expires_at=? WHERE token=?",
                     (int(time.time()) - 1, tok))
        conn.commit()
        check("an expired session is refused", A.resolve_session(conn, tok) is None)
        check("...and is cleaned up",
              conn.execute("SELECT COUNT(*) FROM sessions WHERE token=?",
                           (tok,)).fetchone()[0] == 0)

        A.audit(conn, "test.action", user=A.User("jane", "admin"), ip="1.2.3.4",
                detail="hello")
        rows = A.read_audit(conn, limit=5)
        check("audit rows are written and readable",
              any(r["action"] == "test.action" and r["ip"] == "1.2.3.4" for r in rows))

        A.delete_user(conn, "jane")
        check("user deleted", A.get_user(conn, "jane") is None)


def test_throttle() -> None:
    section("Login throttling")
    A._FAILURES.clear()
    ip, who = "10.0.0.9", "target"
    check("a clean slate is not throttled", A.throttle_check(ip, who) == 0)
    for _ in range(A.FAIL_LIMIT):
        A.throttle_fail(ip, who)
    check("throttled after the failure limit", A.throttle_check(ip, who) > 0)
    check("a different account from the same IP is also throttled",
          A.throttle_check(ip, "someone-else") > 0)
    A._FAILURES.clear()
    for _ in range(A.FAIL_LIMIT):
        A.throttle_fail("10.0.0.1", who)
    check("the account is throttled from a new IP too",
          A.throttle_check("10.0.0.2", who) > 0)
    A.throttle_clear("10.0.0.1", who)
    A.throttle_clear("10.0.0.2", who)
    check("a successful login clears the counters",
          A.throttle_check("10.0.0.2", who) == 0)
    A._FAILURES.clear()


# --------------------------------------------------------------------------
# The field-level gate. This is the part that actually stops a DM, because the
# editor page posts the whole document on every save -- blocking the merit
# routes alone would leave /api/save as an open back door.
# --------------------------------------------------------------------------
ADMIN = A.ROLES["admin"]
DM = A.ROLES["dm"]


def disk_doc() -> list[dict]:
    return [
        {"id": "idea-backlog", "status": "wip", "title": "A backlog item"},
        {"id": "idea-progress", "status": "confirmed", "title": "In progress"},
        {"id": "idea-shipped", "status": "implemented", "title": "Shipped",
         "manual_steps": [{"step": "check it", "kind": "uat", "status": "open"}]},
        {"id": "idea-paid", "status": "awarded", "title": "Paid",
         "merit_awarded": True,
         "uat_credits": [{"player": "Alice", "awarded": True},
                         {"player": "Bob"}]},
    ]


def edited(mutate) -> list[dict]:
    import copy
    doc = copy.deepcopy(disk_doc())
    mutate({i["id"]: i for i in doc}, doc)
    return doc


def denied(caps, posted) -> list[str]:
    return A.enforce_idea_permissions(caps, posted, disk_doc())


def test_permissions_block() -> None:
    section("Field-level gate — what a DM must NOT be able to do")

    def promote(by, _d):
        by["idea-progress"]["status"] = "implemented"
    check("blocks promoting an item to `implemented`", denied(DM, edited(promote)))

    def promote_manual(by, _d):
        by["idea-progress"]["status"] = "manual"
    check("blocks promoting an item to `manual`", denied(DM, edited(promote_manual)))

    def promote_awarded(by, _d):
        by["idea-backlog"]["status"] = "awarded"
    check("blocks promoting an item to `awarded`", denied(DM, edited(promote_awarded)))

    def new_shipped(_by, doc):
        doc.append({"id": "idea-new", "status": "implemented", "title": "Sneaky"})
    check("blocks creating a new item already shipped", denied(DM, edited(new_shipped)))

    def demote(by, _d):
        by["idea-shipped"]["status"] = "wip"
    check("blocks demoting a shipped item back to the backlog",
          denied(DM, edited(demote)))

    def delete_shipped(_by, doc):
        doc[:] = [i for i in doc if i["id"] != "idea-shipped"]
    check("blocks deleting a shipped item", denied(DM, edited(delete_shipped)))

    def flip_merit(by, _d):
        by["idea-progress"]["merit_awarded"] = True
    check("blocks setting the merit-awarded flag", denied(DM, edited(flip_merit)))

    def clear_merit(by, _d):
        by["idea-paid"].pop("merit_awarded")
    check("blocks clearing the merit-awarded flag", denied(DM, edited(clear_merit)))

    def pay_uat(by, _d):
        by["idea-paid"]["uat_credits"][1]["awarded"] = True
    check("blocks marking a UAT credit as paid", denied(DM, edited(pay_uat)))

    def unpay_uat(by, _d):
        by["idea-paid"]["uat_credits"][0]["awarded"] = False
    check("blocks un-marking a paid UAT credit", denied(DM, edited(unpay_uat)))

    def drop_paid_uat(by, _d):
        by["idea-paid"]["uat_credits"] = [{"player": "Bob"}]
    check("blocks removing an already-paid UAT credit",
          denied(DM, edited(drop_paid_uat)))

    def delete_paid(_by, doc):
        doc[:] = [i for i in doc if i["id"] != "idea-paid"]
    check("blocks deleting an item whose merit was paid",
          denied(DM, edited(delete_paid)))


def test_permissions_allow() -> None:
    section("Field-level gate — what a DM MUST still be able to do")
    check("an untouched document passes", not denied(DM, disk_doc()))

    def move_in_backlog(by, _d):
        by["idea-backlog"]["status"] = "confirmed"
    check("moving an item up to `confirmed` (In progress)",
          not denied(DM, edited(move_in_backlog)))

    def demote_backlog(by, _d):
        by["idea-progress"]["status"] = "later"
    check("moving an item back down the backlog",
          not denied(DM, edited(demote_backlog)))

    def new_idea(_by, doc):
        doc.append({"id": "idea-new", "status": "planned", "title": "A proposal"})
    check("creating a new backlog item", not denied(DM, edited(new_idea)))

    def del_backlog(_by, doc):
        doc[:] = [i for i in doc if i["id"] != "idea-backlog"]
    check("deleting an unshipped item", not denied(DM, edited(del_backlog)))

    # The whole point of the "narrow" scoping: a shipped parent must not freeze
    # its subtasks. This is the DM's core workflow.
    def add_step(by, _d):
        by["idea-shipped"].setdefault("manual_steps", []).append(
            {"step": "also check the other thing", "kind": "uat", "status": "open"})
    check("adding a manual step to a SHIPPED item", not denied(DM, edited(add_step)))

    def tick_step(by, _d):
        by["idea-shipped"]["manual_steps"][0]["status"] = "done"
    check("ticking a step on a SHIPPED item", not denied(DM, edited(tick_step)))

    def del_step(by, _d):
        by["idea-shipped"]["manual_steps"] = []
    check("deleting a step on a SHIPPED item", not denied(DM, edited(del_step)))

    def edit_notes(by, _d):
        by["idea-paid"]["notes"] = "Reworded release note."
        by["idea-paid"]["impl_notes"] = "Technical record."
        by["idea-paid"]["title"] = "Renamed"
    check("editing notes and title on an AWARDED item",
          not denied(DM, edited(edit_notes)))

    def add_question(by, _d):
        by["idea-shipped"]["design_questions"] = [{"q": "which colour?"}]
    check("adding a design question to a SHIPPED item",
          not denied(DM, edited(add_question)))

    def add_uat(by, _d):
        by["idea-paid"]["uat_credits"].append({"player": "Carol"})
    check("adding an UNPAID UAT credit", not denied(DM, edited(add_uat)))

    def drop_unpaid_uat(by, _d):
        by["idea-paid"]["uat_credits"] = [{"player": "Alice", "awarded": True}]
    check("removing an UNPAID UAT credit", not denied(DM, edited(drop_unpaid_uat)))


def test_permissions_admin() -> None:
    section("Field-level gate — an admin is never blocked")
    for name, mutate in (
        ("promote to implemented", lambda by, d: by["idea-progress"].__setitem__("status", "implemented")),
        ("delete a shipped item", lambda by, d: d.__setitem__(slice(None), [i for i in d if i["id"] != "idea-shipped"])),
        ("set the merit flag", lambda by, d: by["idea-progress"].__setitem__("merit_awarded", True)),
        ("pay a UAT credit", lambda by, d: by["idea-paid"]["uat_credits"][1].__setitem__("awarded", True)),
    ):
        check(f"admin may {name}", not A.enforce_idea_permissions(
            ADMIN, edited(mutate), disk_doc()))


def test_permissions_edges() -> None:
    section("Field-level gate — edges")
    check("an empty posted document is not a crash",
          isinstance(A.enforce_idea_permissions(DM, [], disk_doc()), list))
    check("an empty disk document is not a crash",
          isinstance(A.enforce_idea_permissions(DM, disk_doc(), []), list))
    check("non-dict entries are ignored, not fatal",
          isinstance(A.enforce_idea_permissions(DM, ["junk", None], disk_doc()), list))
    check("malformed uat_credits are ignored, not fatal",
          isinstance(A.enforce_idea_permissions(
              DM, [{"id": "x", "status": "wip", "uat_credits": ["junk", None]}],
              [{"id": "x", "status": "wip"}]), list))

    def promote(by, _d):
        by["idea-progress"]["status"] = "implemented"
    errs = denied(DM, edited(promote))
    check("the error names the offending item", any("idea-progress" in e for e in errs),
          str(errs))
    check("the error is human-readable, not a field dump",
          all(len(e) > 40 for e in errs), str(errs))

    # Many simultaneous violations must not produce a wall of text.
    import copy
    doc = copy.deepcopy(disk_doc())
    for i in range(40):
        doc.append({"id": f"bulk-{i}", "status": "implemented", "title": "x"})
    check("the error list is capped", len(A.enforce_idea_permissions(DM, doc, disk_doc())) <= 20)


def main() -> int:
    print("roadmap editor — access control self-test")
    test_passwords()
    test_roles()
    test_users_and_sessions()
    test_throttle()
    test_permissions_block()
    test_permissions_allow()
    test_permissions_admin()
    test_permissions_edges()
    print()
    if FAILURES:
        print(f"{len(FAILURES)} FAILED:")
        for f in FAILURES:
            print(f"  - {f}")
        return 1
    print("All checks passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
