# Homer's LOTR VEL v3

Source-form mirror of the Neverwinter Nights 1 module **Homer's LOTR VEL v3**,
unpacked for git tracking and LLM-assisted editing.

The original `.mod` is a binary ERF archive (~68 MB, ~7280 resources). This
project keeps each resource as a plain-text file under `unpacked/` — GFFs as
JSON, scripts as `.nss` source — so changes diff cleanly and an LLM can read
or modify them directly.

## Layout

```
nasher.cfg       build-target definition (output filename, source patterns)
unpacked/        the source tree — JSON + .nss (committed)
.nasher/source   path of the .mod to unpack/install (per-machine, gitignored)
dist/            build output (gitignored)
wiki/            generated HTML wiki (gitignored)
.nasher/         nasher's working cache (gitignored)
```

## Round-trip workflow

Driven by `nwn-manager` from the [nwn_manager](../nwn_manager/README.md)
project:

```sh
nwn-manager unpack       # NWN/data/mod/Homer's…v3.mod  →  unpacked/
# ... edit JSON / .nss in unpacked/, commit to git ...
nwn-manager repack       # unpacked/  →  dist/  →  NWN/data/mod/Homer's…v3.mod
nwn-manager wiki         # unpacked/  →  wiki/index.html (multi-page HTML wiki)
# ... open the module in the NWN:EE toolset or run it ...
```

`unpack` overwrites whatever is currently in `unpacked/`; `repack` overwrites
the `.mod` in NWN's modules folder. Source of truth is `unpacked/` + git, not
the `.mod`. The wiki is regenerated only on explicit `nwn-manager wiki`.

## Source `.mod` path

The path to the installed `.mod` is recorded in `.nasher/source` (gitignored,
per-machine). It points at:

```
/home/james/Link to Neverwinter Nights/data/mod/Homer's LOTR VEL v3.mod
```

`nwn-manager` sanitizes the path through `/tmp` before invoking `nwn_erf`,
so the apostrophe in the filename is no longer an issue.

## Wiki

A browsable reference for all areas, creatures, items, quests, and scripts is
published at:

**<https://homerslotr.com/index.html>**

The wiki is generated from `unpacked/` via `nwn-manager wiki` and deployed
separately; the `wiki/` directory is gitignored.

## Bestiary & creature-kill tracking

Every creature kill is recorded per **character** (identity = `GetObjectUUID`,
which persists in the `.bic`, so duplicate character names don't collide) in the
`bestiarydb` campaign SQLite database (`<NWN_HOME_DIR>/database/bestiarydb.sqlite3`
— the filename always matches the campaign DB name `BST_DB="bestiarydb"`).

- **Solo vs Party** — a kill is counted as *Party* when more than one PC dealt
  damage to the creature, otherwise *Solo*. Every PC who contributed damage is
  credited (their summons/henchmen count for them via the master chain).
- **Combat-log confirmation** — after each kill, every contributor gets a message
  with their running total for that creature and whether it was Solo or Party.
- **Server First** — the first server-wide kill of any creature with Challenge
  Rating ≥ 60 is recorded and broadcast to everyone online.
- **In-game Bestiary** — players receive the **Bestiary of Middle-earth** book
  (`bestiarybook`, granted on entering the Well of Eru) and *activate* it to open
  a conversation listing creatures **slain** and **not yet slain**, each paged and
  sorted by descending CR.
- **Wiki** — the creatures index gains Kills/Solo/Party columns, each creature
  page shows a kill block and a Server-First badge, and a generated **Server
  Firsts** leaderboard appears under the Documents menu.

How it works (no per-creature edits): a single OnDamaged/OnDeath **wrapper** is
installed on every creature at spawn/area-entry (`bst_install`), which records the
kill then chains the creature's original handlers (loot, alignment, respawn are
preserved). Core files: `bst_db.nss` (DB helpers), `bst_install` / `bst_ondamage`
/ `bst_ondeath`, the `bst_*` menu scripts, `bestiarybook.uti.json`, and the
`bst_book.dlg.json` conversation (dispatched from `dmfi_activate.nss`).

