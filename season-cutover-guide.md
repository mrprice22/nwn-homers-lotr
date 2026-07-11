# Season Cutover Guide — Homer's LOTR (draft 1.0)

> **Status:** draft 1.0. This is a technical runbook for standing up a *new
> season* of Homer's LOTR as a second NWN server, running it alongside the old
> season during an overlap period, and eventually retiring the old one. It
> describes changes to make; it does **not** itself change any code, DB, or unit.
> Ports, container names, and directory suffixes below (`-s2`, `S2`, `5122`,
> `8001`, …) are **suggested conventions** — pick your own, but keep them
> consistent everywhere.

---

## 0. Why seasons

Give players a periodic **fresh start** — everyone rolls new characters — so the
server can absorb major rebalances (gear, bosses, the legendary-level system)
without the weight of legacy characters and inflated economies. A season is a
distinct server + module + character vault.

**Cadence trigger:** run a cutover roughly quarterly, *or* whenever a change is
large enough that old characters can't be fairly carried forward (gear power
curve, boss/loot tables, or legendary-level math). There is no fixed calendar;
the trigger is "the change is too big to hot-patch."

**Design guarantees a season preserves across the boundary:**
- **Account-wide merit** (earned merit + redemption entitlements) is *shared*
  across all seasons — it's an account reward, not a character reward.
- Everything else about a character (levels, gear, gold, bestiary, houses, banks,
  boss-kill history) is **fresh** each season.

---

## 1. Lifecycle at a glance

```
        ┌─────────────┐   promote    ┌──────────────────────┐   go public   ┌────────────┐
        │  TEST REALM │─────────────▶│ LIMITED PRE-CUTOVER  │──────────────▶│    LIVE    │
        │ (admin only)│  (password)  │  (password, testers) │   (wipe +     │  SEASON 2  │
        └─────────────┘              └──────────────────────┘   no password)└────────────┘
                                              │                                     │
                                    testers warned:                        Season 1 stays up
                                    progress WILL be wiped                  in parallel (overlap)
                                    at real cutover                                 │
                                                                          retire S1 once empty
                                                                          (wiki archived first)
```

| Phase | Who can join | S2 vault/DBs | Merit | Wiki |
|-------|--------------|--------------|-------|------|
| Test realm | admin only | throwaway | shared | not published |
| Limited pre-cutover | password-gated testers | throwaway (**wiped at cutover**) | shared | not published (or staging) |
| Live cutover | everyone | **fresh, permanent** | shared | S2 → `homerslotr.com`; S1 frozen → `season1.homerslotr.com` |
| Overlap | everyone (both seasons) | S2 permanent; S1 permanent | shared | as above |
| Retire S1 | — | S1 archived | shared | S1 stays read-only at subdomain |

---

## 2. The data contract — what carries over vs resets

All persistent state is **campaign SQLite DBs** in
`NWN_HOME_DIR/database/*.sqlite3`. Campaign DBs are **campaign-scoped**: any
module running under the *same* `NWN_HOME_DIR` shares them by filename; a *separate*
`NWN_HOME_DIR` gets a completely fresh `database/` folder. **A separate
`NWN_HOME_DIR` per season is therefore the single lever that makes almost
everything reset automatically.** You then deliberately re-share the one DB that
should persist.

### Shared across seasons

| DB | Keyed by | Contents | How shared |
|----|----------|----------|------------|
| `meritdb` | `GetPCPublicCDKey` (account) | `players`, `redemptions`, `merit_ledger` | symlink the one file (§4) |
| `admindb` *(optional)* | CD key | admin whitelist (+ house ownership) | share only if staff/houses persist; usually **fresh** so houses reset |

