# Season Cutover Runbook — Homer's LOTR (v2.0, repeatable)

> **Status:** v2.0 — a **season-agnostic** runbook. Everything below is written in
> terms of **season N** (the outgoing/current season) and **season N+1** (the
> incoming one). Run it unchanged every cutover; substitute the numbers.
> It describes changes to make; it does **not** itself change any code, DB, or unit.

---

## 0. Why seasons, and how often

Give players a periodic **fresh start** — everyone rolls new characters — so the
server can absorb major rebalances (gear, bosses, the legendary-level system)
without the weight of legacy characters and inflated economies.

**Cadence:** roughly **every 3–4 months**, *or* whenever a change is large enough
that old characters can't be carried forward fairly (gear power curve, boss/loot
tables, legendary-level math). There is no fixed calendar; the trigger is "the
change is too big to hot-patch."

**What a season preserves across the boundary:**
- **Account-wide merit** (earned merit + redemption entitlements) is *shared* by
  every season, forever — it's an account reward, not a character reward.
- Everything else about a character (levels, gear, gold, bestiary, houses, banks,
  boss-kill history, saved teleport slots) is **fresh** each season.

---

## 1. Invariants — memorise these, they never change

```
PORTS        5121/udp  = the LIVE season, always
             5122/udp  = the ALTERNATE slot (early-access realm OR archived season)
NWSYNC       8000/tcp  = live      8001/tcp = alternate
INSTANCES    never more than 2 servers running at once
REPOS        nwn_homers_lotr          = the NEWEST season. Always. Never re-cloned.
             nwn_homers_lotr_s<N>     = archived season N (created at that season's retirement)
RUNTIME      season N owns  ~/.local/share/Neverwinter Nights S<N>   (home: vault + database/)
                            ~/.local/state/nwnxee-homer-s<N>          (run: logs + Anvil)
                            container  nwnxee-homer-s<N>
WIKI         homerslotr.com            -> whichever season is LIVE
             season<N>.homerslotr.com  -> season N, permanently (early-access, then archive)
SHARED       ~/.local/share/nwn-shared/meritdb.sqlite3   <- the ONLY cross-season file
```

**Legacy wart (season 1 only):** season 1 keeps today's *unnumbered* runtime dirs
(`~/.local/share/Neverwinter Nights`, `~/.local/state/nwnxee-homer`, container
`nwnxee-homer`). Don't rename them — a rename buys uniformity and risks the live
vault. Every season from 2 onward is numbered.

### Why the folder rule looks inverted

Intuition says "the new season goes in the new folder." It's the other way round,
and deliberately so:

> At Phase 1 the **outgoing** season is the one copied out to
> `nwn_homers_lotr_s<N>`, **inheriting its runtime pointers verbatim** — same home
> dir, run dir, container, same port 5121. So **nothing about the live server
> moves and no player data is touched**. The unnumbered repo stays where it is,
> gets re-parameterized onto fresh season-`N+1` dirs and the alternate port, and
> becomes the early-access realm — which then *becomes* the live season at Phase 2.

Two payoffs: development never leaves `nwn_homers_lotr` (the early-access branch
*is* the go-live code basis — no re-clone, no merge), and there is **never a third
environment**, so Phase 2 is a role/port swap between two existing servers rather
than a stand-up plus a shutdown.

### Lifecycle

```
   PHASE 1                          PHASE 2                        PHASE 3
   copy out season N          -->   swap roles + ports       -->   retire season N
   ┌──────────────────┐             ┌──────────────────┐           ┌──────────────────┐
   │ _s<N>   : LIVE   │ 5121        │ _s<N>  : ARCHIVE │ 5122      │ _s<N>  : stopped │  —
   │ unnum'd : TEST   │ 5122        │ unnum'd: LIVE    │ 5121      │ unnum'd: LIVE    │ 5121
   └──────────────────┘             └──────────────────┘           └──────────────────┘
   password "volatile"              vault+DBs wiped                wiki frozen at
   wipe warning sign                "season over" sign             season<N> subdomain
```

