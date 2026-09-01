#!/usr/bin/env python3
"""Rebrand every season-scoped reference in this repo from the season block.

One idempotent pass. `server.env`'s SEASON_* block is the single source of
truth; this script derives and writes everything downstream of it — the module
description's connect string and wiki link, the guide/merit NPC wiki links, the
login floaty text, the Recent Updates board's roadmap link, the Cloudflare
worker name and
redirect target, the roadmap editor's links, and (from season 2 on) the module
and server names in nasher.cfg and server.env.

ROLES. `SEASON_ROLE` is one of `live | test | dev | archive`:

    live     this season is production, reachable at the apex. Its own
             season<N>. subdomain 301s to the apex (src/index.js).
    test     an early-access realm on the alternate port, at season<N>.
    dev      the PERMANENT test realm — never a season, never production.
             All of its names are number-independent (homers_lotr_test.mod,
             "Homer's LOTR TEST", dev.homerslotr.com), because SEASON_NUM here
             tracks whichever season it currently feeds and bumping it must
             not rename the module.
    archive  a retired season, frozen at its own season<N>. subdomain.

NAMING is uniform across every realm, with no exemptions:

    seasons (live/test/archive)   homers_lotr_s<N>.mod   "Homer's LOTR Season <N>"
    the dev realm                 homers_lotr_test.mod   "Homer's LOTR TEST"

NWN_MODULE must equal the installed .mod filename minus the extension, or
nwserver exits at boot with module-not-found; this script writes them as a pair.

Only ONE repo may hold each of `live` and `dev`. Development happens in the
dev repo and reaches production through bin/season-promote.sh, which re-runs
this script in the target so the promoted tree is rebranded for wherever it
landed. That is why every rule here is shape-matched: promotion copies a tree
branded for one environment into another, and this pass has to correct it in
full, from whatever it previously said.

Behaviour that differs between dev and production (cheat gear, dev NPCs, the
early-access wipe notice) is NOT here — see bin/season-profile.py. This script
owns strings and URLs; that one owns flags.

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

The "family" is the apex and `season<N>.` ONLY — see WIKI_HOST_RE. Any other
subdomain of homerslotr.com is an ARCHIVE WIKI for one of the forked modules
(`lotr.homerslotr.com` = the 2008 original, `2009.homerslotr.com` = Homer's LOTR
Edit). Those are separate, read-only modules, not seasons of this one: they are
never rebuilt, never rebranded, and must survive every cutover untouched. Do not
"fix" a rule so that it reaches them.

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
#
# `dev.` is in the family because the permanent dev realm is branded by this same
# script (SEASON_ROLE=dev -> dev.homerslotr.com). It has to be MATCHED, not just
# written: rehost() re-matches the value it last wrote, which is what makes a
# second --apply a no-op. Leave it out and every dev rebrand is a fresh diff.
WIKI_HOST_RE = re.compile(
    r"(?<![\w.-])(?:season\d+\.|dev\.)?" + re.escape(APEX_DOMAIN))


# --- opt-out regions on the landing page ------------------------------------
# The landing page is the one place that legitimately advertises ANOTHER
# environment: the live season's front page points testers at the permanent dev
# realm (dev.homerslotr.com, its own port, its own password). Both landing-page
# rules are shape-matched by design, so they would happily rewrite that block
# into this season's own host and port — i.e. silently send testers to
# production and the gate would then demand it stay that way. Anything between
# these markers is left exactly as authored, by the rewrite AND by the
# published-wiki advisory:
#
#   <!-- season-brand:ignore (why) --> … <!-- /season-brand:ignore -->
#
# Use it ONLY for a deliberate cross-environment reference. A season's own
# strings must stay branded, or a cutover leaves them pointing at the old realm.
BRAND_IGNORE_RE = re.compile(
    r"<!--\s*season-brand:ignore\b.*?-->.*?<!--\s*/season-brand:ignore\s*-->",
    re.S)


def outside_ignored(s: str, fn) -> str:
    """Apply `fn` to every part of `s` outside a season-brand:ignore region."""
    out, pos = [], 0
    for m in BRAND_IGNORE_RE.finditer(s):
        out.append(fn(s[pos:m.start()]))
        out.append(m.group(0))
        pos = m.end()
    out.append(fn(s[pos:]))
    return "".join(out)


# The Well of Eru area, for the Recent Updates board's roadmap link.
WELL_OF_ERU = UNPACKED / "thewelloferu.git.json"

class BrandError(Exception):
    pass


# ---------------------------------------------------------------- env ------
def load_env(path: Path) -> dict[str, str]:
    """Parse KEY=VALUE lines. The values this script needs carry no shell
    interpolation, so a full `bash -c . server.env` is unnecessary — but the
    trailing-comment handling does have to match bash, because the season block
    documents each value inline (`SEASON_ROLE=live   # live | test | dev | archive`)
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
    if role not in ("live", "test", "dev", "archive"):
        raise BrandError(f"SEASON_ROLE must be live|test|dev|archive, got {role!r}")

    wiki_url = need("SEASON_WIKI_URL")
    if not wiki_url.endswith("/"):
        wiki_url += "/"
    m = re.match(r"https?://([^/]+)/", wiki_url)
    if not m:
        raise BrandError(f"SEASON_WIKI_URL must be an absolute URL, got {wiki_url!r}")
    wiki_host = m.group(1)


    # Where PRODUCTION publishes, which is not the same question as
    # SEASON_WIKI_URL (this environment's own wiki). The dev realm needs it so
    # its roadmap editor can link to the live roadmap; a live season's copy is
    # simply its own URL. Defaults to the apex, which is true by definition:
    # the apex is bound to whichever season is live.
    live_wiki_url = env.get("SEASON_LIVE_WIKI_URL") or f"https://{APEX_DOMAIN}/"
    if not live_wiki_url.endswith("/"):
        live_wiki_url += "/"

    cfg: dict[str, object] = {
        "num": num,
        "role": role,
        "live_wiki_url": live_wiki_url,
        "wiki_url": wiki_url,
        "wiki_host": wiki_host,
        "worker_name": need("SEASON_WORKER_NAME"),
        "connect": f'{need("SEASON_CONNECT_HOST")}:{need("NWN_PORT")}',
        "container": need("NWN_CONTAINER_NAME"),
    }

    # Names are standardized across every realm — see the rule block further
    # down for why the old SEASON_LEGACY_NAMES exemption was safe to drop.
    if role == "dev":
        # The test realm is PERMANENT and is never a season, so none of its
        # names carry the season number. SEASON_NUM still tracks whichever
        # season it currently feeds (2 now, 3 later) because season-profile.py
        # and the promote script want to know — but bumping it must not rename
        # the module, so nothing here reads it.
        #
        # It is branded TEST rather than DEV: "dev" is the internal role name,
        # but what a player sees in the module list and the server browser is
        # the realm they are choosing, and TEST says what it is to them.
        cfg["package_name"] = "homers_lotr_test"
        cfg["mod_file"] = "homers_lotr_test.mod"
        cfg["nwn_module"] = "Homer's LOTR TEST"
    else:
        cfg["package_name"] = f"homers_lotr_s{num}"
        cfg["mod_file"] = f"homers_lotr_s{num}.mod"
        cfg["nwn_module"] = f"Homer's LOTR Season {num}"

    # THE SERVER BROWSER NAME IS THE MODULE NAME. Not "derived from" it, not
    # "based on" it - identical, character for character.
    #
    # It used to add a separator and a role suffix: "Homer's LOTR - Season 2
    # (EARLY ACCESS)" / " (ARCHIVED)" / " - TEST REALM (password required)".
    # The game client truncates this string in the server browser, and those
    # extra characters pushed the part that actually identifies the realm - the
    # season number - past the cut. The result was a browser listing three
    # servers whose visible names were indistinguishable, which is the one job
    # this string has.
    #
    # So role is NOT encoded here. A realm's status reaches players through
    # channels that do not truncate: the module description, the Well of Eru
    # notice board, and the login messages. Do not reintroduce a suffix.
    #
    # ASCII hyphen only if one is ever needed again: this string is passed
    # through the container env to nwserver and on to the master server browser,
    # where a UTF-8 dash would be mangled.
    cfg["nwn_servername"] = cfg["nwn_module"]
    return cfg


