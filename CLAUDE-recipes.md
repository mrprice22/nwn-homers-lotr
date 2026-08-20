# Common edit recipes

## Modify an existing NPC's stats / appearance

1. Find the blueprint: `<resref>.utc.json` in `unpacked/`.
2. Edit the field directly (e.g. `Str.value`, `MaxHitPoints.value`,
   `Appearance_Type.value`).
3. **Note**: `.utc.json` is the *blueprint*. Existing instances in
   `<area>.git.json` carry a copy of the blueprint fields and won't
   automatically pick up changes. To update placed instances too, also
   patch the embedded creature struct inside `<area>.git.json`'s
   `Creature List`. Easiest way for many areas: re-place from the
   palette in the toolset, or script a JSON patch.
4. **On respawn the blueprint wins.** `se_respawn_inc.nss` recreates a dead
   static creature with `CreateObject(GetResRef(self), …)`, preserving only
   the tag — so an instance you *didn't* sync silently reverts after its
   first death. `tests/check_divergent_creatures.py` gates on name, faction,
   conversation, abilities, classes, feats, special abilities, equipment
   (resref **and** slot), carried inventory, natural AC and race. It does
   **not** cover `PortraitId`, `SoundSetFile`, `Gender`, `ChallengeRating`,
   `Appearance_Type`/`Appearance_Head` or the colour/body-part fields — those
   revert too, silently, with no build error. Sync them by hand.
5. Repack and test in-game.

## Place an existing NPC in another area

**"Copy NPC X to area Y" means a second *instance* of the same blueprint** —
not a second blueprint. Only an explicit **"deep copy"** means duplicate the
`.utc.json`.

1. Keep the same `TemplateResRef`. Do **not** create `<resref>_2`.
2. Clone a neighbouring `__struct_id: 4` struct in the *target* area's
   `Creature List` and overwrite its position fields (see
   [CLAUDE-blueprints.md](CLAUDE-blueprints.md); use `bin/place-helper.py` to
   pick coordinates).
3. Add the parallel entry to the area's `.gic.json` at the same index —
   the two lists are positional.
4. Nothing else to do: both instances now share one blueprint, so there is no
   divergence to keep in sync and no duplicate palette leaf.

Two blueprints that share a `Tag` are legal and silent — see
[CLAUDE-gotchas.md](CLAUDE-gotchas.md). This is how the module ended up with
`butcha` and `butcha_2`, two indistinguishable "Ping Pong" entries in the
toolset palette, one of them attached to nothing.

## Add a new NPC creature

1. Pick a unique resref ≤ 16 chars (e.g. `myorc01`). Verify nothing else
   in `unpacked/` uses it: `ls unpacked/myorc01.*`.
2. Copy a similar `.utc.json` to `myorc01.utc.json`. Edit
   `TemplateResRef`, `Tag`, `FirstName`/`LastName`, ability scores,
   `ClassList`, `Appearance_Type`, `Conversation`, scripts, equipment.
   - **Unique appearance.** Give the NPC a deliberately distinct
     `Appearance_Type` — don't reuse a neighbouring NPC's model by
     default (identical models everywhere is the "bland" trap).
     **Clone the numeric value from a real creature; never guess it**
     (a wrong id renders as the invisible-model fallback with no
     error). Check `module-index/creature_index.json` (`appearance_id`)
     for what's already used nearby so you pick something different.
   - **Proficiency feats must match the equipped gear.** If the NPC
     ships with equipped weapons/armor, put the matching proficiency
     feats in its `FeatList` — Armor Proficiency (Light/Medium/Heavy)
     + Shield for the armor, Weapon Proficiency (Simple/Martial/Exotic)
     for the weapon — or the module's **Jasperre AI unequips the gear
     at spawn** (the NPC appears unarmed/unarmoured; this bit the
     `fighter-line-early` / `rogue-line-early` UAT passes). Copy the
     feat ids from a real `.utc.json` that already equips that gear
     rather than recalling the numbers.
3. To place an instance in an area, **copy a neighboring creature struct
   already in that area's `<area>.git.json` `Creature List`** and edit
   only the identity fields (`Tag`, `TemplateResRef`, `FirstName`, etc.)
   and the position (`XPosition`, `YPosition`, `ZPosition`,
   `XOrientation`, `YOrientation`). The wrapping struct must use
   `__struct_id: 4` (creature instance). Do **not** start from the
   `.utc.json` blueprint — its root struct id is different and the engine
   will silently skip the placement.
   Then add a matching empty `Comment` struct to `<area>.gic.json`'s
   `Creature List`. Keeping `.git` and `.gic` in sync by index matters.
   The same pattern applies to placeables (`Placeable List`,
   `__struct_id: 9`, position fields `X`/`Y`/`Z`/`Bearing`) — placeables
   use a different position-field shape than creatures.
4. To make the NPC spawnable from script: leave it as a blueprint and
   spawn with `CreateObject(OBJECT_TYPE_CREATURE, "myorc01", lLoc)`.
