# MeaningWave — Developer Notes

Player-facing guide lives at `docs/manual/MeaningWave.html`.
This file covers implementation details, script locations, and maintenance tasks.

## Quick reference

| NPC | Blueprint resref | Class build | Waypoint tag | Area resref | Reward items |
|-----|-----------------|-------------|--------------|-------------|--------------|
| Jordan Peterson | `mw_peterson_w` | Wizard 60 | `MW_SPAWN_PETERSON` | `rivendellupperha` | `mw_peter_robes`, `mw_peter_staff` |
| Alan Watts | `mw_watts_w` | Cleric 30 / Monk 30 | `MW_SPAWN_WATTS` | `oldforest001` | — |
| Joseph Campbell | `mw_campbell_w` | Bard 60 | `MW_SPAWN_CAMPBELL` | `balinstomb` | `mw_camp_robes`, `mw_camp_staff` |
| Terence McKenna | `mw_mckenna_w` | Druid 60 | `MW_SPAWN_MCKENNA` | `northernforestso` | — |
| Jocko Willink | `mw_jocko_w` | Fighter 30 / Monk 30 | `MW_SPAWN_JOCKO` | `helmsdeep001` | — |
| Carl Jung | `mw_jung_w` | Fighter 20 / Rogue 20 / Shadowdancer 20 | `MW_SPAWN_JUNG` | `cryptsofthelosts` | — |
| Marcus Aurelius | `mw_aurelius_w` | Paladin 60 | `MW_SPAWN_AURELIUS` | `gwaththrone` | `mw_aurel_armor`, `mw_aurel_sword` |
| Akira the Don | `mw_akira` | — | — | `hallofleg` | — |

> **16-char limit:** All NWN ResRefs (filenames, `TemplateResRef`, `Conversation`) must be ≤ 16 chars.
> Item resrefs use abbreviated names (`mw_aurel_`, `mw_camp_`, `mw_peter_`) for this reason.

## Key scripts

- **`mw_spawn.nss`** — called from `onmoduleload.nss`; spawns each wandering `_w` NPC at its
  waypoint tag. Add new `SpawnAtWaypoint` calls here for any new Meaningwave NPCs.
- **`mw_unlock_inc.nss`** — shared include for unlock state checks. Used by quiz dialogue
  conditionals and by the emote-wand summon logic.
- **`emotewand.dlg`** — contains the "[Summon a Legend.]" branch; conditionals gate each
  option on the matching unlock flag.
- **Dialogue resrefs** — each NPC has a `mw_<name>_h.dlg.json` (henchman) for the post-summon
  dialogue. The five-question quiz lives in `mw_<name>_l` / `mw_<name>_m`.

## Combat styles

Each summoned guide understands a "Let's talk tactics." dialogue option (shown only
when the NPC is currently your henchman) that switches their combat behaviour.

Style is stored as `LocalInt(oNPC, "MW_STYLE")` = 0/1/2.
Scripts `mw_style_0.nss`, `mw_style_1.nss`, `mw_style_2.nss` set the value from dialogue.
`mw_is_hench.nss` is the Active conditional that gates the tactics reply.

| NPC | Script | Style 0 (default) | Style 1 | Style 2 |
|-----|--------|-------------------|---------|---------|
| Peterson (Wiz) | `mw_arc_er` | **Calculated** — Epic Warding first, then nuke | **Aggressive** — Hellball/Ruin/Dragon Knight immediately | — |
| Watts (Clr/Mnk) | `mw_watts_er` | **Enlightened** — heal party <50% HP, self-buff, then fight | **Guardian** — pure support; heal party <70% HP, buff when healthy | **Zen Strike** — Divine Power + Quivering Palm in melee |
| Campbell (Brd) | `mw_sup_er` | **Balanced** — heal <25% HP, else standard AI | **Combat** — offensive spells, emergency heal <15% | **Healer** — heal <50% HP, Haste on master |
| McKenna (Drd) | `mw_sup_er` | **Balanced** | **Combat** | **Healer** |
| Jocko (Ftr/Mnk) | `mw_jocko_er` | **Get After It** — Stunning Fist every round + standard AI | **Extreme Ownership** — attacks enemies targeting the master | — |
| Aurelius (Pal) | `mw_aurel_er` | **Guardian** — heal master <50% HP | **Offensive** — self-heal if critical, attack master's attackers | — |
| Jung (Ftr/Rog/SD) | `mw_jung_er` | **Shadow** — hide (HIPS), attack master's attacker for sneak | **Warrior** — standard AI | — |

**Notes:**
- Epic spell `ActionUseFeat` silently no-ops once the daily slot is expended; regular memorized
  spells (now populated in all caster blueprints) are handled by `x2_def_endcombat` fallback.
- Guardian (Watts) returns early without falling to `x2_def_endcombat` — she will not attack.
- Healer (Campbell/McKenna) also returns early — pure support mode.
- Jung's Shadow mode calls `SetActionMode(OBJECT_SELF, ACTION_MODE_STEALTH, 1)` mid-combat;
  Hide in Plain Sight (granted by Shadowdancer 1) lets this succeed while observed.

## Adding a new Meaningwave NPC

1. Create `mw_<name>.utc.json` (wandering blueprint) and `mw_<name>_w.utc.json` (placed world variant).
2. Add a `SpawnAtWaypoint("MW_SPAWN_<NAME>", "mw_<name>_w")` call in `mw_spawn.nss`.
3. Add `mw_<name>_w` to `creaturepalcus.itp.json` category index 11 (ID=116).
4. Place an `mw_spawn` waypoint in the target area (Waypoint palette → Custom 5) with
   Tag = `MW_SPAWN_<NAME>`.
5. Author `mw_<name>.dlg.json` with the five-question quiz and summon/henchman wiring.
6. Add the unlock flag check to `mw_unlock_inc.nss` and a new branch in `emotewand.dlg`.
7. Update `docs/manual/MeaningWave.html` with the player-facing location and path info.

## Regenerating path documentation

If new transitions are added to the module, regenerate paths with the `nwn-area-path`
tool that ships with `nwn-manager`:

```sh
# All guide paths (after `nwn-manager wiki` is up to date):
for area in rivendellupperha oldforest001 balinstomb northernforestso \
            helmsdeep001 cryptsofthelosts gwaththrone hallofleg; do
  echo "=== thewelloferu → $area ==="
  nwn-area-path thewelloferu "$area"
done

# Or pipe through JSON for tooling:
nwn-area-path --json thewelloferu rivendellupperha
```

The graph is built from the static wiki under `docs/areas/`. Doors and triggers are reliable
edges; conversation teleports (talk-NPCs like the Guardian of Light) are also captured.
Re-run `nwn-manager wiki` after adding new areas (like the Hall of Legends) so the graph
stays current.

The wiki extractor does **not** pick up placeable-OnUsed teleports (the Wayshrine of the Wave
is one), so those edges live in a hand-maintained side-car at `docs/area_edges_extra.json`.
Add `{"from","to","kind","label"}` objects there to declare any custom teleport that scripts
handle but the wiki misses.

## Hall of Legends — statue / unlock mechanic

Statues on unearned pedestals are converted to live figures via a script that checks
the unlock flags set in `mw_unlock_inc.nss`. See the Hall of Legends area and the
`hallofleg` conversation for the Akira reward ("Akira's Mixtape") trigger.
