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

## Boss respawn tracker (Roll of the Fallen)

A billboard next to the Recent Updates sign in the Well of Eru
(`thewelloferu`, tag `boss_respawn_board`) lists every tracked boss that is
**currently dead**, sorted by CR, with time-to-respawn in the row and the
slaying player/party in the drill-down. State lives in the `respawndb`
campaign DB (`<NWN_HOME_DIR>/database/respawndb.sqlite3`): `boss_registry`
(reseeded from source on every module load), `boss_alias`, `boss_deaths`
(wiped on load — a restart revives everything, so the board starts empty).

**The registry is generated from a rule, not hand-curated.**
`bin/gen-boss-registry.py` scans `unpacked/` and rewrites the `BRD_SeedBoss(...)`
block (between `// BEGIN/END GENERATED REGISTRY` markers) in
`unpacked/brd_db.nss`. A creature is a boss when it has **ChallengeRating > 60**
and only ever **one live copy** in the world — one placement and no encounter
slot (`placed`), or one `MaxCreatures=1`/`Respawns=-1`/`Reset=1` encounter
instance and no placement (`encounter`) — and it is **not plot/immortal** and
**not a merchant/utility NPC**. Same tag in different areas is fine (the two
Khamuls); same tag in the same area is dropped (two copies alive at once).

To change the list, edit the rule/levers in `gen-boss-registry.py` (`EXCLUDE`
denylist for vendors/props, `INCLUDE` to force a sub-CR-60 boss on, `CR_MIN`),
run it once as a dry-run to read the report (included bosses, respawn warnings,
diff vs. current), then `--write`. It's on-demand like `gen-roadmap.py`, not
part of repack — re-run it after adding boss content.

The generated block is validated at build time by
`tests/check_boss_registry.py` (part of `tests/smoke-test`, run by every
repack): it **independently** re-derives placements and encounter slots from
`unpacked/` and fails the build on any drift — a boss placed a second time, a
changed ResetTime, a tag rename, a deleted blueprint. Encounter bosses carry
their real `ResetTime` as `respawn_seconds` (accurate countdowns); placed
bosses respawn 900 s after death via `SE_DoCreatureRespawn`. The generator
reports any placed boss whose OnDeath won't bring it back so it can be fixed —
none currently (the Rancid Skinner, Wart Gondorian Gate Captain and Fell Beast
were repaired). See [CLAUDE-boss-tracker.md](CLAUDE-boss-tracker.md).

Death recording rides the bestiary wrapper — one `BRD_RecordDeath()` call in
`bst_ondeath.nss` (which reads the `bst_ctrb_N` damage-contributor locals for
the "Slain by" line). Don't remove that call or bypass `bst_install`'s OnDeath
wrapping for a tracked boss, and keep `BRD_InitDb()` in `onmoduleload.nss`.
The board conversation is `brd_sign.dlg` + the `brd_*` scripts (custom tokens
**6300–6313** — reserved, don't reuse elsewhere).

**Wiki page stays in sync automatically:** `nwn-wiki` parses the same
`BRD_SeedBoss` rows out of `brd_db.nss` at build time and generates
`docs/creatures/bosses.html` (Creatures → Bosses menu) plus
`module-index/bosses.json` — there is no second list to maintain. Regenerating
the registry updates the game on the next repack and the wiki on the next
scheduled refresh. A seed row whose resref has no creature page renders
unlinked and is flagged in `module-index/lookup_warnings.json`.

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

## Chest / container loot tables

Most chests in the module don't carry a static loot list. Instead, the placed
**instance's `OnOpen` field** (in the area's `.git.json`, not the `.utp`
blueprint) points at one of three scripts that procedurally roll fresh loot
every time the chest is opened:

| `OnOpen` script | Tier | Generator called |
|---|---|---|
| `chest_refilllow.nss` | Low | `GenerateLowTreasure` |
| `chest_respawner.nss` | Medium | `GenerateMediumTreasure` |
| `chest_refillhigh.nss` | High | `GenerateHighTreasure` |

All three live in `unpacked/` and share the same shape: on open, destroy
everything currently in the chest's inventory, then call the matching
`Generate*Treasure(oLastOpener, OBJECT_SELF)` helper from
`unpacked/nw_o2_coninclude.nss`, which rolls level-scaled gold/items onto the
container. A `CS_Opened`/`NW_DO_ONCE` local-int pair throttles this to once per
~200 real-world seconds, so re-opening immediately doesn't reroll. Two more
tiers exist in the same include but aren't wired to any chest yet —
`GenerateBossTreasure` and `GenerateBookTreasure` — available if a boss-tier or
book-drop chest is ever needed.

**The gotcha:** placing a chest from the toolset palette using a non-module
blueprint (e.g. stock Hordes-of-the-Underdark `x0_treasure_high`,
`x0_mod_trea_uniq`, `x0_mod_trea_high`) gives you an instance whose event
script fields — including `OnOpen` — are all blank. The chest looks and opens
fine but never drops anything, because nothing is wired to generate loot into
it. This happened to 3 chests placed in `mistymountainsa`
(`unpacked/mistymountainsa.git.json`, tags `X0_TREASURE_HIGH` /
`X0_MOD_TREASURE_UNIQ` / `X0_MOD_TREASURE_HIGH`) and was fixed by setting their
`OnOpen` to `chest_refillhigh`.

