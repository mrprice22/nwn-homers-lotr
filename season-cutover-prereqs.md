# Season Cutover — one-off prerequisite work

Companion to [season-cutover-guide.md](season-cutover-guide.md). **That** file is
the per-season runbook, re-run every 3–4 months. **This** file is the one-time
engineering that makes the runbook possible: build it once, and every future
cutover is a checklist rather than a project.

> ## ⚠ Partly superseded by the dev-realm refactor (guide v3.0)
>
> This file is a **historical record of work already done**, written against the
> v2 model where `nwn_homers_lotr` was the newest season and *became* production
> at Phase 2. It is now the permanent **dev realm** and never becomes production.
> The items below still describe real, still-installed machinery — but where one
> contradicts the guide, **the guide wins**. Specifically:
>
> | Item | Status under v3 |
> |---|---|
> | **4** — de-hard-code `refresh-homers-lotr-wiki` | Done differently in the end: the shared `nwn_manager` copy is now a **refusing stub**. With three environments there is no correct default `--base-url`/`--log-dir` to fall back to. Use each repo's own copy. |
> | **8** — the branded-string completeness grep | Still correct, but `season-brand.py` now owns strings/URLs **only**. Behaviour (cheat chest, dev NPCs, wipe notice) moved to `bin/season-profile.py`, gated by `tests/check_season_profile.py`. |
> | **11** — per-season dev shortcuts | Superseded again. Shortcuts key on **role first, number second** (`-dev` vs `-s<N>`), because dev carries the season number it feeds and would otherwise collide with that season's own set. |
> | **13** — the Cloudflare build connection | Still the one piece of state no script owns, but much less exposed: dev keeps its own worker permanently, so Phase 1 only *adds* a worker instead of re-pointing two. |
> | The roadmap-editor note at the end | Editor still single-instance, now on the **dev** repo. Its Publish reaches dev only; production gets the roadmap at the next promotion. |
>
> Nothing here needs redoing. Read it for *why* something is the way it is, not
> for what to do next.

Items 1–2 touch live player data and must be finished before the first Phase 1;
items 2b–12 are tooling and can land any time before it.

> **Status: all twelve items are done** (2026-07-24); item 13 is a
> documentation-only guard note added afterwards. What follows is kept as
> the rationale for each piece, with the boxes ticked and any deviation from the
> original design recorded in a **Built** note under the item. The pieces that
> only *run* at a cutover — `season-brand.py` for a non-season-1 config, the
> archive prune, the per-season ops shortcuts, a second systemd instance — are
> exercised by the rehearsal at the bottom, not by season 1 itself.
>
> **Deviations from the design as first written, in one place:**
> - `SEASON_LEGACY_NAMES` (new): item 8's table lists `nasher.cfg` and
>   `server.env`'s names as both *inputs to* and *outputs of* `season-brand.py`.
>   `SEASON_NUM` + `SEASON_ROLE` are now the only authored facts and the names
>   are derived; season 1's exemption is this flag rather than a special case.
> - `SEASON_CONNECT_HOST` (new): `homerslotr.ddns.net` was recorded nowhere —
>   it existed only mid-sentence inside `module.ifo.json`'s description.
> - **Item 9 (the two season signs) is RETIRED** — built, used once at the
>   season 1 -> 2 cutover, then removed along with the whole `SEASON_PEER_*`
>   block. The rule that replaced it: the *outgoing* season repurposes its own
>   `recent_updates` board as the next-season notice, and the *incoming* season
>   gets a coloured login message. Neither gets a new placeable. See item 9.
> - `NWN_SERVERNAME` uses an ASCII hyphen, not an em dash: it is passed through
>   the container env to `nwserver` and on to the master server browser.
> - Item 10's predicted prune split was wrong — see its **Built** note.

---

## 1. Split `teledb` out of `meritdb` — **live data, do first**

`unpacked/tele_db.nss` line 16 still reads:

```nwscript
const string TELE_DB = "meritdb";   // -> "teledb"
```

Everything else in that file already routes through `TELE_DB`, and
`Tele_InitDb()` is an idempotent `CREATE TABLE IF NOT EXISTS` bootstrap that
creates `teledb.sqlite3` on first use — so this is a one-line change.

**Why it's mandatory:** `meritdb` becomes one of two files shared by *every*
season (item 2). `tele_db.nss` currently piggybacks on it and stores
**per-character** `tele_slots` / `tele_state` keyed by `GetObjectUUID`. Left
alone, every future season would inherit stale teleport rows for characters that
no longer exist.

~~**Player impact, once:** saved teleport *slots* reset.~~ **No player impact —
the rows were migrated instead.** See the Built note. Teleport *unlocks* are
merit redemptions 101–107 living in `meritdb.redemptions`, keyed by CD key — they
were never at risk.

- [x] `tele_db.nss` edited, repacked, deployed, **existing rows migrated**

