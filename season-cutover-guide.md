# Season Cutover Runbook — Homer's LOTR (v2.1, repeatable)

> **Status:** v2.1 — a **season-agnostic** runbook. Everything below is written in
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
SHARED       ~/.local/share/nwn-shared/meritdb.sqlite3    <- account merit + entitlements
             ~/.local/share/nwn-shared/admindb.sqlite3    <- admin whitelist + house records
             (the ONLY cross-season files; both symlinked into every season's database/)
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
almost everything reset automatically.** You then deliberately re-share the two
files that must persist.

**The rule, not a list:** *everything resets except the two shared files.* Don't
maintain an inventory of DB names here — the live server already holds 32 campaign
DBs and new systems add more every month, so a list here would be stale within
weeks. What matters is the mechanism: the shared DBs are **symlinks**, everything
else is a regular file, and the wipe deletes regular files only (§7).

| | |
|---|---|
| **Shared — merit** | `meritdb` → `~/.local/share/nwn-shared/meritdb.sqlite3`. Keyed by `GetPCPublicCDKey`: `players`, `redemptions`, `merit_ledger`. Account-level rewards and entitlements. |
| **Shared — admin** | `admindb` → `~/.local/share/nwn-shared/admindb.sqlite3`. `admins` (the CD-key whitelist behind `Admin_CanAdmin/Homeless/Chest`) and `houses` (see below). Admin access and UAT shortcuts don't change between seasons, so re-seeding them every cutover is pure toil. |
| **Fresh** | Everything else. A new `NWN_HOME_DIR` gives it to you for free — no per-DB surgery. Includes `coderedeem` (see below). |
| **Self-resetting** | `respawndb` — `BRD_InitDb()` wipes and re-seeds `boss_registry`/`boss_alias`/`boss_deaths` on every module load. Never carries cross-season state. |

### Redemption codes: the code lives in source, the *usage* is per-season

A promo/redemption code has two halves, and only one is a DB:

- **The code itself** — its name, `YYYY-MM-DD` expiry and reward — is defined in
  **module source** (`unpacked/code_redeem.nss`: `GetCodeExpiration()` and
  `ApplyCodeBenefit()`; list them with `bin/list-promo-codes.py`). It travels with
  the module build, so **every environment honors its codes up to each code's set
  expiry date** — nothing to share or reset.
- **The usage record** — who redeemed what — is the `coderedeem` campaign DB
  (`redemptions(code, cdkey, redeemed_at)`), per-`NWN_HOME_DIR`, so **per-season**.
  It resets like any other fresh DB: a new season starts with an empty record, and
  Phase 2's wipe clears it, while the codes stay valid to their expiry. That is the
  intended "reset who-redeemed-what at go-live without invalidating the codes."

Do **not** confuse this with **merit** redemptions (401–408, 101–107, …) — those
are account-wide entitlements in the shared `meritdb` and persist forever. Code
redemptions are per-season and every current code's reward is character-level
(`SetXP` / `GiveXPToCreature` / `CreateItemOnObject`), so resetting `coderedeem`
can never double-grant an account-wide reward. Keep it that way: a code that ever
writes `meritdb` would become re-claimable each season — don't add one.

### Why `houses` rides along with the admin whitelist

`admindb.houses` is the *fulfilment record* for a player home — area tag, home
waypoint, key resref. The **entitlement** to that home is a merit redemption
(401–408 for the home itself, 501–505 for add-ons like the storage chest, store
and forges), and merit redemptions already persist forever in the shared
`meritdb`. Resetting `houses` while the entitlement persists would mean a player
who spent merit on a home has paid for something they no longer have — the
escrow trap of §7b — and would leave the DM re-fulfilling every home by hand at
every cutover. So the fulfilment record persists too.

Two consequences worth knowing:

- **The house's *contents* still reset.** `housechest` is a separate campaign DB
  and gets wiped like everything else — otherwise a persistent chest would be a
  clean pipeline for carrying season-N gear into season N+1.
- **New seasons must keep the house area tags alive.** A `houses` row points at
  `area_tag` / `home_wp_tag` in the module. If a new season drops or renames one
  of those areas, the row dangles and the player's Home teleport breaks. That is
  a Phase 1 check (§5), not something to discover at go-live.

**Wiki metrics reset for free — with one catch.**
- Server-firsts / kill leaderboards come from `bestiarydb` → fresh home dir ⇒ empty.
- Activity charts are built from `--log-dir` server logs + `activity-sessions.json`
  → fresh run dir ⇒ charts start at zero.
- **The catch:** this is only free for a *brand new* home/run dir. The
  early-access realm accumulates weeks of both before it goes live, so Phase 2
  must actively clear the **run dir's logs and `activity-sessions.json`** as well
  as the vault and DBs — and then **regenerate the wiki**, because `docs/` is
  committed to git and still holds the early-access numbers. Full audit in §7a.

---

## 3. Prerequisites

This runbook assumes the one-time engineering in
**[season-cutover-prereqs.md](season-cutover-prereqs.md)** is done: the
`teledb`/`meritdb` split, the `meritdb` + `admindb` DBs moved to their neutral
shared path, the season
block in `server.env`, relocatable wrappers, templated systemd units,
`bin/season-brand.py`, the two season placeables, and
`bin/roadmap-archive-prune.py`.

**Do not start Phase 1 until that file's boxes are ticked** — every phase below
calls into one of those pieces, and two of them (the `teledb` split and the merit
DB move) touch live player data and cannot be done mid-cutover.

---

## 4. Module and server naming

Three names get confused constantly. In NWN, **the module name *is* the installed
`.mod` filename**, so `NWN_MODULE` must match it exactly or `nwserver` won't find
the module at boot.

| Name | Where | Season N value | Changed at |
|------|-------|----------------|-----------|
| Build artifact | `nasher.cfg` → `[package].name`, `[target].file` | `homers_lotr_s<N>.mod` | Phase 1 |
| **Installed module** | `$NWN_HOME_DIR/modules/<name>.mod`, written by the repack wrapper | `Homer's LOTR Season <N>.mod` | Phase 1 |
| `NWN_MODULE` | `server.env` — the installed filename **minus `.mod`** | `Homer's LOTR Season <N>` | Phase 1 |
| `NWN_SERVERNAME` | `server.env` — server-browser name, free text | role-dependent ↓ | Phase 1 **and** Phase 2 |

`NWN_SERVERNAME` tracks `SEASON_ROLE`, so the two instances are tellable apart in
the server browser:

| Role | Server name |
|------|-------------|
| `test` | `Homer's LOTR — Season <N> (EARLY ACCESS)` |
| `live` | `Homer's LOTR — Season <N>` |
| `archive` | `Homer's LOTR — Season <N> (ARCHIVED)` |

Renaming also means updating the **repack wrapper's install destination** — the
`.mod` filename it copies into `$NWN_HOME_DIR/modules/`. See prereq item 5; until
that wrapper is parameterized this is a hand-edit and it is the single most
error-prone step in Phase 1. A mismatch between the installed filename and
`NWN_MODULE` shows up as the server exiting at startup with a module-not-found
error, not as anything subtler.

**Season 1 keeps its legacy names** (`homers_lotr_v3.mod`, module
`Homer's LOTR VEL v3`, server name `Homer's LOTR Very Easy Leveling`). Never
rename a live module — the filename change alone breaks every player's saved
server entry. Numbering starts at season 2.

No data consequence: the servervault is per-`NWN_HOME_DIR` and campaign DBs are
scoped by their own name, so neither is keyed to the module name.

---

## 5. Phase 1 — stand up the early-access realm (season N+1)

The live season keeps running throughout; nothing about it moves.

1. **Copy the outgoing season out.** `cp -a nwn_homers_lotr nwn_homers_lotr_s<N>`
   (or clone). Give it a **new GitHub remote** — it needs its own Cloudflare
   deploy target. Its `server.env` is **inherited unchanged**: same home dir, run
   dir, container, `NWN_PORT=5121`, **same module and server name**. Set
   `SEASON_NUM=<N>`, `SEASON_ROLE=live`,
   `SEASON_WIKI_URL=https://homerslotr.com/`,
   `SEASON_WORKER_NAME=homers-lotr-wiki-s<N>`, and the peer block
   `SEASON_PEER_ROLE=test`, `SEASON_PEER_NUM=<N+1>`, `SEASON_PEER_PORT=5122`,
   `SEASON_PEER_PASSWORD=volatile` — this peer block is what drives its in-game
   cross-advert sign in step 5. Repoint its systemd instance at the new directory.
2. **Re-parameterize the unnumbered repo onto season N+1.** In `server.env`:
   `NWN_HOME_DIR="$HOME/.local/share/Neverwinter Nights S<N+1>"`,
   `NWN_RUN_DIR="$HOME/.local/state/nwnxee-homer-s<N+1>"`,
   `NWN_CONTAINER_NAME=nwnxee-homer-s<N+1>`, `NWN_PORT=5122`,
   `NWNSYNC_PORT=8001`, `NWNSYNC_CONTAINER=nwnsync-nginx-s<N+1>`,
   `NWNSYNC_REPO=…/nwsync/HomersLOTR-S<N+1>`,
   `SEASON_NUM=<N+1>`, `SEASON_ROLE=test`,
   `SEASON_WIKI_URL=https://season<N+1>.homerslotr.com/`,
   `SEASON_WORKER_NAME=homers-lotr-wiki-s<N+1>`, and the peer block pointing back
   at the live season (`SEASON_PEER_ROLE=live`, `SEASON_PEER_NUM=<N>`,
   `SEASON_PEER_PORT=5121`, `SEASON_PEER_PASSWORD=""`).
   `bin/serve` runs `--network=host`, so **every listening port must be unique** —
   there is no container port isolation.
3. **Rename the module (§4).** In the unnumbered repo only: `nasher.cfg`
   `[package].name` and `[target].file` → `homers_lotr_s<N+1>.mod`;
   `NWN_MODULE="Homer's LOTR Season <N+1>"`;
   `NWN_SERVERNAME="Homer's LOTR — Season <N+1> (EARLY ACCESS)"`. Point the repack
   wrapper's production copy at
   `$NWN_HOME_DIR/modules/Homer's LOTR Season <N+1>.mod` — the installed filename
   must match `NWN_MODULE` exactly. Season N keeps its existing names.
4. **Password-gate it.** `NWN_PLAYERPASSWORD="volatile"` in `server.env.local`
   (gitignored). Hand it only to chosen testers. Also set `NWNSYNC_PUBLIC_URL`
   there for port 8001.
5. **Rebrand + build both modules.** `python3 bin/season-brand.py --apply` in the
   unnumbered repo → wiki links point at `season<N+1>.homerslotr.com`, the connect
   string at `:5122`, and the season sign shows the wipe warning. Repack, deploy.

   **Then do the same in `nwn_homers_lotr_s<N>`** — the live season needs a
   rebuild too, because its peer block just changed: `season-brand.py` turns on
   its **cross-advert placeable** in the Well of Eru, telling every player that
   season N+1 early access is open on port 5122 with password `volatile`. This is
   the only in-game advertisement testers get, so it is not optional. (The sign
   text and its states are specified in prereq item 9.)
6. **Link the two shared DBs.** After the new server's first boot creates
   `database/`:
   ```bash
   DB="$HOME/.local/share/Neverwinter Nights S<N+1>/database"
   for f in meritdb admindb; do
     rm -f "$DB/$f.sqlite3"
     ln -s "$HOME/.local/share/nwn-shared/$f.sqlite3" "$DB/$f.sqlite3"
   done
   ls -l "$DB"/{merit,admin}db.sqlite3    # verify both point at the shared files
   ```
   The shared `admindb` means the early-access realm inherits the live admin
   whitelist and UAT shortcuts on day one — no re-seed. Because `houses` is shared
   too (§2), **confirm the new season still has every house `area_tag` /
   `home_wp_tag` that `admindb.houses` references** — a renamed or dropped home
   area leaves that row dangling and breaks the owner's Home teleport. Check now,
   while it's a test realm, not at go-live:
   ```bash
   sqlite3 "$HOME/.local/share/nwn-shared/admindb.sqlite3" \
     'select player_name, area_tag, home_wp_tag from houses;'
   # each area_tag must exist in this season's unpacked/*.are.json
   ```
7. **Cloudflare.** New worker `homers-lotr-wiki-s<N+1>` deploying from the
   unnumbered repo, custom domain `season<N+1>.homerslotr.com` + DNS record.
   The apex stays bound to the **season-N** worker, which now deploys from
   `nwn_homers_lotr_s<N>`. Cloudflare auto-deploys **on git push** — "publish" is
   just commit `docs/` + push; no `wrangler deploy` anywhere.
8. **Router.** Forward 5122/udp and 8001/tcp. Permanent — reused every season.
9. **Enable both systemd instances.** Both servers now come up at boot, in parallel.
10. **Stand up the new environment's aux services** (§6a): its per-season backup
    subfolder (automatic once `SEASON_NUM` is set) and its per-season *ops*
    app-grid shortcuts (restart / stop / monitor, labelled with the season). Leave
    the dev shortcuts and the roadmap editor alone — they already track the newest
    repo. Confirm the **live** season still owns the `nwn-shared` backup.
11. **Announce loudly and repeatedly:** the early-access vault and *all* its DBs
   **will be wiped at go-live**. Every character, item, bestiary entry and bank
   balance gained in testing is temporary. **Merit earned still counts**, and
   **admin access + player-home *entitlements* carry over** (both are shared) —
   though a home's *contents* (its storage chest) reset with everything else.

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

## 6a. Auxiliary services at a glance

Beyond the server and the wiki, a handful of host services touch a season. This
is which ones are shared, which are per-season, and what to do with each. The
per-season engineering (templated units, per-season backup, ops shortcuts) is
built once — see `season-cutover-prereqs.md` items 2b, 7, 11.

| Service | Scope | At cutover |
|---------|-------|------------|
| Game server + NWSync (systemd `@`-instances) | **per-season** | Phase 1 enable the new instance; Phase 3 disable the retired one |
| `nwn-reboot.timer` (root, 03:03) | **shared** | nothing — one OS reboot restarts every instance (all are `WantedBy=default.target`) |
| Backup (`bin/backup-homers-lotr`) | **per-season**, into `…/backups/s<N>/` | runs per instance; the `SEASON_ROLE=live` one also snapshots the shared `nwn-shared/` DBs (§2, prereq 2b) |
| Wiki publish (`refresh-…-wiki --publish`) | **per-season** | live → apex, archive → its subdomain; stops at Phase 3 |
| Empty-restart watch (`.path`/`.service`) | **per-season** | its watch path is the instance's run dir — do not let a clone keep the old path |
| Dev shortcuts (unpack / repack / wiki / nwsync) | **single**, newest repo | none — you never rebuild a frozen season |
| Ops shortcuts (restart / stop / monitor) | **per-season** | Phase 1 create the new set; Phase 3 delete the retired set + its monitor autostart |
| Roadmap editor (`:8765`) | **single**, newest repo | none — one backlog, ever (§11) |

**Ops shortcut lifecycle.** The restart/stop/monitor `.desktop` files are the only
app-grid entries that are per-season, because during the overlap two servers run.
Each environment's set points its `Exec` at that season's repo `bin/`; create the
new set at Phase 1 (step 10), delete the retiring season's set at Phase 3. Dev
shortcuts stay pointed at the unnumbered repo — which is always the newest season
— so they never need touching.

**Roadmap editor.** One instance, `WorkingDirectory` on the unnumbered repo, so it
always edits the newest season's backlog and publishes to that season's wiki +
`roadmapdb`. Never instance it per season. The archived season's roadmap is frozen
once at Phase 2 by `bin/roadmap-archive-prune.py` and the editor never reopens it.

---

## 7. Phase 2 — go live (the swap)

A maintenance window with both servers stopped. Nothing here is a stand-up or a
teardown — it is a role and port swap between two servers that are already running.

1. **Snapshot season N's `bestiarydb`** to a safe path *before* anything else —
   the returning-player reward (§9) reads it. Snapshot character XP from the
   season-N servervault too if the XP-bank tier is in play.
2. **Final full wiki republish of season N** against its live DBs, so the archive
   is complete and current.
3. **Wipe the early-access realm to a clean live state.** Both servers stopped.
   Weeks of testing have to leave *nothing* behind — see §7a for exactly what this
   covers and why.
   ```bash
   H="$HOME/.local/share/Neverwinter Nights S<N+1>"
   R="$HOME/.local/state/nwnxee-homer-s<N+1>"

   # characters (players + DM + local)
   rm -rf "$H/servervault"/* "$H/dmvault"/* "$H/localvault"/*

   # every campaign DB except the two shared symlinks
   find "$H/database" -maxdepth 1 -name '*.sqlite3' \
        ! -name 'meritdb.sqlite3' ! -name 'admindb.sqlite3' -delete

   # wiki activity + session history, and stale module instances
   rm -rf "$R"/logs "$R"/logs.* "$R"/activity-sessions.json* \
          "$R"/currentgame.* "$R"/temp.* "$R"/cache

   ls -l "$H/database"/{merit,admin}db.sqlite3   # both symlinks MUST still be intact
   ls    "$H/database"                            # should now hold ONLY those two
   ```
   - **Never `rm -rf` the whole `database/` dir**, and never let anything follow
     the merit or admin symlinks — deleting a link is recoverable, truncating a
     shared file is not. `-delete` on a `-name '*.sqlite3'` match won't traverse
     them; `-maxdepth 1` keeps the search off anything else.
   - **Do not touch `$R/database` or `$R/servervault`.** In the run dir those are
     symlinks to the container-internal paths `/nwn/home/database` and
     `/nwn/home/servervault` — dangling on the host, but a recursive delete
     through them *inside* the container would take the real data with it. The
     run dir is the server's `-userdirectory`; the real files live under
     `NWN_HOME_DIR`, which is what the commands above target.
   - The run-dir clear is what makes activity charts and player-hours start at
     zero (§2). Leaving `activity-sessions.json` behind is the most likely way to
     launch a season with early-access playtime already on its charts.
   - Deleting `coderedeem` here **is** the intended reset of promo/redemption-code
     *usage* — who redeemed what starts empty on go-live, while the codes stay
     valid to their `code_redeem.nss` expiry (§2). Before the window, run
     `bin/list-promo-codes.py` and check each code's expiry is right for the new
     season: early-access-only codes should expire ≤ go-live, and any code carried
     forward should have a future date. Retire/adjust codes as normal source edits
     in `code_redeem.nss`.
4. **Re-seed and republish what the wipe legitimately destroyed.** Three stores get
   deleted that are *not* player progress and must come straight back, or the new
   season launches broken:
   - **The admin whitelist and house records are *not* wiped** — `admindb` is a
     shared symlink (§2), so `Admin_Can*` access, UAT shortcuts and existing homes
     survive automatically. Just confirm the symlink is intact (the `ls -l` above).
     Only run `bin/seed-admindb.sh` if you are *adding* a new admin or tier.
   - Republish `roadmapdb` from `roadmap.yaml` (roadmap editor → *Publish to Wiki &
     DB*), or the Well of Eru "Recent Updates" sign comes up blank.
   - **Full wiki regen + push** (`bin/refresh-…-wiki --publish`). `docs/` is
     **tracked in git**, so the new season's repo is carrying committed pages full
     of early-access kill counts, server-firsts and activity charts. The DB wipe
     does not touch them — only a regen does. Skip this and the freshly launched
     season's public wiki advertises testers' bestiary records.
5. **Swap the ports.** Unnumbered repo: `NWN_PORT` 5122→**5121**, `NWNSYNC_PORT`
   8001→**8000**. `_s<N>`: 5121→**5122**, 8000→**8001**. Container names, home
   dirs and run dirs never change — only these two numbers per side.
6. **Flip the roles, names and peer blocks, then rebrand both.**

   | | unnumbered (season N+1) | `_s<N>` (season N) |
   |---|---|---|
   | `SEASON_ROLE` | `live` | `archive` |
   | `SEASON_WIKI_URL` | `https://homerslotr.com/` | `https://season<N>.homerslotr.com/` |
   | `NWN_SERVERNAME` | `Homer's LOTR — Season <N+1>` | `Homer's LOTR — Season <N> (ARCHIVED)` |
   | `SEASON_PEER_ROLE` | `archive` | `live` |
   | `SEASON_PEER_PORT` | `5122` | `5121` |
   | `SEASON_PEER_PASSWORD` | `""` | `""` |

   Drop the `(EARLY ACCESS)` suffix from the new season's `NWN_SERVERNAME` — it is
   the only naming value that changes at Phase 2. The module filename and
   `NWN_MODULE` were set at Phase 1 and stay put (§4).

   Then run `python3 bin/season-brand.py --apply` in **both** repos and repack and
   deploy **both** modules. This is what:
   - flips season N's sign from nothing to *"this season has ended"* and moves its
     in-game links off the apex — without it, the archived season's signs would
     send its remaining players to the new season's wiki;
   - **turns off season N's early-access cross-advert** (peer is no longer `test`,
     so the password and port 5122 stop being advertised) and replaces it with the
     archived-season pointer;
   - turns off the new season's wipe warning and points its links at the apex.