**To add a working loot chest:** clone an existing working chest *instance*
from the same or a neighboring area — search any `.git.json` for
`TemplateResRef` `chest1`/`chest2`/`chest3` or `plc_chest1`–`plc_chest4`
(`Tag` values like `ChestLow`/`ChestMed`/`ChestHigh`) — and only overwrite
`Tag`, position (`X`/`Y`/`Z`/`Bearing`), and description/name fields. Don't
build the struct from scratch off a `.utp`/palette blueprint; see the
"clone a working sibling" placement guidance in
[CLAUDE-blueprints.md](CLAUDE-blueprints.md). If you do need a stock/non-module
blueprint's appearance for some reason, at minimum set its instance `OnOpen` to
one of the three scripts above so it actually drops loot.

## Plot-door audit

`bin/list_plot_doors.py` scans all area instance files and lists every **locked**
door that has the **Plot** flag set but **no key requirement** (`KeyRequired = 0`,
`KeyName = ""`). These are the doors the Knock spell can unlock.

```sh
python3 bin/list_plot_doors.py          # pretty table
python3 bin/list_plot_doors.py --json   # JSON array for scripting
```

Output columns: door name, door tag, area, destination tag, destination type
(`door` / `waypoint` / `none/trigger`).

`bin/list_plot_containers.py` does the same for placeable containers (`HasInventory = 1`).
Output columns: container name, tag, area.

```sh
python3 bin/list_plot_containers.py
python3 bin/list_plot_containers.py --json
```

