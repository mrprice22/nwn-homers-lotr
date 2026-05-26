# Resource shapes cheat sheet

When adding or modifying a blueprint, copy a similar existing file and
mutate it. Don't try to write one from scratch — the engine is fussy about
field presence and `__struct_id` values.

## Area (`<name>.are.json` / `<name>.git.json` / `<name>.gic.json`)

- `.are.json` — static area data: `Tileset` (resref like `ttr01`),
  `Width`/`Height` in tiles, `Tile_List` (one struct per tile;
  `Tile_ID`, `Tile_Orientation`, lighting), event scripts (`OnEnter`,
  `OnExit`, `OnHeartbeat`, `OnUserDefined`), weather, lighting, fog,
  day/night colors. `ResRef` and `Tag` must be present.
- `.git.json` — Game Instance Tracking. Lists every placed creature, door,
  encounter, placeable, sound, store, trigger, waypoint. Each instance is
  a struct that **mostly** mirrors the blueprint's fields but wraps them
  with the list's canonical `__struct_id` and instance-level position
  fields — and those position fields differ by list (see table below). Top-level
  `AreaProperties` holds music/ambient sound IDs.

  **An instance struct is not the same shape as the corresponding `.utc` /
  `.utp` blueprint.** Copying the blueprint root verbatim into a list is
  the most common way to silently break a placement — the engine skips
  wrong-shape entries with no error, no compile warning, no in-game
  message. Always start from a *neighboring existing instance* in the same
  `.git.json` list and overlay only identity/position fields.

  Canonical per-list values (surveyed across the module, ≥99.9% agreement):

  | List              | `__struct_id` | Position fields                                              |
  |-------------------|---------------|--------------------------------------------------------------|
  | `Creature List`   | `4`           | `XPosition`, `YPosition`, `ZPosition`, `XOrientation`, `YOrientation` |
  | `Placeable List`  | `9`           | `X`, `Y`, `Z`, `Bearing` (**not** the `*Position`/`*Orientation` fields) |
  | `Door List`       | `8`           | (verify against a sibling before placing)                    |
  | `TriggerList`     | `1`           | (verify)                                                     |
  | `Encounter List`  | `7`           | (verify)                                                     |
  | `WaypointList`    | `5`           | (verify)                                                     |
  | `SoundList`       | `6`           | (verify)                                                     |
  | `StoreList`       | `11`          | (verify)                                                     |

  Instances should also **not** carry `Comment` or `PaletteID` — those are
  toolset/palette-only and belong in `.gic.json` (Comment) or `*palcus.itp.json`
  (PaletteID), not in the live `.git` entry. Both fields silently break
  creature spawns when present on a `Creature List` entry: across the
  module's 984 working creatures, **0 carry `PaletteID`** and only 2 carry
  `Comment`. The corresponding `.gic.json` entry for a creature is a
  tiny struct of exactly two fields: `__struct_id: 4` and
  `Comment: {type: cexostring, value: ""}`.

  **GIC `__struct_id` must always be the constant `4` for creatures (never
  the list index).** If you programmatically append GIC entries using a loop
  counter as the struct_id you get wrong IDs (0, 1, 2, …) which cause the
  NWN toolset to crash with an access violation when opening the area.
  Always hardcode `__struct_id: 4` for every creature GIC entry regardless
  of position.

  **The safest way to place a new instance:** clone (deep-copy) an
  existing working sibling from the *same area* and overwrite only the
  identity fields — `Tag`, `TemplateResRef`, `FirstName`/`LastName`,
  position. Don't author the embedded struct from a `.utc/.utp`
  blueprint. The .git instance carries ~70-95 fields with specific GFF
  types, and any drift (wrong type, missing field, extra toolset field)
  silently nullifies the placement.

### Picking coordinates — use `bin/place-helper.py`

Coordinates that look fine in `.are.json` bounds can still land in walls,
on top of placeables, or on tiles the engine considers unreachable. Use:

```
bin/place-helper.py <area_resref>                # overview + ASCII map
bin/place-helper.py <area_resref> <x> <y>        # clearance + reachability for one point
bin/place-helper.py <area_resref> --suggest      # propose clear, reachable spots
```

Heuristics it uses:

- **Tiered reachability anchors:**
  1. **Placed creatures** (strongest) — provably walking around in-game,
     within ~15m is a strong walkable signal.
  2. **Encounter spawn points** (medium) — engine spawns creatures there,
     so the spot itself plus a few metres around is walkable.
  3. **Waypoints** (weakest) — author put a path marker there; often but
     not always walkable.
- **Clearance:** placeables get an assumed footprint radius (~2.5m); a
  candidate that sits inside another placeable's footprint will look
  collided in-game even if both technically exist.
- **`--suggest` excludes `mw_*`** anchors (circular result prevention).
- **Placeables ≠ walkable evidence.** `ZEP_WATER*` and other scenery can
  sit on non-walkable tiles.

- `.gic.json` — parallel comment list, one entry per instance, in the
  same order as `.git`. Don't reorder one without the other.