7. **Cloudflare:** move the `homerslotr.com` custom domain from worker
   `homers-lotr-wiki-s<N>` to `homers-lotr-wiki-s<N+1>`. Season N keeps its
   subdomain and its publish job.
8. **Prune the archived roadmap.** In `_s<N>`: `bin/roadmap-archive-prune.py` →
   keeps `status: awarded` only, deletes every other item (backlog and
   shipped-but-unpaid alike — that work all lives on in the unnumbered repo's
   roadmap, which is untouched). Run `bin/gen-roadmap.py`, commit both files, and
   publish to that season's `roadmapdb` so its in-game Recent Updates sign matches
   its public page. The archived season's roadmap is now a pure merit-credit ledger.
9. **Go public.** Remove `NWN_PLAYERPASSWORD` from the unnumbered
   `server.env.local`, start both servers, and confirm the server browser lists
   season N+1 on 5121 with NWSync on 8000, and season N on 5122 / 8001.
10. **Verify merit** — log in on both and confirm the same balance reads through.
11. **Apply the returning-player reward** (§9) and announce: new season live,
    old season still playable on the alternate port, old wiki at its subdomain.

### 7a. What the Phase-2 wipe actually covers

Testers spend weeks on the early-access realm. This is the audit of where that
progress lives, so the wipe can be checked rather than trusted.

