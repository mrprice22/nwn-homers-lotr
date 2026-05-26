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
4. Repack and test in-game.

## Add a new NPC creature

1. Pick a unique resref ≤ 16 chars (e.g. `myorc01`). Verify nothing else
   in `unpacked/` uses it: `ls unpacked/myorc01.*`.
2. Copy a similar `.utc.json` to `myorc01.utc.json`. Edit
   `TemplateResRef`, `Tag`, `FirstName`/`LastName`, ability scores,
   `ClassList`, `Appearance_Type`, `Conversation`, scripts, equipment.
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

## Add a new item

1. Pick a resref. Copy a similar `.uti.json` (one with the right `BaseItem`
   row).
2. Edit `TemplateResRef`, `Tag`, `LocalizedName`, `Description`, `Cost`,
   appearance fields, `PropertiesList`.
3. To put it in a creature's inventory or a chest, add an entry to the
   container's `ItemList` with `InventoryRes` = your resref.
4. Or spawn with `CreateItemOnObject("myitem", oTarget, 1);`.

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