Both scripts are useful after adding or editing plot doors/containers to confirm
they are (or aren't) Knock-able.

## Map notes on area transitions

`bin/gen-map-notes.py` keeps every area transition labeled on the in-game area
map. It places a map-note waypoint (`nw_mapnote001`, `HasMapNote = 1`) on each
**door / trigger / placeable-portal** transition, labeled with the **destination
area's name**, and one **point-of-interest** note at each **conversation-teleporter
NPC**, labeled with that NPC's name.

```sh
python3 bin/gen-map-notes.py                   # dry-run audit (default)
python3 bin/gen-map-notes.py --verbose         # + every per-note action
python3 bin/gen-map-notes.py --apply           # write the .git/.gic edits
python3 bin/gen-map-notes.py --update-manual   # also rewrite disagreeing hand notes
```

Transition resolution (which door goes where, edge kinds) comes from
`module-index/area_graph.json`; object positions and NPC names come from
`unpacked/`. The tool is **idempotent** — auto notes carry deterministic tags
(`mnx_<object-tag>` for transfers, `mnp_<npc-tag>` for NPC POIs) that it updates
in place, so re-running never creates overlapping duplicates. It **defers to
hand-placed notes** within 8 m of a transition (reported, not overwritten unless
`--apply --update-manual`) and **skips ambiguous multi-destination tags** (e.g.
the Gwathdor maze, whose destinations are randomized at reboot).

**Re-run it whenever you add or change areas / transitions.** After adding a new
area, door, trigger, portal placeable, or teleporter NPC, run
`python3 bin/gen-map-notes.py` to see what's missing, then `--apply` to add the
notes. It's on-demand like `gen-boss-registry.py` / `gen-roadmap.py`, not part of
the wiki refresh. Note: `area_graph.json` is a wiki-generated index, so it must
reflect the new areas — if you added areas since the last wiki build, the tool
warns that the graph is stale; refresh the wiki (or wait for the daily refresh)
before relying on a full sync.

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
Edit it (by hand or with the GUI editor) and commit — the daily wiki refresh
regenerates the public page and pushes the same data to the in-game Recent
Updates sign. To make a change land immediately instead, use the editor's
**Publish to Wiki & DB** button, or run `python3 bin/gen-roadmap.py` +
`python3 bin/publish-roadmap-db.py`.

Each item's admin to-do list (`manual_steps`) is tagged by **kind** — `toolset`,
`uat`, `publish`, `admin` — and a `uat` step records which character it takes to
run it (`tester`). Two panels in the editor read those: the **Toolset Queue**
(everything waiting on the toolset or a deploy) and the **UAT Queue** (everything
waiting on an in-game check, grouped by the character needed). The same `uat`
flag drives the in-game sign's second branch, where players can see — and help
with — what has shipped but is not yet validated.

To avoid typos in the controlled fields (player names, group ids, statuses,
`dupe_of`), use the local web editor:

```sh
python3 bin/roadmap-editor.py          # opens http://localhost:8765
```

It validates with `gen-roadmap.py`'s own checks before writing and only
rewrites the `ideas:` block, leaving the rest of the file untouched. It can run
on boot as a systemd user service (`systemd/roadmap-editor.service`).

`gen-roadmap.py` also prints an advisory (non-blocking) warning when two ideas in
the same group have titles that share too many words — a nudge to link them with
`dupe_of` if they're really the same request. See **CLAUDE-roadmap.md** for the
exact word-overlap rule and threshold, and how to reword a false positive.

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
    if (sCodeLower == "freelegendary") {
        if (GetXP(oPC) < XP_LEVEL_60) SetXP(oPC, XP_LEVEL_60);
        return TRUE;
    }
    if (sCodeLower == "mynewcode")     {                                    // ← add
        CreateItemOnObject("some_item_resref", oPC, 1);
        return TRUE;
    }
    return FALSE;
}
```

`XP_LEVEL_60` (3,581,000) is a constant at the top of `code_redeem.nss`, taken
from the last real row of `hak_2da/exptable.2da` — the server's own experience
table for levels 41–60. Any code that grants XP outright should be written
against the published table, never against the retired HGLL leveler's internal
accounting (whose total-to-60 was ~17.5M, about 5x the real cost). XP codes
that use an absolute `SetXP()` should also guard against moving XP *downwards*,
as the `freelegendary` case above does.

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
  `pers_state_inc.nss`, `hgll_featreq_inc.nss` (since deleted),
  `bdm_include.nss`,
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
3. Build the hak and install it. `lotr_rules.hak` must contain **all twelve** of
   `ruleset.2da`, `baseitems.2da` (the module's custom item stack sizes — ammo 999,
   potions/scrolls 99), `classes.2da` (multiclass `XPPenalty` zeroed on all 11
   player base classes, so a 4-class build takes no XP penalty), `exptable.2da`
   (the experience table extended to level 60 — see "Levels 41–60" below), the
   seven `cls_spgn_*.2da` caster tables (spell slots per day across levels 41-60,
   also "Levels 41–60") and `feat.2da` (the stock table plus the legendary feat
   rows — see [CLAUDE-legendary-feats.md](CLAUDE-legendary-feats.md); its names
   and descriptions are strrefs into `tlk/lotr.tlk`, so the hak and the TLK must
   be published together), all twelve tracked in git under `hak_2da/`. Pack all of
   them, or a from-scratch rebuild silently drops those customizations — which is
   exactly what happened twice, so **don't pack it by hand**:
   ```sh
   bin/build-lotr-rules-hak --install
   ```
   The script packs the twelve 2DAs from `hak_2da/`, verifies the result with
   `nwn_erf -t` before installing, backs up the hak it replaces, and installs
   into `$NWN_HOME_DIR/hak` (this season's home — pass `--home <dir>` to install
   into another NWN home as well, e.g. the local toolset's). Run it with no
   arguments to build into `dist/` and verify without installing.

   `hak_2da/ruleset.2da` is the edited copy from step 2; it is tracked so the hak
   is reproducible from the repo alone, without re-extracting from the game data.
   Inspect any built or installed hak with
   `~/.nimble/bin/nwn_erf -t -f <path>/lotr_rules.hak`.
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

## Levels 41–60

Levels 41 to 60 are **real character levels**, not a bolt-on system. They come
from `hak_2da/exptable.2da`, the stock experience table extended past the
level-40 sentinel: level 41 at **828,800** cumulative XP through level 60 at
**3,581,000** — the level-41 step is 48,800 XP over level 40 and each step after
that compounds by 1.1x. Rows for levels 1–40 are byte-identical to stock.

- The table only takes effect once `exptable.2da` is packed into `lotr_rules.hak`
  and published (`bin/build-lotr-rules-hak --install`, then `bin/refresh-nwsync`).
- **The level cap is two levers, and you need both.** They fail in opposite
  halves and the combination is a trap:
  - `NWNX_MAXLEVEL_SKIP=n` + `NWNX_MAXLEVEL_MAX` in `server.env` — the NWNX
    plugin, which is what lets a character *gain* a level past 40. It also needs
    `NWNX_ELC_SKIP=n`: the plugin's readme requires NWNX_ELC to be *loaded* (no
    configuration) to bypass the engine's level-40 restriction. That is not the
    same as turning on the server's own ELC — `NWN_ELC`/`NWN_ILR` stay 0 (see
    "Character validation" below).
  - `NWN_MAXLEVEL` in `server.env` — the **server's own** restriction. The
    container entrypoint passes it as `-maxlevel` (defaulting to **40**), it is
    what the server browser advertises as the level range, and it is what decides
    whether a character may *log in*. `bin/serve` also writes it into
    `settings.tml` as `max-character-level`, along with that key's schema
    constraint (which ships as `max = 40` and would otherwise clamp it).
  Raise only the NWNX one and the server cheerfully levels a character to 41,
  then refuses it at the door: *"Invalid character - player login refused,
  character level disallowed by server restrictions."* The character is not
  damaged — it logs in again as soon as `NWN_MAXLEVEL` matches. `server.env`
  keeps them in step by defining `NWNX_MAXLEVEL_MAX="$NWN_MAXLEVEL"`, and
  `tests/check_epic_tables.py` fails the build if they ever diverge.
  Don't also call `NWNX_Administration_SetMaxLevel()` — one NWNX lever only.
  A startup line "Server: Invalid argument to -maxlevel" is expected and safe to
  ignore (the plugin raises the limit after the argument is parsed).
- **Martial progression to 60 needs no 2DA work.** Stock NWN:EE `CLS_*` tables
  already carry 60 rows, so `classes.2da` keeps pointing at them and levels 41-60
  progress on their own: BAB keeps climbing +0.5/level (`cls_atk_1` 30 at level 39
  → 40 at level 59; `cls_atk_3` 20 → 30), saves keep climbing
  (`cls_savthr_fight` 21/15/15 → 31/25/25), and epic bonus feats keep their cadence
  (`cls_bfeat_fight` alternating to row 58). General feats (1 per 3 levels) and
  ability increases (+1 per 4) are engine-side and continue past 40.
- **Caster progression DID need 2DA work.** Earlier revisions of this section
  claimed flat spell slots past 20 were "the intended design" — that was wrong,
  and it contradicted the recorded design answer on roadmap
  `ll-class-progression-41-60` ("caster level keeps scaling in all the regular
  ways: **spell slots**, caster DC, duration, damage caps"). Stock `cls_spgn_*` is
  flat from level 20 (`cls_spgn_wiz` reads `4` at levels 20, 40 **and** 60), so a
  caster gained no slots for twenty levels. Fixed by shipping all seven
  `cls_spgn_*.2da` in `lotr_rules.hak`, which is the path the MaxLevel readme
  names ("Spell counts gained can be configured for the additional levels"):
  - **+1 slot at every castable spell level** at each cadence threshold.
    Full cadence (wizard/sorcerer/cleric/druid/**bard**): **44, 48, 52, 56, 60**
    → +5 by level 60. Half cadence (paladin/ranger): **50, 60** → +2. So a wizard
    goes 4 → 9 slots per spell level, a cleric 6/6/6/6/6/6/5/5/5/5 →
    11/11/11/11/11/11/10/10/10/10, a paladin 3 → 5.
  - Rows 0-39 stay **byte-identical to stock** — the sub-40 band is untouched, and
    the gate below asserts it. Slots are computed from the table at rest, not
    stored per level in the `.bic`, so existing level-41+ characters get the new
    slots **retroactively** with no relevel.
  - Rows 40-59 are owned by **`bin/gen-caster-slots.py`** (dry-run by default,
    `--apply` to write, idempotent). Retune the cadence table at the top of that
    script — never by hand-editing a 2DA, and never by re-extracting from the game
    data, which silently reverts twenty levels of progression.
  - `classes.2da` needed no change: it already points `SpellGainTable` at the stock
    table names, so a same-named 2DA in the hak overrides it.
- Two upstream quirks come with the MaxLevel plugin. The character sheet's
  "Next Level" XP figure is wrong from level 40 up — **worked around** in
  `unpacked/nextlvl_inc.nss`, which overrides strref 315 ("Next Level")
  per player with the real requirement read out of `exptable.2da` and a trailing
  newline that pushes the engine's wrong figure out of the field. It is applied
  at login (`mod_cliententer.nss`) and re-applied on every level up / level down
  (`nextlvl_evt.nss`, subscribed in `onmoduleload.nss`), and clears itself below
  40 or when the hak is missing. The second quirk is **spells known**, and it is
  **still open** — the level-up spell picker is confirmed broken above 40 and
  **cannot be fixed from this repo**:
  - **Measured 2026-07-29 (UAT).** At level 41 the spell-selection panel appears
    and asks a wizard for its usual 2 picks, but **only the cantrip (spell level 0)
    tab is populated — every other spell-level tab is empty**, and the panel reports
    the stock engine string **strref 10278**, *"There are no more spells available
    at this level"* (that "level" is the *spell*-level tab, not character level). A
    level-41 wizard has known all **7** stock cantrips since about level 5, hence an
    empty list. Levels 1–40 behave normally on the same character, and the level-up
    still **completes without spending the picks**, so they are silently lost.
  - So the client resolves the wizard's **maximum castable spell level as 0** at
    class level 41. This is not data-driven: the shipped `cls_spgn_wiz.2da` row 40
    reads `4` at all ten spell levels, and `classes.2da`'s Wizard row has nothing
    that bounds it (`MaxLevel 0`, `EpicLevel -1`, `MinCastingLevel 1`,
    `SkipSpellSelection 0`). The 2-picks-per-level count is engine-side — Wizard has
    no `SpellKnownTable` and nothing in `ruleset.2da` exposes it. And no server-side
    lever reaches that panel: `nwnx_player` has no GUI-panel opener beyond
    inventory/examine/character-sheet, and
    `NWNX_ON_CLIENT_LEVEL_UP_BEGIN_BEFORE/_AFTER` carries no event data. This is
    MaxLevel's documented "Spellcasters may not change spells when levelling up",
    and it is why "just use the native level-up GUI" is not an available option.
  - **The `unpacked/sk_probe_*.nss` scripts** turn that observation into numbers:
    snapshot `GetKnownSpellCount()` on `NWNX_ON_LEVEL_UP_BEFORE`, diff on `_AFTER`,
    report the delta to admins and the log. Wizard/Sorcerer/Bard only — those are
    the `SpellbookRestricted` classes. **Delete all three plus the two
    subscriptions in `onmoduleload.nss` once the fix lands.** Note they only run
    from a **repacked `.mod`** — publishing the hak alone does not deploy them,
    which is exactly how the first UAT produced no probe output.
  - **Root cause, and why no data fix can work: the spell-level tabs render
    *enabled* for roughly one frame, then are hidden/greyed.** So the client builds
    the correct tab set from the 2DA data on its first pass — the data was never the
    problem — and a *later* pass in client code disables them. Nothing in a 2DA, a
    hak, a plugin option or a server script can intercept a client-side disable
    pass. **Treat this as unfixable from this repo pending a client build**, and do
    not spend another publish cycle on 2DA experiments.
  - **The cap keys on *class* level, not character level.** A fresh caster class
    taken at character level 41 (sorcerer 1) offers spells normally. Only a
    character with **40+ levels in a single casting class** is affected; multiclass
    casters are fine. That bounds the blast radius usefully.
  - **Tested and disproven — do not retry:**
    - Extending and packing `cls_spkn_sorc.2da` / `cls_spkn_bard.2da` (the one thing
      MaxLevel's readme calls "not worth changing" without having tested it). A
      *sorcerer* past class level 40 fails identically, so a genuinely table-driven
      class does not help. Both tables were deleted; `bin/gen-caster-slots.py` no
      longer generates them and `bin/build-lotr-rules-hak` carries a do-not-re-add
      note.
    - `classes.2da` Wizard `MaxLevel` `0` → `60`. No effect; reverted.
    - Giving Wizard its own `cls_spkn_wiz` table was **not** attempted — the
      sorcerer result makes it pointless, since the table-driven path is broken too.
  - **Not tracked upstream.** Beamdog/nwn-issues has no report of it. Only a client
    fix can restore the native page, so it is worth reporting.
  - Reference counts for whatever fix ships — stock wizard/sorcerer-learnable
    spells, from `spells.2da`'s `Wiz_Sorc` column (**179** total, and no hak in the
    NWN home overrides `spells.2da`): `L0:7 L1:22 L2:28 L3:23 L4:21 L5:18 L6:20
    L7:13 L8:13 L9:14`.
- `tests/check_epic_tables.py` (smoke-test gate) keeps `exptable.2da`, the
  transcribed fallback switch in `unpacked/_build_lvl_inc.nss`, `classes.2da`'s
  zeroed `XPPenalty` and the seven `cls_spgn_*.2da` caster tables from drifting
  apart. For the caster tables it imports `bin/gen-caster-slots.py`'s own cadence
  table rather than transcribing the numbers twice, and it asserts level 40 still
  equals level 20 so an edit to the sub-40 band is caught too.
- `hak_2da/xptable.2da` is the **kill award** table (`exptable.2da` is the *cost*
  of a level) and covers levels 1–40; levels 41–60 are paid in script by
  `unpacked/ll_xp_inc.nss`, which has no rows to index. **Both halves are one
  model** — a CR-versus-level curve where each level has a difficulty tier and the
  award falls off below it — fitted to five anchors the admin chose directly.
  `bin/gen-xptable.py` owns the 1–40 half; run it with `--apply` and never
  hand-edit the 2DA. `check_epic_tables.py` re-derives the table from the
  generator, and also enforces the 6,000 per-kill cap, that a lower level is never
  paid less for the same kill, that every level can reach the cap at some CR, and
  that the level-1 row still pays a starting character properly at low CR (the
  knee used to be a flat 5 % of tier, which at level 1 sat on CR 1.5 and paid the
  60 floor for the starter content itself).
- **`classes.2da` needs no change for the 60 cap.** (Earlier revisions of this
  section claimed its `MaxLevel`/`EpicLevel` columns were part of the lever — they
  are not.) In `hak_2da/classes.2da` every player base class already has
  `MaxLevel 0` (= no per-class cap) and `EpicLevel -1` (= default epic progression
  from 21). The only non-zero `MaxLevel` values are stock prestige-class limits
  (40 for Shadowdancer / Arcane Archer / Assassin / Blackguard / Champion of Torm /
  Weapon Master / Pale Master / Shifter / Dwarven Defender / Dragon Disciple, 5 for
  Harper Scout and Purple Dragon Knight); none of those is reachable inside a
  60-level budget once the prestige class's own base-class prerequisites are paid,
  so they don't constrain a level 60 build.

### Character validation (ELC / ILR)

`server.env` runs with `NWN_ELC=0` (Enforce Legal Characters **off**) and
`NWN_ILR=0` (Item Level Restrictions **off**), and has for the life of the server.
That is the correct posture for a 41–60 cap and it needs no change:

- With ELC off the server does **not** re-validate a connecting character's
  level/XP/feat/skill spend against the 2DAs, so a level 41+ character cannot be
  rejected at login or silently rolled back to 40. Turning ELC **on** is what would
  put legendary characters at risk — don't, unless `exptable.2da` and the rest of
  `lotr_rules.hak` are provably identical on server and client.
- The **NWNX ELC plugin is loaded** (`NWNX_ELC_SKIP=n`), but only because the
  MaxLevel plugin requires it to bypass the level-40 restriction. It is not a
  second validation path: nothing in `unpacked/` subscribes to the NWNX ELC
  events (`NWNX_ON_ELC_VALIDATE_CHARACTER_BEFORE`/`_AFTER`) — the only mentions
  are in the vendored `nwnx_events.nss` / `nwnx_player.nss` headers — and there
  is no custom validation script. Loading the plugin ≠ `NWN_ELC=1`.
- The remaining level-41+ login hazard is **hak mismatch, not validation**: a
  client without the published `exptable.2da` reads the level-40 table, so its
  character sheet clamps the display at 40. The fix is `bin/refresh-nwsync` after
  the hak rebuild, not an ELC setting.
- **The old `hgll_*` "legendary leveler" is gone.** It was a Letoscript-based
  add-on with its own XP tally, its own leveler statue and its own area, and none
  of that is how levels 41–60 work now. All 21 `hgll_*.nss` scripts plus
  `sha_leto_inc.nss` were deleted (roadmap `ll-hgll-remove-scripts`) — don't
  reintroduce them, and don't cite them as the level-41+ mechanism.
  `Mod_OnClientEntr` / `Mod_OnClientLeav` are `mod_cliententer.nss` /
  `mod_clientexit.nss`, which hold all the real wiring (merit, forge, bestiary,
  journal catch-up, bank boxes, persistent state) and no longer call into any
  leveler script. The Legendary Levelling Area is gone too (roadmap
  `ll-hgll-retire-area`): `legendarylevelli.are/.git/.gic.json` were deleted as a
  set, the area was dropped from `Mod_Area_list`, and the Well of Eru trigger and
  level-40 warning script (`servershout5.nss`) that led to it went with it.

## Legendary feats (level 60)

Feats selectable only at character level 60, granted by a custom picker rather
than the engine's own level-up feat page. Architecture, build order and the
publish sequence: [CLAUDE-legendary-feats.md](CLAUDE-legendary-feats.md).

The feat table is owned by `bin/gen-legendary-feats.py`, which writes three
things from one list: the `hak_2da/feat.2da` rows, the strings
`bin/build-lotr-tlk` puts in `tlk/lotr.tlk`, and `unpacked/legfeat_ids_inc.nss`
(the script-side view). Never hand-edit any of the three.

### Re-choosing legendary feats (players)

Talk to **Halmir the Grey** — the keeper of the old orders, in the Well of Eru —
→ *"Let me choose my legendary feats again."* The node only appears for a
level-60 character (`legfeat_cond`). It hands every legendary feat back and
reopens the picker with the full allotment; **the character's level does not
change**. This is the intended way to follow a growing feat pool or a change of
gear without rerolling and levelling to 60 again.

The node lives on Halmir (`prsg_conv.dlg`) because it is a **player** feature.
It used to sit on Ping Pong, and that was only ever safe while every realm was
also a dev realm: Ping Pong is a dev-only NPC, and `onmoduleload` destroys it
wherever `SP_DEV_TOOLS` is off (see `bin/season-profile.py`), so leaving the
re-pick there would have deleted it from every live season. The scripts still do
not care where the node lives — moving it again is a dialog edit and nothing
else — but it must stay on an NPC that exists in production.

**The invariant that keeps this from being an exploit:** giving a feat back has
to be exactly as complete as taking it — the feat *and* the base ability points.
`LegFeat_Respec` goes through `LegFeat_RevokeAll`, which undoes both from the
`legfeatdb` pick records, so swapping Legendary Strength for Legendary Wisdom
leaves you +6 Wisdom, not +6 to both. A re-pick path that removed the feat but
kept the points would be a repeatable stat farm; `tests/check_legendary_feats.py`
asserts the respec still calls that function. Re-picking is refused while
polymorphed, because a base-score write lands on a body that is about to be
replaced.

### Tuning the picker's subtitle

The text after *"You may choose N legendary feats."* is a single constant at the
top of `unpacked/legfeat_nui.nss`:

```c
const string LEGFEAT_SUBTITLE = "Can repick with Halmir in Well of Eru";
```

Edit it, repack, restart. `""` drops it. It exists because where a player
re-picks was not settled, and the window should not need editing when it moves —
which it since has, off Ping Pong and onto Halmir the Grey (see above).

His first name is used deliberately: the longest header state is *"Your
legendary picks are all spent."* (35 characters) plus a two-space join, leaving
the subtitle 43. *"Halmir the Grey in Well of Eru"* spends 46 and would drop that
one state to the left-justified fallback while every other reads centred.

**It shares the header's line, centred.** Keep **header + subtitle together under
80 characters** (`LEGFEAT_HDR_WRAP_AT`) and it stays one centred line. The
current pair is 75.

**Over 80 it falls back to a two-line wrapping box, which is left-justified.**
That is not a choice, it is NUI: a `label` centres but never wraps — it clips
silently, which is how the header once read "You may choose 2 leg" — while a
`text` wraps but takes no alignment. There is no centred wrapping control, so
the layout picks whichever failure is less bad: centred while it fits, wrapped
rather than truncated when it does not.

The threshold counts characters against a proportional font, so it is an
estimate and deliberately conservative — a player running a larger UI scale fits
fewer characters per line than you do.

Two consequences worth knowing:

- **The "all spent" header is kept short on purpose.** It is concatenated with
  the same subtitle, so if you lengthen it that one state drops to the
  left-justified fallback while every other state reads centred.
- **Neither form pushes the feat list down.** NUI cannot reflow a built layout,
  so heights are fixed. Past two lines the wrapped form clips. If you genuinely
  need three, raise `LEGFEAT_SUB_H` to ~56 and `LEGFEAT_WIN_H` by the same
  amount together; changing one without the other either clips the text or
  leaves a gap above the Close button.

### Where the picker opens from

Reaching level 60 opens it. After that: **Force Rest** (rest menu → *Force Rest*,
or Admin Options → *Force Rest*) reopens it while picks remain. Note it is
**Force Rest specifically, not resting**: the module cancels the engine's own
rest at `REST_STARTED` to open the rest menu, so a plain rest never completes and
`REST_FINISHED` never fires for it. A green login message reports outstanding
picks.

### Resetting a character's legendary feats

Testing feats means taking them, looking at the result, and starting over. A
legendary feat is added with `NWNX_Creature_AddFeat` and lives in the character's
`.bic`, so **nothing else in game removes one** — deleting `legfeatdb` clears the
records but leaves the feats on the character.

In game, on the character you want to reset:

> **Rest → `[Admin Options]` → `[Admin] Reset my legendary feats`**

Admin Options is gated by the `admindb` whitelist (`_cdkey`), so the reset tool
inherits that gate and sits beside `Grant me level 60`. It puts the character
back to "never had a legendary feat":

- every legendary feat is removed;
- base-score points are subtracted **for picks that were recorded in
  `legfeatdb`**;
- the pick and allotment records are cleared, so the next level-up, rest or
  login grants a fresh allotment;
- the character is exported, writing the corrected base scores through.

**A feat with no pick record has its feat removed but its ability score left
alone** — DM-granted feats and leftovers from a wiped `legfeatdb` land here.
Nothing recorded granting those points, and subtracting on a guess would
permanently lower a base stat. If you wipe the DB *and* want the scores back,
note the values first and set them with a DM.

The tool iterates the generated feat table, so it keeps working unchanged as the
feat pool grows. It is `unpacked/legfeat_reset.nss` →
`LegFeat_ResetCharacter()` in `legfeat_inc.nss`.

### Wiping the database instead

To clear every character's picks at once (test server only — this is not a
migration path):

```sh
rm "$HOME/.local/share/Neverwinter Nights S2/database/legfeatdb.sqlite3"
```

Restart the server afterwards; nwserver keeps writing to the unlinked file until
it stops, then creates a fresh one. The feats themselves stay on each `.bic` —
use the reset tool above per character to remove those.

Wiping is rarely the right move: `LegFeat_InitDb` migrates the schema in place
(the `pragma_table_info` guard, as in `bst_db.nss`), so a column added later does
not need a wipe. It is worth knowing what a *missing* migration looks like,
because it is quiet: every statement naming the new column fails to **prepare**,
the log fills with `sqlite error: not prepared`, no allotment is written, and the
picker simply never opens.

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
   It also carries the **roadmap** with it, in this order:
   `bin/gen-roadmap.py` (rebuilds `docs.manual/Roadmap.html` from `roadmap.yaml`) →
   `bin/publish-roadmap-db.py` (refills `roadmapdb`, the in-game Recent Updates
   sign) → the wiki build, which is what folds `docs.manual/` into `docs/`. Both
   roadmap steps warn and continue: a `roadmap.yaml` that fails validation is a
   roadmap problem, not a reason to skip republishing 287 areas. Before this, both
   were manual — `gen-roadmap.py` by hand and the sign only from the editor's
   *Publish to Wiki & DB* button — so anything shipped by an agent left the public
   page and the in-game board stale.
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

### Adhoc "reboot on empty"

To push a module update mid-day without kicking players or waiting for 03:00:
deploy the new `.mod`, then `bin/reboot-on-empty "<message>"` (add `--nwsync` if
haks/tlk changed). The `ServerRestartManager` warns online players and shows new
joiners an on-login notice; once the server is empty for ~45s it saves + shuts down
cleanly and the host `homers-lotr-empty-restart.path` unit restarts **just the
server service** onto the new module. Cancel with `bin/reboot-on-empty off`. Full
setup + one-time unit install: [`rebootSchedule.md`](rebootSchedule.md#adhoc-reboot-on-empty-push-an-update-without-kicking-players).

## Season identity & rotation

The server rotates through **seasons** every 3–4 months — everyone rolls new
characters, so the module can absorb big rebalances without legacy characters and
inflated economies. The per-season runbook is
[`season-cutover-guide.md`](season-cutover-guide.md); the one-time engineering it
depends on is [`season-cutover-prereqs.md`](season-cutover-prereqs.md).

### This repo is the DEV realm

**`nwn_homers_lotr` is never production.** It is the permanent dev realm — port
5123, `dev.homerslotr.com`, password-gated, cheat gear and the Ping Pong builder
NPC switched on — and it is the only repo anything is authored in. Each season
lives in its own `nwn_homers_lotr_s<N>`, and a season repo is a *derived* copy of
this tree plus its own season block. Nothing is hand-edited there:

```bash
bin/season-promote.sh --to ../nwn_homers_lotr_s<N> --apply --season <N>
```

rsyncs this tree in with `--delete`, then rebrands and re-profiles the target
from its own `server.env`. An edit made directly in a season repo is destroyed by
the next promotion, deliberately — see the guide's §5a and §5c.

### The season block in `server.env`

Every season-scoped value in this repo derives from one block at the bottom of
`server.env`:

| Var | Meaning |
|-----|---------|
| `SEASON_NUM` | This environment's season number |
| `SEASON_ROLE` | `live` \| `test` \| `dev` \| `archive` — drives the server name, the in-game status sign, **and behaviour** (cheat chest, dev NPCs, wipe notice) via `season-profile.py` |
| `SEASON_LEGACY_NAMES` | Season 1 only: suppress the derived module/server names (see below) |
| `SEASON_WIKI_URL` | This environment's own wiki: `https://homerslotr.com/` for the live season, `https://dev.homerslotr.com/` for dev, `https://season<N>.homerslotr.com/` otherwise |
| `SEASON_LIVE_WIKI_URL` | Where *production* publishes. Only differs from the above off the live season; lets dev's roadmap editor link to the live roadmap. Defaults to the apex |
| `SEASON_WORKER_NAME` | Cloudflare worker serving `docs/`. **Must be unique per season** — two repos deploying the same worker name collide |
| `SEASON_CONNECT_HOST` | Host half of the module description's `Connect:` line |