| Phase | Live on 5121 | On 5122 | Merit | Wiki |
|-------|--------------|---------|-------|------|
| steady state | season N | — | shared | apex → N |
| Phase 1 | season N | season N+1 (password) | shared | apex → N; `season<N+1>.` → N+1 |
| Phase 2 | season N+1 | season N (archive) | shared | apex → N+1; `season<N>.` → N |
| Phase 3 | season N+1 | — | shared | apex → N+1; `season<N>.` frozen |

---

## 2. The data contract — what carries over, what resets

All persistent state is **campaign SQLite DBs** in `NWN_HOME_DIR/database/`.
Campaign DBs are campaign-scoped: any module under the *same* `NWN_HOME_DIR`
shares them by filename; a *separate* `NWN_HOME_DIR` gets a completely fresh
`database/`. **A separate `NWN_HOME_DIR` per season is the single lever that makes
almost everything reset automatically.** You then deliberately re-share the one
file that must persist.

**The rule, not a list:** *everything resets except the shared merit file.* Don't
maintain an inventory of DB names here — new systems add new DBs (today:
`admindb`, `ammorepdb`, `bestiarydb`, `boostdb`, `dyedb`, `factiondb`, `roadmapdb`,
`respawndb`, `teledb`, plus bank/house/fellbeast/meaningwave/partyloot/promo
stores) and a stale list is worse than none.