| Progress | Lives in | Cleared by |
|---|---|---|
| Characters: levels, gear, gold, feats, **journal/quest entries** | `.bic` files in `servervault/` (journal state is stored *in* the character) | `rm -rf servervault/* dmvault/* localvault/*` |
| Quest flags, cooldowns, world state | campaign DBs — `questcddb`, `worldstatedb`, `craftdb`, `prestigedb`, the `*linedb` class-line DBs, `forbiddendb`, `potd`, `fret`, `cregistred`, area DBs like `maz20`/`mos2` | the `*.sqlite3` sweep |
| Bestiary kills + server-firsts | `bestiarydb` (plus a legacy `bestiary.sqlite3`) | the `*.sqlite3` sweep |
| Banks, house **chests**, dyes, boosts, party loot, ammo, factions, teleport slots | `bankdb`, `kpb_bank`, `housechest`, `dyedb`, `boostdb`, `partyloot`, `ammorepdb`, `factiondb`, `teledb`, … | the `*.sqlite3` sweep |
| Promo/redemption code **usage** (who redeemed what) | `coderedeem` | the `*.sqlite3` sweep — the codes themselves stay valid (they're in module source, §2) |
| Admin whitelist + UAT access, player-**home** records | `admindb` (`admins`, `houses`) | **kept** — shared symlink, like merit (§2) |
| Boss respawn history | `respawndb` | self-resetting — `BRD_InitDb()` re-seeds on every module load |
| Wiki activity charts, player-hours | `$NWN_RUN_DIR/logs*`, `activity-sessions.json` | the run-dir clear |
| **Published wiki pages** showing early-access stats | `docs/`, **committed to git** | **only** a full wiki regen + push (step 4) |
| Merit earned in early access | shared `meritdb` | **kept** — testers keep what they earned |

**Why the `*.sqlite3` sweep is trustworthy:** it is name-agnostic. The live server
today holds 32 campaign DBs, well over half of them undocumented anywhere, and
new systems add more every month. Anything a module script persists with
`SqlPrepareCampaign*` or the legacy `SetCampaign*` family lands in
`database/<name>.sqlite3` and is caught. There is no other on-disk persistence
surface: no `.bdb`/`.dbf` files, and nothing under the run dir but logs, caches
and symlinks back into the home dir.

**Verify after wiping, before going public:**

```bash
ls "$H/database"                  # ONLY meritdb.sqlite3 and admindb.sqlite3 (both symlinks)
ls -A "$H/servervault"            # empty
ls "$R" | grep -c '^logs\.'       # 0
```
Then log in on the new season and confirm: character list empty, journal empty,
bestiary at zero, no bank balance, boss board unclaimed — and merit balance intact.

### 7b. The one thing the wipe *cannot* undo — merit escrow

Merit spending is escrowed: `meritdb.players.merit_spent` is a counter, and
`available = earned - merit_spent` (`CLAUDE-merit.md`). A tester who **redeems a
merit reward during early access** gets an item that Phase 2 deletes, while the
`merit_spent` charge survives in the shared DB. The wipe cannot fix this —
`meritdb` is the one file it must not touch.

Pick one before opening early access and put it in the announcement:

- **Ask testers not to redeem during early access** (simplest; relies on them).
- **Refund at cutover** — snapshot `merit_spent` per CD key at the start of Phase
  1, and at Phase 2 reverse any redemption logged during the window. Auditable via
  `merit_ledger`, and it pairs naturally with the returning-player reward NPC (§9).
- **Let redemptions ride** — accept that early-access redeemers lose the item. Fine
  for cosmetics, not for anything expensive.

The same logic applies to any future account-wide unlock stored in `meritdb`.

**Rollback.** Until Phase 3 this is fully reversible: season N's vault and DBs were
never touched, so swapping the two port pairs back restores the previous state.
The shared objects are `meritdb` and `admindb` — so **avoid schema changes to
either during the overlap**, since both seasons write the same two files.

---

## 8. Phase 3 — retire season N

Once `_s<N>` is consistently empty for a decent stretch:

1. Stop and disable its server + NWSync systemd instances, and its wiki-publish
   and backup units.
2. Stop pushing that repo. Cloudflare keeps serving its last-deployed `docs/`
   frozen at `season<N>.homerslotr.com` — indefinitely, no maintenance.
3. Leave its home dir on disk, or take one final cold archive of vault + DBs.
   Its runtime dirs stay reserved to that season's number.
4. In the **live** repo set `SEASON_PEER_ROLE=none`, rebrand, repack and deploy —
   this retires the cross-advert sign that was pointing players at a server that
   no longer answers.
5. **Delete the retired season's *ops* app-grid shortcuts** (its restart / stop /
   monitor `.desktop` files) and its monitor autostart entry — the server they
   drove is gone (§6a). Leave the dev shortcuts and the roadmap editor; they track
   the newest repo and never pointed at the archived season. The retired season's
   backup subfolder `…/backups/s<N>/` stays as its frozen history.

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
- [ ] `cp -a` → `nwn_homers_lotr_s<N>`; new git remote; season block `= live`; peer block `= test`; systemd repointed
- [ ] Unnumbered repo re-parameterized to season N+1 (home/run/container/5122/8001/nwsync repo)
- [ ] Module renamed (§4): `nasher.cfg` target, `NWN_MODULE`, `NWN_SERVERNAME` `(EARLY ACCESS)`, repack wrapper install path
- [ ] `NWN_PLAYERPASSWORD="volatile"` + `NWNSYNC_PUBLIC_URL` in `server.env.local`
- [ ] `season-brand.py --apply`; repack; deploy — **in the new season repo**
- [ ] `season-brand.py --apply`; repack; deploy — **in `_s<N>` too**, so the live season advertises the test realm + password
- [ ] Both shared symlinks (`meritdb`, `admindb`) created into the new home dir and verified with `ls -l`
- [ ] House area-tags checked: every `admindb.houses.area_tag` exists in the new season (§5)
- [ ] Worker `homers-lotr-wiki-s<N+1>` + `season<N+1>.homerslotr.com` + DNS
- [ ] Router: 5122/udp, 8001/tcp forwarded
- [ ] Both systemd instances enabled; both servers up after a reboot
- [ ] Aux services stood up (§6a): per-season backup subfolder; per-season ops shortcuts (restart/stop/monitor)
- [ ] Wipe warning announced to testers — including the merit-redemption policy (§7b)

