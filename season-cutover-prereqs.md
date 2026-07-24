# Season Cutover — one-off prerequisite work

Companion to [season-cutover-guide.md](season-cutover-guide.md). **That** file is
the per-season runbook, re-run every 3–4 months. **This** file is the one-time
engineering that makes the runbook possible: build it once, and every future
cutover is a checklist rather than a project.

Items 1–2 touch live player data and must be finished before the first Phase 1;
items 2b–12 are tooling and can land any time before it.

> **Status: all twelve items are done** (2026-07-24). What follows is kept as
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
> - The season placeables need **no new blueprint** and no palette filing: they
>   reuse `plc_billboard7`, exactly as `ru_sign` does.
> - Hiding a sign is an appearance swap (157 `plc_invisobj` + `Static` +
>   not useable), which keeps the whole thing declarative in the `.git.json`.
> - A **`live` peer state** was added. The item-9 table covers `test`/`archive`/
>   `none`, but Phase 1 sets `SEASON_PEER_ROLE=live` on the new season's repo.
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

# The OTHER running instance, for the in-game cross-advert placeable.
SEASON_PEER_ROLE=live        # live | test | archive | none
SEASON_PEER_NUM=1
SEASON_PEER_PORT=5121
SEASON_PEER_PASSWORD=""      # the peer's player password, if it has one
```

`SEASON_PEER_PASSWORD` sits in `server.env` (committed) rather than
`server.env.local` **on purpose**: it is a password the module *advertises to
every player on a sign*, so it is not a secret. This is not an exception to the
"no secrets in `unpacked/`" rule in `CLAUDE.md` — that rule is about CD keys and
admin credentials, which still never appear in source or in the packed `.mod`.

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

## 5. `repack-homers-lotr` — make it per-season

**Lives in the `nwn_manager` repo** (`GIT/nwn_manager/bin/repack-homers-lotr`),
not here, and hard-codes six season-scoped values:

- `PROJECT=/var/home/james/GIT/nwn_homers_lotr`
- the build artifact `homers_lotr_v3.mod` (eight occurrences)
- the OneDrive copy dir `$HOME/OneDrive/Games/NWNHomersLOTR`
- the production install path `$HOME/.local/share/Neverwinter Nights/modules`
- **the installed module filename `Homer's LOTR VEL v3.mod`** — this is what
  `NWN_MODULE` must match (see item 6)
- the timestamped archive prefix

Rework it to source the target repo's `server.env` + `nasher.cfg` and derive all
six, so one script serves every season. Same for `repack-homers-lotr-clean`.
Until then, each new season needs a hand-edited clone — workable, but it is the
single most error-prone step in Phase 1.

- [x] Parameterized

> **Built** in `nwn_manager`: new `bin/repack-project.sh` resolves all six
> values from the target repo's `nasher.cfg` (`[target].file`) and `server.env`
> (`NWN_MODULE`, `NWN_HOME_DIR`); `repack-homers-lotr` and `-clean` source it
> and gain `--project DIR` (also `$NWN_PROJECT`) plus `--show-config`. The
> default stays the unnumbered repo, so the app-grid shortcuts are unchanged.
> Verified by an actual repack: installed to `homers_lotr_v3.mod` ->
> `Homer's LOTR VEL v3.mod`, exactly as before.

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
> Acceptance met: a dry run against this repo, with the season block describing
> today's reality, reports **zero changes**. A scratch season-2/test tree fires
> all 11 files with correct content and a second `--apply` produces no diff.
> The completeness grep is clean; the only survivors are the seven float
> coordinates, `roulette_os.nss`, `NWN_MANAGER_BIN`, the legacy (disabled)
> units kept for rollback, and comments.

## 9. The two season placeables

Both go in the Well of Eru (`thewelloferu.git.json`), both are placed **once** and
then only have their text changed by `season-brand.py` — so no season ever has to
edit a `.git.json` by hand.

Mirror the existing `ru_sign` placeable in that file: `__struct_id: 9`,
Appearance 89, text carried in `Description`. Use `bin/place-helper.py` to pick
coordinates and follow the GIT-instance rules in `CLAUDE-blueprints.md` (correct
struct id, and `X`/`Y`/`Z`/`Bearing` for placeables — *not* `XPosition`/
`Orientation`). After adding the blueprints run
`python3 bin/file-palette-orphans.py --apply`.

**(a) Season status sign** — states driven by `SEASON_ROLE`:

| Role | Text |
|------|------|
| `test` | *"EARLY ACCESS — Season N. This is a testing realm. Your characters, gear and progress here will be **wiped** when this season goes live. Merit you earn still counts."* |
| `archive` | *"Season N has ended. This realm is no longer updated or maintained. The current season is live on port 5121."* |
| `live` | hidden |

**(b) Cross-advert sign** — states driven by `SEASON_PEER_*`, so the *live*
season can point players at whatever is running in the alternate slot:

| Peer role | Text |
|-----------|------|
| `test` | *"Season N+1 EARLY ACCESS is now open — same server address, **port 5122**, password `volatile`. Come help test the new season. Progress there will be wiped at go-live; merit earned still counts."* |
| `archive` | *"Season N is still playable on port 5122, archived and unmaintained. Its wiki lives at season\<N\>.homerslotr.com."* |
| `none` | hidden |

Hide by clearing visibility/usability rather than deleting the instance, so the
same two placeables serve every future season.

- [x] Both placed once, all six states render

> **Built** — and **no blueprint and no palette filing were needed**: like
> `ru_sign`, both instances use the stock `plc_billboard7`. Placed at
> (21.5, 15.4) and (28.5, 15.4), flanking the Recent Updates sign, both
> verified clear with `bin/place-helper.py`.
>
> The clone trap: `ru_sign`'s `Description`/`LocName` carry StrRef ids
> (14567 / 14561), and a non-`0xFFFFFFFF` StrRef wins over the inline string —
> a verbatim clone would render `ru_sign`'s text forever. The season signs are
> created StrRef-free.
>
> "Five states" is really **six**: a `live` peer state was added (see
> deviations). All six verified, plus every hide/show transition.

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