| | |
|---|---|
| **Shared** | `meritdb` — real file at `~/.local/share/nwn-shared/meritdb.sqlite3`, symlinked into every season's `database/`. Keyed by `GetPCPublicCDKey`: `players`, `redemptions`, `merit_ledger`. |
| **Fresh** | Everything else. A new `NWN_HOME_DIR` gives it to you for free — no per-DB surgery. |
| **Self-resetting** | `respawndb` — `BRD_InitDb()` wipes and re-seeds `boss_registry`/`boss_alias`/`boss_deaths` on every module load. Never carries cross-season state. |
| **Deliberately fresh** | `admindb` — leave it fresh so player houses start empty; re-seed the admin whitelist with `bin/seed-admindb.sh` against the new home dir (it's out-of-band and key-free). |

**Wiki metrics reset for free — with one catch.**
- Server-firsts / kill leaderboards come from `bestiarydb` → fresh home dir ⇒ empty.
- Activity charts are built from `--log-dir` server logs + `activity-sessions.json`
  → fresh run dir ⇒ charts start at zero.
- **The catch:** during Phase 1 the early-access realm accumulates *both* for
  weeks. Phase 2's wipe must therefore clear the **run dir's logs and
  `activity-sessions.json`**, not just the vault and DBs. Miss this and season
  N+1 launches with early-access playtime already on its charts.

---

## 3. Prep work — one-time, before the first cutover

The runbook below assumes these exist. Do them once; every later season reuses them.

| # | Item | Detail |
|---|------|--------|
| 1 | **Split `teledb` out of `meritdb`** | `unpacked/tele_db.nss` still has `const string TELE_DB = "meritdb";`. Change to `"teledb"`. Everything else in the file already routes through `TELE_DB`; `Tele_InitDb()` is idempotent and creates the new DB on first use. **Required** — with a shared merit file, per-character `tele_slots`/`tele_state` would otherwise leak into every future season. Teleport *unlocks* are merit redemptions 101–107 in `meritdb.redemptions` and are unaffected; players lose their **saved slots** once. Repack, deploy, announce. |
| 2 | **Move the merit DB to the neutral path** | Server stopped: `mkdir -p ~/.local/share/nwn-shared`, `mv` the real `meritdb.sqlite3` there, absolute-symlink it back into the season's `database/`. No season is special afterwards, and retiring season 1 can never orphan it. |
| 3 | **Season block in `server.env`** | `SEASON_NUM`, `SEASON_ROLE` (`live`\|`test`\|`archive`), `SEASON_WIKI_URL`, `SEASON_WORKER_NAME`. The single source of season identity — everything else derives from it. |
| 4 | **De-hard-code `bin/refresh-homers-lotr-wiki`** | It pins `PROJECT=/var/home/james/GIT/nwn_homers_lotr` (line ~24), `--base-url https://homerslotr.com/` and `--log-dir …/nwnxee-homer` (line ~46). Derive `PROJECT` from `BASH_SOURCE` (copy the idiom from `bin/serve`), and take base-url / log-dir from `$SEASON_WIKI_URL` / `$NWN_RUN_DIR`. This is the only wrapper that isn't already relocatable — `bin/serve` and `bin/backup-homers-lotr` compute `PROJECT_ROOT` correctly already. |
| 5 | **Backup script** | Exclude `database/meritdb.sqlite3` (a symlink — must not be followed) from every season's snapshot; back up `~/.local/share/nwn-shared/` from exactly one place, gated on `SEASON_ROLE=live`. |
| 6 | **`@`-templated systemd units** | Today's units hard-code the repo path and `nwnxee-homer`; `homers-lotr-empty-restart.path` also hard-codes the Anvil watch path `%h/.local/state/nwnxee-homer/anvil/PluginData/restart-server`. Convert to instance units keyed on the repo dir name, with `WorkingDirectory`, the podman `ExecStop` name and that `PathExists` all derived from an instance env file. **First commit `homers-lotr-server.service`** — it's installed under `~/.config/systemd/user/` but missing from the repo's `systemd/`. `nwn-reboot.timer` (root, 03:03) stays shared and restarts both instances. |
| 7 | **`bin/season-brand.py`** (new) | Idempotent rebrand pass driven by the season block. Rewrites every reference in §4 and sets the season sign's text for the current `SEASON_ROLE`. Dry-run by default, `--apply` to write, second `--apply` must produce no diff. |
| 8 | **Season sign placeable** | One new `.utp` placed once in `thewelloferu.git.json`, mirroring `ru_sign` (`__struct_id: 9`, Appearance 89, text in `Description`). Use `bin/place-helper.py` for coordinates and follow the GIT-instance shape rules in `CLAUDE-blueprints.md`. Three states set by `season-brand.py`: `test` → "Early-access realm — your progress will be wiped when this season goes live"; `archive` → "This season has ended and is no longer updated or maintained"; `live` → hidden (turn visibility off — keep the instance so it serves every future season). Then `python3 bin/file-palette-orphans.py --apply`. |
| 9 | **`bin/roadmap-archive-prune.py`** (new) | Deletes every `ideas:` entry whose `status` is not `awarded`, plus any epic left childless, then runs `bin/gen-roadmap.py`. Only ever run inside an archived season's repo. |

---

## 4. What `season-brand.py` must rewrite

The complete set of season-scoped references. Anything added later that names the
wiki host, the connect port, or the worker belongs in this table *and* in the script.

| File | What |
|------|------|
| `unpacked/module.ifo.json` | Module description: `Connect: homerslotr.ddns.net:5121` and `Wiki: homerslotr.com` |
| `unpacked/npguide.dlg.json` | Guide NPC — two wiki links, one of them `…/manual/Customizations` |
| `unpacked/meritconv.dlg.json` | Merit NPC wiki link |
| `unpacked/servershout4.nss` | Login floaty text: `View the Wiki at homerslotr.com` |
| `unpacked/thewelloferu.git.json` | `ru_sign` Description → `https://homerslotr.com/manual/Roadmap#shipped`; and the season sign's text/visibility |
| `src/index.js` | Worker redirect target for `*.workers.dev` |
| `wrangler.jsonc` | Worker `name` — **mandatory, not cosmetic**: two repos deploying the same worker name collide (see §6) |
| `bin/roadmap-editor.py` | The editor's "Public wiki / Public roadmap" links, and its `nwnxee-homer` container-name fallback |
| `bin/watch-server` | `NWN_CONTAINER_NAME` default (`nwnxee-homer`) |
| `nasher.cfg` | Target `.mod` filename — one per season (see §11) |

`unpacked/module.jrl.json` currently needs **no** rebrand: the "Website" journal
entry links Discord only, and the Server Info entries say "wiki: Manual >
Customizations" without a host. Re-check it each cutover anyway — it's the most
likely place for a new bare URL to appear.

> **Do not implement this as a blind `sed` over `unpacked/`.** `5121` occurs
> inside float coordinates in at least seven `.git.json` files
> (`"value": 54.5121`, `-22.5121`, …) and as a listen-pattern integer in
> `unpacked/roulette_os.nss`. A global port substitution silently moves
> placeables and breaks a conversation. `season-brand.py` must target the exact
> fields listed above — and the port only ever inside the `Connect:` line of the
> module description.

---

## 5. Phase 1 — stand up the early-access realm (season N+1)

The live season keeps running throughout; nothing about it moves.

1. **Copy the outgoing season out.** `cp -a nwn_homers_lotr nwn_homers_lotr_s<N>`
   (or clone). Give it a **new GitHub remote** — it needs its own Cloudflare
   deploy target. Its `server.env` is **inherited unchanged**: same home dir, run
   dir, container, `NWN_PORT=5121`. Set `SEASON_NUM=<N>`, `SEASON_ROLE=live`,
   `SEASON_WIKI_URL=https://homerslotr.com/`,
   `SEASON_WORKER_NAME=homers-lotr-wiki-s<N>` (see §6). Repoint its systemd
   instance at the new directory.
2. **Re-parameterize the unnumbered repo onto season N+1.** In `server.env`:
   `NWN_HOME_DIR="$HOME/.local/share/Neverwinter Nights S<N+1>"`,
   `NWN_RUN_DIR="$HOME/.local/state/nwnxee-homer-s<N+1>"`,
   `NWN_CONTAINER_NAME=nwnxee-homer-s<N+1>`, `NWN_PORT=5122`,
   `NWNSYNC_PORT=8001`, `NWNSYNC_CONTAINER=nwnsync-nginx-s<N+1>`,
   `NWNSYNC_REPO=…/nwsync/HomersLOTR-S<N+1>`,
   `NWN_MODULE`/`NWN_SERVERNAME` naming the new season,
   `SEASON_NUM=<N+1>`, `SEASON_ROLE=test`,
   `SEASON_WIKI_URL=https://season<N+1>.homerslotr.com/`,
   `SEASON_WORKER_NAME=homers-lotr-wiki-s<N+1>`.
   `bin/serve` runs `--network=host`, so **every listening port must be unique** —
   there is no container port isolation.
3. **Password-gate it.** `NWN_PLAYERPASSWORD="volatile"` in `server.env.local`
   (gitignored). Hand it only to chosen testers. Also set `NWNSYNC_PUBLIC_URL`
   there for port 8001.
4. **Rebrand + build.** `python3 bin/season-brand.py --apply` → in-game wiki links
   point at `season<N+1>.homerslotr.com`, the connect string at `:5122`, and the
   season sign shows the wipe warning. Repack and deploy.
5. **Share merit.** After the new server's first boot creates `database/`:
   ```bash
   S="$HOME/.local/share/Neverwinter Nights S<N+1>/database/meritdb.sqlite3"
   rm -f "$S"
   ln -s "$HOME/.local/share/nwn-shared/meritdb.sqlite3" "$S"
   ls -l "$S"      # verify it points at the shared file
   ```
6. **Cloudflare.** New worker `homers-lotr-wiki-s<N+1>` deploying from the
   unnumbered repo, custom domain `season<N+1>.homerslotr.com` + DNS record.
   The apex stays bound to the **season-N** worker, which now deploys from
   `nwn_homers_lotr_s<N>`. Cloudflare auto-deploys **on git push** — "publish" is
   just commit `docs/` + push; no `wrangler deploy` anywhere.
7. **Router.** Forward 5122/udp and 8001/tcp. Permanent — reused every season.
8. **Enable both systemd instances.** Both servers now come up at boot, in parallel.
9. **Announce loudly and repeatedly:** the early-access vault and *all* its DBs
   **will be wiped at go-live**. Every character, item, bestiary entry, house and
   bank gained in testing is temporary. **Merit earned still counts** — it's the
   shared account DB.

Iterate freely: this repo is the real season N+1 code base, and all development
from here to go-live carries straight through.

---

## 6. Wiki hosting — one worker per season

`wrangler.jsonc` defines a worker serving `./docs` as static assets; `src/index.js`
301-redirects `*.workers.dev` to the season's own host.

**Rule: every season owns a permanently-named worker `homers-lotr-wiki-s<N>`,
permanently bound to `season<N>.homerslotr.com`. The apex `homerslotr.com` custom
domain is *moved* between workers at Phase 2 — it is the only binding that ever
changes.**

This is why the `wrangler.jsonc` rename in §4 is mandatory: at Phase 1 the
unnumbered repo stops being the live season, so if it kept the shared worker name
it would deploy the *early-access* wiki onto the apex the first time a tester
pushed. (Season 1's existing worker may keep its legacy name; just bind
`season1.homerslotr.com` to it.)

Archived seasons **keep publishing** during Phase 2 — players may still be on
them, and their kill counts and activity charts should keep updating at their
subdomain. Publishing stops at Phase 3, and Cloudflare then serves the last
deployed `docs/` frozen, indefinitely.

---

## 7. Phase 2 — go live (the swap)

A maintenance window with both servers stopped. Nothing here is a stand-up or a
teardown — it is a role and port swap between two servers that are already running.

1. **Snapshot season N's `bestiarydb`** to a safe path *before* anything else —
   the returning-player reward (§9) reads it. Snapshot character XP from the
   season-N servervault too if the XP-bank tier is in play.
2. **Final full wiki republish of season N** against its live DBs, so the archive
   is complete and current.
3. **Wipe the early-access realm to a clean live state** (server stopped):
   ```bash
   H="$HOME/.local/share/Neverwinter Nights S<N+1>"
   R="$HOME/.local/state/nwnxee-homer-s<N+1>"
   rm -rf "$H/servervault"/*
   find "$H/database" -name '*.sqlite3' ! -name 'meritdb.sqlite3' -delete
   rm -rf "$R"/logs.*  "$R"/activity-sessions.json*
   ls -l "$H/database/meritdb.sqlite3"    # symlink MUST still be intact
   ```
   **Never `rm -rf` the whole `database/` dir** and never let anything follow the
   merit symlink — deleting the link is recoverable, truncating the shared file is
   not. The run-dir clear is what makes activity charts and server-firsts start at
   zero (§2).
4. **Swap the ports.** Unnumbered repo: `NWN_PORT` 5122→**5121**, `NWNSYNC_PORT`
   8001→**8000**. `_s<N>`: 5121→**5122**, 8000→**8001**. Container names, home
   dirs and run dirs never change — only these two numbers per side.
5. **Flip the roles and rebrand both.**
   - unnumbered → `SEASON_ROLE=live`, `SEASON_WIKI_URL=https://homerslotr.com/`
   - `_s<N>` → `SEASON_ROLE=archive`, `SEASON_WIKI_URL=https://season<N>.homerslotr.com/`

   Run `python3 bin/season-brand.py --apply` in **both** repos, then repack and
   deploy **both** modules. Season N's rebuild is what flips its sign to "this
   season has ended" and moves its in-game links off the apex — without it, the
   archived season's own signs would send players to the new season's wiki.
6. **Cloudflare:** move the `homerslotr.com` custom domain from worker
   `homers-lotr-wiki-s<N>` to `homers-lotr-wiki-s<N+1>`. Season N keeps its
   subdomain and its publish job.
7. **Prune the archived roadmap.** In `_s<N>`: `bin/roadmap-archive-prune.py` →
   keeps `status: awarded` only, deletes every other item (backlog and
   shipped-but-unpaid alike — that work all lives on in the unnumbered repo's
   roadmap, which is untouched). Run `bin/gen-roadmap.py`, commit both files, and
   publish to that season's `roadmapdb` so its in-game Recent Updates sign matches
   its public page. The archived season's roadmap is now a pure merit-credit ledger.
8. **Go public.** Remove `NWN_PLAYERPASSWORD` from the unnumbered
   `server.env.local`, start both servers, and confirm the server browser lists
   season N+1 on 5121 with NWSync on 8000, and season N on 5122 / 8001.
9. **Verify merit** — log in on both and confirm the same balance reads through.
10. **Apply the returning-player reward** (§9) and announce: new season live,
    old season still playable on the alternate port, old wiki at its subdomain.

**Rollback.** Until Phase 3 this is fully reversible: season N's vault and DBs were
never touched, so swapping the two port pairs back restores the previous state.
The one shared object is `meritdb` — so **avoid merit schema changes during the
overlap**, since both seasons write the same file.

---

## 8. Phase 3 — retire season N

Once `_s<N>` is consistently empty for a decent stretch:

1. Stop and disable its server + NWSync systemd instances, and its wiki-publish
   and backup units.
2. Stop pushing that repo. Cloudflare keeps serving its last-deployed `docs/`
   frozen at `season<N>.homerslotr.com` — indefinitely, no maintenance.
3. Leave its home dir on disk, or take one final cold archive of vault + DBs.
   Its runtime dirs stay reserved to that season's number.

You are back to a single running instance. 5122/8001 sit idle until the next
Phase 1 reuses them, and the router forwards stay in place.

---

## 9. Returning-player reward

Decided **per season, at Phase 2**. The mechanism is fixed; only the numbers change.

**A claim-once "Season N Veteran" NPC** in the new season's start area, backed by a
**one-time season-N snapshot table in the shared merit DB** (populated from step 1
of Phase 2), granting:

- **(a)** a small, **capped XP-bank stipend** to everyone who played season N
  (participation tier), plus
- **(b)** **one achievement-gated gear or cosmetic piece** for standouts —
  server-firsts, bestiary completion.

One auditable code path, eligibility keyed by CD key in the DB that is already
shared, no double-claims, no DM presence needed. Keep gear **medium tier or
cosmetic-forward**: a strong veteran item distorts a fresh economy far more than
it rewards. Other ideas that fold into the same NPC if wanted: a permanent
"Season N Veteran" account flag unlocking a title or veteran-only vendor, or a
modest bestiary kill-count head start.

---

## 10. Cutover checklist

Copy this into the announcement/tracking issue for each cutover.

**Phase 1 — early access**
- [ ] `cp -a` → `nwn_homers_lotr_s<N>`; new git remote; season block `= live`; systemd repointed
- [ ] Unnumbered repo re-parameterized to season N+1 (home/run/container/5122/8001/nwsync repo)
- [ ] `NWN_PLAYERPASSWORD="volatile"` + `NWNSYNC_PUBLIC_URL` in `server.env.local`
- [ ] `season-brand.py --apply`; repack; deploy
- [ ] Merit symlink created and verified with `ls -l`
- [ ] Worker `homers-lotr-wiki-s<N+1>` + `season<N+1>.homerslotr.com` + DNS
- [ ] Router: 5122/udp, 8001/tcp forwarded
- [ ] Both systemd instances enabled; both servers up after a reboot
- [ ] Wipe warning announced to testers

**Phase 2 — go live**
- [ ] `bestiarydb` (+ XP) snapshot taken
- [ ] Final season-N wiki republish
- [ ] Vault + DBs + **run-dir logs/activity-sessions** wiped; merit symlink intact
- [ ] Ports swapped both sides
- [ ] Roles flipped; `season-brand.py --apply` run in **both**; both repacked + deployed
- [ ] Apex custom domain moved to the new worker
- [ ] Archived roadmap pruned to `awarded`-only; `gen-roadmap.py`; published to its `roadmapdb`
- [ ] Player password removed; both servers verified in the server browser
- [ ] Merit balance verified on both
- [ ] Veteran reward live; cutover announced

**Phase 3 — retire**
- [ ] Season-N server + NWSync stopped and disabled
- [ ] Its wiki-publish and backup units disabled; repo no longer pushed
- [ ] Frozen wiki confirmed serving at `season<N>.homerslotr.com`

---

## 11. Notes for the next person running this

- **Core tooling needs no changes.** `nwn-manager` / `nwn-wiki` are already
  module-agnostic — they key off the working directory, `nasher.cfg`,
  `.nasher/source`, `server.env`, and the `--base-url` / `--out` / `--db-dir` /
  `--log-dir` flags. Prefer wrapper and env changes over touching the core.
- Give each season a **distinct `.mod` filename** in `nasher.cfg`
  (`homers_lotr_s<N>.mod`): `nwn-manager` builds via a `/tmp/nwnmgr_<modfile>`
  symlink and a `nwnmgr_bstamp.nss` build stamp, so a shared filename can race if
  both seasons ever repack at once.
- A season needs its **own NWSync repo/manifest** as soon as its hak/tlk content
  diverges from the other's — which it will, once you rebalance.
- The **roadmap editor** (`:8765`) is single-instance; run it from whichever repo
  you're actually editing. Its "Publish to Wiki" body-swaps `<main>` into the
  already-built `docs/manual/Roadmap.html` — nav changes land at the next full
  refresh, not at publish.
- **Capture surprises back into this file.** Anything that bit you during a
  cutover belongs here before you forget it.

*v2.0 — first written for the season 1 → 2 cutover, but parameterized for every
cutover after it.*