> **Built.** `TELE_DB` is now `"teledb"`. `tele_woe.nss` is the only other
> consumer and goes through the `Tele_*` helpers, so nothing else changed.
>
> **The "announce the slot reset" step above was wrong, and was not needed.**
> This is a *mid-season-1* change, not a cutover: season 1 players had 95 saved
> slots across 94 characters and there was no reason for them to lose any. The
> rows were copied into the new per-season `teledb.sqlite3` (server stopped, no
> logins in between, so nothing was lost even briefly) and verified byte-identical
> on both tables:
>
> ```bash
> sqlite3 "$DB_DIR/teledb.sqlite3" <<'SQL'
> CREATE TABLE IF NOT EXISTS tele_slots (pid TEXT NOT NULL,slot INTEGER NOT NULL,
>   area TEXT,name TEXT,x REAL, y REAL, z REAL, facing REAL,PRIMARY KEY(pid, slot));
> CREATE TABLE IF NOT EXISTS tele_state (pid TEXT PRIMARY KEY,
>   return_armed INTEGER NOT NULL DEFAULT 0);
> SQL
> sqlite3 "$DB_DIR/teledb.sqlite3" \
>   "ATTACH '$SHARED/meritdb.sqlite3' AS old;
>    INSERT OR REPLACE INTO tele_slots SELECT * FROM old.tele_slots;
>    INSERT OR REPLACE INTO tele_state SELECT * FROM old.tele_state;"
> ```
>
> The DDL is copied verbatim from `Tele_InitDb()`, so its
> `CREATE TABLE IF NOT EXISTS` is a no-op on the first login afterwards.
>
> The stale copies were then **dropped from the shared `meritdb`** (`DROP TABLE`
> + `VACUUM`, after a `meritdb.sqlite3.pre-tele-migration-<ts>` backup in
> `nwn-shared/`), which is the whole point of the split — otherwise every future
> season would still see them sitting in the shared file.
>
> **Future seasons need no migration and must not do one.** A new season gets a
> fresh `NWN_HOME_DIR`, so its `teledb.sqlite3` is created empty on first login
> and the slots reset as intended by the data contract (guide §2).

## 2. Move the shared DBs to a season-neutral path — **live data**

Two files persist across every season: `meritdb` (account merit + entitlements)
and `admindb` (the CD-key admin whitelist + player-home fulfilment records). Admin
access and UAT shortcuts don't change between seasons, and player-home
entitlements are merit purchases — so both must survive a cutover. Neither should
live inside any season's directory, or retiring that season orphans it.

```bash
# server stopped
SRC="$HOME/.local/share/Neverwinter Nights/database"
mkdir -p "$HOME/.local/share/nwn-shared"
for f in meritdb admindb; do
  cp "$SRC/$f.sqlite3" "$SRC/$f.sqlite3.bak"          # keep a copy first
  mv "$SRC/$f.sqlite3" "$HOME/.local/share/nwn-shared/$f.sqlite3"
  ln -s "$HOME/.local/share/nwn-shared/$f.sqlite3" "$SRC/$f.sqlite3"
done
ls -l "$SRC"/{merit,admin}db.sqlite3     # both must point into nwn-shared/
```

Use **absolute** symlinks — later seasons live at different depths.

Why `admindb` as a whole, not just its `admins` table: it also holds `houses`
(the fulfilment record for merit-purchased player homes). Keeping the whitelist
but resetting homes would strand players who spent merit on a home — see
"Why `houses` rides along" in the guide's §2. The house's *contents*
(`housechest`, a separate DB) still reset each season.

Once moved, these two files are the home of irreplaceable state that no season's
own backup captures automatically — each season sees them only as symlinks. Item
2b handles backing them up.

- [x] Both moved, symlinked, verified

> **Built** as `bin/season-shared-dbs.sh` rather than loose shell, so Phase 1
> can re-run it to link a *new* season's `database/` at the same files —
> re-running once the symlinks exist is a clean no-op. It refuses to run while
> the season's container is up (a live server holds these files open) and
> leaves a `.bak` on the old path. Verified: md5sums identical across the move,
> and 50 `players` / 16 `redemptions` / 59 `merit_ledger` / 10 `admins` /
> 2 `houses` rows all readable through the symlinks.
>
> ### The symlinks alone are not enough — the container must be able to follow them
>
> **This bit, and it is not obvious.** The recipe above is correct on the host
> and wrong for the *server*, which runs in a container with only two bind
> mounts — `$NWN_RUN_DIR:/nwn/run` and `$NWN_HOME_DIR:/nwn/home`. An **absolute**
> symlink to `~/.local/share/nwn-shared/…` resolves fine from a host shell (which
> is why `ls -l` and `sqlite3` both looked healthy) but **dangles inside the
> container**, because that path is not mounted there. nwserver treats an
> unopenable campaign DB as fatal, so the server aborts at module load:
>
> ```
> terminate called after throwing an instance of 'std::runtime_error'
>   what():  database unavailable
>  NWNX 8193.37-17 has crashed. Fatal error: Program aborted (6).
> ```
>
> and systemd restart-loops it. The whole-file backup, the row counts and the
> `ls -l` verification in the recipe all pass while this is broken — the only
> symptom is the crash.
>
> Fixed in `bin/serve`, which now mounts the shared dir **at its own host path**
> so absolute symlinks resolve identically on both sides:
>
> ```bash
> NWN_SHARED_DIR="${NWN_SHARED_DIR:-$HOME/.local/share/nwn-shared}"
> [[ -d $NWN_SHARED_DIR ]] && shared_args=(-v "$NWN_SHARED_DIR:$NWN_SHARED_DIR:rw,z")
> ```
>
> Guarded on the directory existing, so a repo without the shared DBs still
> starts. **Every season's `bin/serve` needs this** — it comes along free with a
> `cp -a` at Phase 1, but check it if you ever hand-build a season's repo.

## 2b. Make `bin/backup-homers-lotr` season-aware

