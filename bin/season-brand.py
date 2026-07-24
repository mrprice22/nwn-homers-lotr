#!/usr/bin/env python3
"""Rebrand every season-scoped reference in this repo from the season block.

One idempotent pass. `server.env`'s SEASON_* block is the single source of
truth; this script derives and writes everything downstream of it — the module
description's connect string and wiki link, the guide/merit NPC wiki links, the
login floaty text, the Well of Eru signs, the Cloudflare worker name and
redirect target, the roadmap editor's links, and (from season 2 on) the module
and server names in nasher.cfg and server.env.

Usage:
    python3 bin/season-brand.py              # dry run — show what would change
    python3 bin/season-brand.py --apply      # write
    python3 bin/season-brand.py --check      # exit 1 if anything is out of date
    python3 bin/season-brand.py --diff       # dry run with full unified diffs

`--check` is what tests/check_season_brand.py runs as a build gate, so a repo
whose tree has drifted from its season block cannot be packed.

IDEMPOTENCE is the contract: a second `--apply` must produce no diff. Every rule
therefore matches the *shape* of the target (any host in the homerslotr.com
family, any name in the "name" field) rather than a specific old value, so
re-running re-matches the value it just wrote and does nothing.

NEVER substitute a bare port number. `5121` occurs as a float fraction in at
least seven .git.json files ("value": 54.5121, -22.5121, …) and as a
SetListenPattern match-ID in unpacked/roulette_os.nss. A global port
substitution silently moves placeables and breaks a conversation. The port is
touched only inside the module description's "Connect:" line.

Adding a new branded string? Add a rule here, then re-run the completeness grep
from season-cutover-prereqs.md item 8. unpacked/module.jrl.json currently needs
no rule — its only link is Discord and its wiki references are host-free
breadcrumbs ("wiki: Manual > Customizations") — but it is the likeliest place
for a new bare URL to appear, so re-check it each cutover.
"""
from __future__ import annotations

import argparse
import difflib
import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
UNPACKED = REPO / "unpacked"

# --- invariants (season-cutover-guide.md §1) --------------------------------
# The apex domain. Every season's wiki is either this host (the live season) or
# season<N>.<apex>, which is what makes a single "host family" regex safe.
APEX_DOMAIN = "homerslotr.com"
WIKI_HOST_RE = re.compile(r"(?:season\d+\.)?" + re.escape(APEX_DOMAIN))
# The live season is always on this port; the alternate slot is always 5122.
LIVE_PORT = "5121"

# --- the two season signs in the Well of Eru --------------------------------
# Placed once (by tag) and only ever re-texted here, so no season edits a
# .git.json by hand. Hidden is an appearance swap rather than a deletion, so the
# same two instances serve every future season.
WELL_OF_ERU = UNPACKED / "thewelloferu.git.json"
SIGN_VISIBLE = {"Appearance": 89, "Static": 0, "Useable": 1}
SIGN_HIDDEN = {"Appearance": 157, "Static": 1, "Useable": 0}  # 157 = plc_invisobj

# In-game text is ASCII only. The module's own description already spells its
# dashes "--"; non-ASCII in a placeable Description risks mojibake in the game
# client, and these signs are the first thing a new tester reads.


class BrandError(Exception):
    pass


# ---------------------------------------------------------------- env ------
def load_env(path: Path) -> dict[str, str]:
    """Parse KEY=VALUE lines. The values this script needs carry no shell
    interpolation, so a full `bash -c . server.env` is unnecessary — but the
    trailing-comment handling does have to match bash, because the season block
    documents each value inline (`SEASON_ROLE=live   # live | test | archive`)
    and bash strips that."""
    env: dict[str, str] = {}
    if not path.exists():
        raise BrandError(f"missing {path}")
    for line in path.read_text(encoding="utf-8").splitlines():
        m = re.match(r"\s*(?:export\s+)?([A-Z_][A-Z0-9_]*)\s*=\s*(.*)$", line)
        if not m:
            continue
        key, rest = m.group(1), m.group(2)
        q = rest[:1]
        if q in ('"', "'"):
            end = rest.find(q, 1)
            val = rest[1:end] if end > 0 else rest[1:]
        else:
            # Unquoted: ` #` starts a comment, exactly as in bash.
            val = re.split(r"\s+#", rest, maxsplit=1)[0].strip()
        env[key] = val
    return env