The wiki seeds the full creature catalogue into the live DB and reads kill stats
from it; because the server runs in a container, the wiki is pointed at the real
DB dir with `--db-dir` (see `refresh-homers-lotr-wiki`), not `--log-dir`.

## Donations Chest sync

The Well of Eru area stocks a Donations Chest on each server reset with random
bonus items from a pool of obtainable custom items. Items that turn out to be
unobtainable are tracked on an "illicit" list — players who hold them have them
reclaimed and are refunded 5× gold. After store or loot fixes, previously illicit
items may become legitimately accessible and should be returned to the bonus pool.

The sync script automates this:

```sh
nwn-manager wiki                      # rebuild module-index/ (always do this first)
python3 bin/sync_donations.py         # graduate accessible items back to bonus pool
nwn-manager repack                    # compile and install
```

Use `--dry-run` to preview changes without writing:

```sh
python3 bin/sync_donations.py --dry-run
```

The script only removes items from the illicit list (when they become accessible);
it never adds new ones. The managed data lives in `unpacked/_inc_donations.nss`,
which is included by `unpacked/welloferuenter.nss`. Do not hand-edit
`_inc_donations.nss` — run the sync script instead.

If a graduated item is ammunition and should give a stack of 99, add its case
number to the `GetBonusItemStackSize` switch in `_inc_donations.nss` manually
after the sync run.

## Forge legal-variant whitelist

The Forge contraband system (`unpacked/forge_inc.nss`) jails players who carry
items that exceed the legal caps (6 properties / 750,000 gp) **and** deviate
from their stock blueprint. But the module legitimately places many such items:
stores, creature loot, and containers embedded in area files carry full item
structs whose properties differ from the `.uti` blueprint of the same resref
(see `module-index/item_tag_conflicts.json`). Without a guard, a player who
buys or loots one of those would be jailed for a crime they didn't commit.

The whitelist closes that gap: a generator scans `unpacked/` for every embedded
item variant that deviates from (or lacks) a module blueprint and writes
`unpacked/forge_legal_inc.nss`, which `ForgeIsItemIllegal` consults before
jailing. Matching is by resref **plus a full property fingerprint**, so forging
extra enchantments onto a whitelisted item still gets caught.

```sh
python3 bin/gen-forge-legal.py    # regenerate unpacked/forge_legal_inc.nss
nwn-manager repack                # compile and install
```

Use `--dry-run` to preview the entries without writing. Re-run the generator
whenever store inventories, creature loot, or placed container items are added
or edited, and commit the regenerated include — it is module source, not a
build artifact. Do not hand-edit `forge_legal_inc.nss`.