> Recommendation: share **`meritdb` only**. Leave `admindb` fresh so Season-2
> houses start empty; re-seed the admin whitelist with `bin/seed-admindb.sh`
> against the S2 home dir (it's out-of-band and key-free anyway).

### Reset fresh — do NOT carry

`bestiarydb` (kills **and** server-firsts that feed the wiki), `boostdb`,
`coderedeem`, `bankdb`, `housechest`, `fellbeast`, `meaningwave`, `partyloot`,
`kpb_bank`, `ppis`, `dyedb`, `roadmapdb`, and the new `teledb` (§3).

A fresh `NWN_HOME_DIR` gives all of these an empty `database/` automatically — you
do nothing per-DB.

### Self-resetting (no action)

`respawndb` — `BRD_InitDb()` runs `DELETE FROM boss_registry/boss_alias/
boss_deaths` and re-seeds from generated source on **every module load**. It never
carries cross-season state.

### Wiki metrics reset for free

- **Server-firsts / kill leaderboards** are read from `bestiarydb` (`server_first`
  + `kills` tables in `unpacked/bst_db.nss`). A fresh home dir ⇒ empty ⇒ the wiki
  shows a clean slate.
- **Activity charts** are built from `--log-dir` server logs, not a DB. A fresh
  `NWN_RUN_DIR` ⇒ fresh logs ⇒ charts start at zero.

So "reset wiki activity + server-firsts at cutover" needs **no manual DB
surgery** — it falls out of the fresh home/run dirs.

---

## 3. One-time prep on the CURRENT (Season 1) module — split `teledb` out of `meritdb`

**Do this in the live Season-1 module first**, before forking, so both seasons
agree on the schema. Reason: `unpacked/tele_db.nss` currently piggybacks on
`meritdb` (`const string TELE_DB = "meritdb";`) and adds **per-character**
`tele_slots` / `tele_state` (keyed by `GetObjectUUID`). If we shared `meritdb`
whole, every season would drag along stale per-UUID teleport rows.

**Change:** in `unpacked/tele_db.nss`, set

```nwscript
const string TELE_DB = "teledb";   // was "meritdb"
```

Everything else in that file already routes through `TELE_DB`, so no other edits
are needed there. Confirm `Tele_InitDb()` still runs at module load
(it's the `CREATE TABLE IF NOT EXISTS` bootstrap) — it's idempotent and will
create `teledb.sqlite3` on first use.

**Behaviour after the split (this is exactly the intended outcome):**
- **Teleport *access*/unlocks** — merit redemptions **101–107**, stored in
  `meritdb.redemptions`, per-CD-key — **carry over** with the shared merit DB.
- **Saved teleport locations** (`tele_slots` slots 0–5, `tele_state`) live in
  `teledb` and are **per-season / per-character** — they start fresh each season.
- On Season 1, applying this split resets existing players' saved teleport slots
  **once** (a one-time inconvenience; their *ability* to teleport, being a merit
  redemption, is untouched). Announce it.

> See `CLAUDE-merit.md` for the merit DB schema and redemption ranges, and
> `unpacked/merit_db.nss` / `unpacked/merit_redeem.nss` for the tables that stay
> account-wide.

Repack + deploy Season 1 with this change before proceeding.

---

## 4. Standing up Season 2 (same machine)

Both seasons run on this one box. Isolation is by **distinct dirs, ports, and
container names**; sharing is by **one symlink**. Nothing in the core tooling
(`nwn-manager` / `nwn-wiki`) needs changing — it's already module-agnostic and
keys off the working directory, `nasher.cfg`, `.nasher/source`, `server.env`, and
CLI flags.

### 4.1 New working directory + module

1. Create `GIT/nwn_s2_homerslotr` as its own git repo with its own remote.
2. Fork the module content (copy `unpacked/`, `nasher.cfg`, `hak_2da/`, the
   `bin/` wrappers you'll adapt, `systemd/`, `wrangler.jsonc`, `src/`, the
   `CLAUDE*.md` docs).
3. In `nasher.cfg`, give S2 a **distinct target filename**, e.g.
   `homers_lotr_s2.mod`. This matters: `nwn-manager` builds via a
   `/tmp/nwnmgr_<modfile>` symlink and a `nwnmgr_bstamp.nss` build stamp — a
   distinct filename avoids any race if both seasons ever repack at once.
4. Set S2's `.nasher/source` (gitignored) to S2's install/source `.mod` path.

### 4.2 New `server.env` (the parameter surface)

Clone `server.env` and change every instance-scoped value. The ones that **must**
differ from Season 1:

| Var | Season 1 | Season 2 (suggested) | Why |
|-----|----------|----------------------|-----|
| `NWN_CONTAINER_NAME` | `nwnxee-homer` | `nwnxee-homer-s2` | else `bin/serve` stops/removes S1's container |
| `NWN_PORT` | `5121` | `5122` | `--network=host` = no port isolation |
| `NWN_RUN_DIR` | `~/.local/state/nwnxee-homer` | `~/.local/state/nwnxee-homer-s2` | separate logs + fresh activity charts |
| `NWN_HOME_DIR` | `~/.local/share/Neverwinter Nights` | `~/.local/share/Neverwinter Nights S2` | **fresh vault + fresh `database/`** (the key lever) |
| `NWN_MODULE` | `Homer's LOTR VEL v3` | `Homer's LOTR Season 2` | locates `$NWN_HOME_DIR/modules/${NWN_MODULE}.mod` |
| `NWN_SERVERNAME` | `Homer's LOTR Very Easy Leveling` | `Homer's LOTR — Season 2` | server-browser name |
| `NWNSYNC_PORT` | `8000` | `8001` | nginx port collision |
| `NWNSYNC_CONTAINER` | `nwnsync-nginx` | `nwnsync-nginx-s2` | container-name collision |
| `NWNSYNC_REPO` | `.../nwsync/HomersLOTR` | `.../nwsync/HomersLOTR-S2` | separate manifest (needed if hak/tlk content diverges) |

Passwords still go in **`server.env.local`** (gitignored) — see §7.

### 4.3 Share the merit DB (one symlink)

After S2 has been started once (so `$S2_HOME/database/` exists), replace S2's
merit DB file with a symlink to Season 1's:

```bash
S1_DB="$HOME/.local/share/Neverwinter Nights/database/meritdb.sqlite3"
S2_DB="$HOME/.local/share/Neverwinter Nights S2/database/meritdb.sqlite3"
rm -f "$S2_DB"                    # remove the empty S2 copy if present
ln -s "$S1_DB" "$S2_DB"
```

Both servers now read/write the same `meritdb.sqlite3`. **Backup implication:** the
merit DB is a single shared file written by two processes — SQLite handles
concurrent access, but make sure only one backup job snapshots it (keep it in the
S1 backup, exclude it from S2's) so you don't double-archive or race the copy.

> Because the teleport *saves* were moved to `teledb` in §3, this shared file is
> now purely account-wide (`players`/`redemptions`/`merit_ledger`) — no stale
> per-character rows leak across seasons.

### 4.4 Clone the wrapper scripts

The homers-specific values live entirely in the wrappers, not the core tool.
Clone these as `*-s2` and swap the hard-coded paths/filenames/URL:

- `bin/repack-homers-lotr` → `repack-s2` (`PROJECT`, `.mod` filename, install dirs)
- `bin/refresh-homers-lotr-wiki` → `refresh-s2-wiki` (`PROJECT`, `--base-url`, `--log-dir`, `--db-dir`)
- `bin/backup-homers-lotr` → `backup-s2` (`BACKUP_DEST`, archive prefix, exclude the shared `meritdb`)

> **Optional refactor (recommend deferring past v1):** rework the wrappers to take
> a project directory argument and source that project's `server.env`, so one set
> of scripts serves both seasons. Simpler for now: straight clones.

---

## 5. Networking / ports / NWSync

`bin/serve` launches the container with `--network=host`, so there is **no
per-container port isolation** — every listening port must be unique across the
two seasons.

| Service | Season 1 | Season 2 |
|---------|----------|----------|
| Game (UDP) | 5121 | 5122 |
| NWSync (nginx, TCP) | 8000 | 8001 |
| Roadmap editor (TCP) | 8765 | *share S1's; run one instance* |

Router / DDNS to update:
- Port-forward the second game port (5122/udp) and the second NWSync port
  (8001/tcp) to this host.
- Set `NWNSYNC_PUBLIC_URL` for S2 in its `server.env.local` (e.g.
  `http://homerslotr.ddns.net:8001`). The game server only *advertises* this URL;
  nginx serves the bytes.
- S2 needs its **own NWSync repo/manifest** whenever its hak/tlk content differs
  from S1 (it will, once you rebalance). Run S2's `refresh-nwsync` against
  `NWNSYNC_REPO=.../HomersLOTR-S2`.

---

## 6. Linux background services

Existing units live in the repo `systemd/` and are installed under
`~/.config/systemd/user/` (user units) and `/etc/systemd/system/` (root reboot
timer). They are single-instance and hard-code `nwnxee-homer`, the
`WorkingDirectory`, and the run-dir watch path. Stand up a **parallel `s2-*` set**:

| Unit | Action for Season 2 |
|------|---------------------|
| `homers-lotr-server.service` | **Clone** → `s2-server.service`: `WorkingDirectory` = S2 repo, `ExecStop` podman name = `nwnxee-homer-s2` |
| `homers-lotr-wiki-publish.service` | **Clone** → `s2-wiki-publish.service`: runs `refresh-s2-wiki --publish` in the S2 repo |
| `homers-lotr-backup.service` | **Clone** → `s2-backup.service`: `backup-s2` (excludes shared `meritdb`) |
| `homers-lotr-empty-restart.path` + `.service` | **Clone** → `s2-empty-restart.*`: **fix the hard-coded watch path** (currently `%h/.local/state/nwnxee-homer/anvil/PluginData/restart-server`) to the **S2 run dir**, and restart `s2-server.service` |
| `roadmap-editor.service` | **Share** — one editor instance (S1's) during overlap; S2 only needs its own if you edit an S2 roadmap separately |
| `nwn-reboot.timer` (root) | **Share/leave** — one daily 03:03 OS reboot restarts *both* servers (both have `WantedBy=default.target`) |

Also: `bin/serve` starts an in-process activity monitor
(`nwn-manager serve … --auto-publish`). S2's `serve` must point it at the **S2 run
dir + S2 repo** so it refreshes the correct `docs/activity.html`.

> **Long-term tidy form:** convert to `@`-templated instance units
> (`homers-lotr-server@s1`, `@s2`) parameterized by an instance-named env file.
> For draft-1.0 cutover, straight `s2-*` clones are fine.

---

## 7. Wiki — active site + archived subdomain

Hosting is **Cloudflare Workers**: `wrangler.jsonc` defines worker
`homers-lotr-wiki` serving `./docs` as static assets; `src/index.js` 301-redirects
`*.workers.dev` → `homerslotr.com`. Cloudflare auto-deploys **on git push** — no
`wrangler deploy` in any script. So "publish" = commit `docs/` + push.

**Active season → `homerslotr.com`:** the *current* season's repo owns the apex
domain. Its `refresh-…-wiki` uses `--base-url https://homerslotr.com/`. At
cutover, Season 2 takes over this domain/worker.

**Archive Season 1 → `season1.homerslotr.com`:**
1. Do a final full wiki republish of S1 (with its live DBs) so the archive is
   complete and current.
2. Stop pushing to the S1 repo — Cloudflare will simply keep serving the last
   deployed `docs/` (frozen).
3. Add a **second Cloudflare worker/route** (or a route on the existing worker)
   bound to `season1.homerslotr.com`, pointing at S1's frozen `docs/`. Add the
   `season1` DNS record in Cloudflare.
4. Rebuild S1's wiki once with `--base-url https://season1.homerslotr.com/` so its
   absolute links (area-map SVG, module-index JSON) resolve under the subdomain,
   and add a visible **"Season 1 — archived, read-only"** banner
   (a small edit to the S1 wiki template or a manual page).

**Metrics reset:** covered for free — S2's fresh home/run dirs mean its wiki
starts with empty server-firsts, leaderboards, and activity charts (§2).

---

## 8. Limited pre-cutover test phase

Let a few named players into Season 2 early to validate the rebalance, **with a
clear wipe warning**.

1. Set `NWN_PLAYERPASSWORD="…"` in S2's `server.env.local` (gitignored). Hand the
   password only to chosen testers.
2. **Announce loudly and repeatedly:** the test vault and *all* Season-2 DBs
   (except shared merit) **will be wiped at real cutover** — every character,
   item, bestiary entry, house, and bank gained in testing is temporary. Merit
   earned still counts (it's the shared account DB).
3. Iterate on balance; repack/redeploy S2 freely.

**Wipe → go-live procedure** (the transition from test to live):

```bash
S2_HOME="$HOME/.local/share/Neverwinter Nights S2"
# Stop S2 first (systemctl --user stop s2-server.service)
rm -rf "$S2_HOME/servervault"/*          # drop all test characters
find "$S2_HOME/database" -name '*.sqlite3' \
     ! -name 'meritdb.sqlite3' -delete   # drop all test DBs, KEEP the merit symlink
# (the meritdb.sqlite3 symlink is untouched by the find above)
```

Then deploy the *final* module build, apply the returning-player reward (§9–10),
**remove `NWN_PLAYERPASSWORD`** from `server.env.local`, and start S2 public.

> Double-check the `meritdb.sqlite3` **symlink** survives the wipe (the `find`
> above excludes it by name; verify with `ls -l`). Never `rm -rf` the whole
> `database/` dir while the symlink is present — deleting the symlink is fine, but
> be sure you don't follow it and truncate S1's real file.

---

## 9. Cutover-day runbook

Ordered, with a rollback note at the end.

1. **Freeze S1 content.** Final repack of S1 is done; no further module edits.
2. **Snapshot S1 `bestiarydb`** *before* archiving — the reward computation reads
   it (server-firsts, bestiary completion). Copy
   `"$S1_HOME/database/bestiarydb.sqlite3"` to a safe path; also snapshot
   character XP if using the XP-bank reward (read from the S1 servervault).
3. **Final S1 wiki republish**, then **archive** it to `season1.homerslotr.com`
   (§7): add the subdomain worker/route + DNS, rebuild S1 wiki with the subdomain
   `--base-url`, add the archived banner, stop pushing to the S1 repo.
4. **Point the apex domain at Season 2:** S2's wiki publish now targets
   `homerslotr.com`.
5. **Wipe/seed S2** to a clean live state (§8 wipe procedure) — fresh vault, fresh
   DBs, merit symlink intact.
6. **Verify the merit symlink** (`ls -l "$S2_HOME/database/meritdb.sqlite3"` →
   points at the S1 file) and that a test login reads the correct merit balance.
7. **Apply the returning-player reward** (§10): populate the one-time S1 snapshot
   table in the shared merit DB from step 2's data.
8. **Go public:** remove `NWN_PLAYERPASSWORD`, start `s2-server.service`, confirm
   the server browser shows Season 2 on 5122 and NWSync serves on 8001.
9. **Announce** the cutover, the archived S1 subdomain, and that S1 stays playable
   during overlap.
10. **Retire S1 later:** once S1 is consistently empty, stop `homers-lotr-server`
    (and S1 NWSync). The archived wiki stays up at the subdomain indefinitely.

**Rollback:** until S1 is retired, cutover is reversible — S1's server, vault, and
DBs are untouched by the S2 stand-up (separate home dir). If S2 goes badly, keep
directing players to S1 on 5121 while you fix S2; nothing about S1 was destroyed.
The one shared object is `meritdb`, so avoid schema-breaking merit changes in S2
during overlap.

---

## 10. Returning-player reward — options menu (decide later)

Reward Season-1 participants at cutover. Below are the candidate mechanisms with
trade-offs, some extra ideas, concrete example gear, and a recommendation. **Final
pick is deferred** — this section is a menu.

### Candidate mechanisms

**A. XP bank (% of prior XP).**
Sum a CD-key's total Season-1 character XP; grant e.g. **20%** into a Season-2
"XP-bank" balance the player draws down on new characters.
- *Data source:* S1 servervault character XP (snapshot at cutover).
- *Effort:* medium — needs a small XP-bank table (best placed in the shared merit
  DB, keyed by CD key) + an in-game "withdraw XP" interaction.
- *Pros:* scales with actual playtime; self-serve; account-fair.
- *Cons:* raw XP can over-reward AFK/grind; consider a cap.

**B. Achievement gear.**
Medium-tier **unique starting gear** for players with notable S1 achievements
(most server-firsts, highest bestiary completion).
- *Data source:* the S1 `bestiarydb` snapshot (`server_first`, `kills`).
- *Effort:* medium-high — author the items + a gated hand-out; must snapshot
  before archiving.
- *Pros:* prestige, visible bragging rights; strong "veteran" flavour.
- *Cons:* manual curation; power-creep risk if items are too strong for a fresh
  economy — keep them *medium* tier / mostly cosmetic-plus.

**C. Merit grant.**
One-time **merit award** sized by S1 achievement, using the already-shared merit
plumbing (`merit_*.nss`, DM emote wand, redemption catalogue).
- *Data source:* any S1 metric you choose.
- *Effort:* lowest — no new system; merit is already cross-season.
- *Pros:* trivial to implement and audit; players spend it how they like.
- *Cons:* least "fresh-start flavour"; merit already persists, so it can feel
  like less of an event.

### Additional ideas

- **"Season 1 Veteran" account flag** in the shared merit DB — unlocks cosmetics,
  a title, or a veteran-only starter vendor. Cheap, permanent, account-wide.
- **Claim-once Veteran NPC** in the S2 start area that reads the one-time S1
  snapshot table and dispenses the reward — one auditable code path for *all*
  reward types, prevents double-claims, and needs no DM presence.
- **Tiered rewards:** a small *participation* reward for anyone who played S1 at
  all, plus an *achievement* tier for standouts — so everyone feels recognized.
- **Bestiary "New Game+" head-start:** seed a modest kill-count credit in S2's
  fresh `bestiarydb` from S1 progress (soft continuity without gear power-creep).

### Example achievement-gear pieces (illustrative)

- **Cloak of the First Blade** — for the player with the most S1 server-first
  slays. Cosmetic-forward with a modest, non-scaling bonus and a unique
  description naming the season.
- **Loremaster's Ring of Beasts** — for top S1 bestiary completion; a small,
  flavour-appropriate set-style bonus (e.g. minor lore / vs-specific-type).
- **Veteran of Season 1 (token/title item)** — everyone who played gets it;
  purely cosmetic + a redeemable "veteran" flag; no combat power.

### Recommendation

A single **claim-once "Season 1 Veteran" NPC** in the Season-2 start area, backed
by a **one-time S1 snapshot table in the shared merit DB**, granting:
- **(a)** a small **XP-bank stipend** to *everyone* who played S1 (participation
  tier, capped), plus
- **(b)** **one achievement-gated gear/cosmetic piece** for standout players
  (server-firsts / bestiary tier).

This unifies mechanisms A, B, and C behind one auditable code path, reuses the
already-shared, CD-key-keyed merit DB for eligibility, and can't be double-claimed.
Keep gear medium-tier to protect the fresh economy.

---

## 11. Follow-up implementation checklist

The work this guide *specifies* (none of it done yet). Grouped by where it lands:

**Module (Season 1, before forking)**
- [ ] Split `teledb` out of `meritdb` — edit `unpacked/tele_db.nss`
  (`TELE_DB = "teledb"`); repack + deploy S1; announce the one-time slot reset.

**Season 2 project**
- [ ] Create `GIT/nwn_s2_homerslotr` repo; fork module content; distinct
  `nasher.cfg` target (`homers_lotr_s2.mod`) + `.nasher/source`.
- [ ] New `server.env` with distinct container/port/run-dir/**home-dir**/module
  name (§4.2); passwords in `server.env.local`.
- [ ] Symlink S2 `meritdb.sqlite3` → S1's; exclude it from S2 backups (§4.3).
- [ ] Clone wrappers → `repack-s2`, `refresh-s2-wiki`, `backup-s2` (§4.4).

**Infra / systemd / hosting**
- [ ] Parallel `s2-*` systemd set; **fix the empty-restart `.path` watch path** to
  the S2 run dir (§6).
- [ ] Second game + NWSync port-forwards; S2 `NWNSYNC_PUBLIC_URL`; S2 NWSync repo
  (§5).
- [ ] Cloudflare: `season1.homerslotr.com` worker/route + DNS; archived banner;
  rebuild S1 wiki with the subdomain `--base-url` (§7).

**Reward system (final mechanism TBD, §10)**
- [ ] One-time S1 snapshot table in the shared merit DB (from `bestiarydb` +
  character XP).
- [ ] Claim-once "Season 1 Veteran" NPC in the S2 start area + reward hand-out.
- [ ] XP-bank plumbing (if the XP-bank tier is chosen).

**Core tooling (`nwn_manager`)**
- [ ] *No changes expected* — `nwn-manager` / `nwn-wiki` are already
  module-agnostic (they key off cwd, `nasher.cfg`, `.nasher/source`, `server.env`,
  and the `--base-url` / `--out` / `--db-dir` / `--log-dir` flags). Prefer
  wrapper/env changes over touching the core.

---

*Draft 1.0 — refine as the first real cutover is executed; capture anything that
surprised you back into this file.*