def season_config(env: dict[str, str]) -> dict[str, object]:
    """Everything the rules need, derived from the season block."""
    def need(key: str) -> str:
        val = env.get(key, "")
        if not val:
            raise BrandError(
                f"{key} is unset in server.env — the season block is required "
                f"(see README.md 'Season identity')"
            )
        return val

    num = need("SEASON_NUM")
    role = need("SEASON_ROLE")
    if role not in ("live", "test", "archive"):
        raise BrandError(f"SEASON_ROLE must be live|test|archive, got {role!r}")

    wiki_url = need("SEASON_WIKI_URL")
    if not wiki_url.endswith("/"):
        wiki_url += "/"
    m = re.match(r"https?://([^/]+)/", wiki_url)
    if not m:
        raise BrandError(f"SEASON_WIKI_URL must be an absolute URL, got {wiki_url!r}")
    wiki_host = m.group(1)

    peer_role = env.get("SEASON_PEER_ROLE", "none") or "none"
    if peer_role not in ("live", "test", "archive", "none"):
        raise BrandError(f"SEASON_PEER_ROLE must be live|test|archive|none, got {peer_role!r}")

    cfg: dict[str, object] = {
        "num": num,
        "role": role,
        "legacy_names": env.get("SEASON_LEGACY_NAMES", "0") in ("1", "true", "yes"),
        "wiki_url": wiki_url,
        "wiki_host": wiki_host,
        "worker_name": need("SEASON_WORKER_NAME"),
        "connect": f'{need("SEASON_CONNECT_HOST")}:{need("NWN_PORT")}',
        "container": need("NWN_CONTAINER_NAME"),
        "peer_role": peer_role,
        "peer_num": env.get("SEASON_PEER_NUM", ""),
        "peer_port": env.get("SEASON_PEER_PORT", ""),
        "peer_password": env.get("SEASON_PEER_PASSWORD", ""),
    }

    # Season 1 keeps its legacy names: renaming a live module leaves every
    # player's saved server entry pointing at a module that no longer exists.
    if cfg["legacy_names"]:
        cfg["package_name"] = None      # signals "don't touch"
        cfg["mod_file"] = None
        cfg["nwn_module"] = None
        cfg["nwn_servername"] = None
    else:
        suffix = {"test": " (EARLY ACCESS)", "archive": " (ARCHIVED)", "live": ""}[role]
        cfg["package_name"] = f"homers_lotr_s{num}"
        cfg["mod_file"] = f"homers_lotr_s{num}.mod"
        cfg["nwn_module"] = f"Homer's LOTR Season {num}"
        # ASCII hyphen, not an em dash: this string is passed through the
        # container env to nwserver and on to the master server browser.
        cfg["nwn_servername"] = f"Homer's LOTR - Season {num}{suffix}"

    if peer_role != "none" and not (cfg["peer_num"] and cfg["peer_port"]):
        raise BrandError(
            f"SEASON_PEER_ROLE={peer_role} needs SEASON_PEER_NUM and SEASON_PEER_PORT"
        )
    return cfg


# -------------------------------------------------------------- sign text ---
def status_sign(cfg) -> tuple[str, bool]:
    """(text, visible) for the season-status sign, from SEASON_ROLE."""
    n = cfg["num"]
    if cfg["role"] == "test":
        return (
            f"EARLY ACCESS - Season {n}\n\n"
            "This is a testing realm. Your characters, gear and progress here "
            "WILL BE WIPED when this season goes live.\n\n"
            "Merit you earn still counts.",
            True,
        )
    if cfg["role"] == "archive":
        return (
            f"Season {n} has ended.\n\n"
            "This realm is no longer updated or maintained.\n\n"
            f"The current season is live on port {LIVE_PORT}.",
            True,
        )
    return ("", False)  # live: nothing to say