The backup already sources `server.env` at the top, so the season block (item 3)
is in scope for free. Three changes make it safe to run two seasons at once:

1. **Per-season archive folder.** Default `BACKUP_DEST` to a season subfolder so
   the retention-prune never crosses seasons — today it regex-matches
   `^homers-lotr-(\d{8})-(\d{6})\.tar\.gz$` across the **whole** `backups/` dir, so
   two seasons in one folder would prune each other's monthly keepers:
   ```bash
   : "${BACKUP_DEST:=$HOME/OneDrive/Games/NWNHomersLOTR/backups/s${SEASON_NUM}}"
   ```
2. **Skip the shared symlinks.** The DB loop does
   `for db in "$NWN_HOME_DIR"/database/*.sqlite3; do sqlite3 "$db" ".backup" …`,
   and `sqlite3 .backup` reads *through* a symlink — so as written every season
   archives `meritdb`/`admindb`. Skip them; they are not that season's data:
   ```bash
   [[ -L $db ]] && continue          # shared DBs are backed up once, by the live season (below)
   ```
   Fix the DRY_RUN count the same way (it uses `ls …/database/*.sqlite3 | wc -l`).
3. **Live season owns the shared backup.** Exactly one place snapshots
   `~/.local/share/nwn-shared/`, gated so two running seasons never race it:
   ```bash
   if [[ ${SEASON_ROLE:-} == live ]]; then
     for f in meritdb admindb; do
       sqlite3 "$HOME/.local/share/nwn-shared/$f.sqlite3" \
         ".backup '$stage/home/database/$f.sqlite3'"
     done
   fi
   ```
   (`sqlite3 .backup` gives a consistent snapshot even while both servers hold the
   file open.) The archived season's backups then contain only its own per-season
   DBs; the account-wide state lives in the live season's archive.

- [x] `BACKUP_DEST` per-season; symlinks skipped; shared DBs captured only when `SEASON_ROLE=live`
- [x] `--dry-run` verified for a `test` and a `live` role

> **Built.** `BACKUP_DEST` uses `${SEASON_NUM:+/s$SEASON_NUM}`, so a repo with
> no season block keeps the old flat layout. The 31 existing archives were
> moved into `backups/s1/` so the prune keeps its monthly-keeper history. The
> manifest now records `season_num`, `season_role` and whether the shared DBs
> are in the archive. Verified: `role=live` captures them into `backups/s1/`;
> a scratch season-2 `role=test` repo skips them into `backups/s2/`; the DB
> count dropped 31 -> 29 once the two became symlinks.

## 3. Season identity block in `server.env`

One block that every other piece derives from. Add to each season's `server.env`:

```bash
# ------------------------------------------------------------------ season ---
SEASON_NUM=2                 # this environment's season number
SEASON_ROLE=test             # live | test | archive
SEASON_WIKI_URL="https://season2.homerslotr.com/"
SEASON_WORKER_NAME="homers-lotr-wiki-s2"
```

> The block originally carried a `SEASON_PEER_*` sub-block describing the other
> running instance, to drive the in-game cross-advert sign. **Both were retired**
> at the season 1 -> 2 cutover — see item 9. The next season's port and password
> are now written into the outgoing season's repurposed `recent_updates` board by
> hand, which is a `.git.json` edit and needs no config.

- [x] Block added to `server.env`, documented in `README.md`

> **Built** with `SEASON_LEGACY_NAMES` and `SEASON_CONNECT_HOST` added (see the
> deviations list at the top). Note `bin/serve` forwards only `TZ`, `NWN_*`,
> `NWNX_*` and `ANVIL_*` into the container, so `SEASON_*` deliberately does
> **not** reach the module at runtime — the signs are baked in at brand time.

## 4. De-hard-code `bin/refresh-homers-lotr-wiki`

The only wrapper in this repo that isn't relocatable. It pins:

| Line | Hard-coded | Should be |
|------|-----------|-----------|
| ~24 | `PROJECT=/var/home/james/GIT/nwn_homers_lotr` | derived from `BASH_SOURCE` — copy the idiom in `bin/serve` |
| ~46 | `--base-url https://homerslotr.com/` | `$SEASON_WIKI_URL` |
| ~46 | `--log-dir "$HOME/.local/state/nwnxee-homer"` | `$NWN_RUN_DIR` |

`bin/serve` and `bin/backup-homers-lotr` already compute `PROJECT_ROOT`
correctly and need no change.

- [x] Rewritten; a copy of the repo at another path regenerates its own wiki

> **Built.** All three lines fixed. `--log-dir` now uses `$NWN_RUN_DIR`, which
> the script already sourced two lines earlier — the literal had simply never
> been updated. `NWN_MANAGER_BIN` stays absolute: `nwn_manager` is genuinely
> one shared checkout. Verified the three resolved values are byte-identical to
> the hard-coded ones.

## 5. `repack-homers-lotr` / `refresh-homers-lotr` — make them per-season

**Live in the `nwn_manager` repo** (`GIT/nwn_manager/bin/`), not here.
`repack-homers-lotr` hard-codes six season-scoped values:

- `PROJECT=/var/home/james/GIT/nwn_homers_lotr`
- the build artifact `homers_lotr_v3.mod` (eight occurrences)
- the OneDrive copy dir `$HOME/OneDrive/Games/NWNHomersLOTR`
- the production install path `$HOME/.local/share/Neverwinter Nights/modules`
- **the installed module filename `Homer's LOTR VEL v3.mod`** — this is what
  `NWN_MODULE` must match (see item 6)