**Phase 2 — go live**
- [ ] `bestiarydb` (+ XP) snapshot taken
- [ ] Final season-N wiki republish
- [ ] Vault (`servervault`/`dmvault`/`localvault`) + all `*.sqlite3` except merit **and admin** + run-dir `logs*`/`activity-sessions.json`/`currentgame.*` wiped
- [ ] Wipe verified (§7a): `database/` holds only `meritdb`+`admindb` symlinks, vault empty, no `logs.N`
- [ ] Both shared symlinks (`meritdb`, `admindb`) confirmed intact — admin access carries over, no re-seed needed
- [ ] Promo codes reviewed (`bin/list-promo-codes.py`): expiries right for the new season; `coderedeem` usage reset by the wipe
- [ ] `roadmapdb` republished (Recent Updates sign)
- [ ] **Full wiki regen + push** — `docs/` is tracked in git and still holds early-access stats
- [ ] Merit-escrow policy applied (§7b) for anyone who redeemed during early access
- [ ] Ports swapped both sides
- [ ] Roles, `NWN_SERVERNAME` and peer blocks flipped both sides; `(EARLY ACCESS)` dropped
- [ ] `season-brand.py --apply` run in **both**; both repacked + deployed
- [ ] Early-access advert confirmed **gone** from the live season's Well of Eru
- [ ] Apex custom domain moved to the new worker
- [ ] Archived roadmap pruned to `awarded`-only; `gen-roadmap.py`; published to its `roadmapdb`
- [ ] Player password removed; both servers verified in the server browser
- [ ] Merit balance verified on both
- [ ] Veteran reward live; cutover announced

