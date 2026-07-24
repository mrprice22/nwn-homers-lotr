# Season Cutover — one-off prerequisite work

Companion to [season-cutover-guide.md](season-cutover-guide.md). **That** file is
the per-season runbook, re-run every 3–4 months. **This** file is the one-time
engineering that makes the runbook possible: build it once, and every future
cutover is a checklist rather than a project.

Nothing here is done yet unless its box is ticked. Items 1–2 touch live player
data and must be finished before the first Phase 1; items 3–10 are tooling and
can land any time before it.

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

**Player impact, once:** saved teleport *slots* reset. Teleport *unlocks* are
merit redemptions 101–107 living in `meritdb.redemptions`, keyed by CD key — they
are untouched. Repack, deploy, announce the slot reset.

- [ ] `tele_db.nss` edited, repacked, deployed, announced

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

**Backup follow-through:** `~/.local/share/nwn-shared/` is now the home of two
irreplaceable files that no season's own backup captures (each season sees them
only as symlinks, which a sane backup won't follow). Add the shared dir to the
backup set from **exactly one** place — gate it on `SEASON_ROLE=live` in
`bin/backup-homers-lotr` so only the live season snapshots it, and so two running
seasons never race the same copy. Both files are single SQLite files written by
up to two servers at once; SQLite handles the concurrency, but the backup must
not.

- [ ] Both moved, symlinked, verified; server restarts, admin menus + merit both work
- [ ] `nwn-shared/` added to exactly one backup path, gated on `SEASON_ROLE=live`

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

- [ ] Block added to `server.env`, documented in `README.md`

## 4. De-hard-code `bin/refresh-homers-lotr-wiki`

The only wrapper in this repo that isn't relocatable. It pins:

| Line | Hard-coded | Should be |
|------|-----------|-----------|
| ~24 | `PROJECT=/var/home/james/GIT/nwn_homers_lotr` | derived from `BASH_SOURCE` — copy the idiom in `bin/serve` |
| ~46 | `--base-url https://homerslotr.com/` | `$SEASON_WIKI_URL` |
| ~46 | `--log-dir "$HOME/.local/state/nwnxee-homer"` | `$NWN_RUN_DIR` |

`bin/serve` and `bin/backup-homers-lotr` already compute `PROJECT_ROOT`
correctly and need no change.

- [ ] Rewritten; a copy of the repo at another path regenerates its own wiki

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

- [ ] Parameterized (or: clone-per-season accepted and documented)

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

- [ ] Convention agreed and recorded in `README.md`

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
  instance. Same for `roadmap-editor.service` — single instance, run it from
  whichever repo you're editing.

- [ ] Units templated; both instances start and stop independently

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

- [ ] Script written, idempotence verified, completeness grep clean

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

- [ ] Both blueprints created, placed once, palette-filed, all five states render

## 10. `bin/roadmap-archive-prune.py` (new)

Run **only inside an archived season's repo**. Deletes every `ideas:` entry whose
`status` is not `awarded`, plus any `epics:` entry left with no children, then
runs `bin/gen-roadmap.py`. Dry-run by default.

Against today's `roadmap.yaml` that keeps **115** items and deletes **~500**
(`open` 294, `planned` 48, `done` 40, `implemented` 36, `later` 32, `soon` 16,
`answered` 9, `manual` 8, `design` 7, `wip` 6, `unlikely` 5). The deleted items
are not lost — they live on in the newest season's repo, which is where they will
actually get worked.

- [ ] Script written; dry-run reports the expected split; `gen-roadmap.py` still renders

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