5. File the new creature into the toolset palette:
   `python3 bin/file-palette-orphans.py --apply` (files it at its `PaletteID`
   home in `creaturepalcus.itp.json` so DMs can place it — placement follows the
   blueprint's `PaletteID`, matching the toolset; the `check_palette_coverage`
   smoke gate aborts the repack until it's filed). Standalone — **not** a wiki
   refresh.
6. **Verify in-game (UAT).** Spawn the NPC and confirm the model looks
   right **and** its weapon/armor stay equipped (not stripped by the AI
   for a missing proficiency feat). Under autopilot, record this as a
   `manual_steps` UAT entry naming the area by its **full toolset Name
   plus resref** (e.g. `Bree: The Prancing Pony (theprancingpo001)`),
   since the toolset sorts areas by Name.

## Add a new item

1. Pick a resref. Copy a similar `.uti.json` (one with the right `BaseItem`
   row).
2. Edit `TemplateResRef`, `Tag`, `LocalizedName`, `Description`, `Cost`,
   appearance fields, `PropertiesList`.
3. To put it in a creature's inventory or a chest, add an entry to the
   container's `ItemList` with `InventoryRes` = your resref.
4. Or spawn with `CreateItemOnObject("myitem", oTarget, 1);`.
5. If you embed a **full item struct** (own `PropertiesList`) in a store,
   creature inventory, or container — rather than an `InventoryRes` ref — and
   its properties differ from the `.uti` blueprint, re-run
   `python3 bin/gen-forge-legal.py` so the Forge contraband system whitelists
   the variant (otherwise legally obtaining it can jail the player). See
   "Forge legal-variant whitelist" in README.md.
6. File the new item into the toolset palette:
   `python3 bin/file-palette-orphans.py --apply` (files it at its `PaletteID`
   home in `itempalcus.itp.json`, matching the toolset; the
   `check_palette_coverage` smoke gate aborts the repack until it's filed).
   Standalone — **not** a wiki refresh.

## Add a new area

This is the most invasive change.

1. Build the area in the NWN:EE toolset (much easier than hand-rolling
   tile layouts), export it as `.are` + `.git` + `.gic`, then convert
   to JSON via `nwn_gff` and drop into `unpacked/`. Or copy a small existing
   area trio and edit.
2. The three files must share a base name = the area's ResRef.
3. **Append the new ResRef** to `module.ifo.json` →
   `Mod_Area_list.value` as a `{ "__struct_id": 6, "Area_Name": …}`
   struct. Without this the engine won't load the area.
4. Wire transitions: triggers (`.utt`) with `OnEnter` scripts that call
   `JumpToLocation`/`JumpToObject`, or doors (`.utd`) with a
   `LinkedTo` waypoint tag.
5. Repack — script compile errors will surface here.
6. **Re-run the map-note sync** so the new transitions get destination pins on
   the area map: `python3 bin/gen-map-notes.py` (audit) then `--apply`. It adds a
   destination-labeled map note on each new door/trigger/portal and a POI note at
   any teleporter NPC; it's idempotent so it won't touch existing notes. **Not
   optional** — `tests/check_map_notes.py` fails the repack while a transition
   has no pin. If a transition is meant to stay off the map (a back way in, a
   secret door), put `@nomapnote` in its Comment box in the toolset instead;
   `@mapnote Some Text` relabels a pin. See the "Map notes on area transitions"
   section in `README.md`. (The tool reads `module-index/area_graph.json`, which
   is wiki-generated — if you added areas since the last wiki build it warns
   which areas the graph can't see, and the gate stands down rather than
   blocking; the full sync lands after the next wiki refresh.)

## Add or edit a conversation

For small edits to existing dialogues, hand-editing `.dlg.json` is fine
if you understand the index linkage (see [CLAUDE-blueprints.md](CLAUDE-blueprints.md)).

For new conversations or large edits, **use the toolset** — index
bookkeeping is tedious to get right by hand. Round-trip will leave the
dialogue clean.

To wire a creature to its conversation: set `Conversation.value` on the
`.utc.json` (and on any placed instances in `.git.json`) to the dialogue's
resref (filename without `.dlg.json`).

## Add a script

1. Create `unpacked/myscript.nss` with `void main()` (or
   `int StartingConditional()` for a conditional).
2. Reference its resref (no extension) from wherever — a creature's
   `Script*` field, a door's `OnOpen`, a dialogue node's `Script`, etc.
3. Repack — compilation errors will appear with file/line.

## Add or edit a journal quest

Edit `module.jrl.json`:

1. Add a new struct to `Categories.value` with a unique `Tag`, a `Name`,
   and an `EntryList` with stages (`ID=1`, `ID=2`, … `End=1` on final).
2. Reference the quest from scripts via
   `AddJournalQuestEntry("MyQuestTag", 1, oPC);`.

## Edit module-level event hooks

Edit `module.ifo.json`. Set the relevant `Mod_On*` field's `value` to
the resref of an `.nss` script (no extension). The script must compile.
If you're adding the *first* implementation of a hitherto-unused hook,
add the script to `Mod_CacheNSSList` only if it's hot-path.

## Verifying a change

1. `./repack.sh` — compiles all changed scripts and packs the `.mod`.
   Compilation errors here are the first signal something's wrong;
   the script will halt and the message includes file + line.
2. Open the module in the NWN:EE toolset for a quick structural sanity
   check (it'll refuse to open a corrupt `.mod`).
3. Launch NWN:EE and load the module. Use the in-game DM client (this
   module ships dmfi/dmw, so DM tools are available) to teleport to the
   relevant area and exercise the changed feature.
4. Tail the NWN log if something silent is going wrong:
   `~/.local/share/Neverwinter Nights/logs/nwclientLog1.txt` (Linux).

The module has no automated test suite — verification is manual, in-game.