- the timestamped archive prefix

`refresh-homers-lotr` (the **unpack** half) hard-codes three more: the project
path, the same flat OneDrive dir, and `CANONICAL_NAME="homers_lotr_v3.mod"` — a
season-1 artifact name used as the newest-mtime tie-break.

Rework them to source the target repo's `server.env` + `nasher.cfg` and derive
everything, so one set of scripts serves every season. Until then, each new
season needs a hand-edited clone — workable, but it is the single most
error-prone step in Phase 1.

- [x] Parameterized

> **Built** in `nwn_manager`: new `bin/repack-project.sh` resolves all six
> values from the target repo's `nasher.cfg` (`[target].file`) and `server.env`
> (`NWN_MODULE`, `NWN_HOME_DIR`); `repack-homers-lotr` and `-clean` source it
> and gain `--project DIR` (also `$NWN_PROJECT`) plus `--show-config`. The
> default stays the unnumbered repo, so the app-grid shortcuts are unchanged.
> Verified by an actual repack: installed to `homers_lotr_v3.mod` ->
> `Homer's LOTR VEL v3.mod`, exactly as before.
>
> **Unpack half built (2026-07-24).** The OneDrive copy dir is now split into a
> shared `ONEDRIVE_ROOT` plus a per-season `ONEDRIVE_MOD_DIR` =
> `$ONEDRIVE_ROOT/Season$SEASON_NUM`; the repack wrappers `mkdir -p` it, so a new
> season's folder appears on its first build. `refresh-homers-lotr` now sources
> the same resolver, scans **only** that folder, and gained `--project` /
> `--show-config`. The newest-mtime + canonical-name-tie-break rule is kept, but
> the tie-break is now `$MODFILE` from the target repo's `nasher.cfg` instead of
> the literal `homers_lotr_v3.mod`. Renamed point-in-time backups returning from
> the Windows toolset still win on mtime; the tie-break only separates
> same-second candidates and keeps `.nasher/source` off a stray alt-named build.
> The project root and
> `$NWN_HOME_DIR/modules` are deliberately not scanned (the repack archive in the
> project root would shadow an older OneDrive edit by mtime). Verified:
> `--show-config` on both halves resolves the same `Season1` path, and a scratch
> `SEASON_NUM=2` repo resolves to `Season2`/`homers_lotr_s2.mod` with no season-1
> file reachable.

## 6. Nail down the module / server naming convention

Three different names, easy to confuse. In NWN, **the module name is the
installed `.mod` filename** — `NWN_MODULE` must equal it exactly, minus the
extension, or `nwserver` fails to find the module at boot.

| Name | Where it lives | Season N value |
|------|----------------|----------------|
| Build artifact | `nasher.cfg` → `[target].file`, and `[package].name` | `homers_lotr_s<N>.mod` |
| **Installed module** | `$NWN_HOME_DIR/modules/<name>.mod`, written by the repack wrapper | `Homer's LOTR Season <N>.mod` |
| `NWN_MODULE` | `server.env` — must match the installed filename, **no `.mod`** | `Homer's LOTR Season <N>` |
| `NWN_SERVERNAME` | `server.env` — the server-browser name, free text, role-dependent | see below |

`NWN_SERVERNAME` changes with `SEASON_ROLE`, so players can tell the instances
apart in the browser:

| Role | Server name |
|------|-------------|
| `test` | `Homer's LOTR — Season <N> (EARLY ACCESS)` |
| `live` | `Homer's LOTR — Season <N>` |
| `archive` | `Homer's LOTR — Season <N> (ARCHIVED)` |

**Season 1 keeps its legacy names** (`homers_lotr_v3.mod`,
`Homer's LOTR VEL v3`, `Homer's LOTR Very Easy Leveling`). Never rename a live
module: the filename change alone would leave every player's saved server entry
pointing at a module that no longer exists. Numbering starts with season 2.

Neither the servervault nor the campaign DBs are keyed by module name (vault is
per-`NWN_HOME_DIR`, DBs are campaign-scoped by their own name), so a rename has
no data consequence — it is purely cosmetic plus the `NWN_MODULE` match.

- [x] Convention agreed and recorded in `README.md`

> **Built.** Recorded under README's "Season identity & rotation", and now
> *enforced* rather than merely documented: from season 2 on `season-brand.py`
> derives all four names from `SEASON_NUM`/`SEASON_ROLE`, and the repack
> wrapper takes the installed filename from `NWN_MODULE`, so the two cannot
> drift apart. `NWN_SERVERNAME` uses an ASCII hyphen (see deviations).

## 7. `@`-templated systemd units

Today's units hard-code the repo path and container name, so a second instance
means hand-cloned copies. Convert to instance units keyed on the repo directory
name (`nwn-season-server@nwn_homers_lotr.service`, `…@nwn_homers_lotr_s1`), with
`WorkingDirectory`, the podman `ExecStop` name, and the empty-restart watch path
all derived from an instance env file.

Watch out for:
- `homers-lotr-empty-restart.path` hard-codes
  `%h/.local/state/nwnxee-homer/anvil/PluginData/restart-server` — a cloned unit
  that keeps this path silently restarts the **wrong** server.