# ------------------------------------------------------------ file helpers --
def read_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def dump_json(obj) -> str:
    """Match nwn_gff's JSON formatting exactly, so a rebrand diff shows only the
    strings it changed and never a whole-file reformat."""
    return json.dumps(obj, indent=2, ensure_ascii=False) + "\n"


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
    # Everything outside a season-brand:ignore region is rebranded; the regions
    # themselves are left alone (see BRAND_IGNORE_RE).
    def landing(s, notes):
        connect_re = re.compile(
            re.escape(str(cfg["connect"]).rsplit(":", 1)[0]) + r":\d+")
        hosts = conns = 0

        def brand_segment(seg: str) -> str:
            nonlocal hosts, conns
            rehosted = rehost(seg)
            if rehosted != seg:
                hosts += 1
            after, n = connect_re.subn(str(cfg["connect"]), rehosted)
            if n and after != rehosted:
                conns += n
            return after

        new = outside_ignored(s, brand_segment)
        if hosts:
            notes.append("wiki host link(s)")
        if conns:
            notes.append(f"direct-connect string x{conns}")
        return new

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

    # The worker owns two generated constants: the canonical host, and the list
    # of hosts that 301 to it. The list is non-empty only for the LIVE season,
    # which is reachable at both the apex and its own season<N>. subdomain —
    # serving the same site at two addresses splits inbound links and the SEO
    # for no gain, so the subdomain folds into the apex. Archiving the season
    # empties the list and season<N>. serves its frozen wiki again.
    def index_js(s, notes):
        new, n = re.subn(r"(const CANONICAL\s*=\s*')[^']*(')",
                         rf"\g<1>{host}\g<2>", s, count=1)
        if not n:
            raise BrandError("src/index.js: CANONICAL constant not found — "
                             "season-brand rule is stale")
        if new != s:
            notes.append(f"canonical host -> {host}")

        folded = [f"season{cfg['num']}.{APEX_DOMAIN}"] if cfg["role"] == "live" else []
        # Keep the literal shape a JS array of single-quoted strings, so the
        # rule re-matches what it just wrote (idempotence).
        want = ", ".join(f"'{h}'" for h in folded)
        after, n = re.subn(r"(const REDIRECT_HOSTS\s*=\s*\[)[^\]]*(\])",
                           rf"\g<1>{want}\g<2>", new, count=1)
        if not n:
            raise BrandError("src/index.js: REDIRECT_HOSTS constant not found — "
                             "season-brand rule is stale")
        if after != new:
            notes.append(f"redirect hosts -> [{want}]")
        return after

    text_edit(REPO / "src" / "index.js", index_js)

    # --- roadmap editor: public links ---------------------------------------
    # There used to be a second rule here that rewrote container_name()'s
    # hardcoded fallback. The fallback is GONE: with a dev realm plus two
    # seasons on one host, a guessed container name silently shows another
    # realm's logs, so container_name() now raises instead of defaulting.
    # Nothing to keep in sync, so no rule.
    #
    # The links are rewritten by data-brand attribute, NOT by a blanket
    # rehost(). The editor runs in the dev repo but its ROADMAP link points at
    # the LIVE site, and a blanket host substitution would rewrite it to dev's
    # host too - pointing the one link whose entire purpose is "go and look at
    # production" back at dev.
    #
    # There used to be a third link, data-brand="roadmap", for this realm's own
    # roadmap page. It went when Publish started pushing the page into the live
    # realm's docs/ too (roadmap-editor.publish_to_live_realm): with production
    # current the moment you publish, a per-realm roadmap link only raised the
    # question of which of the two was the real one.
    def editor(s, notes):
        def href(src: str, key: str, url: str) -> str:
            pat = rf'(<a data-brand="{key}" href=")[^"]*(")'
            out, n = re.subn(pat, lambda m: m.group(1) + url + m.group(2),
                             src, count=1)
            if not n:
                raise BrandError(
                    f'roadmap-editor.py: no <a data-brand="{key}"> link - '
                    "season-brand rule is stale")
            return out

        new = href(s,   "live-wiki",     cfg["live_wiki_url"])
        new = href(new, "live-roadmap",  f'{cfg["live_wiki_url"]}manual/Roadmap')
        if new != s:
            notes.append("public wiki/roadmap links")
        return new

    text_edit(REPO / "bin" / "roadmap-editor.py", editor)

    # --- watch-server container fallback ------------------------------------
    def watch(s, notes):
        new, n = re.subn(r"(NWN_CONTAINER_NAME=\$\{NWN_CONTAINER_NAME:-)[^}]*(\})",
                         rf'\g<1>{cfg["container"]}\g<2>', s, count=1)
        if n and new != s:
            notes.append("container-name fallback")
        return new

    text_edit(REPO / "bin" / "watch-server", watch)

    # --- module and server names --------------------------------------------
    # Unconditional. SEASON_LEGACY_NAMES used to exempt season 1 from the
    # derived names, on the reasoning that renaming a live module is dangerous.
    # It is not: the servervault is per-NWN_HOME_DIR and campaign DBs are scoped
    # by their own name, so nothing player-owned is keyed to the module name,
    # and a saved server entry addresses host:port. The only hard requirement is
    # that NWN_MODULE match the installed .mod filename exactly, which this
    # writes as a pair. Every realm is named the same way now:
    #
    #     seasons     homers_lotr_s<N>.mod    "Homer's LOTR Season <N>"
    #     test realm  homers_lotr_test.mod    "Homer's LOTR TEST"
    if True:
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