## Creature (`<name>.utc.json`, type `UTC`)

See `docs/creatures/<resref>.html` for a human-readable view of any existing
creature's fields. Non-obvious fields when editing: `Appearance_Type` (numeric
row — see catalogue below), `FactionID` (index into `repute.fac.json`),
`Conversation` (resref of `.dlg`, not a tag), ability scores all `byte`,
HP fields all `short`, `ClassList` a list of `{ Class, ClassLevel }` structs.

**Standard creature event scripts.** This module mixes the NW1 default
set (`nw_c2_default*`) with the X2/HotU set (`x2_def_*`). Use whichever
the surrounding similar creatures use; both ship with NWN:EE.

| Script field        | NW1 default       | X2/HotU default      |
|---------------------|-------------------|----------------------|
| `ScriptHeartbeat`   | `nw_c2_default1`  | `x2_def_heartbeat`   |
| `ScriptOnNotice`    | `nw_c2_default2`  | `x2_def_percept`     |
| `ScriptEndRound`    | `nw_c2_default3`  | `x2_def_endcombat`   |
| `ScriptDialogue`    | `nw_c2_default4`  | `x2_def_onconv`      |
| `ScriptAttacked`    | `nw_c2_default5`  | `x2_def_attacked`    |
| `ScriptDamaged`     | `nw_c2_default6`  | `x2_def_ondamage`    |
| `ScriptDeath`       | `nw_c2_default7`  | `x2_def_ondeath`     |
| `ScriptDisturbed`   | `nw_c2_default8`  | `x2_def_ondisturb`   |
| `ScriptSpawn`       | `nw_c2_default9`  | `x2_def_spawn`       |
| `ScriptRested`      | `nw_c2_defaulta`  | `x2_def_rested`      |
| `ScriptSpellAt`     | `nw_c2_defaultb`  | `x2_def_spellcast`   |
| `ScriptUserDefine`  | `nw_c2_defaultd`  | `x2_def_userdef`     |
| `ScriptOnBlocked`   | `nw_c2_defaulte`  | `x2_def_onblocked`   |

Common module-specific overrides: `ScriptDeath` is often `staticspawn`,
`gpondeath`, or a per-quest script (e.g. `dolguldurshout`).

### Appearance constants

`Appearance_Type` is a numeric row index into `appearance.2da`. **Don't guess**
— a wrong value renders as the invisible-model fallback with no error.

Best approach: clone an existing creature's `Appearance_Type` verbatim.
`docs/creatures/<resref>.html` shows each blueprint's appearance as a readable
label (e.g. "Human", "Balor"). To find the numeric value for a constant name:

```
grep APPEARANCE_TYPE_BALOR ~/.local/share/Steam/steamapps/common/Neverwinter\ Nights/ovr/nwscript.nss
```

Available in-module options: grep `unpacked/sd_appear_*.nss` — each file's
`APPEARANCE_TYPE_*` constant corresponds to one choice in the in-game
appearance changer (area `appearancechange`, NPC tag `NW_COW`).

## Item (`<name>.uti.json`, type `UTI`)

Key fields: `TemplateResRef`, `Tag`, `LocalizedName`, `Description`,
`BaseItem` (row in `baseitems.2da` — e.g. 16 = half plate, 70 = leather
boots, 113 = arrow), `Cost`, `StackSize`, `PropertiesList`, color slots
(`Cloth1Color`/`Metal1Color`/`Leather1Color`/etc), and for armor the
20 `ArmorPart_*` fields (model parts like `ArmorPart_Belt`,
`ArmorPart_LBicep`, etc).

`PropertiesList` entries describe item properties:

```jsonc
{ "__struct_id": 0,
  "PropertyName": { "type": "word", "value": 1   },  // itempropdef.2da row
  "Subtype":      { "type": "word", "value": 0   },  // depends on PropertyName
  "CostTable":    { "type": "byte", "value": 2   },  // iprp_costtable.2da row
  "CostValue":    { "type": "word", "value": 5   },  // index into that table
  "Param1":       { "type": "byte", "value": 255 },  // 255 = unused
  "Param1Value":  { "type": "byte", "value": 0   },
  "ChanceAppear": { "type": "byte", "value": 100 } }
```

## Door / Placeable / Trigger / Encounter / Waypoint / Store

All follow the same pattern as creatures: a `TemplateResRef`, a `Tag`,
typed fields, and event-script `resref` fields. Defaults to copy:

- **Doors** (`UTD`): `OnDeath` → `x2_door_death`, `OnSpellCastAt` → `close_door_fast`.
- **Placeables** (`UTP`): event scripts default to empty unless interactive.
- **Triggers** (`UTT`): `ScriptOnEnter`/`ScriptOnExit`/`ScriptHeartbeat`/`ScriptUserDefine`.
- **Encounters** (`UTE`): `OnEntered`/`OnExit`/`OnExhausted`/`OnHeartbeat`/`OnUserDefined`,
  plus `CreatureList` (what spawns) and `MaxCreatures`/`Difficulty`.