- **The new season's run dir needs a *real* `anvil/` directory**, or the rendered
  `.path` watches a host path that can never exist and the empty-restart shuts
  the season down without bringing it back. The Anvil image entrypoint symlinks
  `anvil` to the container-only `/nwn/home/anvil` whenever it is missing from
  `/nwn/run`; that is fine for `database`/`hak`/`tlk`/… and fatal for `anvil`.
  `bin/serve` now pre-creates it on every start and
  `bin/season-units.sh --install` refuses to render the unit against a symlinked
  layout — `bin/season-anvil-fix` repairs a season already in that state. Season
  2 shipped broken this way (guide §5a).
- `homers-lotr-server.service` is installed under `~/.config/systemd/user/` but
  **missing from the repo's `systemd/`** — commit it first, drop-in and all.
- `nwn-reboot.timer` (root, 03:03) stays **shared**; one OS reboot restarts every
  instance. Same for `roadmap-editor.service` — single instance (see item 11),
  run it from whichever repo you're editing.
- `bin/server-restart` and `bin/server-stop` hard-code
  `systemctl --user … homers-lotr-server.service` by literal name — the templated
  unit renames it, so both break. Have them derive the instance from the repo dir
  name (mirror how `bin/watch-server` reads `NWN_CONTAINER_NAME` from the local
  `server.env`), e.g. `systemctl --user restart "nwn-season-server@$(basename "$PROJECT_ROOT")"`.

- [x] Units templated; this instance starts and stops on its own unit
- [x] `server-restart`/`server-stop` resolve the right unit from the repo they live in

> **Built.** `nwn-season-{server,backup,wiki-publish,empty-restart}@.service`,
> installed by `bin/season-units.sh` (`--install` / `--enable` / `--remove`).
> Two things the plan did not anticipate:
>
> - The `.path` unit is **rendered, not templated**: `PathExists=` cannot expand
>   environment variables, and `NWN_RUN_DIR` is not derivable from `%i` because
>   season 1 keeps the legacy unnumbered run dir.
> - The repo's `systemd/` was missing `homers-lotr-server.service`, both
>   `priority.conf` drop-ins, and the backup unit's `ExecStartPost`. Those were
>   committed verbatim first, or templating would have dropped live config.
>
> `bin/season-unit.sh` resolves the unit from the repo a script lives in, and
> falls back to the legacy `homers-lotr-server.service` when the instance is
> not configured — which is what keeps the flip reversible. It tests for the
> instance **env file**, not `systemctl cat`: once the `@` template is
> installed, systemctl resolves *every* instance name against it, so `cat`
> succeeds for seasons that were never set up and the fallback never fires.
>
> Season 1 is now running on `nwn-season-server@nwn_homers_lotr.service`; the
> legacy units are installed but disabled. "Both instances" waits for a real
> Phase 1.

## 8. `bin/season-brand.py` (new)

Idempotent rebrand pass driven by the season block. Dry-run by default,
`--apply` to write, and a second `--apply` must produce **no diff**.

It rewrites every season-scoped reference in the module and hosting config:

| File | What |
|------|------|
| `unpacked/module.ifo.json` | Module description: `Connect: homerslotr.ddns.net:5121` and `Wiki: homerslotr.com` |
| `unpacked/npguide.dlg.json` | Guide NPC — two wiki links, one `…/manual/Customizations` |
| `unpacked/meritconv.dlg.json` | Merit NPC wiki link |
| `unpacked/servershout4.nss` | Login floaty text: `View the Wiki at homerslotr.com` |
| `index.html` (repo root) | **The wiki landing page** — hand-maintained, *not* generated from `unpacked/`; `nwn-wiki` only injects the header/footer around it. Carries the `Direct connect <host>:<port>` string **twice** plus a wiki link |
| `unpacked/thewelloferu.git.json` | `ru_sign` Description → `…/manual/Roadmap#shipped`; plus the two season placeables (item 9) |
| `src/index.js` | Worker redirect target for `*.workers.dev` |
| `wrangler.jsonc` | Worker `name` — **mandatory, not cosmetic**: two repos deploying the same worker name collide |
| `bin/roadmap-editor.py` | "Public wiki / Public roadmap" links, and its `nwnxee-homer` container-name fallback |
| `bin/watch-server` | `NWN_CONTAINER_NAME` default |
| `nasher.cfg` | `[package].name` and `[target].file` (item 6) |
| `server.env` | `NWN_MODULE`, `NWN_SERVERNAME` (item 6) |

`unpacked/module.jrl.json` currently needs no rebrand — its "Website" entry links
Discord only, and the Server Info entries say "wiki: Manual > Customizations"
with no host. Re-check it each cutover; it's the likeliest place for a new bare
URL to appear.

> **Never implement this as a blind `sed` over `unpacked/`.** `5121` occurs
> inside float coordinates in at least seven `.git.json` files
> (`"value": 54.5121`, `-22.5121`, …) and as a listen-pattern integer in
> `unpacked/roulette_os.nss`. A global port substitution silently moves
> placeables and breaks a conversation. Target the exact fields above, and touch
> the port **only** inside the `Connect:` line of the module description.

**Completeness check** — run this each cutover; every hit must be in the table
above or already parameterized:

```bash
grep -rIn "homerslotr\|5121\|nwnxee-homer\|/var/home/james/GIT/nwn_homers_lotr" \
     bin/ systemd/ src/ wrangler.jsonc nasher.cfg unpacked/
```

