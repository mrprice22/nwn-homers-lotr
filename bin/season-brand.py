#!/usr/bin/env python3
"""Rebrand every season-scoped reference in this repo from the season block.

One idempotent pass. `server.env`'s SEASON_* block is the single source of
truth; this script derives and writes everything downstream of it — the module
description's connect string and wiki link, the guide/merit NPC wiki links, the
login floaty text, the Recent Updates board's roadmap link, the Cloudflare
worker name and
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
# The lookbehind makes this match a WHOLE host only. Without it the pattern also
# matches the tail of an unrelated subdomain: the archive wikis for the two forked
# modules (lotr.homerslotr.com, 2009.homerslotr.com — added to the landing page in
# a819138bb1d) became lotr.season2.homerslotr.com on every season, i.e. the gate
# demanded a rewrite that breaks the links. Those archives are permanent and are
# NOT season-scoped. Neither host appears anywhere in unpacked/ or server.env, so
# nothing the branding actually owns is matched by a partial host.
WIKI_HOST_RE = re.compile(r"(?<![\w.-])(?:season\d+\.)?" + re.escape(APEX_DOMAIN))


# The Well of Eru area, for the Recent Updates board's roadmap link.
WELL_OF_ERU = UNPACKED / "thewelloferu.git.json"

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


    cfg: dict[str, object] = {
        "num": num,
        "role": role,
        "legacy_names": env.get("SEASON_LEGACY_NAMES", "0") in ("1", "true", "yes"),
        "wiki_url": wiki_url,
        "wiki_host": wiki_host,
        "worker_name": need("SEASON_WORKER_NAME"),
        "connect": f'{need("SEASON_CONNECT_HOST")}:{need("NWN_PORT")}',
        "container": need("NWN_CONTAINER_NAME"),
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
    return cfg


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

    # --- the wiki landing page ---------------------------------------------
    # docs/index.html is NOT generated from unpacked/ like the rest of the wiki:
    # index.html in the repo root is hand-maintained and nwn-wiki only injects
    # the header/footer around it. So nothing else in this script reaches it, and
    # it is the one page that greets a player with "Direct connect <host>:<port>"
    # — twice, plus a wiki link. The season 1 -> 2 cutover shipped it still
    # advertising 5121 on the early-access site, which is the worst possible
    # place to be wrong: it is the first thing a tester reads.
    #
    # The connect string is matched as the CONNECT-HOST:PORT shape, never as a
    # bare port (see the module docstring — a bare 5121 substitution corrupts
    # float coordinates and a listen pattern).
    def landing(s, notes):
        new = rehost(s)
        if new != s:
            notes.append("wiki host link(s)")
        connect_re = re.compile(
            re.escape(str(cfg["connect"]).rsplit(":", 1)[0]) + r":\d+")
        after, n = connect_re.subn(str(cfg["connect"]), new)
        if n and after != new:
            notes.append(f"direct-connect string x{n}")
        return after

    landing_page = REPO / "index.html"
    if landing_page.exists():
        text_edit(landing_page, landing)

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