- **Waypoints** (`UTW`): no event scripts. Walk-path waypoints are tagged
  `WP_<creature_tag>_NN` and used by `WalkWayPoints()`.
- **Stores** (`UTM`): `StoreList` of struct IDs 0..4 = the five inventory
  pages (Armor, Misc, Potions, Rings, Weapons in CEP layout). `MarkUp`/
  `MarkDown` are buy/sell percentages; `MaxBuyPrice` caps individual
  buys; `BlackMarket=1` enables stolen-goods handling.

## Conversation (`<name>.dlg.json`, type `DLG`)

Three parallel lists held at the root, plus a `StartingList`:

- **`StartingList`** — links into `EntryList`. The engine evaluates each
  `Active` (a `StartingConditional` script) in order and shows the first
  whose conditional passes (or the first with no conditional).
- **`EntryList`** — what the **NPC** says. Each entry has a `Text`
  (locstring), an optional `Sound`, `Animation`, `Quest`, and a per-node
  `Script` (action: `void main()` that runs when this node fires). Its
  `RepliesList` links into `ReplyList`.
- **`ReplyList`** — what the **PC** can pick. Same fields as Entry plus
  an `EntriesList` linking back into `EntryList` for the next NPC line.
  An empty `EntriesList` ends the conversation.

Links carry the conditional, the targets carry the action — schematically:

```
StartingList[i].Active   → StartingConditional (gates whether entry shows)
StartingList[i].Index    → EntryList[Index]
EntryList[i].Script      → action script (runs when NPC line shown)
EntryList[i].RepliesList[j].Active → conditional (gates the PC choice)
EntryList[i].RepliesList[j].Index  → ReplyList[Index]
ReplyList[k].Script      → action script (runs when PC line picked)
ReplyList[k].EntriesList[l].Index → next EntryList[Index]
```

`Index` values are 0-based positions in the sibling list. **Renumbering
or deleting an entry/reply re-indexes everyone**: when removing a node,
patch every `Index` in every link list that refers to a higher position.
Easier to leave dead nodes in place than to compact.

`EndConverAbort` and `EndConversation` at the root are scripts that run
when the conversation ends naturally / is interrupted (commonly
`nw_walk_wp` to resume a waypoint patrol).

Convention in this module:
- Action scripts: `at_NNN.nss` (numeric, e.g. `at_054`) — auto-named by
  the toolset's script wizard.
- Conditional scripts: signature must be `int StartingConditional()`
  returning `TRUE`/`FALSE`. Many use the `dmfi_univ_cond` family.

## Journal (`module.jrl.json`)

`Categories` is a list of quests; each quest has a `Tag` (string used by
`AddJournalQuestEntry`), a `Name`, `Priority`, `XP`, and an `EntryList`
of entry stages (`ID` = stage number passed to `AddJournalQuestEntry`,
`End=1` marks final stage).

## Faction (`repute.fac.json`)

`FactionList` holds factions in struct-id order — referenced from
`UTC.FactionID`. The first four are the engine-required PC/Hostile/
Commoner/Merchant/Defender. `RepList` is a flat list of pairwise
reputations (`FactionID1`, `FactionID2`, `FactionRep` 0–100).

## Palette files (`*palcus.itp.json`)

These are the toolset's custom-blueprint palettes, one per category
(creature/door/encounter/item/placeable/sound/store/trigger/waypoint).
Editing them affects only the in-toolset categorization, never gameplay.

**Every new blueprint you create must be added to the matching
`*palcus.itp.json` or it will be invisible in the toolset and DM client
palette.** Scripts that `CreateObject` from a resref work without a palette
entry, but a DM trying to manually place or inspect the blueprint from the
palette won't find it.

- **Creature entries** need `RESREF`, `NAME` (or `STRREF` for a TLK ref),
  `CR` (float), and `FACTION` (cexostring like `"Commoner"` or `"Hostile"`).
- **Waypoint entries** need only `RESREF` and `NAME` (cexostring display label).
- Add to an existing category — categories are identified by their `ID`
  (byte) + `STRREF` (TLK ref for the label); creating a new category
  requires a new TLK entry, so prefer re-using an existing one.
- MW creatures live in **category index 11** (`creaturepalcus.itp.json`,
  ID=116) alongside other module-custom creatures.
- The `mw_spawn` waypoint blueprint lives in **category index 4**
  (`waypointpalcus.itp.json`, ID=4).

**`LocalizedName` on placed instances controls what the DM client displays.**
When you place a waypoint from a stock blueprint like `nw_waypoint001`, the
instance inherits the TLK name (`{"id": 14817}` → "Waypoint"). To give it a
meaningful label, set `LocalizedName` to an explicit inline string in the
`.git.json` entry:

```json
"LocalizedName": { "type": "cexolocstring", "value": { "0": "MW Spawn: Jordan Peterson" } }
```

All `MW_SPAWN_*` waypoints already have this set.