def peer_sign(cfg) -> tuple[str, bool]:
    """(text, visible) for the cross-advert sign, from SEASON_PEER_*."""
    role, n, port = cfg["peer_role"], cfg["peer_num"], cfg["peer_port"]
    if role == "none":
        return ("", False)
    if role == "test":
        pw = cfg["peer_password"]
        pw_clause = f", password: {pw}" if pw else ""
        return (
            f"Season {n} EARLY ACCESS is now open.\n\n"
            f"Same server address, port {port}{pw_clause}.\n\n"
            "Come help test the new season. Progress there will be wiped at "
            "go-live; merit earned still counts.",
            True,
        )
    if role == "archive":
        return (
            f"Season {n} is still playable on port {port}, archived and "
            "unmaintained.\n\n"
            f"Its wiki lives at season{n}.{APEX_DOMAIN}.",
            True,
        )
    # role == "live": this realm is the early-access one, pointing at the live
    # season. Not in the prereqs table, but Phase 1 sets exactly this on the new
    # season's repo, so it needs a state or the sign would be blank-but-visible.
    return (
        f"Season {n} - the current live season - is running on port {port}.\n\n"
        "This realm is early access. The live season is where your progress "
        "is permanent.",
        True,
    )


# ------------------------------------------------------------ file helpers --
def read_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def dump_json(obj) -> str:
    """Match nwn_gff's JSON formatting exactly, so a rebrand diff shows only the
    strings it changed and never a whole-file reformat."""
    return json.dumps(obj, indent=2, ensure_ascii=False) + "\n"


def sub_in_function(src: str, func: str, pattern: str, repl: str) -> str:
    """Apply a substitution only inside `def <func>(...)`'s body — from its `def`
    line to the next top-level `def`/`class`. Keeps a narrow rule from matching
    a similar-looking line elsewhere in a 3000-line file."""
    m = re.search(rf"^def {re.escape(func)}\(", src, flags=re.M)
    if not m:
        raise BrandError(f"function {func}() not found — season-brand rule is stale")
    end = re.search(r"^(?:def |class )", src[m.end():], flags=re.M)
    stop = m.end() + (end.start() if end else len(src) - m.end())
    body = src[m.start():stop]
    return src[:m.start()] + re.sub(pattern, repl, body, count=1) + src[stop:]


def set_locstring(node: dict, text: str) -> None:
    """Write language 0 and drop any StrRef. A non-0xFFFFFFFF "id" wins over the
    inline string in-game, so leaving one would pin the sign to TLK text."""
    node["value"] = {"0": text}