`SEASON_NUM` and `SEASON_ROLE` are the only authored facts. Everything else is
**derived and written** by two scripts, and neither's output may be hand-edited:

| Script | Owns | Gate |
|---|---|---|
| `bin/season-brand.py --apply` | **strings and URLs** — module name, server name, worker name, every in-game URL, the apex redirect, both season signs | `tests/check_season_brand.py` |
| `bin/season-profile.py --apply` | **behaviour flags** — `unpacked/season_prof_inc.nss`: cheat chest, dev NPCs, early-access wipe notice | `tests/check_season_profile.py` |

Edit the block, re-run both, repack. Both gates run on every repack, so a tree
that has drifted from its season block cannot be packed.

The profile split exists because dev and production share one source tree. "Turn
the cheat chest off before go-live" used to be a hand edit to
`don_cheat_inc.nss`; with a dev realm promoting into production on every release,
that edit would be reverted by the next successful deploy and the live season
would start handing out best-in-slot gear silently. Deriving it from the role
makes it unforgettable rather than merely documented.

For dev, **the names carry no season number** (`homers_lotr_dev.mod`,
`dev.homerslotr.com`). `SEASON_NUM` in the dev repo only records which season it
currently feeds, so bumping it at a cutover renames nothing.

The two in-game cutover notices are **not** driven by this block, and are not
placeables `season-brand.py` manages — that design was retired (see
`season-cutover-prereqs.md` item 9). The outgoing season's existing
`recent_updates` board is re-texted by hand as the next-season notice, and the
incoming season's wipe warning is a coloured message in `servershout4.nss`.

