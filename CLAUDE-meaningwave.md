# Meaningwave NPCs

Eight philosopher/thinker NPCs that spawn via script at module load. The spawn
logic is in `mw_spawn.nss`, called from `onmoduleload.nss`. Each NPC spawns at
a waypoint whose **Tag** you set in the toolset.

To place or relocate an NPC: open the area in the toolset, place the
**`mw_spawn`** waypoint blueprint (Waypoint palette → Custom 5), then set its
Tag to the value in the table in `docs/scripts/mw_spawn.html` (or read the
header comment in `unpacked/mw_spawn.nss`). Using the `mw_spawn` blueprint
gives it the correct `LocalizedName` automatically. Alternatively place any
waypoint and hand-edit `LocalizedName` in the `.git.json` to
`{"0": "MW Spawn: <NPC Name>"}` so it's identifiable in the DM client.

The `_w` blueprint variants are the wandering versions placed in-world. The
non-`_w` blueprints (e.g. `mw_peterson`) are alternates (e.g. for quests/
dialogues). To add a new Meaningwave NPC:

1. Create the `.utc.json` blueprint.
2. Add a `SpawnAtWaypoint` call in `mw_spawn.nss`.
3. Add the `_w` blueprint to `creaturepalcus.itp.json` category 11 (so it
   appears in the DM palette).
4. Place an `mw_spawn` waypoint in the target area (from Waypoint palette →
   Custom 5) with the correct `Tag`.
5. Extend the spawn table in `docs/scripts/mw_spawn.html`.

See also `MeaningWave.md` for fuller developer notes: blueprint resrefs,
waypoint tags, spawn script locations, and how to regenerate path documentation.