- [x] Script written, idempotence verified, completeness grep clean

> **Built** as `bin/season-brand.py` (dry-run default, `--apply`, `--check`,
> `--diff`). Every rule is **shape-matched** — any host in the homerslotr.com
> family, any string in the `"name"` field — rather than matched against a
> specific old value, so re-running re-matches what it just wrote. Two bugs
> worth remembering, both caught by testing against a scratch season-2 tree:
>
> - Rewriting `ru_sign`'s locstring wholesale dropped its StrRef **and eight
>   other-language strings**. It now edits language 0 in place; only the
>   StrRef-free season signs are replaced outright.
> - A bare `return "..."` regex for the container fallback matched
>   `server_tz()`'s `"America/Chicago"` first. Narrow rules are now scoped to a
>   named function's body.
>
> **A twelfth file was added during the season 1 -> 2 cutover: `index.html`,
> the wiki landing page.** It was missed because every other branded page under
> `docs/` is *generated* from `unpacked/`, so the completeness grep over
> `bin/ systemd/ src/ wrangler.jsonc nasher.cfg unpacked/` never looked at the
> repo root — and `docs/index.html` is a copy of a hand-maintained root
> `index.html` that `nwn-wiki` only wraps in a header/footer. Result: the
> early-access wiki greeted testers with `Direct connect homerslotr.ddns.net:5121`
> (the *live* season's port) in two places plus an apex wiki link. Worst possible
> page to be wrong on. **Widen the completeness grep to the repo root** when
> checking a future cutover.
>
> Acceptance met: a dry run against this repo, with the season block describing
> today's reality, reports **zero changes**. A scratch season-2/test tree fires
> all 11 files with correct content and a second `--apply` produces no diff.
> The completeness grep is clean; the only survivors are the seven float
> coordinates, `roulette_os.nss`, `NWN_MANAGER_BIN`, the legacy (disabled)
> units kept for rollback, and comments.

## 9. ~~The two season placeables~~ — RETIRED, superseded at the season 1 -> 2 cutover

**Do not build this. It was built, used once, and removed.** Kept here because
the reasoning is what a future cutover needs, and because the traps it uncovered
still apply to the thing that replaced it.

**The original design:** two purpose-built placeables in the Well of Eru — a
`season_status` sign whose text came from `SEASON_ROLE`, and a `season_peer`
cross-advert sign whose text came from a `SEASON_PEER_*` block — both placed once
and only ever re-texted by `season-brand.py`, hidden by an appearance swap to 157
(`plc_invisobj`) rather than deleted.

### What actually happened, and the rule that replaced it

Both were placed and all six states verified. Then the first real Phase 1 showed
the design was solving the wrong problem:

- The **outgoing** season is where the players are, and the notice it needs is
  one message, not two: "next season opens on <date>, here is the test port and
  password, your test progress will be wiped, here is what is new." That is a
  single board's worth of text.
- The **incoming** early-access realm needs no sign at all. Its wipe warning and
  merit-hold list belong in the **login script** (`servershout4.nss`), coloured
  with `COLOR_LIGHT_BLUE` from the `color` include so it reads as a different
  kind of message — every player sees it, unmissably, without walking to a
  placeable.
- And the outgoing season **already had** the perfect board: `recent_updates`,
  the Recent Updates sign. Once its season is winding down, a shipped-items feed
  matters less than the cutover notice.

> **The rule now: the OUTGOING season repurposes its own `recent_updates` board
> as the next-season notice. The incoming season gets a coloured login message.
> Neither season gets a new placeable.**

Repurposing is a `.git.json` edit on the `recent_updates` instance: set `LocName`
("Season <N> ending soon - examine me"), replace `Description` with the static
notice, and clear `Conversation` (`ru_sign`) and `OnUsed` (`ru_use`) so it is
examine-only instead of an interactive board. Leave `OnMeleeAttacked`
(`_attackplaceable`) — that is shared boilerplate, not board machinery.

### The traps, which still apply

- **StrRefs beat inline strings.** `recent_updates`'s `LocName`/`Description`
  carry StrRef ids **14561 / 14567**, and a non-`0xFFFFFFFF` `id` wins over the
  inline language-0 string in-game. Rewrite the locstring as `{"0": text}` with
  no `id`, or the sign renders CEP TLK text forever. (This is the same trap that
  made a verbatim `ru_sign` clone show `ru_sign`'s text.)
- **`season-brand.py` still owns one string on that board** — the
  `/manual/Roadmap#shipped` link inside `Description`. That rule is narrow (it
  rewrites only a URL matching that shape), so a repurposed description with no
  such URL is left alone and `--check` still passes. Do not widen it to a
  blanket rehost: a next-season notice legitimately contains
  `season<N+1>.homerslotr.com`, and a rehost would rewrite it to the *current*
  season's host and destroy the address.
- **GIT and GIC are index-parallel.** Deleting a placeable from
  `thewelloferu.git.json` means deleting the same index from
  `thewelloferu.gic.json`, or every later comment is attached to the wrong
  object. Verify equal list lengths after any such edit.
- Both signs reused the stock `plc_billboard7`, so **no blueprint and no palette
  filing were ever needed** — which also holds for anything else cloned from
  `ru_sign`.

### What was removed

`status_sign()`, `peer_sign()`, `SIGN_VISIBLE`/`SIGN_HIDDEN` and the sign loop in
`season-brand.py`'s `well()`; the `SEASON_PEER_*` block from `server.env` and its
validation in `season_config()`; and the two instances from season 2's Well of
Eru (replaced there by a copy of the **Ping Pong** PC-builder NPC, `butcha`, at
the freed spot). Season 1's two instances were left in place — already invisible
and inert once the rules were gone — to be dropped at its Phase 2 repack rather
than costing the live server a restart.

- [x] Built, used at the season 1 -> 2 cutover, then retired in favour of the rule above

## 10. `bin/roadmap-archive-prune.py` (new)

Run **only inside an archived season's repo**. Deletes every `ideas:` entry whose
`status` is not `awarded`, plus any `epics:` entry left with no children, then
runs `bin/gen-roadmap.py`. Dry-run by default.

Against today's `roadmap.yaml` that keeps **115** items and deletes **~500**
(`open` 294, `planned` 48, `done` 40, `implemented` 36, `later` 32, `soon` 16,
`answered` 9, `manual` 8, `design` 7, `wip` 6, `unlikely` 5). The deleted items
are not lost — they live on in the newest season's repo, which is where they will
actually get worked.

- [x] Script written; `gen-roadmap.py` still renders

> **Built** as `bin/roadmap-archive-prune.py`, guarded on `SEASON_ROLE=archive`
> (`--force` to override) — running it in the live/dev repo would delete the
> whole working backlog. It reuses the roadmap editor's comment-preserving
> `write_document()`; a plain `yaml.dump` would flatten every comment and
> reflow the `notes` block scalars.
>
> **The predicted split above is wrong.** The real numbers are **115 kept /
> 155 deleted out of 270 ideas**. The "~500" came from grepping `status:`
> across the whole file, which also counts the nested status fields on
> `design_questions` and `manual_steps` — `open` (294), `done` (40) and
> `answered` (9) are not idea statuses at all. The 115 figure is right.
> Verified on a scratch archive repo: 115 ideas + 2 epics, `meta`/`groups`/
> `players` and all header comments intact, `Roadmap.html` regenerated.

## 11. App-grid shortcuts — split dev from ops

The GNOME shortcuts under `~/.local/share/applications/nwn-homers-lotr-*.desktop`
(plus the autostart `homers-lotr-monitor.desktop`) all hard-code the unnumbered
repo or the shared `nwn_manager/bin` wrappers. Split them by purpose:

- **Dev shortcuts stay single** — unpack, repack, repack-clean, repack-test, wiki,
  refresh-nwsync (×2). You never rebuild a frozen archived season, so these
  correctly keep targeting the newest (unnumbered) repo. Nothing per-season.
- **Ops shortcuts are per-season** — `server-restart`, `server-stop`, and the
  monitor (`watch-server`). During the overlap two servers run, so each
  environment gets its own set: clone the three `.desktop` files with a
  season-labelled `Name=` (e.g. *"Restart Homer's LotR — Season 1 (archived)"*)
  and `Exec=` pointing at **that season's repo** `bin/`. The season these launch
  is implied by the repo path in `Exec`, so they need no arguments.

**Lifecycle** (referenced by the guide's phases): the ops set for a new
environment is created at **Phase 1** stand-up, and the retiring season's ops set
— plus its monitor autostart entry — is **deleted at Phase 3**. Dev shortcuts and
the roadmap editor are never touched; they already track the newest repo.

- [x] Ops shortcuts clonable per-season; dev shortcuts confirmed single

> **Built** as `bin/season-shortcuts.sh` (`--install` / `--remove`), rendering
> the three ops entries plus the monitor autostart from `server.env` with a
> season-labelled `Name=` and a repo-local `Exec=`. Season 1 keeps the existing
> unnumbered filenames; season 2+ get `-s<N>` ones, so both sets coexist during
> an overlap. Verified install/validate/remove in a sandboxed `HOME`.
>
> Season 1's shortcuts were deliberately **not** regenerated — relabelling them
> adds noise until a second season exists. Run `--install` at Phase 1.
>
> ### Reversed at the season 1 -> 2 cutover: the dev set is per-season too
>
> **"You never rebuild a frozen archived season" is false for the whole
> overlap.** At Phase 1 the *outgoing* season is the one copied out, and it keeps
> serving every player on 5121 — so `_s<N>` is the **live** server and is exactly
> the repo that may need an urgent hotfix (guide §5a says as much). It is frozen
> by policy, not by circumstance, and it had **no dev shortcuts at all**.
>
> The mirror-image problem is worse: the unnumbered repo's dev shortcuts silently
> *changed meaning* at Phase 1. "Repack Homer's LotR Module" stopped building the
> live server and started building the early-access realm, with nothing in the
> label saying so. Eight unlabelled buttons pointing at a test realm, and no way
> to rebuild live.
>
> So `bin/season-shortcuts.sh` now renders **11 entries per season** — the four
> ops entries plus a per-season `NWN Logs`, plus the seven dev entries (unpack,
> repack, repack-clean, repack-test, wiki, nwsync, nwsync-force) — every one
> season-labelled. The eight legacy unlabelled entries were deleted. Three
> details worth keeping:
>
> - The `nwn_manager` wrappers are driven with `--project`, but
>   **`nwn_manager/bin/refresh-homers-lotr-wiki` still hard-codes the unnumbered
>   repo and has no `--project`** (item 4 fixed only the *repo-local* copy). The
>   wiki entry therefore calls `$PROJECT_ROOT/bin/refresh-homers-lotr-wiki`.
>   Same for `refresh-nwsync`. Both derive `PROJECT` from `BASH_SOURCE`.
> - The logs entry opens **`$NWN_RUN_DIR/logs.0`**, not the home dir. The old
>   `nwn-logs.desktop` opened `$NWN_HOME_DIR/logs`, which holds a couple of stale
>   files and does not exist at all in a fresh season's home dir.
> - Paths inside the `bash -lc '…'` wrapper are double-quoted; writing
>   `--project '$PROJECT_ROOT'` closes and reopens the single quote and only
>   works by luck while no repo path contains a space.
>
> ### 2026-08-14: the monitor autostart is no longer per season
>
> `season-shortcuts.sh` now renders **10** entries — the per-season monitor
> **autostart** entry is gone. It never worked: gnome-session fires XDG autostart
> before `xdg-desktop-portal` owns its bus name, ptyxis needs the portal, and
> every boot logged `Failed to register: Timeout was reached` (ptyxis even dumped
> core), so the monitors had to be started by hand after each reboot. Three
> simultaneous `ptyxis --new-window` calls at t+0 also raced to be the primary
> instance.
>
> Replaced by **one cross-realm window**: `bin/watch-all-servers` interleaves
> every realm's container log into a single colour- and tag-prefixed stream,
> launched at login by `systemd/nwn-monitor-all.service` (ordered after
> `xdg-desktop-portal.service` *and* waiting on its bus name), installed by
> `bin/monitor-all-shortcut.sh --install`. It belongs to no season, lives only in
> the unnumbered dev repo, and **no cutover phase creates or retires it** — the
> Phase 3 step is now "delete the retired season's ops/dev tiles", full stop.
>
> The per-season **app-grid** monitor tile stays: watching one realm on its own
> is still often what you want. `$MONITOR_AUTO` stays in `OPS_FILES` so
> `--remove` still cleans up any stale pre-2026-08-14 autostart file.

## 12. Roadmap editor stays single-instance (no work — a guard note)

`systemd/roadmap-editor.service` has `WorkingDirectory` = the unnumbered repo,
which is **always** the newest/dev season. So the one editor instance already
follows the live backlog, and its "Publish to Wiki & DB" writes that repo's
`docs/` + `roadmapdb`. **Do not instance it per season** — there is one backlog,
ever. The archived season's roadmap is frozen once at Phase 2 by
`bin/roadmap-archive-prune.py` (item 10) and the editor never reopens it.

- [x] Confirmed: no per-season editor; `WorkingDirectory` stays on the unnumbered repo

> **Confirmed.** `systemd/roadmap-editor.service` was deliberately left out of
> the `@`-templating in item 7, and `bin/season-units.sh` does not touch it.

## 13. The Cloudflare build connection lives outside the repo (a guard note)

No engineering — a fact worth recording, because it is the one piece of cutover
state that no script owns and no build gate can catch.

The wiki is deployed by **Workers Builds via the Cloudflare GitHub App**
(the `cloudflare/workers-autoconfig` branch on the origin repo is the bot's), and
that connection binds a Worker to a **GitHub repository**, not to a directory
here. `season-brand.py` rewrites `wrangler.jsonc`'s worker `name`, but it cannot
touch which repo Cloudflare builds from — so at Phase 1, when the original GitHub
repo stops being the live season, the connections must be re-pointed by hand in
the dashboard, **before the re-parameterized repo is pushed**. Publishing is
unattended (`serve --auto-publish`, `nwn-season-wiki-publish@`), so getting the
order wrong deploys the early-access wiki onto the apex on its own.

Ordered procedure: guide §5.7. Git-side topology, remotes and the hotfix
cherry-pick flow: guide §5a.

- [x] Recorded (no code)

> **Possible follow-up, not built:** a gate asserting `SEASON_WORKER_NAME` ==
> `wrangler.jsonc`'s `name`, the way `tests/check_season_brand.py` covers the
> rest of the branded surface. It would catch a hand-edit, but not the thing that
> actually bites — the dashboard-side repo binding, which nothing local can see.

---

## Rehearsal before the first real Phase 1

Do this on a throwaway copy — it exercises almost everything above without
touching a live server:

1. `cp -a` the repo to a scratch path; point its `server.env` at a scratch home
   dir, port 5123, `SEASON_ROLE=test`.
2. `bin/season-brand.py` (dry-run, then `--apply`); confirm a repack succeeds and
   a **second `--apply` produces no diff**.
3. `bin/roadmap-archive-prune.py --dry-run` on a copy of `roadmap.yaml`.
4. Merit symlink drill: create a scratch `database/` with a symlink in it, run the
   Phase 2 `find … ! -name 'meritdb.sqlite3' ! -name 'admindb.sqlite3' -delete`,
   confirm both target files survive.
5. Start the scratch server alongside the live one and confirm no port, container
   or run-dir collision.
6. `python3 tests/check_manual_menus.py` plus the standard repack gates after any
   `unpacked/` change.
7. **Git drill** (guide §5a) on the scratch copy: rename `main`, `checkout
   --orphan main`, commit, and confirm `git diff --stat HEAD` is empty and
   `git remote -v` / `git config branch.main.remote` show the *new* target. Then
   `git fetch dev && git cherry-pick <sha>` a commit from the real repo to prove
   a hotfix crosses the orphan cut. Do **not** create a real GitHub repo.
