# Boss respawn tracker ("Roll of the Fallen") — maintenance

The Well of Eru board that lists currently-slain bosses with respawn countdowns
and who killed them. Player-facing docs: `docs.manual/Customizations.html#boss-respawn-tracker`.

## Moving parts

| Piece | Where |
|-------|-------|
| Registry + all DB/board logic | `unpacked/brd_db.nss` (campaign DB `respawndb`: `boss_registry`, `boss_alias`, `boss_deaths`) |
| Death hook | one `BRD_RecordDeath()` call in `unpacked/bst_ondeath.nss` (rides the bestiary's runtime OnDeath wrapper — covers every boss with no per-blueprint edits) |
| Init / reset | `BRD_InitDb()` in `unpacked/onmoduleload.nss` — reseeds the registry from source and **wipes `boss_deaths`** (a restart revives every boss) |
| Board | placeable tag `boss_respawn_board` in `thewelloferu.git.json` (`Conversation: brd_sign`, `OnUsed: brd_use`), dialog `brd_sign.dlg.json`, scripts `brd_use` / `brd_vis_0..8` / `brd_open_0..8` / `brd_page_n|p` / `brd_has_next|prev` / `brd_back` |
| Custom tokens | **6300–6313 reserved** (6300-6308 rows, 6309 header, 6310-6313 detail) |
| Build gate | `tests/check_boss_registry.py` in `tests/smoke-test` — every repack verifies the registry against `unpacked/` |

## Adding a boss

All manual curation happens in **one place**: the `BRD_SeedBoss(...)` block in
`brd_db.nss`. No dialog/token/git edits needed for a new boss.

1. Confirm the **single-instance rule** — the creature can only ever have one
   live copy in the world. Placed: exactly one instance across all
   `*.git.json` and in no encounter. Encounter: not placed anywhere and in
   exactly one encounter *instance* with `MaxCreatures=1`, `Respawns=-1`,
   `Reset=1`. (Multi-spawn or dual-source creatures were deliberately
   excluded: Bilbo, Underlord of Sauron, thundergut, weathertop-class bosses.)
2. Confirm it **actually respawns**:
   - placed → OnDeath must reach `SE_DoCreatureRespawn()`
     (`nw_c2_default7`, `x2_def_ondeath`, `staticspawn`, and now
     `deathalert`/`dunharrowdeath` all do). Tag must not contain `NSP`.
     Respawn is the flat 900 s in `se_respawn_inc.nss`.
   - encounter → respawn = the encounter instance's `ResetTime`. If you
     change it, change the `.ute` **and** the instance struct in the area's
     `.git.json` (the instance value is what the engine uses), and keep the
     registry's `respawn_seconds` equal to it.
3. Add a `BRD_SeedBoss("resref", "Display Name", "Tag", "area_resref",
   "Area Display Name", CR, 900, "placed"|"encounter")` row. Use the
   **blueprint's ChallengeRating** for CR (it drives the board sort) and
   ASCII-only display names (NWScript literals with non-ASCII bytes are a
   known compiler hazard — see the Khamul entries).
4. If the boss spawns as multiple variant blueprints of one identity (like the
   five leveled Xanith `.utc`s in a Max=1 encounter), pick one canonical
   resref and add `BRD_SeedAlias("variant", "canonical")` for the rest.
5. Run `python3 tests/check_boss_registry.py` — it fails with a specific
   message for every rule above. Then repack (the smoke-test runs it again).

Removing a boss = delete its seed row (and any alias rows pointing at it).
The registry is `DELETE`d and reseeded on every module load, so stale DB rows
clean themselves up.

## Don't break it

- **Don't remove or reorder the `BRD_RecordDeath(oCre)` call** in
  `bst_ondeath.nss` past the early-return blocks — it must run even when no PC
  gets kill credit (trap/DM kills still leave the boss dead).
- **Don't give a tracked boss a second placement or encounter slot** (and
  don't re-tag one) without updating the registry — the build gate will catch
  it, that's what it's for; fix the registry, don't weaken the test.
- **Two same-tag bosses exist** (`Khamul` on both `creature007` and
  `creature007_2`). Liveness checks are tag **+ area** (`BRD_BossAlive`);
  keep `area_resref` correct if a boss is ever moved.
- **Encounter instance overrides repurpose blueprints**: the five `moriabyss`
  instances in `theabyssofmoria` are trash overrides; only the
  `thebalrogofmoria` instance spawns the Balrog. Same trick spawns Legolas
  from a `nw_aberration` instance in `area023`. Always inspect the
  instance-level `CreatureList` in the `.git.json`, never trust the `.ute`
  alone.
- **Tokens 6300–6313 are claimed** — pick a different range for new systems.
- The `boss_deaths` wipe in `BRD_InitDb()` is intentional (restart = all
  alive). Don't "fix" it into persistence without also persisting respawn
  timers, which don't survive a restart.