`SEASON_*` is deliberately **not** forwarded into the container: `bin/serve`
passes only `TZ`, `NWN_*`, `NWNX_*` and `ANVIL_*`. Nothing needs it at runtime —
every branded string is baked in at brand time.

### Module and server naming

Three names get confused constantly. In NWN **the module name *is* the installed
`.mod` filename**, so `NWN_MODULE` must equal it exactly, minus the extension, or
`nwserver` exits at boot with a module-not-found error.

| Name | Where it lives | Season N value |
|------|----------------|----------------|
| Build artifact | `nasher.cfg` → `[package].name` and `[target].file` | `homers_lotr_s<N>.mod` |
| **Installed module** | `$NWN_HOME_DIR/modules/<name>.mod`, written by the repack wrapper | `Homer's LOTR Season <N>.mod` |
| `NWN_MODULE` | `server.env` — the installed filename, **no `.mod`** | `Homer's LOTR Season <N>` |
| `NWN_SERVERNAME` | `server.env` — server-browser name, free text | role-dependent ↓ |

| `SEASON_ROLE` | `NWN_SERVERNAME` | Build artifact |
|------|-------------|---|
| `test` | `Homer's LOTR - Season <N> (EARLY ACCESS)` | `homers_lotr_s<N>.mod` |
| `live` | `Homer's LOTR - Season <N>` | `homers_lotr_s<N>.mod` |
| `archive` | `Homer's LOTR - Season <N> (ARCHIVED)` | `homers_lotr_s<N>.mod` |
| `dev` | `Homer's LOTR - DEV REALM (password required)` | `homers_lotr_dev.mod` |

The dash is an ASCII hyphen, not an em dash: the string is passed through the
container env to `nwserver` and on to the master server browser.

**Season 1 keeps its legacy names** — `homers_lotr_v3.mod`, module
`Homer's LOTR VEL v3`, server name `Homer's LOTR Very Easy Leveling` — which is
what `SEASON_LEGACY_NAMES=1` enforces. Never rename a live module: the filename
change alone leaves every player's saved server entry pointing at a module that
no longer exists. Numbering starts at season 2.

Renaming has no data consequence — the servervault is per-`NWN_HOME_DIR` and
campaign DBs are scoped by their own name, so neither is keyed to the module
name. It is purely cosmetic plus the `NWN_MODULE` match.

## Prerequisites

`nasher`, `nwn_gff`, `nwn_script_comp`, and `python3` (for `wiki`) must be
on `PATH`. See [`nwn-manager`](../nwn_manager/README.md) for install
instructions on Bazzite / immutable Fedora.
