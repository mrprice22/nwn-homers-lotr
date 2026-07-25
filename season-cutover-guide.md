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

The live season keeps running throughout; nothing about it moves.

1. **Copy the outgoing season out.** `cp -a nwn_homers_lotr nwn_homers_lotr_s<N>`
   — **`cp -a`, never a clone**: `server.env.local`, `.nasher/source` and the
   build cache are untracked and a clone loses them. Then repoint its git remote
   and cut its publish history **before anything else** — the exact procedure,
   and why the order is not negotiable, is §5a. Its `server.env` is
   **inherited unchanged**: same home dir, run
   dir, container, `NWN_PORT=5121`, **same module and server name**. Set
   `SEASON_NUM=<N>`, `SEASON_ROLE=live`,
   `SEASON_WIKI_URL=https://homerslotr.com/`,
   `SEASON_WORKER_NAME=homers-lotr-wiki-s<N>`. Repoint its systemd instance at
   the new directory. (There is no peer block any more — the in-game notice is
   step 5's repurposed Recent Updates board.)
2. **Re-parameterize the unnumbered repo onto season N+1.** In `server.env`:
   `NWN_HOME_DIR="$HOME/.local/share/Neverwinter Nights S<N+1>"`,
   `NWN_RUN_DIR="$HOME/.local/state/nwnxee-homer-s<N+1>"`,
   `NWN_CONTAINER_NAME=nwnxee-homer-s<N+1>`, `NWN_PORT=5122`,
   `NWNSYNC_PORT=8001`, `NWNSYNC_CONTAINER=nwnsync-nginx-s<N+1>`,
   `NWNSYNC_REPO=…/nwsync/HomersLOTR-S<N+1>`,
   `SEASON_NUM=<N+1>`, `SEASON_ROLE=test`,
   `SEASON_WIKI_URL=https://season<N+1>.homerslotr.com/`,
   `SEASON_WORKER_NAME=homers-lotr-wiki-s<N+1>`.
   `bin/serve` runs `--network=host`, so **every listening port must be unique** —
   there is no container port isolation.
3. **Rename the module (§4).** In the unnumbered repo only: `nasher.cfg`
   `[package].name` and `[target].file` → `homers_lotr_s<N+1>.mod`;
   `NWN_MODULE="Homer's LOTR Season <N+1>"`;
   `NWN_SERVERNAME="Homer's LOTR — Season <N+1> (EARLY ACCESS)"`. The repack
   wrapper derives its production copy from these, installing to
   `$NWN_HOME_DIR/modules/Homer's LOTR Season <N+1>.mod` — the installed filename
   must match `NWN_MODULE` exactly. Season N keeps its existing names. Confirm
   with `repack-homers-lotr --show-config` before the first build; it also shows
   the new `…/NWNHomersLOTR/Season<N+1>/` folder the build will create.
4. **Password-gate it.** `NWN_PLAYERPASSWORD="volatile"` in `server.env.local`
   (gitignored). Hand it only to chosen testers. Also set `NWNSYNC_PUBLIC_URL`
   there for port 8001.
5. **Rebrand + build the new season.** `python3 bin/season-brand.py --apply` in
   the unnumbered repo → wiki links point at `season<N+1>.homerslotr.com` and the
   connect string at `:5122`. Repack, deploy.

   **Then the two in-game notices** — one per season, and neither is a new
   placeable (prereq item 9 explains why the old two-sign design was retired):

   - **New season (early access): a coloured login message.** Add the wipe
     warning and the merit-redemption hold list to `unpacked/servershout4.nss`,
     wrapped in `ColorString(..., COLOR_LIGHT_BLUE)` from the `color` include so
     it reads as a different kind of message from the standing reminders. Use the
     include, **never an inline `<c...>` literal** — a colour token is three raw
     bytes, and the high bytes make the file invalid UTF-8, which breaks
     `season-brand.py` (it reads this exact file as UTF-8).
   - **Outgoing season: repurpose its `recent_updates` board.** In
     `nwn_homers_lotr_s<N>`, edit that one placeable in `thewelloferu.git.json`:
     `LocName` → "Season <N> ending soon - examine me", `Description` → the
     static notice (go-live date; that season N stays online while people play
     it; port 5122 + password + `season<N+1>.homerslotr.com`; the wipe; what's
     new; the merit hold list), and clear `Conversation` (`ru_sign`) and `OnUsed`
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
7. **Cloudflare.** Deploys run through **Workers Builds**, which is bound to a
   **GitHub repository**, not to a folder on this machine (§6). At Phase 1 the
   *original* GitHub repo stops being the live season, so the connections have to
   be re-pointed — and in this order:

   1. Create the archive GitHub repo and push it (§5a) — the build target must
      exist before anything is re-pointed.
   2. On the **existing** worker (`homers-lotr-wiki` for season 1):
      *Settings → Build* → disconnect `nwn-homers-lotr`, reconnect to
      `nwn-homers-lotr-s<N>`, production branch `main`. Confirm the apex custom
      domain is still bound to this worker.
   3. Create worker `homers-lotr-wiki-s<N+1>`, connected to `nwn-homers-lotr`
      (the unnumbered repo, branch `main`), and add the custom domain
      `season<N+1>.homerslotr.com`. **The DNS record is created automatically** —
      there is no separate DNS step.
   4. *Only now* run `season-brand.py --apply` and push in the unnumbered repo
      (step 5). Its `wrangler.jsonc` name is already `homers-lotr-wiki-s<N+1>`,
      matching the worker from step 3.

   > **Do not push from the unnumbered repo between the `cp -a` and step 2.**
   > That repo is still wired to the apex worker, so the first push deploys the
   > early-access wiki onto `homerslotr.com`. And the push may not be yours:
   > `serve --auto-publish` and `nwn-season-wiki-publish@` push unattended (§5a).

   Verify: push a trivial commit on each side and confirm each build lands on its
   own worker; `curl -I https://homerslotr.com` and
   `https://season<N+1>.homerslotr.com` both 200; each worker's `*.workers.dev`
   URL 301s to its own host (`src/index.js`).

   Cloudflare auto-deploys **on git push** — "publish" is just commit `docs/` +
   push; no `wrangler deploy` anywhere.
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

## 5a. Git topology and the two-repo overlap

From Phase 1 to Phase 3 there are **two repos accumulating commits**. This is the
part of the cutover with no undo button on the hosting side, because **nothing
about publishing is manual**:

- `bin/serve` runs `nwn-manager serve --auto-publish`, which
  `git commit && git push`es `docs/activity.html` **every time the server
  empties**;
- `nwn-season-wiki-publish@.service` does a full regen + commit + push **once per
  boot**;
- every one of those pushes triggers a Cloudflare Workers build.

So during the overlap two unattended agents are pushing to git and deploying to
Cloudflare. A mis-wired remote is not a latent bug you find next week — it fires
within hours, while you sleep.

### Repo roles

| Repo | Role | GitHub remote |
|---|---|---|
| `nwn_homers_lotr` (unnumbered) | always the newest season and the only dev repo | keeps the original repo, forever |
| `nwn_homers_lotr_s<N>` | season N's frozen line | its own repo, created fresh at each cutover |

The archive repo's **GitHub name is whatever you create** — the season 1 archive
is `mrprice22/nwn_homers_lotr_s1` (underscores, matching the local directory),
not the `nwn-homers-lotr-s<N>` this file used to assume. Nothing derives from it;
only the Cloudflare build connection points at it. Just use the real name.

### The copy procedure (Phase 1 step 1, in full)

`cp -a` inherits `origin` **and** `main`'s upstream, so straight out of the copy
the archive pushes to the *live* repo. Repoint it before enabling any unit or
starting either server.

The pushed history is **squashed to a single commit**: `.git` here is ~1 GB of
`docs/` churn, and re-pushing all of it to a new GitHub repo every cutover buys
nothing — the full history already lives (and continues) in the unnumbered repo.
Keep it locally for archaeology, publish an orphan line.

```bash
cp -a nwn_homers_lotr nwn_homers_lotr_s<N>      # cp -a only — never a clone
cd nwn_homers_lotr_s<N>

git branch -m main s<N>-full-history            # keep history locally, unpushed
git checkout --orphan main                      # squashed publish line
git commit -m "Season <N> final — archived at cutover to season <N+1>"

gh repo create mrprice22/nwn-homers-lotr-s<N> --private --source=. --remote=origin
git push -u origin main
git remote add dev ../nwn_homers_lotr           # sibling, for cherry-picks

git remote -v                                   # origin MUST be the new repo
git config branch.main.remote                   # MUST be origin -> new repo
git diff --stat HEAD                            # empty: orphan tree == working tree
```

The orphan branch has **no upstream until the `-u` push**, which is a small piece
of luck: in the window between the copy and the push, a bare `git push` from an
automated job errors out instead of guessing the old remote. Don't lean on it —
`origin` is still the live repo until `set-url`/`gh repo create` runs.

And in the unnumbered repo, the matching half:

```bash
git remote add archive ../nwn_homers_lotr_s<N>
```

### Which repo gets which commit

| | unnumbered repo (season N+1) | `_s<N>` (season N) |
|---|---|---|
| **Phase 1 → 2** | all development: `unpacked/`, scripts, `roadmap.yaml`, `docs.manual/` | season block + `season-brand.py` output; emergency hotfixes only; auto-published `docs/` |
| **Phase 2** | wipe-related regen, role/port/peer flip, brand, full wiki regen + push | role/port/peer flip, brand, roadmap prune, final republish |
| **Phase 3** | everything — single repo again | nothing; repo goes read-only |

The counter-intuitive line is the middle column at Phase 1: during the overlap
the **archive repo is the live server with all the players on it**, so it is the
one that may need an urgent fix. It is frozen by policy, not by circumstance.

### Hotfixes cross by cherry-pick, never by merge

Fix it in whichever repo has to ship it first, then carry it across:

```bash
# live-season hotfix during the overlap, then forward it to the new season
cd nwn_homers_lotr_s<N> && git commit -am "hotfix: ..."       # repack + deploy here
cd ../nwn_homers_lotr  && git fetch archive && git cherry-pick <sha>

# or the other direction, for a fix developed in the new season
cd nwn_homers_lotr_s<N> && git fetch dev && git cherry-pick <sha>
```

`git cherry-pick` applies a diff and does not need shared ancestry, so it works
across the orphan cut. **Never `merge` or `rebase` between the two repos** — the
archive's published line is orphaned, and a merge would drag the entire dev
history onto it and undo the point of the squash.

Two caveats: the roadmap entry always lives in the **unnumbered** repo (one
backlog, ever — §11), even when the code shipped in the archive; and each side
needs its own repack + deploy, because the `.mod` filenames differ (§4).

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

This is why the `wrangler.jsonc` rename in §4 is mandatory: at Phase 1 the
unnumbered repo stops being the live season, so if it kept the shared worker name
it would deploy the *early-access* wiki onto the apex the first time a tester
pushed. (Season 1's existing worker may keep its legacy name; just bind
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
| Game server + NWSync (systemd `@`-instances) | **per-season** | Phase 1 enable the new instance; Phase 3 disable the retired one |
| `nwn-reboot.timer` (root, 03:03) | **shared** | nothing — one OS reboot restarts every instance (all are `WantedBy=default.target`) |
| Backup (`bin/backup-homers-lotr`) | **per-season**, into `…/backups/s<N>/` | runs per instance; the `SEASON_ROLE=live` one also snapshots the shared `nwn-shared/` DBs (§2, prereq 2b) |
| Wiki publish (`refresh-…-wiki --publish`) | **per-season** | live → apex, archive → its subdomain; stops at Phase 3 |
| Empty-restart watch (`.path`/`.service`) | **per-season** | its watch path is the instance's run dir — do not let a clone keep the old path, and that run dir needs a **real** `anvil/` (§5a) |
| Anvil plugins (`anvil/Plugins/`) | **per-season** | deploy `DungeonSolitaire.Nwn` to the new season's run dir — it carries `ServerRestartManager`, so without it the season has no daily restart and no reboot-on-empty (§5b) |
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
5. **Swap the ports — in `server.env` *and* `server.env.local`.** In `server.env`,
   unnumbered repo: `NWN_PORT` 5122→**5121**, `NWNSYNC_PORT` 8001→**8000**;
   `_s<N>`: 5121→**5122**, 8000→**8001**. Container names, home dirs and run dirs
   never change — only these two numbers per side.

   Then the easily-missed half: **`NWNSYNC_PUBLIC_URL` hard-codes its port and
   lives in the gitignored `server.env.local`**, which `cp -a` duplicated at
   Phase 1. It is the URL clients are *told* to fetch haks from, so if it isn't
   swapped too (`:8001`→`:8000` on the new live, `:8000`→`:8001` on the archive)
   both seasons advertise the other's nginx. Nothing in git or `season-brand.py`
   catches this — `server.env.local` is untracked by design.
   ```bash
   grep -H NWNSYNC_PUBLIC_URL */server.env.local     # both, before starting either
   ```
6. **Flip the roles and names, then rebrand both.**

   | | unnumbered (season N+1) | `_s<N>` (season N) |
   |---|---|---|
   | `SEASON_ROLE` | `live` | `archive` |
   | `SEASON_WIKI_URL` | `https://homerslotr.com/` | `https://season<N>.homerslotr.com/` |
   | `NWN_SERVERNAME` | `Homer's LOTR - Season <N+1>` | `Homer's LOTR - Season <N> (ARCHIVED)` |

   Drop the `(EARLY ACCESS)` suffix from the new season's `NWN_SERVERNAME` — it is
   the only naming value that changes at Phase 2. The module filename and
   `NWN_MODULE` were set at Phase 1 and stay put (§4).

   Then run `python3 bin/season-brand.py --apply` in **both** repos and repack and
   deploy **both** modules. That moves season N's in-game wiki links off the apex
   (without it the archived season sends its remaining players to the new season's
   wiki) and points the new season's links at it.

   **Then re-text the two notices by hand** — `season-brand.py` does not own
   either of them:
   - **Season N's `recent_updates` board** (the one repurposed at Phase 1) →
     *"Season N has ended. This realm is no longer updated or maintained. The
     current season is live on port 5121."* Same edit as Phase 1: `LocName`,
     `Description`, StrRef-free.
   - **The new season's login script** → delete the cyan early-access block from
     `servershout4.nss`. Its wipe warning is now false: this realm is live and
     progress is permanent. Leaving it in is the single most confusing thing you
     could ship at go-live.
7. **Cloudflare: move the apex.** A hostname attaches to exactly one Worker, so
   this is *remove then add*, not a re-assign: remove the `homerslotr.com` custom
   domain from `homers-lotr-wiki-s<N>`, add it to `homers-lotr-wiki-s<N+1>`, then
   **purge the cache** for the zone. Season N keeps its subdomain and its publish
   job. **No build connection changes at Phase 2** — both were wired at Phase 1
   (§5.7) and stay put; this step is only the domain binding.

   The apex serves whatever `homers-lotr-wiki-s<N+1>` last built, so step 4's
   full wiki regen + push **must already have landed** — otherwise the moment the
   domain moves, the public apex is the early-access wiki.
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
- [ ] `cp -a` → `nwn_homers_lotr_s<N>` (never a clone); season block `= live`; systemd repointed
- [ ] **Before any unit is enabled or server started** (§5a): archive repo's `origin` repointed and verified (`git remote -v`, `git config branch.main.remote`)
- [ ] Orphan `main` squashed + pushed to the new GitHub repo; `s<N>-full-history` kept locally
- [ ] Sibling remotes added both ways (`dev` in the archive, `archive` in the unnumbered repo)
- [ ] Unnumbered repo re-parameterized to season N+1 (home/run/container/5122/8001/nwsync repo)
- [ ] Module renamed (§4): `nasher.cfg` target, `NWN_MODULE`, `NWN_SERVERNAME` `(EARLY ACCESS)`, repack wrapper install path
- [ ] `NWN_PLAYERPASSWORD="volatile"` + `NWNSYNC_PUBLIC_URL` in `server.env.local`
- [ ] `season-brand.py --apply`; repack; deploy — **in the new season repo**
- [ ] Landing page checked: the root `index.html` "Direct connect" string (**it appears twice**) and its wiki link show the *new* season's port and host — `season-brand.py` owns these now, so this is a spot-check that the gate ran, not a hand-edit
- [ ] Cyan early-access notice added to the new season's `servershout4.nss` (via the `color` include, never an inline `<c…>` literal)
- [ ] Outgoing season's `recent_updates` board repurposed as the next-season notice (StrRef-free; `Conversation`/`OnUsed` cleared); `_s<N>` repacked + deployed
- [ ] New season's home dir seeded: `hak/`, `tlk/`, `override/`, `nwn.ini`, `settings.tml` (§5.5a) — an empty home dir has no CEP and the module will not load
- [ ] New season's run dir seeded with `settings.tml` **before first boot** (§5.5a) — a missing bind-mount source becomes a directory
- [ ] Both shared symlinks (`meritdb`, `admindb`) created **before the new server's first boot** and verified with `ls -l` (§5.6)
- [ ] House area-tags checked: every `admindb.houses.area_tag` exists in the new season (§5)
- [ ] Season-N worker's **build connection re-pointed** to `nwn-homers-lotr-s<N>` — done *before* the unnumbered repo's first push (§5.7)
- [ ] Worker `homers-lotr-wiki-s<N+1>` created against `nwn-homers-lotr` + custom domain `season<N+1>.homerslotr.com` (DNS is automatic)
- [ ] Both hosts return 200; a test push on each side builds only its own worker
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
- [ ] Ports swapped both sides in `server.env` **and** `NWNSYNC_PUBLIC_URL` in both `server.env.local`
- [ ] Roles and `NWN_SERVERNAME` flipped both sides; `(EARLY ACCESS)` dropped
- [ ] `season-brand.py --apply` run in **both**; both repacked + deployed
- [ ] Archived season's `recent_updates` board re-texted to "season has ended"
- [ ] Cyan early-access block **deleted** from the new live season's `servershout4.nss` — its wipe warning is now false
- [ ] Apex custom domain **removed** from the old worker, **added** to the new one, zone cache purged
- [ ] Archived roadmap pruned to `awarded`-only; `gen-roadmap.py`; published to its `roadmapdb`
- [ ] Player password removed; both servers verified in the server browser
- [ ] Merit balance verified on both
- [ ] Veteran reward live; cutover announced

**Phase 3 — retire**
- [ ] (No live-module change needed — the archived season's own board goes away with its server)
- [ ] Season-N server + NWSync stopped and disabled
- [ ] Its wiki-publish and backup units disabled
- [ ] Season-N GitHub repo archived read-only (`gh repo archive`); its Workers Build disconnected
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
- **The riskiest window is between the `cp -a` and the Cloudflare re-point** —
  publishing is fully automated on both sides (§5a), so a wrong remote or a stale
  build connection is exercised unattended within hours. Do those two steps
  back-to-back, never overnight.
- **Capture surprises back into this file.** Anything that bit you during a
  cutover belongs here before you forget it.

*v2.2 — first written for the season 1 → 2 cutover, but parameterized for every
cutover after it. v2.1 added the auxiliary-service handling (§6a) and the
redemption-code split (§2). v2.2 adds the git topology and two-repo overlap model
(§5a), the ordered Workers-Builds re-point (§5.7), and the `server.env.local`
port swap (§7.5).*