# ------------------------------------------------------------------ rules ---
def brand(cfg) -> list[tuple[Path, str, str, list[str]]]:
    """Return [(path, old_text, new_text, [notes])] for every file that changes."""
    edits: list[tuple[Path, str, str, list[str]]] = []

    def json_edit(path: Path, mutate) -> None:
        old = path.read_text(encoding="utf-8")
        obj = json.loads(old)
        notes: list[str] = []
        mutate(obj, notes)
        new = dump_json(obj)
        if new != old:
            edits.append((path, old, new, notes))

    def text_edit(path: Path, mutate) -> None:
        old = path.read_text(encoding="utf-8")
        notes: list[str] = []
        new = mutate(old, notes)
        if new != old:
            edits.append((path, old, new, notes))

    host = cfg["wiki_host"]
    wiki = cfg["wiki_url"]

    def rehost(s: str) -> str:
        """Point every homerslotr-family host at this season's wiki host.
        Shape-matched, so re-running is a no-op."""
        return WIKI_HOST_RE.sub(host, s)

    # --- module.ifo.json: the Connect: and Wiki: lines of the description ----
    def mod_ifo(obj, notes):
        desc = obj["Mod_Description"]["value"]["0"]
        new = re.sub(r"^Connect: .*$", f'Connect: {cfg["connect"]}', desc, flags=re.M)
        new = re.sub(r"^Wiki: .*$", f"Wiki: {host}", new, flags=re.M)
        if new != desc:
            notes.append("module description Connect:/Wiki: lines")
        obj["Mod_Description"]["value"]["0"] = new

    json_edit(UNPACKED / "module.ifo.json", mod_ifo)

    # --- conversations: guide NPC and merit NPC wiki links ------------------
    def dlg_rehost(obj, notes):
        for i, entry in enumerate(obj.get("EntryList", {}).get("value", [])):
            texts = entry.get("Text", {}).get("value")
            if not isinstance(texts, dict):
                continue
            for lang, s in list(texts.items()):
                if lang == "id" or not isinstance(s, str):
                    continue
                new = rehost(s)
                if new != s:
                    texts[lang] = new
                    notes.append(f"EntryList[{i}] wiki host")

    json_edit(UNPACKED / "npguide.dlg.json", dlg_rehost)
    json_edit(UNPACKED / "meritconv.dlg.json", dlg_rehost)

    # --- login floaty text --------------------------------------------------
    def shout(s, notes):
        new = rehost(s)
        if new != s:
            notes.append("login floaty wiki host")
        return new

    text_edit(UNPACKED / "servershout4.nss", shout)

    # --- Well of Eru: the roadmap sign + the two season signs ---------------
    def well(obj, notes):
        by_tag = {}
        for p in obj["Placeable List"]["value"]:
            by_tag[p.get("Tag", {}).get("value", "")] = p

        ru = by_tag.get("recent_updates")
        if ru is None:
            raise BrandError("recent_updates placeable missing from thewelloferu.git.json")
        # Rewrite language 0 IN PLACE only. This sign predates the season work
        # and carries a StrRef plus eight other-language strings; dropping them
        # would change what it renders. Only the two season signs (created
        # StrRef-free below) get their locstring replaced wholesale.
        cur = ru["Description"]["value"].get("0", "")
        want = re.sub(r"https?://[^\s]*?/manual/Roadmap#shipped",
                      f"{wiki}manual/Roadmap#shipped", cur)
        if want != cur:
            ru["Description"]["value"]["0"] = want
            notes.append("recent_updates sign link")

        for tag, (text, visible) in (
            ("season_status", status_sign(cfg)),
            ("season_peer", peer_sign(cfg)),
        ):
            sign = by_tag.get(tag)
            if sign is None:
                raise BrandError(
                    f"{tag} placeable missing from thewelloferu.git.json — place it "
                    f"once (see season-cutover-prereqs.md item 9)"
                )
            state = SIGN_VISIBLE if visible else SIGN_HIDDEN
            changed = []
            if sign["Description"]["value"].get("0") != text or "id" in sign["Description"]["value"]:
                set_locstring(sign["Description"], text)
                changed.append("text")
            for field, val in state.items():
                if sign[field]["value"] != val:
                    sign[field]["value"] = val
                    changed.append(field)
            if changed:
                notes.append(f"{tag}: {'visible' if visible else 'hidden'} ({', '.join(changed)})")

    json_edit(WELL_OF_ERU, well)

    # --- Cloudflare worker: name and redirect target ------------------------
    # The name is mandatory, not cosmetic: two repos deploying the same worker
    # name collide, and at Phase 1 the unnumbered repo stops being the live
    # season — keeping the shared name would push the early-access wiki onto the
    # apex the first time a tester pushed.
    def wrangler(s, notes):
        new, n = re.subn(r'("name"\s*:\s*")[^"]*(")', rf'\g<1>{cfg["worker_name"]}\g<2>',
                         s, count=1)
        if n and new != s:
            notes.append(f'worker name -> {cfg["worker_name"]}')
        return new

    text_edit(REPO / "wrangler.jsonc", wrangler)

    def index_js(s, notes):
        new, n = re.subn(r"(url\.hostname\s*=\s*')[^']*(')", rf"\g<1>{host}\g<2>", s, count=1)
        if n and new != s:
            notes.append(f"workers.dev redirect -> {host}")
        return new

    text_edit(REPO / "src" / "index.js", index_js)

    # --- roadmap editor: public links + container fallback ------------------
    def editor(s, notes):
        new = rehost(s)
        if new != s:
            notes.append("public wiki/roadmap links")
        # Scope the fallback rewrite to container_name()'s own body. A bare
        # `return "..."` regex over the whole file matches server_tz()'s
        # "America/Chicago" first — which is exactly what it did on the first
        # run of this script.
        out = sub_in_function(new, "container_name",
                              r'(return ")[^"]*(")', rf'\g<1>{cfg["container"]}\g<2>')
        if out != new:
            notes.append("container-name fallback")
        return out

    text_edit(REPO / "bin" / "roadmap-editor.py", editor)

    # --- watch-server container fallback ------------------------------------
    def watch(s, notes):
        new, n = re.subn(r"(NWN_CONTAINER_NAME=\$\{NWN_CONTAINER_NAME:-)[^}]*(\})",
                         rf'\g<1>{cfg["container"]}\g<2>', s, count=1)
        if n and new != s:
            notes.append("container-name fallback")
        return new

    text_edit(REPO / "bin" / "watch-server", watch)

    # --- module + server names (season 2 onward) ----------------------------
    if not cfg["legacy_names"]:
        def nasher(s, notes):
            new, _ = re.subn(r'(^name\s*=\s*")[^"]*(")', rf'\g<1>{cfg["package_name"]}\g<2>',
                             s, count=1, flags=re.M)
            new, _ = re.subn(r'(^\s*file\s*=\s*")[^"]*(")', rf'\g<1>{cfg["mod_file"]}\g<2>',
                             new, count=1, flags=re.M)
            if new != s:
                notes.append(f'build artifact -> {cfg["mod_file"]}')
            return new

        text_edit(REPO / "nasher.cfg", nasher)

        def env_names(s, notes):
            new, _ = re.subn(r'(^NWN_MODULE\s*=\s*").*?("\s*$)',
                             rf'\g<1>{cfg["nwn_module"]}\g<2>', s, count=1, flags=re.M)
            new, _ = re.subn(r'(^NWN_SERVERNAME\s*=\s*").*?("\s*$)',
                             rf'\g<1>{cfg["nwn_servername"]}\g<2>', new, count=1, flags=re.M)
            if new != s:
                notes.append(f'NWN_MODULE -> {cfg["nwn_module"]}')
            return new

        text_edit(REPO / "server.env", env_names)

    return edits