**Phase 3 — retire**
- [ ] Live season's peer block set to `none` (archived-season pointer removed); rebrand, repack, deploy
- [ ] Season-N server + NWSync stopped and disabled
- [ ] Its wiki-publish and backup units disabled; repo no longer pushed
- [ ] Retired season's ops app-grid shortcuts + monitor autostart deleted (§6a); dev shortcuts + roadmap editor left alone
- [ ] Frozen wiki confirmed serving at `season<N>.homerslotr.com`

---

## 11. Notes for the next person running this

- **Core tooling needs no changes.** `nwn-manager` / `nwn-wiki` are already
  module-agnostic — they key off the working directory, `nasher.cfg`,
  `.nasher/source`, `server.env`, and the `--base-url` / `--out` / `--db-dir` /
  `--log-dir` flags. Prefer wrapper and env changes over touching the core.
- The **distinct `.mod` filename** per season (§4) isn't only cosmetic:
  `nwn-manager` builds via a `/tmp/nwnmgr_<modfile>` symlink and a
  `nwnmgr_bstamp.nss` build stamp, so a shared filename can race if both seasons
  ever repack at once.
- A season needs its **own NWSync repo/manifest** as soon as its hak/tlk content
  diverges from the other's — which it will, once you rebalance.
- The **roadmap editor** (`:8765`) is single-instance and stays on the unnumbered
  (newest) repo — one backlog, ever (§6a). Its "Publish to Wiki" body-swaps
  `<main>` into the already-built `docs/manual/Roadmap.html` — nav changes land at
  the next full refresh, not at publish.
- **Aux services** (backup foldering, per-season ops shortcuts, the shared vs
  per-season split) are catalogued in §6a; the one-time engineering behind them is
  `season-cutover-prereqs.md` items 2b, 7 and 11.
- **Capture surprises back into this file.** Anything that bit you during a
  cutover belongs here before you forget it.

*v2.1 — first written for the season 1 → 2 cutover, but parameterized for every
cutover after it. v2.1 adds the auxiliary-service handling (§6a) and the
redemption-code split (§2).*
