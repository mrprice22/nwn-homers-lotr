# Season Cutover Runbook — Homer's LOTR (v3.0, repeatable)

> **Status:** v3.0 — a **season-agnostic** runbook. Everything below is written in
> terms of **season N** (the outgoing/current season) and **season N+1** (the
> incoming one). Run it unchanged every cutover; substitute the numbers.
> It describes changes to make; it does **not** itself change any code, DB, or unit.

> ### What changed in v3.0 — read this if you knew v2
>
> v2 had **no test realm after go-live**. The early-access realm *became*
> production at Phase 2, so from that moment every change was tested in live
> production. It also **swapped ports** at Phase 2, so a player's saved server
> entry silently changed which season it reached.
>
> v3 makes `nwn_homers_lotr` a **permanent dev realm** that is never production,
> and each season a separate environment derived from it. Concretely:
>
> | | v2 | v3 |
> |---|---|---|
> | `nwn_homers_lotr` | the newest season, becomes live | **dev, forever** |
> | New season stood up in | `_s<N>` gets the **outgoing** season | `_s<N+1>` gets the **incoming** one |
> | Phase 2 ports | 5121↔5122 swapped | **nothing moves** |
> | Phase 2 wipe | `rm -rf` the early-access vault | no wipe — production is a **fresh dir** |
> | Cheats off for live | hand-edit `don_cheat_inc.nss` | derived from `SEASON_ROLE` |
> | Dev → production | `git cherry-pick` across an orphan cut | `bin/season-promote.sh` |
>
> Two whole classes of Phase-2 risk are gone as a result: there is no destructive
> delete next to a shared symlink, and there is no "did we remember to turn the
> cheat chest off" step. The **§1 "inverted folder rule"** of v2 is gone too —
> season N+1 now goes in the new folder, which is what intuition expects.

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
PORTS        A PORT BELONGS TO AN ENVIRONMENT AND NEVER MOVES.
             5123/udp  = the DEV realm, permanently
             5121/udp  \  the two SEASON SLOTS. A season keeps the slot it is
             5122/udp  /  born in for its whole life, live and archived alike.
NWSYNC       8002/tcp = dev      8000/tcp = slot A      8001/tcp = slot B
INSTANCES    dev + at most 2 seasons = 3 servers during an overlap, 2 at rest
REPOS        nwn_homers_lotr        = the DEV realm. Forever. Never a season.
                                      The only repo development happens in.
             nwn_homers_lotr_s<N>   = season N, created at its Phase 1 and kept
                                      for that season's whole life
RUNTIME      dev owns       ~/.local/share/Neverwinter Nights Dev
                            ~/.local/state/nwnxee-homer-dev
                            container  nwnxee-homer-dev
             season N owns  ~/.local/share/Neverwinter Nights S<N>   (home: vault + database/)
                            ~/.local/state/nwnxee-homer-s<N>          (run: logs + Anvil)
                            container  nwnxee-homer-s<N>
WIKI         homerslotr.com            -> whichever season is LIVE
             season<N>.homerslotr.com  -> season N, permanently. While season N
                                          IS live this 301s to the apex rather
                                          than serving a duplicate site; when it
                                          is archived it serves its frozen wiki.
             dev.homerslotr.com        -> the dev realm
             lotr.homerslotr.com       -> the 2008 original module      \ FORKED MODULES,
             2009.homerslotr.com       -> Homer's LOTR Edit (2009)      / NOT seasons:
             read-only archives of separate modules. Never rebuilt, never rebranded,
             untouched by every cutover. bin/season-brand.py must never match them
             (WIKI_HOST_RE is whole-host: apex + season<N>. + dev. only).
SHARED       ~/.local/share/nwn-shared/meritdb.sqlite3    <- account merit + entitlements
             ~/.local/share/nwn-shared/admindb.sqlite3    <- admin whitelist + house records
             (the ONLY cross-environment files; symlinked into EVERY environment's
              database/, dev included — see §2 for what that means)
```

**Why ports no longer move.** In v2, 5121 meant "whoever is live", so Phase 2
swapped the two seasons' ports. That silently repointed every player's saved
server entry at a different season — the one thing a player cannot see happening.
A port now identifies an *environment*, so a player's saved entry always reaches
the realm they chose, and choosing to move is theirs. The cost is that "which
port is live?" is no longer answerable from the port number alone; the server
browser name carries it instead.

**Slot allocation is recycling, not a rule.** Season 1 holds slot A (5121/8000)
and season 2 holds slot B (5122/8001). When season 1 is retired (Phase 3), slot A
frees up and season 3 is born into it. So the slots alternate, and there is never
a live season and an early-access season competing for one.

**Legacy wart (season 1 only):** season 1 keeps the *unnumbered* runtime dirs
(`~/.local/share/Neverwinter Nights`, `~/.local/state/nwnxee-homer`, container
`nwnxee-homer`) and its `SEASON_LEGACY_NAMES=1` module/server names. Don't rename
them — a rename buys uniformity and risks the live vault.

### The one rule that makes the rest obvious

> **Development happens in the dev realm. Every season is a derived copy of it.**

A season repo is dev's tree plus that season's own season block. Nothing is ever
authored in one — `bin/season-promote.sh` copies dev's tree in with `rsync
--delete` and the target rebrands itself from its own `server.env`. An edit made
directly in a production repo is destroyed by the next promotion, deliberately
(§5a). That is what buys the test realm: there is always somewhere to break
things that is not where the players are.

### Lifecycle

Dev sits above all of it and never changes role. Only the seasons move.

```
                    nwn_homers_lotr  =  DEV, 5123, dev.homerslotr.com
                    always password-gated, cheats on, never production
                                         |
                        bin/season-promote.sh --to _s<N>
                                         v
   PHASE 1                          PHASE 2                     PHASE 3
   stand up season N+1        -->   go live                --> retire season N
   ┌──────────────────┐             ┌──────────────────┐        ┌──────────────────┐
   │ _s<N>   : LIVE   │ slot A      │ _s<N>  : ARCHIVE │ slot A │ _s<N>  : stopped │  —
   │ _s<N+1> : TEST   │ slot B      │ _s<N+1>: LIVE    │ slot B │ _s<N+1>: LIVE    │ slot B
   └──────────────────┘             └──────────────────┘        └──────────────────┘
   fresh vault, password            no wipe, no port swap       wiki frozen at
   wipe warning notice              apex moves to N+1           season<N> subdomain
                                    "season over" notice        slot A freed for N+2
