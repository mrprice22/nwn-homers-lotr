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

1. Create the `.utc.json` blueprint. The world (`_w`) variant's **Tag must be
   `mw_<guide>_w`** — the generic quiz scripts derive the guide name from it.
2. Add a `SpawnAtWaypoint` call in `mw_spawn.nss`.
3. Add the `_w` blueprint to `creaturepalcus.itp.json` category 11 (so it
   appears in the DM palette).
4. Place an `mw_spawn` waypoint in the target area (from Waypoint palette →
   Custom 5) with the correct `Tag`.
5. Extend the spawn table in `docs/scripts/mw_spawn.html`.
6. Wire up the unlock quiz: add a 20-question bank to **`mw_quiz_bank.yaml`** (the
   single source of truth), register the guide in `bin/gen-mw-quiz.py`, then run it
   to (re)generate `mw_quiz_data.nss`, `mw_quiz_bank.json`, the `MeaningWave.md`
   answer key, `mw_<guide>_m.dlg.json`, and the in-wiki practice quiz on
   `docs.manual/MeaningWave.html`. See the "Adding a new Meaningwave NPC"
   recipe in [MeaningWave.md](MeaningWave.md) for the full checklist. The quiz engine
   itself (`mw_quiz_inc.nss` + generic `mw_q_*.nss` scripts) is shared across all
   guides — you do not write per-NPC quiz scripts, and you never hand-edit the files
   generated from the YAML.

   **In-wiki practice quiz.** `docs.manual/MeaningWave.html` also hosts a per-legend
   *practice* quiz (same 5-of-20 draw and 4/5 pass mark, reports score % only, no
   in-game unlock). `gen-mw-quiz.py` owns only the question data — it injects the
   bank into the page's `#mw-quiz-bank` island between the `MW-QUIZ-DATA` markers;
   the quiz engine, per-legend `<div class="mw-quiz" data-guide="…">` widgets, and
   CSS are hand-authored in the page. A new guide needs one widget div added under
   its `<h2 id>` section (slug = guide key). Re-running the generator keeps the wiki
   data in sync; `tests/check_mw_quiz.py` gates drift. The questions change rarely,
   so this re-sync stays a **manual** `python3 bin/gen-mw-quiz.py` run — do **not**
   trigger a wiki refresh for it.

See also `MeaningWave.md` for fuller developer notes: blueprint resrefs,
waypoint tags, spawn script locations, and how to regenerate path documentation.