def docs_stale(cfg) -> list[str]:
    """Report where the PUBLISHED wiki disagrees with the season block.

    `index.html` at the repo root is the hand-maintained source this script
    owns. `docs/index.html` is GENERATED from it by the wiki build, which
    injects the header/footer around it - so rebranding updates the source and
    leaves the published page untouched until someone runs a full wiki refresh.

    Nothing else notices that gap, and it is publicly visible the whole time.
    It bit the season 1 -> 2 cutover: the dev realm was rebranded onto port
    5123, but dev.homerslotr.com kept telling visitors to connect on 5122 -
    production's port - because docs/ still held the early-access build.

    Deliberately an ADVISORY, not a build gate. docs/ legitimately lags between
    a rebrand and the next scheduled wiki publish, and failing `--check` here
    would block a module repack over a stale wiki, which is the wrong coupling.
    It is printed loudly right after the rebrand instead, which is the moment
    the operator can act on it.
    """
    docs_index = REPO / "docs" / "index.html"
    if not docs_index.exists():
        return []
    try:
        published = docs_index.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return []

    # HTML comments survive into the generated page, so the same opt-out that
    # spares the dev-realm block from the rewrite spares it from this audit —
    # otherwise a correctly authored cross-environment link would be reported
    # as a stale wiki forever.
    published = BRAND_IGNORE_RE.sub("", published)

    problems: list[str] = []
    connect = str(cfg["connect"])
    host = str(cfg["wiki_host"])

    # The connect string is host:port; a stale one points players at another
    # environment's server, which is the damaging case.
    found_conn = set(re.findall(
        re.escape(connect.rsplit(":", 1)[0]) + r":\d+", published))
    if found_conn and found_conn != {connect}:
        wrong = ", ".join(sorted(found_conn - {connect}))
        problems.append(f"advertises {wrong} but this environment is {connect}")

    # WIKI_HOST_RE has no capturing groups, so findall yields whole hosts.
    found_hosts = set(WIKI_HOST_RE.findall(published))
    if found_hosts and found_hosts != {host}:
        wrong = ", ".join(sorted(found_hosts - {host}))
        problems.append(f"links to {wrong} but this environment's wiki is {host}")
    return problems


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

    names = f'{cfg["nwn_module"]!r}'
    print(f'season {cfg["num"]} role={cfg["role"]} '
          f'wiki={cfg["wiki_host"]} connect={cfg["connect"]} names={names}')
    print()

    def published_advisory() -> None:
        """Warn if the live wiki still carries another environment's values."""
        stale = docs_stale(cfg)
        if not stale:
            return
        print()
        print("  !! PUBLISHED WIKI IS STALE — docs/index.html still:")
        for s in stale:
            print(f"       {s}")
        print("     docs/ is generated, so rebranding does not touch it. Until a")
        print("     full refresh runs, the live site advertises the old values:")
        print("       bin/refresh-homers-lotr-wiki --publish")

    if not edits:
        print("up to date — nothing to change")
        published_advisory()
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
    published_advisory()
    return 0


if __name__ == "__main__":
    sys.exit(main())