```

Note what Phase 2 no longer contains: no `rm -rf`, no port edits, no source edits
to turn cheats off. Season N+1's vault was *born* empty at Phase 1 and its role
flip does the rest.

| Phase | slot A | slot B | dev | Merit | Wiki |
|-------|--------|--------|-----|-------|------|
| steady state | season N (live) | — | 5123 | shared | apex → N |
| Phase 1 | season N (live) | season N+1 (test, password) | 5123 | shared | apex → N; `season<N+1>.` → N+1 |
| Phase 2 | season N (archive) | season N+1 (**live**) | 5123 | shared | apex → N+1; `season<N>.` → N; `season<N+1>.` → apex |
| Phase 3 | *free* | season N+1 (live) | 5123 | shared | apex → N+1; `season<N>.` frozen |

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

**The dev realm shares them too, and that is a deliberate trade.** Dev's
`database/` gets the same two symlinks as any season, so merit awarded from the
roadmap editor reaches the live ledger immediately and a player-reported merit or
housing bug can be reproduced against the real data. The cost is that dev has
cheat gear and a level-builder NPC pointed at the **real** merit ledger and the
**real** house-fulfilment records. Two things make that survivable:

- the `SEASON_ROLE=live` instance backs `nwn-shared/` up daily (§6a), so there is
  always a restore point, and that duty moves with the role automatically;
- the roadmap editor refuses to write merit unless `meritdb` really is a symlink
  resolving inside `nwn-shared/` (`merit_db_problem()`), so the *other* failure —
  awards quietly landing in a per-season file that the next cutover discards — is
  caught rather than discovered later.

If dev testing ever does corrupt the ledger, the fix is a restore from
`…/backups/s<N>/`, not a repair.
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

This runbook depends on the one-time engineering in
**[season-cutover-prereqs.md](season-cutover-prereqs.md)** — and as of
**2026-07-24 all twelve items are done**: the `teledb`/`meritdb` split, the
`meritdb` + `admindb` DBs moved to their neutral shared path, the season block in
`server.env`, relocatable wrappers, templated systemd units,
`bin/season-brand.py`, and
`bin/roadmap-archive-prune.py`.

The tools each phase calls into:

| Phase step | Tool |
|---|---|
| Link a new season's shared DBs (§5.6, §7) | `bin/season-shared-dbs.sh --apply` |
| Rebrand a repo (§5.5, §7.6) | `python3 bin/season-brand.py --apply` |
| Build a season's module (§5.5) | `repack-homers-lotr --project <repo>` |
| Stand up / tear down a season's units (§5.9, §8.1) | `bin/season-units.sh --enable` / `--remove` |
| Ops app-grid shortcuts (§5.10, §8.5) | `bin/season-shortcuts.sh --install` / `--remove` |
| Freeze the archived roadmap (§7.8) | `python3 bin/roadmap-archive-prune.py --apply` |

Read that file's **Built** notes before the first Phase 1 — several items came
out differently from the design sketched there, and one of them (the shared DBs
needing a container bind mount, not just a symlink) is a crash the host-side
verification steps do not catch.

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
| OneDrive build folder | `~/OneDrive/Games/NWNHomersLOTR/Season<N>/` — derived from `SEASON_NUM` by `repack-project.sh` | created on first repack | Phase 1 (automatic) |

`NWN_SERVERNAME` tracks `SEASON_ROLE`, so the two instances are tellable apart in
the server browser:

| Role | Server name |
|------|-------------|
| `test` | `Homer's LOTR — Season <N> (EARLY ACCESS)` |
| `live` | `Homer's LOTR — Season <N>` |
| `archive` | `Homer's LOTR — Season <N> (ARCHIVED)` |

Renaming also drives the **repack wrapper's install destination** — the `.mod`
filename it copies into `$NWN_HOME_DIR/modules/`. This is no longer a hand-edit:
`repack-project.sh` derives it from `NWN_MODULE`, so setting the names right in
`server.env` + `nasher.cfg` is the whole job (prereq item 5). A mismatch between
the installed filename and `NWN_MODULE` shows up as the server exiting at startup
with a module-not-found error, not as anything subtler.

The **OneDrive build folder** is likewise derived — `Season$SEASON_NUM` under the
shared root — and the repack wrappers create it on the season's first build. The
unpack wrapper scans only that folder, so `.mod` files you rename by hand on the
Windows side stay picked up (newest mtime wins, canonical artifact name breaking
ties) without leaking across seasons.
Check both halves agree with `repack-homers-lotr --show-config` and
`refresh-homers-lotr --show-config`.

**Season 1 keeps its legacy names** (`homers_lotr_v3.mod`, module
`Homer's LOTR VEL v3`, server name `Homer's LOTR Very Easy Leveling`). Never
rename a live module — the filename change alone breaks every player's saved
server entry. Numbering starts at season 2.

No data consequence: the servervault is per-`NWN_HOME_DIR` and campaign DBs are
scoped by their own name, so neither is keyed to the module name.

---

## 5. Phase 1 — stand up the early-access realm (season N+1)

The live season keeps running throughout; nothing about it moves. Neither does
dev. **Season N+1 is stood up in a new directory** — the plain reading, unlike v2.

1. **Create the new season's repo from dev.**
   ```bash
   cd ~/GIT
   cp -a nwn_homers_lotr nwn_homers_lotr_s<N+1>      # cp -a, never a clone
   ```
   `cp -a` and not a clone because `server.env.local`, `.nasher/source` and the
   build cache are untracked and a clone loses them. Then repoint its git remote
   and cut its publish history **before anything else** — the exact procedure and
   why the order is not negotiable is §5a. In outline:
   ```bash
   cd nwn_homers_lotr_s<N+1>
   git branch -m main s<N+1>-dev-history       # keep locally, unpushed
   git checkout --orphan main                  # squashed publish line
   git commit -m "Season <N+1> — forked from dev at Phase 1"
   gh repo create mrprice22/nwn_homers_lotr_s<N+1> --private --source=. --remote=origin
   git push -u origin main
   git remote -v                               # origin MUST be the new repo
   ```
   The orphan squash keeps ~1 GB of `docs/` history off the new GitHub repo.
   Shared ancestry is not needed: promotion is an rsync, not a merge (§5a).

   **The outgoing season is not touched at all.** It already lives in its own
   directory, on its own slot, with its own repo — it was set up this way at
   *its* Phase 1 and simply stays put. (In v2 this step copied the *outgoing*
   season out, which is where the "inverted folder rule" came from.)

2. **Parameterize the new season.** In `nwn_homers_lotr_s<N+1>/server.env` — this
   is a copy of **dev's**, so every one of these is currently a dev value:
   `NWN_HOME_DIR="$HOME/.local/share/Neverwinter Nights S<N+1>"`,
   `NWN_RUN_DIR="$HOME/.local/state/nwnxee-homer-s<N+1>"`,
   `NWN_CONTAINER_NAME=nwnxee-homer-s<N+1>`,
   `NWN_PORT=<the free slot>`, `NWNSYNC_PORT=<its pair>`,
   `NWNSYNC_CONTAINER=nwnsync-nginx-s<N+1>`,
   `NWNSYNC_REPO=…/nwsync/HomersLOTR-S<N+1>`,
   `SEASON_NUM=<N+1>`, `SEASON_ROLE=test`,
   `SEASON_WIKI_URL=https://season<N+1>.homerslotr.com/`,
   `SEASON_WORKER_NAME=homers-lotr-wiki-s<N+1>`.

   The free slot is the one the *retired* season released at its Phase 3 — see §1.
   `bin/serve` runs `--network=host`, so **every listening port must be unique**
   across dev and both seasons; there is no container port isolation.

   Also bump **dev's** `SEASON_NUM` to `<N+1>`, so it records which season it now
   feeds. Nothing dev-facing renames — dev's names are number-independent by
   design (`season-brand.py`), precisely so this bump is free.