# ------------------------------------------------------------------- main ---
def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--apply", action="store_true", help="write the changes")
    ap.add_argument("--check", action="store_true",
                    help="exit 1 if anything is out of date (build gate)")
    ap.add_argument("--diff", action="store_true", help="show full unified diffs")
    args = ap.parse_args()

    try:
        env = load_env(REPO / "server.env")
        cfg = season_config(env)
        edits = brand(cfg)
    except BrandError as e:
        print(f"season-brand: error: {e}", file=sys.stderr)
        return 2

    names = "legacy (season 1)" if cfg["legacy_names"] else f'{cfg["nwn_module"]!r}'
    print(f'season {cfg["num"]} role={cfg["role"]} '
          f'wiki={cfg["wiki_host"]} connect={cfg["connect"]} names={names}')
    peer = cfg["peer_role"]
    print(f'peer: {peer}' + (f' season {cfg["peer_num"]} on port {cfg["peer_port"]}'
                             if peer != "none" else ""))
    print()

    if not edits:
        print("up to date — nothing to change")
        return 0

    for path, old, new, notes in edits:
        rel = path.relative_to(REPO)
        print(f"{rel}")
        for note in notes or ["(content changed)"]:
            print(f"    - {note}")
        if args.diff:
            for line in difflib.unified_diff(old.splitlines(True), new.splitlines(True),
                                             f"a/{rel}", f"b/{rel}"):
                print("    " + line.rstrip("\n"))
    print()

    if args.check:
        print(f"season-brand: FAILED — {len(edits)} file(s) out of date with the "
              f"season block in server.env. Run: python3 bin/season-brand.py --apply")
        return 1

    if not args.apply:
        print(f"{len(edits)} file(s) would change. Re-run with --apply to write "
              f"(or --diff to see them).")
        return 0

    for path, _old, new, _notes in edits:
        path.write_text(new, encoding="utf-8")
    print(f"wrote {len(edits)} file(s).")
    print("Next: repack and deploy. A second --apply must produce no diff.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