**Fallback for false positives:** a jailed player can dispute the charge in
the Forge Warden conversation. The contested item is sequestered (no refund)
into the DM-review chest in the House of Homer (tag `ZEP_CR_QUARANTINE`, the
same chest the Well of Eru's illicit-item scan uses), with a `[FORGE DISPUTE]`
log line recording the account, character, item resref, and value. A DM
returns the item if the claim holds. If a dispute turns out to be a genuine
false positive, fix it permanently by re-running the generator (or
investigating why the fingerprint didn't match — see the normalization notes
in `bin/gen-forge-legal.py`).

## Appraise-scaled merchants & forge ceilings

A character's **Appraise** skill gives two persistent economy benefits, both
driven by the shared helper `unpacked/appraise_inc.nss`:

- **Merchants** pay more for items you sell — up to **+100% (double)** the
  store's max buy cap.
- **Forges** (see [Forge legal-variant whitelist](#forge-legal-variant-whitelist))
  let you enchant an item to a higher gold value — up to **+500,000 gp** above
  the tier ceiling.

The skill is read as a deterministic **"take 20"** (`AppraiseCheck` =
`20 + GetSkillRank(SKILL_APPRAISE, oPC)`, never a d20 roll). `AppraiseBonusScaled`
returns 0 below check 21 (so a character with no Appraise investment is no better
off than the module defaults — they need at least one rank, a +1 Charisma
modifier, or an Appraise item), then scales linearly to the full bonus at check
65 (`APPRAISE_FULL_CHECK`).

### Merchant buy-cap scaling

The lever is each store's **MaxBuyPrice** — the cap on the gold it will pay for
any single item. That cap lives on the (shared) store object, so it can't be
scaled per-player in place without leaking one player's Appraise bonus to anyone
else shopping the same store. Instead, `unpacked/store_appr_inc.nss` opens a
**throwaway copy** of a capped store, scales the copy's `MaxBuyPrice` for the
opening player, and destroys it on close:

- `OpenStoreAppr(oStore, oPC, bAppraisePricing = FALSE)` — copies the live store
  (`CopyObject`, carrying its current inventory + `OnOpenStore`), raises the
  copy's cap by `AppraiseBonusScaled(oPC, baseCap)`, opens the copy, and queues
  it for destruction.
- `unpacked/store_appr_cls.nss` is the copy's `STORE_ON_CLOSE` handler — it
  destroys the copy as soon as the player closes it (a delayed fallback covers a
  missed close, e.g. a disconnect).
- Uncapped stores (`MaxBuyPrice == -1`) open directly with **no copy** — there is
  no cap to scale.

### Wiring a new merchant

Merchant stores are opened from small "opener" scripts (typically wired to an
NPC conversation node) that look up the store by tag and call `OpenStore`. To
give a new merchant the Appraise buy-cap bonus:

1. **Give the placed store a finite buy cap.** Set **Max Buy Price** to a
   non-`-1` value on the *placed store instance* (in the toolset, or the area's
   `.git.json` StoreList — the instance overrides the `.utm` blueprint). This
   value is the "unfavorable reaction" baseline that Appraise scales up from.
   A store left at `-1` (no limit) gets no bonus (nothing to scale).
2. **Call the wrapper instead of `OpenStore` in the opener:**

   ```nss
   #include "store_appr_inc"
   void main()
   {
       object oStore = GetNearestObjectByTag("MY_STORE_TAG");
       if (GetObjectType(oStore) == OBJECT_TYPE_STORE)
           OpenStoreAppr(oStore, GetPCSpeaker());        // plain open
   }
   ```

   If the opener previously used `gplotAppraiseOpenStore` (the stock
   Appraise-priced open), pass `TRUE` as the third argument to preserve that
   pricing on top of the cap scaling:

   ```nss
   OpenStoreAppr(oStore, GetPCSpeaker(), TRUE);          // keep stock appraise pricing
   ```

3. **Leave non-buying merchants alone.** A store that buys nothing from players
   needs no change — the cap is irrelevant. (The wrapper is harmless on such
   stores, but there's no reason to add it.)

The bulk swap of the existing ~104 openers was mechanical: plain `OpenStore(o,
GetPCSpeaker())` → `OpenStoreAppr(o, GetPCSpeaker())`, and
`gplotAppraiseOpenStore(o, GetPCSpeaker())` → `OpenStoreAppr(o, GetPCSpeaker(),
TRUE)`, adding `#include "store_appr_inc"`. Two subsystems were deliberately
**not** converted because they manage their own pricing: the Bedlamson Dynamic
Merchant (`bdm_cnv_opn_stor.nss`, persuade-based haggling) and the thief fence
(`bdm_cnv_steal.nss`).

After adding or editing an opener, recompile (`nwn-manager repack`).

## Roadmap & merit backlog

`roadmap.yaml` is the source of truth for the public dev roadmap and the
merit-tracking backlog — shipped player ideas credit a submitter with Merit.
Edit it (by hand or with the GUI editor), then
`python3 bin/gen-roadmap.py` and `bin/refresh-homers-lotr-wiki` to publish.

To avoid typos in the controlled fields (player names, group ids, statuses,
`dupe_of`), use the local web editor:

```sh
python3 bin/roadmap-editor.py          # opens http://localhost:8765
```

It validates with `gen-roadmap.py`'s own checks before writing and only
rewrites the `ideas:` block, leaving the rest of the file untouched. It can run
on boot as a systemd user service (`systemd/roadmap-editor.service`).

See **[CLAUDE-roadmap.md](CLAUDE-roadmap.md)** for the full schema, the refresh
process, and the editor + service setup.

## Redemption codes

Players redeem codes by typing `Code:<name>` in chat (any channel). The
handler is `unpacked/code_redeem.nss`, wired to `Mod_OnPlrChat`. Matching is
case-insensitive; the chat line is suppressed so the code doesn't broadcast
to other players.

Each redemption is keyed on the player's CD key, so a code can be used at
most once per CD key. Redemptions live in the NWN:EE campaign SQLite
database `coderedeem` (`<server>/database/coderedeem.sqlite3`), table
`redemptions(code, cdkey, redeemed_at)`.

Players see one of:

- **Unknown redemption code.** — the code name isn't defined.
- **That code has expired (was valid until YYYY-MM-DD).** — past expiration.
- **You have already redeemed that code.** — this CD key already used it.
- **Code redeemed successfully!** — reward applied.

### Adding a new code

Edit `unpacked/code_redeem.nss` and add a case in **both** functions:

```nwscript
// Expiration (UTC date, YYYY-MM-DD; "" = unknown code).
string GetCodeExpiration(string sCodeLower)
{
    if (sCodeLower == "freelegendary") return "2026-07-01";
    if (sCodeLower == "mynewcode")     return "2026-12-31";  // ← add
    return "";
}

// Reward.
int ApplyCodeBenefit(string sCodeLower, object oPC)
{
    if (sCodeLower == "freelegendary") { SetXP(oPC, 17498600); return TRUE; }
    if (sCodeLower == "mynewcode")     {                                    // ← add
        CreateItemOnObject("some_item_resref", oPC, 1);
        return TRUE;
    }
    return FALSE;
}
```

Code names in the script must be **lowercase** (the handler lowercases
incoming chat before matching). Advertise them in any case you like —
`Code:MyNewCode`, `code:mynewcode`, etc., all work.

Then `nwn-manager repack` to compile and install.

### Changing or removing an expiration

Edit the date string in `GetCodeExpiration()`. Comparison is `date('now') >
expiration`, so a code with expiration `2026-07-01` stops working on
`2026-07-02` (server time). To make a code permanent, set the expiration to
a far-future date like `9999-12-31`.

To pull a code immediately, set its expiration to a past date or remove its
case from `GetCodeExpiration()` (returning `""` makes it report "Unknown
redemption code.").

### Resetting / inspecting redemptions

Use any SQLite client against `<server>/database/coderedeem.sqlite3`:

```sh
sqlite3 coderedeem.sqlite3 'SELECT * FROM redemptions;'
sqlite3 coderedeem.sqlite3 "DELETE FROM redemptions WHERE code='freelegendary';"
```

Deleting a row lets that CD key redeem the code again.

## Four-class multiclassing

NWN:EE patch 8193.35 added engine support for up to 8 classes. This module
enables a cap of **4 classes** via a server-side `ruleset.2da` override — no
hak changes needed, because `ruleset.2da` is resolved from the server override
folder before any hak and is not distributed to clients via nwsync.

### Current state

- `lotr_rules.hak` — custom hak containing `ruleset.2da` with `MULTICLASS_LIMIT 4`.
  Listed first in `Mod_HakList` (highest hak priority) so it wins over any
  `ruleset.2da` shipped by CEP. nwsync distributes it to clients automatically
  on connect — no manual client-side steps needed.
- `~/.local/share/Neverwinter Nights/override/ruleset.2da` — same file in the
  server override folder, so the server itself also sees `MULTICLASS_LIMIT 4`.
- 11 scripts updated in `unpacked/` to handle a 4th class position:
  `pers_state_inc.nss`, `hgll_featreq_inc.nss`, `bdm_include.nss`,
  `x0_i0_spells.nss`, `my_charfuncs.nss`, `dmfi_dmw_inc.nss`,
  `dmw_func_inc.nss`, `j_inc_generic_ai.nss`, `nw_i0_generic.nss`,
  `nw_o2_coninclude.nss`, `sd_filter_inc.nss`

### Rebuild from scratch (new machine / fresh NWN install)

1. Extract the base `ruleset.2da` from the NWN data files:
   ```sh
   mkdir -p /tmp/nwn_2da
   NWN="$HOME/.local/share/Steam/steamapps/common/Neverwinter Nights"
   ~/.nimble/bin/nwn_resman_extract --root "$NWN" \
     --userdirectory "$HOME/.local/share/Neverwinter Nights" \
     -p "ruleset" -d /tmp/nwn_2da
   ```
2. Edit the extracted file — find the `MULTICLASS_LIMIT` row and change `3` to `4`:
   ```
   519  MULTICLASS_LIMIT                                 4
   ```
3. Build the hak and install it. The live `lotr_rules.hak` contains **both**
   `ruleset.2da` and `baseitems.2da` (the latter holds the module's custom item
   stack sizes — ammo 999, potions/scrolls 99 — tracked in git at
   `hak_2da/baseitems.2da`). Pack both, or a from-scratch rebuild silently drops
   those customizations:
   ```sh
   mkdir -p /tmp/lotr_rules_hak
   cp /tmp/nwn_2da/ruleset.2da /tmp/lotr_rules_hak/
   cp hak_2da/baseitems.2da    /tmp/lotr_rules_hak/
   ~/.nimble/bin/nwn_erf -c -f /tmp/lotr_rules.hak -e HAK \
     /tmp/lotr_rules_hak/ruleset.2da /tmp/lotr_rules_hak/baseitems.2da
   cp /tmp/lotr_rules.hak \
     "$HOME/.local/share/Neverwinter Nights/hak/lotr_rules.hak"
   ```
4. Copy the 2da into the server override folder too (server-side enforcement):
   ```sh
   cp /tmp/nwn_2da/ruleset.2da \
     "$HOME/.local/share/Neverwinter Nights/override/ruleset.2da"
   ```
5. Run `bin/refresh-nwsync` so clients receive the new hak (incremental — see
   [Updating a hak / refreshing nwsync](#updating-a-hak--refreshing-nwsync)). A
   `.mod` repack is only needed if module content under `unpacked/` also changed.

### Rolling back to 3 classes

1. Remove the hak from `Mod_HakList` in `unpacked/module.ifo.json` (delete the
   `lotr_rules` entry).
2. Delete the server override: `rm ~/.local/share/Neverwinter Nights/override/ruleset.2da`
3. Repack and refresh nwsync. Clients will drop the hak on next connect.
4. **Scripts:** The 11 script changes are backward-compatible for 1–3 class
   characters (the extra loop iterations hit `CLASS_TYPE_INVALID` and
   short-circuit). Reverting them is optional; `git revert` the relevant commit
   if you want exact parity with the original.

## Updating a hak / refreshing nwsync

Clients receive the haks + `cep.tlk` the module references through an **nwsync**
repository served by nginx (`bin/serve-nwsync`). After changing any hak, publish
it with:

```sh
bin/refresh-nwsync          # rebuild the manifest; incremental — only changed
                            # resources are hashed, compressed and written
```

Key points:

- **Incremental by default.** The nwsync repo
  (`~/.local/share/Neverwinter Nights/nwsync/HomersLOTR`, ~1.9 GB) is a
  content-addressed store keyed by per-resource SHA1. A routine refresh reuses
  every blob that already exists and writes only what actually changed, then
  publishes a fresh manifest. Editing one 2DA inside `lotr_rules.hak` writes a
  single new blob — it does **not** reprocess the ~8 GB of CEP haks. The first
  run after a clean/empty repo is still a full bootstrap; later runs are fast.
- **A hak-only change does not need a `.mod` repack.** Install the updated hak
  into `~/.local/share/Neverwinter Nights/hak/`, then run `bin/refresh-nwsync`.
  (The `.mod` is only read to discover its hak/tlk dependency list.) A repack is
  only needed when module content under `unpacked/` changed.
- **No nginx bounce.** The repo is updated in place, so the live nginx mount
  keeps serving; `refresh-nwsync` just ensures the container is up. Clients pick
  up the new manifest via the `no-cache` `/latest` pointer on next connect.

Flags:

| Flag | Effect |
|------|--------|
| `--silent` | Quiet spinner instead of full nwsync output. |
| `--force`  | Re-add nwsync's `-f` to rewrite **all** blobs even if identical. Slow (~full rebuild); use only to recover from a suspected-corrupt repo. |
| `--prune`  | After writing, run `nwn_nwsync_prune` to garbage-collect orphaned blobs from superseded manifests (self-protects data < 2 weeks old). Safe to run occasionally — e.g. monthly — not needed every refresh. |

## Area leashing (creatures locked to spawn area)

Players must not be able to lead a creature — especially a boss — out of its home
area and across the module to fight other bosses (an exploit). To prevent this,
**every non-associate creature is locked to the area it spawned in**: if it ends
up in any other area it is teleported straight back to its spawn point. No
heartbeat is involved.

Two pieces (NWN has no per-creature "changed area" event):

- **`leash_to_area.nss`** — the enforcement. Runs on every area's **OnEnter**.
  When a creature enters an area that isn't its home, it does
  `ClearAllActions()` + `JumpToLocation(home)`. It is wired directly on areas
  whose OnEnter was empty, and **chained** (`ExecuteScript("leash_to_area", OBJECT_SELF)`)
  from the shared OnEnter scripts the other areas already use (`d_cleartrash`,
  `s_cleartrash`, `ent`, `map`, the `mw_*_enter` Meaningwave scripts, etc.).
- **Home is recorded at OnSpawn.** Each creature stores its `"spawn"`
  LocalLocation when it spawns — which always happens in its home area, whatever
  the spawn mechanism (placed at area load, encounter, `MWSpawnAtWaypoint`, or
  any `CreateObject`). The module default `x2_def_spawn` → `nw_c2_default9` does
  this. Creatures that used a custom/blank/stock OnSpawn that didn't were fixed:
  the storage line was added to their spawn script, or they were pointed at
  `leash_spawn` (a no-AI store-only OnSpawn) or a thin `sp_*` wrapper that stores
  then runs the stock script (`sp_dropin9` → `nw_c2_dropin9`, `sp_bat9`,
  `sp_dimdoors`). (Note: area events can't establish a true home — by the time
  OnEnter sees a creature it may already have been kited — which is why this is
  done at OnSpawn, not at module load.)

Within-area teleports (e.g. Dimension Door) never cross an area boundary, so they
never fire area OnEnter and never trip the leash.

**Adding new creatures — usually nothing to do.** As long as a new creature's
OnSpawn reaches `nw_c2_default9` / `x2_def_spawn` (the module default) it is
covered. If you write a *custom* OnSpawn that doesn't, add one line so it can be
leashed:

```nss
SetLocalLocation(OBJECT_SELF, "spawn", GetLocation(OBJECT_SELF));
```

**Exempting a creature that is meant to travel** (escort NPCs, ambient
wanderers, scripted plot movers): set local int **`NO_LEASH = 1`** on its
blueprint `VarTable` (applies to all instances) or on a specific `.git` instance.
It may then cross area boundaries freely.

**Associates are never leashed — they keep following their PC.** The enforcement
script returns early for any creature with a valid `GetMaster`, which covers
henchmen, summoned creatures, familiars, animal companions and dominated
creatures. Concretely: **Meaningwave guides** (added as engine henchmen via
`AddHenchman`, see `mw_unlock_inc.nss`) and **summoned creatures** such as the
**Epic Dragon Knight** (`EffectSummonCreature("epicdragonknight",…)` in
`x2_s2_dragknght.nss`) follow the player across areas normally. They still store
`"spawn"` at OnSpawn (harmless — never enforced because of the master check), so
they satisfy the build check below.

### Build-time guard

The invariant — *every creature blueprint must either store a `"spawn"` home at
OnSpawn or set `NO_LEASH = 1`* — is enforced by **`tests/check_spawn_leash.py`**,
run via **`tests/smoke-test`**. `nwn-manager repack` runs `tests/smoke-test`
before packing and **aborts the build (no `.mod` built or installed)** if any
creature lacks both. The check scans `unpacked/` directly (it computes which
spawn scripts store `"spawn"`, following `ExecuteScript` chains), so a newly added
creature with a blank or non-storing OnSpawn fails the repack until it is given a
storing OnSpawn or flagged `NO_LEASH=1`. (`nwn-manager` is module-agnostic — it
only knows to run `tests/smoke-test`; the checks live in this repo.)

## Dungeon Solitaire

The module embeds a playable port of the card game **Dungeon Solitaire**
([github.com/mrprice22/Dungeon-Solitaire](https://github.com/mrprice22/Dungeon-Solitaire)
— designed by Steven Hastings, engine by James Price) in the prepped area
**`area017`**. The unmodified `DungeonSolitaire.Core` engine runs in-process via
an [Anvil](https://nwn-dotnet.github.io/Anvil/) managed plugin
(`csharp/DungeonSolitaire.Nwn`) — an NWN front-end (by James Price and Claude)
alongside that repo's Godot and console front-ends.

Cards are portrayed by NWN creatures and statues instead of sprites: a player
pulls the **DS_NewGame** lever, then clicks ally NPCs to attack the enemy columns;
mid-turn decisions (discard, target, effect order) pop a conversation menu, and an
invisible narrator, **"The Dungeon"**, speaks the engine's running commentary as
colour-coded in-game talk. The engine runs on a background thread and marshals its
events onto Anvil's main thread, mirroring the Godot front-end's threading model.

The plugin is built and deployed separately from the module (`dotnet build` →
copy the DLLs into the server's `anvil/Plugins/`), then its GFF assets ship via
`nwn-manager repack`. **See [`csharp/README.md`](csharp/README.md)** for the full
how-it-plays, architecture, build, and deploy details.

## Backups

The server's irreplaceable runtime state lives outside git. `bin/backup-homers-lotr`
snapshots it to OneDrive at most once per day.

**What it captures** (≈2.4 MB compressed):

- `NWN_HOME_DIR/database/*.sqlite3` — bank, bestiary, craft, merits, redemption
  codes, etc. Captured with the SQLite backup API (`sqlite3 ".backup"`), so each
  snapshot is consistent even while the live server is writing.
- `NWN_HOME_DIR/servervault/` — every player `.bic` character.
- `settings.tml`, `nwn.ini`, `nwnplayer.ini`, `cdkey.ini`, `cryptographic_secret`
  — captured from **both** `NWN_HOME_DIR` and `NWN_RUN_DIR` (nwserver's
  `-userdirectory` is `NWN_RUN_DIR`, so the live copy of some configs lives there),
  mirrored under `home/` and `run/` in the archive.
- `NWN_RUN_DIR/activity-sessions.json` (+ `.bak`) — player-hours history.

A `MANIFEST.txt` (timestamp, module-source git rev, sha256 of every file) is
included. Archives land in `~/OneDrive/Games/NWNHomersLOTR/backups/` as
`homers-lotr-<UTC>.tar.gz`. Retention keeps every backup from the last 30 days
plus one per month for 12 months.

**Not backed up** (regenerable): `hak/`, `tlk/`, `nwsync/` (rebuild via
`bin/refresh-nwsync` — incremental, so a from-empty rebuild is a one-time full
bootstrap), compiled `.mod` files (rebuild from the git module source),
wiki `docs/`, and the Dungeon Solitaire Anvil DLLs (source is in `csharp/`, rebuilt
via `dotnet build`).

### How it runs

Two triggers, both gated by a shared 24h sentinel (`NWN_RUN_DIR/.backup-last-run`),
so it runs **at most once per day** no matter how often it's invoked:

1. **systemd user timer** (`systemd/homers-lotr-backup.timer`) — `OnCalendar=daily`,
   `Persistent=true`, so a backup missed while the machine was off runs at the next
   login/boot. Runs even when the server isn't.
2. **serve poll loop** — `bin/serve` passes `--backup-cmd` to `nwn-manager serve`,
   which runs the backup opportunistically whenever the server goes idle (no players
   online), getting a snapshot sooner than the daily timer when the server empties.

Upload uses a plain `onedrive --sync --threads 1` (respecting the existing
`~/.config/onedrive/sync_list`, which includes `Games/NWNHomersLOTR`); it's
best-effort and never fails the backup. Logs append to `NWN_RUN_DIR/backup.log`.

```sh
# Install / enable the timer (one-time):
cp systemd/homers-lotr-backup.* ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now homers-lotr-backup.timer
# Optional: let the timer fire even when not logged in
loginctl enable-linger "$USER"

# Manual / ad-hoc:
bin/backup-homers-lotr --dry-run   # show what would be captured
bin/backup-homers-lotr --force     # back up now, ignoring the 24h gate
```

### Restore

1. Stop the server: `podman stop -t 8 nwnxee-homer`.
2. Extract the desired archive: `tar xzf homers-lotr-<UTC>.tar.gz -C /tmp/restore`.
   (Optionally verify integrity: `cd /tmp/restore && sha256sum -c <(awk '/^sha256:/{f=1;next} f' MANIFEST.txt)`.)
3. Copy state back:
   - `home/database/*` → `"$NWN_HOME_DIR/database/"`
   - `home/servervault/*` → `"$NWN_HOME_DIR/servervault/"`
   - `run/activity-sessions.json*` → `"$NWN_RUN_DIR/"`
   - config files from `home/` and `run/` to their respective dirs only if you
     intend to roll those back too (they're usually fine as-is).
4. Restart with `bin/serve`.

## Daily restart & reboot

The host reboots itself once a day at **03:00 local** for a clean slate, with
in-game warnings, a clean character save, and an automatic full wiki republish
on the way back up. Pieces:

1. **In-game countdown + save + shutdown** — the Anvil plugin service
   `ServerRestartManager` (`csharp/DungeonSolitaire.Nwn/ServerRestartManager.cs`)
   reads `ANVIL_RESTART_DAILY` (HH:mm, server-local; set in `server.env`,
   default `03:00`). It broadcasts warnings at 60/30/15/10/5/1 min, then at T-0
   runs `ExportAllCharacters()` and `NwServer.ShutdownServer()`. Build/deploy it
   like the rest of the plugin (see [`csharp/README.md`](csharp/README.md)) — the
   service ships in the same `DungeonSolitaire.Nwn.dll`. A control file
   `…/anvil/PluginData/restart-now` triggers an immediate restart for testing.
2. **Unattended OS reboot** — root systemd units (`systemd/nwn-reboot.{service,timer}`)
   fire `systemctl reboot` at **03:03** (a 3-min budget after the save). Root-owned,
   so there is **no password/polkit prompt**. Install once (the only privileged step):
   ```sh
   sudo cp systemd/nwn-reboot.service systemd/nwn-reboot.timer /etc/systemd/system/
   sudo systemctl daemon-reload
   sudo systemctl enable --now nwn-reboot.timer
   ```
3. **Auto-start on boot** — already handled by the XDG autostart entry
   (`~/.config/autostart/nwn-homers-lotr-server.desktop`) + user lingering; the
   server comes back without intervention (~5 min).
4. **Full wiki republish on boot** — `homers-lotr-wiki-publish.service` (user,
   runs once per boot) calls `bin/refresh-homers-lotr-wiki --publish`, which
   regenerates the **whole** wiki (so creature-index/detail **kill counts** update,
   not just the activity pages the serve loop touches), commits, and pushes. The
   serve-loop activity refresh still handles intra-day activity updates.
5. **Backup** — moved off its midnight timer into this cycle:
   `homers-lotr-backup.service` now runs once per boot (24h-sentinel-gated), so the
   snapshot is taken right after the reboot when state is quiescent.

Install the user services (one-time):
```sh
cp systemd/homers-lotr-wiki-publish.service systemd/homers-lotr-backup.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable homers-lotr-wiki-publish.service homers-lotr-backup.service
```

**Activating the plugin change:** the new `ServerRestartManager` only loads when
the server (re)starts. After deploying the DLL, restart `nwnxee-homer` once (or let
the next reboot bootstrap it). To test without waiting for 03:00, set
`ANVIL_RESTART_DAILY` a few minutes ahead in `server.env.local` and restart, or
`touch …/anvil/PluginData/restart-now` while the server runs.

## Prerequisites

`nasher`, `nwn_gff`, `nwn_script_comp`, and `python3` (for `wiki`) must be
on `PATH`. See [`nwn-manager`](../nwn_manager/README.md) for install
instructions on Bazzite / immutable Fedora.