3. **Names are derived, not edited.** `season-brand.py` owns `nasher.cfg`
   `[package].name` / `[target].file`, `NWN_MODULE` and `NWN_SERVERNAME` from
   season 2 onward, so there is nothing to rename by hand — step 5 writes them.
   Confirm with `repack-homers-lotr --project ../nwn_homers_lotr_s<N+1>
   --show-config` before the first build; it also shows the
   `…/NWNHomersLOTR/Season<N+1>/` folder the build will create. The installed
   filename must match `NWN_MODULE` exactly or nwserver exits with
   module-not-found.

4. **Password-gate it.** `NWN_PLAYERPASSWORD="volatile"` in `server.env.local`
   (gitignored — `cp -a` brought dev's copy, so it already has one). Hand it only
   to chosen testers. Also fix `NWNSYNC_PUBLIC_URL` there for the new port: it
   hard-codes its port, nothing in git catches it, and left alone the new season
   advertises **dev's** nginx.
   ```bash
   grep -H NWNSYNC_PUBLIC_URL ~/GIT/nwn_homers_lotr*/server.env.local
   ```

5. **Rebrand, re-profile and build.** In `nwn_homers_lotr_s<N+1>`:
   ```bash
   python3 bin/season-brand.py   --apply   # names, wiki host, connect string, worker
   python3 bin/season-profile.py --apply   # role=test: cheats ON, wipe notice ON
   ```
   `season-profile.py` is what turns the early-access wipe notice **on** — the
   text is already in `servershout4.nss` behind `SP_WIPE_NOTICE`. Update the text
   for this season's dates and ports; it is a player announcement and no script
   writes those. Then repack and deploy.

   **Then the outgoing season's in-game notice** — repurpose its `recent_updates`
   board (prereq item 9 explains why the old two-sign design was retired):
     `nwn_homers_lotr_s<N>`, edit that one placeable in `thewelloferu.git.json`:
     `LocName` → "Season <N> ending soon - examine me", `Description` → the
     static notice (go-live date; that season N stays online while people play
     it; **season N+1's port** + password + `season<N+1>.homerslotr.com`; the
     wipe; what's new; the merit hold list), and clear `Conversation` (`ru_sign`)
     and `OnUsed`
     (`ru_use`) so it is examine-only. **Write both locstrings StrRef-free**
     (`{"0": text}`, no `id`) — they ship with ids 14561/14567 and a
     non-`0xFFFFFFFF` StrRef beats the inline string, so the sign would render
     CEP TLK text instead. Repack and deploy season N too.

   This board is the only in-game advertisement testers get, so it is not
   optional. It also replaces the archived-season notice at Phase 2 — season N
   keeps using the same board, re-texted.
5a. **Seed the new season's home and run dirs — the new `NWN_HOME_DIR` is
   empty, and that is not only about `database/`.** A season's home dir is where
   `nwserver` reads **haks, the TLK, and `override/`** from, so a brand-new one
   means no CEP and no `cep.tlk` and the module cannot load. `bin/serve` only
   `mkdir -p`s the *run* dir; nothing bootstraps the rest. Copy it from the
   outgoing season:
   ```bash
   S1="$HOME/.local/share/Neverwinter Nights"          # outgoing season's home
   S2="$HOME/.local/share/Neverwinter Nights S<N+1>"
   mkdir -p "$S2"/{modules,servervault,dmvault,localvault,nwsync,portraits,ambient,music,movies,development}
   cp -a "$S1"/{hak,tlk,override} "$S2"/               # ~8 GB; reflinks on btrfs/xfs, so instant
   cp -a "$S1"/{nwn.ini,nwnplayer.ini,settings.tml} "$S2"/
   ```
   Then the run dir, and **`settings.tml` must exist there before the first
   boot**: `bin/serve` mounts it `-v "$NWN_RUN_DIR/settings.tml:…:ro"`, and podman
   creates an empty **directory** at a bind-mount source that doesn't exist —
   after which `nwserver` cannot write its settings and the serve-time patch
   (sticky modes, max HP, `max-ability-bonus`) silently never applies.
   ```bash
   R1="$HOME/.local/state/nwnxee-homer"; R2="$HOME/.local/state/nwnxee-homer-s<N+1>"
   mkdir -p "$R2" && cp -a "$R1/settings.tml" "$R2/settings.tml"
   mkdir -p "$R2"/anvil/{PluginData,Plugins}      # REAL dir — see below
   for l in database servervault tlk hak override modules portraits nwsync development; do
     [[ -L $R1/$l ]] && ln -sfn "$(readlink "$R1/$l")" "$R2/$l"
   done
   ```
   Those run-dir entries are symlinks to the *container-internal* `/nwn/home/…`
   paths — they dangle on the host by design (§7 step 3 warns against deleting
   through them).

   **`anvil` is the one entry that must NOT be a symlink, and is deliberately
   absent from that loop.** The Anvil image's entrypoint (`/nwn/run-server.sh`)
   loops over `anvil database hak modules nwsync override portraits saves
   servervault tlk development` and symlinks anything missing from `/nwn/run`
   to `/nwn/home/<entry>` — so if you don't pre-create a real `anvil/`, you get
   a host-dangling link, and with it:
   - `bin/reboot-on-empty` dies in `mkdir` — the season can never be armed;
   - `nwn-season-empty-restart@<instance>.path` watches a path that can never
     exist, so an empty-restart shuts the season down and **never restarts it**.

   `bin/serve` now creates `$NWN_RUN_DIR/anvil/{PluginData,Plugins}` on every
   start, so this is belt-and-braces; `bin/season-anvil-fix` repairs a season
   that is already stuck on the symlink. Season 2 shipped in that state — it had
   no reboot-on-empty and no daily restart until 2026-07-25.

   Don't copy `cryptographic_secret`: let the new season generate
   its own, so the two instances are distinct to the master server.

5b. **Deploy the Anvil plugin to the new season.** `ServerRestartManager` is not
   an Anvil built-in — it ships inside `csharp/DungeonSolitaire.Nwn`. A season
   without it has **no daily 03:00 in-game countdown, character export or clean
   shutdown** (even though `ANVIL_RESTART_DAILY=03:00` is set), **no
   reboot-on-empty**, and a dead Dungeon Solitaire area. The symptom in the log
   is `Loading 0 DotNET plugin/s from: "/nwn/run/anvil/Plugins"`.

   ```bash
   bin/season-anvil-fix        # builds if needed, deploys, restarts the season
   ```

   Or by hand — the folder name **must** equal the assembly name, or Anvil
   silently skips it (`<folder>/<folder>.dll`):

   ```bash
   dotnet build csharp/DungeonSolitaire.Nwn -c Release
   DEST="$NWN_RUN_DIR/anvil/Plugins/DungeonSolitaire.Nwn"   # from that season's server.env
   mkdir -p "$DEST"
   cp csharp/DungeonSolitaire.Nwn/bin/Release/net8.0/DungeonSolitaire.{Nwn,Core}.dll "$DEST"/
   ```

   Verify after the next start:
   ```
   Loading 1 DotNET plugin/s from: "/nwn/run/anvil/Plugins"
   Registered service "DungeonSolitaire.Nwn.ServerRestartManager"
   [ServerRestart] daily restart armed for 03:00 server-local time.
   ```

6. **Link the two shared DBs — _before_ the new server's first boot.** The
   ordering matters and is easy to get backwards: if the server boots first it
   creates `meritdb.sqlite3`/`admindb.sqlite3` as **regular files**, and
   `bin/season-shared-dbs.sh` then refuses with *"regular file here AND a shared
   copy exists — refusing to guess"* rather than silently picking one.
   ```bash
   mkdir -p "$HOME/.local/share/Neverwinter Nights S<N+1>/database"
   bin/season-shared-dbs.sh              # dry run: expect "will link" for both
   bin/season-shared-dbs.sh --apply      # creates the absolute symlinks
   ```
   Prefer the script to hand-rolled `ln -s`: it verifies the links and reads a
   table count back through each one. The shared `admindb` means the early-access realm inherits the live admin
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
7. **Cloudflare.** Deploys run through **Workers Builds**, bound to a **GitHub
   repository**, not to a folder on this machine (§6). In v2 this step was a
   re-point dance, because the original repo kept changing which season it was.
   It no longer does: `nwn-homers-lotr` is dev's forever and stays bound to
   `homers-lotr-wiki-dev`. So Phase 1 only **adds** a worker.

   **Run this after step 5, not before.** The `cp -a` gave the new season repo
   dev's `wrangler.jsonc`, which names **dev's** worker; step 5's
   `season-brand.py --apply` rewrites it to `homers-lotr-wiki-s<N+1>`. Connect a
   worker to the repo while that file still says `-dev` and the build deploys
   under the wrong worker name — the collision §6 warns about.

   1. Create the season's GitHub repo and push it (§5a). Nothing is watching it
      yet, so this push is inert.
   2. Run step 5 in that repo and push, so `wrangler.jsonc` names
      `homers-lotr-wiki-s<N+1>`.
   3. Create worker `homers-lotr-wiki-s<N+1>`, connected to
      `mrprice22/nwn_homers_lotr_s<N+1>`, production branch `main`, and add the
      custom domain `season<N+1>.homerslotr.com`. **The DNS record is created
      automatically** — there is no separate DNS step.

   The outgoing season's worker and the apex binding are **not touched at Phase
   1**. The apex moves once, at Phase 2 (§7 step 7).

   Verify: push a trivial commit in each repo and confirm each build lands on its
   own worker; `curl -I https://homerslotr.com`,
   `https://season<N+1>.homerslotr.com` and `https://dev.homerslotr.com` all 200;
   each worker's `*.workers.dev` URL 301s to its own host (`src/index.js`).

   Cloudflare auto-deploys **on git push** — "publish" is just commit `docs/` +
   push; no `wrangler deploy` anywhere.
8. **Router.** Forward the new season's slot: `<NWN_PORT>/udp` and
   `<NWNSYNC_PORT>/tcp`. Permanent — the slot is reused by every season born into
   it, so this is a one-time forward per slot, not per season.
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

## 5a. Git topology, and how a change reaches production

There are always **three repos accumulating commits** (dev, the live season, an
archived season during an overlap). Publishing is entirely unattended, which is
what makes a mis-wired remote urgent rather than academic:

- `bin/serve` runs `nwn-manager serve --auto-publish`, which
  `git commit && git push`es `docs/activity.html` **every time the server
  empties**;
- `nwn-season-wiki-publish@.service` does a full regen + commit + push **once per
  boot**;
- every one of those pushes triggers a Cloudflare Workers build.

So three unattended agents push to git and deploy to Cloudflare. A repo pointed
at the wrong GitHub remote does not fail next week — it fires within hours, while
you sleep.

### Repo roles

| Repo | Role | GitHub remote |
|---|---|---|
| `nwn_homers_lotr` (unnumbered) | **the dev realm, forever.** The only repo anything is authored in | keeps the original repo, forever |
| `nwn_homers_lotr_s<N>` | season N, from its Phase 1 to its retirement | its own repo, created at that season's Phase 1 |

The season repo's **GitHub name is whatever you create** — season 1's is
`mrprice22/nwn_homers_lotr_s1` (underscores, matching the local directory).
Nothing derives from it; only the Cloudflare build connection points at it.

### Promotion, not cherry-picking

v2 carried changes between repos with `git cherry-pick` across an orphan cut.
That is right for a repo you freeze **once** — a handful of emergency fixes
crossing during a short overlap. It does not survive a permanent dev realm, where
*every* release crosses and the two histories never rejoin: you would be
cherry-picking every commit forever and hand-reconciling the conflicts each time.

So the unit of promotion is the **tree**, not the commit:

```bash
# from the dev repo
bin/season-promote.sh --to ../nwn_homers_lotr_s2                     # dry run
bin/season-promote.sh --to ../nwn_homers_lotr_s2 --apply --season 2
```

It refuses unless the source is `SEASON_ROLE=dev`, the target is `live`/`test`,
dev's tree is clean and its two gates pass, the target has no uncommitted work
outside `docs/`, and the target's container is stopped (`--allow-hot` overrides).
`--season N` is mandatory with `--apply` and must match the target's
`SEASON_NUM`: role alone is not enough of a guard when sibling directories differ
by one character and the wrong one is a live server.

Then it rsyncs an allowlist, and **in the target** runs `season-brand.py --apply`
and `season-profile.py --apply` (which is what makes a tree branded for dev
correct for wherever it landed, and turns the cheats off for a live season),
regenerates the roadmap page and `roadmapdb`, repacks, commits `Promote from dev
@<sha>`, and tags dev `promote/s<N>/<date>`.

```bash
git -C ~/GIT/nwn_homers_lotr log promote/s2/<date>..HEAD --oneline   # in dev, not yet live
```

**What is never promoted** — each environment owns its own: `server.env`,
`server.env.local`, `nasher.cfg`, `wrangler.jsonc`, `src/`, `index.html`,
`docs/`, `.nasher/`, build outputs, `module-index/`,
`roadmap-merit-aliases.json`. The middle three are `season-brand.py` *outputs*,
so the target regenerates them from its own season block — not copying them is
not a gap.

The allowlist is an **allowlist on purpose**: a new top-level file added in dev
is not promoted until it is named in `PROMOTE`. The alternative fails the wrong
way, shipping every new file to production the moment someone creates it.

### The contract: production is never hand-edited

rsync runs with `--delete`, so **an edit made directly in a season repo is
destroyed by the next promotion.** That is the point. Without it production
slowly accumulates divergence that dev knows nothing about — which is the exact
state the dev realm exists to prevent, and the state v2 guaranteed by making the
live repo the only place some fixes could be made.

An urgent fix during an overlap is therefore made **in dev and promoted**, which
is one command and takes as long as a repack. If you must touch a season repo
directly to get a server back up, treat it as a debt: port it to dev the same
day, or the next promotion silently reverts it.

## 5c. Promoting a change to production — the day-to-day loop

Everything above is a cutover, which happens every three or four months. **This
is the part you do every week**, and v2 had no equivalent of it: there, the live
repo was the dev repo, so "deploying" meant repacking in place and restarting.

```bash
cd ~/GIT/nwn_homers_lotr                       # dev: the only place you author

#  1. change something, and build it for the dev realm
vim unpacked/...
repack-homers-lotr                             # gates + pack + install to dev
systemctl --user restart nwn-season-server@nwn_homers_lotr

#  2. test it on the dev realm — port 5123, password "volatile",
#     cheat chest and Ping Pong available to set up the scenario fast

#  3. commit in dev. Promotion refuses a dirty tree: production must always be
#     traceable to a dev commit
git add -A && git commit -m "..."

#  4. see what a promotion would carry
bin/season-promote.sh --to ../nwn_homers_lotr_s<N>

#  5. ship it
systemctl --user stop nwn-season-server@nwn_homers_lotr_s<N>
bin/season-promote.sh --to ../nwn_homers_lotr_s<N> --apply --season <N>
systemctl --user start nwn-season-server@nwn_homers_lotr_s<N>

#  6. push the season repo — Cloudflare rebuilds its wiki on push
git -C ../nwn_homers_lotr_s<N> push
```

Step 5 is the whole deploy. It rebrands and re-profiles the target from its own
season block, so the module it builds carries the live season's names, the live
wiki's URLs, and **no cheat gear** — none of which you have to remember, and all
of which `tests/check_season_profile.py` refuses to let you get wrong.

**What is in dev but not yet live:**
```bash
git log promote/s<N>/<date>..HEAD --oneline    # the tag the last promotion left
```

**Things worth knowing**

- **Promotion needs the target's server stopped**, because swapping the `.mod`
  under a running server does nothing until restart and a mid-session hak change
  is worse. `--allow-hot` overrides it when you know better.
- **`--season <N>` is mandatory** and must match. Sibling directories differ by
  one character and one of them has players on it.
- **A hak or tlk change needs more than a promote.** `hak_2da/` and the tlk
  sources ride along, but the built artifacts do not: run
  `bin/build-lotr-rules-hak --install` and `bin/refresh-nwsync` in the target,
  or clients get a hak mismatch at connect.
- **The roadmap rides along.** `roadmap.yaml` is promoted and the target
  regenerates its own page and `roadmapdb`, so release notes land with the
  release. Merit awards do not wait for a promotion — they are written to the
  shared DB immediately (§6a).
- **Never edit a season repo directly.** `--delete` means the next promotion
  destroys it (§5a).

---

## 6. Wiki hosting — one worker per season

`wrangler.jsonc` defines a worker serving `./docs` as static assets; `src/index.js`
301-redirects `*.workers.dev` to the season's own host.

**The deploy path is Workers Builds via the Cloudflare GitHub App**, and its
connection is to a **GitHub repository**, not to a directory on this machine.
That connection is the one piece of cutover state that lives *outside* the repo —
nothing in `server.env` describes it, and `season-brand.py` cannot fix it. It is
re-pointed by hand in the dashboard at Phase 1 (§5.7) and never touched again.

**A worker cannot be renamed in place.** "Renaming" means creating a new worker
and re-binding its custom domain, which is why season 1's archive repo keeps
`SEASON_WORKER_NAME="homers-lotr-wiki"` (its `SEASON_LEGACY_NAMES=1` covers this)
rather than being renamed to `-s1`.

**Rule: every season owns a permanently-named worker `homers-lotr-wiki-s<N>`,
permanently bound to `season<N>.homerslotr.com`. The apex `homerslotr.com` custom
domain is *moved* between workers at Phase 2 — it is the only binding that ever
changes.**

**The dev realm is a fourth worker**, `homers-lotr-wiki-dev`, permanently bound to
`dev.homerslotr.com` and built from the unnumbered repo. It is created once and
never touched by a cutover, because dev never changes role.

**While a season is live, its own `season<N>.` subdomain 301s to the apex** rather
than serving a second copy of the same site — `src/index.js` carries the redirect
and `season-brand.py` writes it from the role. Archiving the season empties the
list and the subdomain serves its frozen wiki again. So a link to
`season2.homerslotr.com` written during early access keeps working forever: it
follows the season to the apex and back off it again.

**`dev.homerslotr.com` is public.** It shows unreleased content to anyone who
guesses the hostname. Put a Cloudflare Access policy in front of it if that
matters — it is zero code and costs nothing, and the alternative is that your
next season's surprises are readable months early.

This is why `season-brand.py` owning `wrangler.jsonc`'s name is mandatory rather
than cosmetic. A new season repo starts as a `cp -a` of **dev**, so until it is
rebranded its `wrangler.jsonc` names *dev's* worker — and two repos deploying one
worker name collide, with the last push winning. Rebrand before connecting the
worker (§5.7). (Season 1's existing worker may keep its legacy name; just bind
`season1.homerslotr.com` to it.)

Archived seasons **keep publishing** during Phase 2 — players may still be on
them, and their kill counts and activity charts should keep updating at their
subdomain. Publishing stops at Phase 3, and Cloudflare then serves the last
deployed `docs/` frozen, indefinitely.

**Limits worth watching.** A Workers deploy caps at **20,000 asset files** and
**25 MiB per file**; `docs/` is currently 10,765 files / 140 MB with a largest
asset of 4.6 MB, so there is headroom — but content grows every season and a
build that trips the file cap fails at deploy, not at generation. And during the
overlap the **build rate roughly doubles**: every server-empty on either season
is a push and therefore a build.

---

## 6a. Auxiliary services at a glance

Beyond the server and the wiki, a handful of host services touch a season. This
is which ones are shared, which are per-season, and what to do with each. The
per-season engineering (templated units, per-season backup, ops shortcuts) is
built once — see `season-cutover-prereqs.md` items 2b, 7, 11.

| Service | Scope | At cutover |
|---------|-------|------------|
| Game server + NWSync (systemd `@`-instances) | **per environment** — the instance name is the repo's **directory name**, so dev is just another instance (`nwn-season-server@nwn_homers_lotr`) | Phase 1 enable the new season's; Phase 3 disable the retired one; dev's is never touched |
| `nwn-reboot.timer` (root, 03:03) | **shared** | nothing — one OS reboot restarts every instance (all are `WantedBy=default.target`) |
| Backup (`bin/backup-homers-lotr`) | **per environment**, into `…/backups/s<N>/` | runs per instance; **only** the `SEASON_ROLE=live` one snapshots the shared `nwn-shared/` DBs (§2, prereq 2b). That duty therefore moves to season N+1 automatically at Phase 2's role flip, and dev — which shares those DBs but is not live — never takes it |
| Wiki publish (`refresh-…-wiki --publish`) | **per environment** | live → apex, archive → its subdomain, dev → `dev.homerslotr.com`; a season's stops at Phase 3, dev's never does |
| Empty-restart watch (`.path`/`.service`) | **per-season** | its watch path is the instance's run dir — do not let a clone keep the old path, and that run dir needs a **real** `anvil/` (§5a) |
| Anvil plugins (`anvil/Plugins/`) | **per-season** | deploy `DungeonSolitaire.Nwn` to the new season's run dir — it carries `ServerRestartManager`, so without it the season has no daily restart and no reboot-on-empty (§5b) |
| Dev shortcuts (unpack / repack / wiki / nwsync) | **per environment** — `bin/season-shortcuts.sh` keys them on the role (`-dev`) or number (`-s<N>`), so dev and a same-numbered season cannot collide | Phase 1 creates the new season's set; dev's never change |
| Ops shortcuts (restart / stop / monitor) | **per-season** | Phase 1 create the new set; Phase 3 delete the retired set |
| Combined all-realm monitor (`bin/watch-all-servers`, `nwn-monitor-all.service`) | **single**, the DEV repo | none — one window shows every realm; no phase creates or retires it |
| Roadmap editor (`:8765`) | **single**, the DEV repo | none — one backlog, ever (§11) |
| OneDrive build folder | **per environment** — `Season<N>/`, or `Dev/` when `SEASON_ROLE=dev` | none; the split exists so a dev build is never unpacked into a season |

**Shortcut lifecycle.** Every app-grid entry is per environment, ops and build
alike: create the new season's set at Phase 1 (step 10), delete the retiring
season's at Phase 3, and leave dev's alone forever.

`bin/season-shortcuts.sh` keys the filenames on **role first, number second** —
`-dev` when `SEASON_ROLE=dev`, `-s<N>` otherwise. That is not decoration. Dev
carries `SEASON_NUM` = the season it currently feeds, so a purely number-keyed
prefix would give dev and that season's production repo identical `.desktop`
filenames, and whichever ran `--install` last would silently own every button —
including "Repack", pointed at the wrong environment. The same rule governs the
OneDrive build folder (`Dev/` vs `Season<N>/`) for the same reason.

**One wiki script per repo.** `nwn_manager/bin/refresh-homers-lotr-wiki` is a
refusing stub: it used to be a full runner with season 1's `--base-url`, log dir
and level cap baked in, which was merely stale with two environments and is a
live hazard with three — `--base-url` decides the absolute URLs written into
every page, and `--log-dir`/`--db-dir` decide whose kill counts and activity
charts the pages report. There is no correct default, so it refuses instead of
guessing. Always run the copy inside the repo you mean to publish.

**Roadmap editor.** One instance, `WorkingDirectory` on the **dev** repo. Never
instance it per season — one backlog, ever.

Know what its **Publish** button reaches: `docs/` and `roadmapdb` in *dev*, so the
page lands on `dev.homerslotr.com` and the sign it refreshes is the dev server's.
Production gets the roadmap at the next `bin/season-promote.sh`, which re-runs
`gen-roadmap.py` + `publish-roadmap-db.py` **in the target** — the only place that
can write the live season's `roadmapdb`, since it lives under that season's own
`NWN_HOME_DIR`. Release notes ship with the release.

**Merit is the exception**, and deliberately so: Award/Revoke write the shared
`meritdb`, so merit awarded from the dev editor is live immediately. The editor
refuses the write unless that path really is a symlink into `nwn-shared/`, because
a plain file there would accept awards the next cutover silently discards.

The archived season's roadmap is frozen once at Phase 2 by
`bin/roadmap-archive-prune.py` and the editor never reopens it.

---

## 7. Phase 2 — go live

A maintenance window. In v2 this was the dangerous phase: a destructive wipe next
to two shared symlinks, a port swap on both sides, and two source edits that had
to be remembered. **None of that is here any more.** Season N+1's vault was born
empty at Phase 1 and has been accumulating only early-access play; its ports never
move; and its cheats go off because its role changes, not because someone edits a
script.

What is left is a role flip, a domain move, and the notices.

1. **Snapshot season N's `bestiarydb`** to a safe path before anything else — the
   returning-player reward (§9) reads it. Snapshot character XP from the season-N
   servervault too if the XP-bank tier is in play.

2. **Final full wiki republish of season N** against its live DBs, so the archive
   is complete and current.

3. **Clear season N+1's early-access play.** Testers spent weeks on it and that
   progress must not become the launch state. Both servers stopped.

   This is a **much smaller** operation than v2's wipe, because the only things
   that accumulated are the vault, the campaign DBs and the logs — the home dir
   itself was created fresh at Phase 1 and its shared symlinks were linked before
   first boot. Full audit in §7a.

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
     through them *inside* the container would take the real data with it.
   - The run-dir clear is what makes activity charts and player-hours start at
     zero. Leaving `activity-sessions.json` behind is the most likely way to
     launch a season with early-access playtime already on its charts.
   - Deleting `coderedeem` here **is** the intended reset of promo-code *usage*
     (§2). Before the window, run `bin/list-promo-codes.py` and check each code's
     expiry: early-access-only codes should expire ≤ go-live, carried-forward
     ones should have a future date.

4. **Flip the role.** In `_s<N+1>/server.env`:

   | | `_s<N+1>` (incoming) | `_s<N>` (outgoing) |
   |---|---|---|
   | `SEASON_ROLE` | `test` → **`live`** | `live` → **`archive`** |
   | `SEASON_WIKI_URL` | `https://homerslotr.com/` | `https://season<N>.homerslotr.com/` |

   **`NWN_PORT`, `NWNSYNC_PORT`, `NWNSYNC_PUBLIC_URL`, container names, home dirs
   and run dirs are NOT touched.** Ports belong to environments now (§1). If you
   find yourself editing a port here, stop — you are following v2.

   Then in **both** repos:
   ```bash
   python3 bin/season-brand.py   --apply    # names, URLs, worker, apex redirect
   python3 bin/season-profile.py --apply    # cheats + dev NPCs OFF, notice OFF
   ```
   `season-brand.py` drops the `(EARLY ACCESS)` suffix from the new season's
   `NWN_SERVERNAME`, adds `(ARCHIVED)` to the old one, and rewrites
   `src/index.js` so `season<N+1>.homerslotr.com` now 301s to the apex.
   `season-profile.py` turns off the Donations Chest cheat stock, removes the
   Ping Pong builder NPC and drops the early-access wipe notice — **because the
   role changed, not because anyone edited a script.** `tests/check_season_profile.py`
   fails the repack if any of it is out of step, so this cannot be half-done.

   Repack and deploy both modules.

5. **Re-seed what genuinely needs it.**
   - The admin whitelist and house records are **not** touched — `admindb` is a
     shared symlink (§2). Only run `bin/seed-admindb.sh` if *adding* an admin.
   - Republish `roadmapdb` in the new live season, or the Well of Eru "Recent
     Updates" sign comes up blank. A promotion does this for you; if you did not
     promote in this window, run `python3 bin/publish-roadmap-db.py` there.
   - **Full wiki regen + push** in `_s<N+1>` (`bin/refresh-homers-lotr-wiki
     --publish`). `docs/` is **tracked in git**, so the repo is still carrying
     committed pages full of early-access kill counts, server-firsts and activity
     charts. The DB clear in step 3 does not touch them — only a regen does. Skip
     this and the freshly launched season's public wiki advertises testers'
     bestiary records.

6. **Re-text the two notices by hand.** `season-profile.py` owns *whether* the
   early-access notice appears; it does not write announcements.
   - **Season N's `recent_updates` board** → *"Season N has ended. This realm is
     no longer updated or maintained. The current season is live on port
     &lt;slot B&gt;."* Edit `LocName` + `Description`, StrRef-free.
   - **Season N+1's login script** — the cyan block in `servershout4.nss` is
     already switched off by `SP_WIPE_NOTICE`, so nothing is required. If the
     text mentions dates or ports that are now wrong, fix it anyway: it will be
     switched back on for the *next* early-access realm.

7. **Cloudflare: move the apex.** A hostname attaches to exactly one Worker, so
   this is *remove then add*, not a re-assign: remove the `homerslotr.com` custom
   domain from `homers-lotr-wiki-s<N>`, add it to `homers-lotr-wiki-s<N+1>`, then
   **purge the cache** for the zone. Season N keeps its subdomain and its publish
   job. **No build connection changes at Phase 2** — those were wired at Phase 1.

   The apex serves whatever `homers-lotr-wiki-s<N+1>` last built, so step 5's
   full wiki regen + push **must already have landed** — otherwise the moment the
   domain moves, the public apex is the early-access wiki.

8. **Prune the archived roadmap.** In `_s<N>`: `bin/roadmap-archive-prune.py`
   keeps `status: awarded` only. Run `bin/gen-roadmap.py`, commit both files, and
   publish to that season's `roadmapdb`. The archived season's roadmap becomes a
   pure merit-credit ledger; the full backlog lives on in **dev**, untouched.

9. **Go public.** Remove `NWN_PLAYERPASSWORD` from `_s<N+1>/server.env.local`,
   start both servers, and confirm the browser lists season N+1 on its slot with
   NWSync alongside, and season N still on its own.

10. **Verify.** Log in on both and confirm the same merit balance reads through.
    On the new live season confirm the Donations Chest holds no cheat gear, Ping
    Pong is absent, and no wipe warning appears at login — the three things
    `season-profile.py` is responsible for.

11. **Apply the returning-player reward** (§9) and announce: new season live, old
    season still playable on its own port, old wiki at its subdomain.

**Rollback.** Until Phase 3 this is fully reversible, and more cleanly than in
v2: season N's vault and DBs were never touched, and nothing about either
server's ports or directories moved. Flip the two `SEASON_ROLE` values back, re-run
both scripts in both repos, move the apex back. The shared objects are `meritdb`
and `admindb` — **avoid schema changes to either during the overlap**, since all
three environments write the same two files.

### 7a. What the Phase-2 clear actually covers

Testers spend weeks on the early-access realm. This is the audit of where that
progress lives, so step 3 can be checked rather than trusted.

Two rows that used to be here are gone, and it is worth knowing why: the
**cheat-chest stock** and the **early-access login notice** were both source
edits you had to remember at go-live, and both are now consequences of
`SEASON_ROLE` (`bin/season-profile.py`), gated by `tests/check_season_profile.py`
so the repack fails rather than shipping them. They cannot be forgotten, so they
are not on a checklist.

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

cd ~/GIT/nwn_homers_lotr_s<N+1>
python3 bin/season-profile.py --check   # MUST print dev_tools=off cheat_chest=off
```
Then log in on the new season and confirm: character list empty, journal empty,
bestiary at zero, no bank balance, boss board unclaimed, **Donations Chest free of
cheat gear, Ping Pong absent, no wipe warning at login** — and merit balance
intact.

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
2. **Stop pushing that repo — with a control, not a promise.** Step 1 already
   removes both automated pushers (stopping the server ends
   `serve --auto-publish`; disabling `nwn-season-wiki-publish@` ends the
   per-boot republish), so what's left is a stray manual push or a unit someone
   re-enables. Make it structural: **archive the season-N GitHub repo
   (read-only)** — `gh repo archive mrprice22/nwn-homers-lotr-s<N>` — and
   disconnect its Workers Build in the dashboard. Cloudflare keeps serving its
   last-deployed `docs/` frozen at `season<N>.homerslotr.com` indefinitely, with
   no build connection and no maintenance.
3. Leave its home dir on disk, or take one final cold archive of vault + DBs.
   Its runtime dirs stay reserved to that season's number.
4. **Nothing to retire in the live module.** The old design had a cross-advert
   sign here that needed switching off; the notice now lives on the *archived*
   season's own board, which stops being reachable when its server stops. So no
   rebrand, repack or deploy is needed at Phase 3.
5. **Delete the retired season's *ops* app-grid shortcuts** (its restart / stop /
   monitor `.desktop` files) — the server they drove is gone (§6a). The combined
   all-realm monitor is **not** touched: it belongs to no season, and it stops
   showing the retired realm on its own once that container is gone. Leave the
   dev shortcuts and the roadmap editor; they track
   the newest repo and never pointed at the archived season. The retired season's
   backup subfolder `…/backups/s<N>/` stays as its frozen history.

You are back to two running instances: dev and the live season. The retired
season's **slot** (its `NWN_PORT`/`NWNSYNC_PORT` pair) sits idle until the next
Phase 1 gives it to season N+2, and the router forwards stay in place for it.

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

**Phase 1 — stand up season N+1**
- [ ] `cp -a nwn_homers_lotr nwn_homers_lotr_s<N+1>` (never a clone) — the NEW season gets the new folder; the outgoing season is not touched
- [ ] **Before any unit is enabled or server started** (§5a): new repo's `origin` repointed and verified (`git remote -v`, `git config branch.main.remote`)
- [ ] Orphan `main` squashed + pushed to the new GitHub repo; `s<N+1>-dev-history` kept locally
- [ ] New repo parameterized: home/run/container dirs, the free slot's `NWN_PORT`/`NWNSYNC_PORT`, nwsync repo, `SEASON_NUM`, `SEASON_ROLE=test`, wiki URL, worker name
- [ ] Dev's `SEASON_NUM` bumped to N+1 (records which season it feeds; renames nothing)
- [ ] `NWN_PLAYERPASSWORD="volatile"` + **`NWNSYNC_PUBLIC_URL` fixed for the new port** in `server.env.local` — `cp -a` brought dev's, which advertises dev's nginx
- [ ] `season-brand.py --apply` **and** `season-profile.py --apply`; repack; deploy — in the new season repo
- [ ] Landing page checked: the root `index.html` "Direct connect" string (**it appears twice**) and its wiki link show the *new* season's port and host — a spot-check that the gate ran, not a hand-edit
- [ ] Early-access wipe notice text updated for this season's dates/ports (it is switched on by `SP_WIPE_NOTICE`, not by editing it in)
- [ ] Outgoing season's `recent_updates` board repurposed as the next-season notice (StrRef-free; `Conversation`/`OnUsed` cleared); `_s<N>` repacked + deployed
- [ ] New season's home dir seeded: `hak/`, `tlk/`, `override/`, `nwn.ini`, `settings.tml` (§5.5a) — an empty home dir has no CEP and the module will not load
- [ ] New season's run dir seeded with `settings.tml` **before first boot** (§5.5a) — a missing bind-mount source becomes a directory
- [ ] Both shared symlinks (`meritdb`, `admindb`) created **before the new server's first boot** and verified with `ls -l` (§5.6)
- [ ] House area-tags checked: every `admindb.houses.area_tag` exists in the new season (§5)
- [ ] Worker `homers-lotr-wiki-s<N+1>` created against the **new** repo + custom domain `season<N+1>.homerslotr.com` — **after** the rebrand push (§5.7), or the build deploys under dev's worker name
- [ ] All three hosts return 200; a test push in each repo builds only its own worker
- [ ] Router: the new slot's `<NWN_PORT>/udp` and `<NWNSYNC_PORT>/tcp` forwarded
- [ ] Its systemd instance enabled; all three servers up after a reboot
- [ ] Aux services stood up (§6a): per-season backup subfolder; per-season ops + build shortcuts
- [ ] Wipe warning announced to testers — including the merit-redemption policy (§7b)

**Phase 2 — go live**
- [ ] `bestiarydb` (+ XP) snapshot taken
- [ ] Final season-N wiki republish
- [ ] Season N+1's vault (`servervault`/`dmvault`/`localvault`) + all `*.sqlite3` except merit **and admin** + run-dir `logs*`/`activity-sessions.json`/`currentgame.*` cleared
- [ ] Clear verified (§7a): `database/` holds only `meritdb`+`admindb` symlinks, vault empty, no `logs.N`
- [ ] Both shared symlinks confirmed intact — admin access carries over, no re-seed needed
- [ ] Promo codes reviewed (`bin/list-promo-codes.py`): expiries right for the new season; `coderedeem` usage reset by the clear
- [ ] `SEASON_ROLE` flipped: N+1 → `live`, N → `archive`; both `SEASON_WIKI_URL`s updated
- [ ] **No port edited on either side** — if you changed one, you followed v2 (§1)
- [ ] `season-brand.py --apply` **and** `season-profile.py --apply` run in **both**; both repacked + deployed
- [ ] `season-profile.py --check` in the new live season prints `dev_tools=off cheat_chest=off wipe_notice=off`
- [ ] In game on the new live season: Donations Chest free of cheat gear, Ping Pong absent, no wipe warning at login
- [ ] `roadmapdb` republished (Recent Updates sign)
- [ ] **Full wiki regen + push** — `docs/` is tracked in git and still holds early-access stats
- [ ] Merit-escrow policy applied (§7b) for anyone who redeemed during early access
- [ ] Archived season's `recent_updates` board re-texted to "season has ended", naming the new season's port
- [ ] Apex custom domain **removed** from the old worker, **added** to the new one, zone cache purged
- [ ] `season<N+1>.homerslotr.com` now 301s to the apex; `season<N>.` serves the archive
- [ ] Archived roadmap pruned to `awarded`-only; `gen-roadmap.py`; published to its `roadmapdb`
- [ ] Player password removed; all servers verified in the server browser
- [ ] Merit balance verified on both
- [ ] Veteran reward live; cutover announced

**Phase 3 — retire**
- [ ] (No live-module change needed — the archived season's own board goes away with its server)
- [ ] Season-N server + NWSync stopped and disabled
- [ ] Its wiki-publish and backup units disabled
- [ ] Season-N GitHub repo archived read-only (`gh repo archive`); its Workers Build disconnected
- [ ] Retired season's ops + build app-grid shortcuts deleted (§6a); **dev's and the combined all-realm monitor left alone**
- [ ] Frozen wiki confirmed serving at `season<N>.homerslotr.com`
- [ ] Its slot recorded as free for season N+2

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
- The **roadmap editor** (`:8765`) is single-instance and stays on the **dev**
  repo — one backlog, ever (§6a). Its "Publish to Wiki" reaches *dev's* wiki and
  sign only; production gets the roadmap at the next promotion. It body-swaps
  `<main>` into the already-built `docs/manual/Roadmap.html`, so nav changes land
  at the next full refresh, not at publish.
- **Aux services** (backup foldering, per-season ops shortcuts, the shared vs
  per-season split) are catalogued in §6a; the one-time engineering behind them is
  `season-cutover-prereqs.md` items 2b, 7 and 11.
- **The riskiest window is between the `cp -a` and the new repo's `origin`
  repoint** — publishing is fully automated in every repo (§5a), so a wrong
  remote is exercised unattended within hours, not next week. Do those two steps
  back-to-back, never overnight. The v2 hazard of a *build connection* pointing
  at the wrong repo is mostly gone: dev keeps its own worker permanently, so
  Phase 1 only adds one rather than re-pointing two.
- **The two build gates are the load-bearing part of the whole design.**
  `season-brand.py --check` and `season-profile.py --check` run on every repack,
  and they are what make "production is a derived copy" safe to believe. If you
  ever find yourself tempted to bypass one to get a build out, you are about to
  ship a live season with cheat gear or another realm's URLs. Fix the tree.
- **Capture surprises back into this file.** Anything that bit you during a
  cutover belongs here before you forget it.

*v2.2 — first written for the season 1 → 2 cutover, but parameterized for every
cutover after it. v2.1 added the auxiliary-service handling (§6a) and the
redemption-code split (§2). v2.2 adds the git topology and two-repo overlap model
(§5a), the ordered Workers-Builds re-point (§5.7), and the `server.env.local`
port swap (§7.5).*
