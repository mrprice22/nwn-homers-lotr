# Autopilot — unattended roadmap loop

This is the runbook for **autopilot mode**: an unattended Claude session that works the
`roadmap.yaml` backlog item by item until it runs out of compute time (or the backlog is
exhausted). Start it with the `/autopilot` skill, or by telling a session "follow
CLAUDE-autopilot.md".

Everything in [CLAUDE.md](CLAUDE.md) and [CLAUDE-roadmap.md](CLAUDE-roadmap.md) still
applies. This document adds the loop, the guardrails, and a few explicit exceptions.

## Status vocabulary

The loop talks about tiers; `roadmap.yaml` talks about statuses. Mapping:

| Loop term | `roadmap.yaml` status |
|---|---|
| In progress | `confirmed` |
| Needs design input | `design` — blocked on an admin decision; branches off `confirmed` and returns to it |
| Needs manual finishing | `manual` — code done, admin toolset work outstanding; the **default landing state** after implementation |
| Up next | `wip` |
| Soon | `soon` |
| Later | `later` |
| Under consideration | `planned` |
| Shipped — in testing | `implemented` |
| Merit awarded (done) | `awarded` — **never set by the agent** |
| Not likely | `unlikely` — leave alone |

## Context economy

The loop is designed to survive context compaction and long runs. Two rules:

- **Files are the only state.** Each iteration must be executable with zero memory of the
  previous one: `roadmap.yaml` and git are the entire loop
  state — never depend on conversation history for what's done or in flight. Keep
  per-item exploration lean: use `module-index/` and `docs/` for lookups instead of
  reading raw `unpacked/` JSON, and don't pull large files into context when a targeted
  read will do.
- **Fresh context per item — delegate implementation to a subagent.** The orchestrating
  session runs the loop bookkeeping (select, rebalance, roadmap edits, commits, pushes)
  and launches a `general-purpose` subagent (synchronous, `run_in_background: false`) to
  do steps 3/3b for each item. Each subagent starts with a clean context window — the
  equivalent of `/clear` between items. The subagent's brief must include: the item's
  `id`/`title`/`notes`, an instruction to read `CLAUDE.md` + `CLAUDE-autopilot.md` first,
  the no-coordinate-picking and hard rules, and what to report back (see step 3). Small,
  obviously-mechanical items (a typo fix, a single-value tweak) may be done inline by the
  orchestrator instead — don't pay a subagent spin-up for a one-liner.

## The loop

Each iteration works exactly **one** item, end to end:

### 0. Reconcile

Before picking anything, check for a previous run cut off mid-item (reboot, crash, ran
out of compute). Read `autopilot-wip.md` (repo root) and run `git status --porcelain`.

- **`id: none` and a clean tree** → nothing to reconcile, go to step 1 as normal.
- **`stage: shipping` with a `commit:` hash, but `roadmap.yaml` doesn't yet show that
  item as `implemented` with that hash** → the code already shipped; a reboot just hit
  between 7.1 and 7.3. Don't redo the implementation — resume directly at step 7.2 using
  the recorded hash, then continue the loop normally.
- **`stage: implementing`/`test-build` for a named item** (or the tree is dirty and the
  marker names an item) → an item was interrupted mid-work. Treat this as *resuming that
  item*, not picking a new one: inspect what's on disk and either finish it cleanly
  (→ step 6 → step 7) or, if the state is unclear or unsalvageable, apply the step 5
  "too big" escape hatch — append a dated note explaining the interruption and either
  continue it next iteration or fall into the design-question path (step 4). Same
  git-safety rules as always apply: `git status` before anything destructive, never
  `reset --hard`/`clean -f` without confirming first.

### 1. Select

Re-read `roadmap.yaml` fresh (the admin or the roadmap-editor may have changed it since
the last iteration). Pick one `confirmed` item — smallest / lowest-risk / most
self-contained first, by judgment.

### 2. Rebalance (only when `confirmed` is empty)

Promote items up the pipeline until the working tiers are topped up:

- `confirmed` (in progress): top up to **2**, pulling from `wip`
- `wip` (up next): top up to **~6**, pulling from `soon`
- `soon`: top up to **~15**, pulling from `later`

Promotion is by judgment, favoring items that are **small, scriptable, and need no design
decisions** — an item that obviously needs the admin's taste should stay put or go
straight to the design-question path (step 4). Commit the rebalance as its own roadmap
commit (see "Roadmap commits" below) before starting work.

**Termination check:** if after rebalancing there is still nothing in
`confirmed`/`wip`/`soon`/`later` (everything active is `planned` or `unlikely`), the loop
is done — see "Stopping".

### 3. Implement

**Run this step in a fresh subagent** (see "Context economy" above), except for trivial
one-line items. The subagent implements, runs the test build (step 6), and makes the
final code commit (step 7.1), then reports back: **outcome** (`shipped` /
`design-question` / `too-big`), the **commit hash** (if shipped), a **summary for the
item's `notes`** including testing/UAT notes, any **`manual_steps`** (waypoints, deploy
steps), and any **`design_questions`**. The orchestrator then does the roadmap
bookkeeping (steps 4/5/7.2–7.4) from that report — it never trusts "done" without the
subagent citing a passing build and a commit hash.

**Keep `autopilot-wip.md` live while working.** At the very start of the item, overwrite
it with the item's `id`, `started` timestamp, and `stage: implementing`. As you create or
edit files for this item, append their repo-relative paths (space-separated) to its
`files:` line — this is the manifest the session-boundary safety net (below) is allowed
to touch; it never blanket-adds the whole tree. Keep `notes:` a current one-line summary
of what's in flight (e.g. `"placed waypoint AP_x_1, mid-writing forge_inc.nss, build not
yet run"`) — this is the closest thing to human-readable handoff if the session is cut
off. Update `stage` to `test-build` before step 6 and `shipping` (with the `commit:`
hash) right after step 7.1's commit succeeds; reset the whole file to `id: none` after
step 7.3's roadmap commit lands.

**Caution posture — build mechanical, queue creative.** Autopilot's default is to
*implement only what is well-specified and mechanical*, and to **hand every creative or
balance judgment back to the admin** rather than deciding it itself. The whole reason this
mode exists is to clear unambiguous work — not to invent content whose taste is the
admin's call.

- **Implement autonomously:** `Defect` and `Exploit` items; `Enhancement`s that are fully
  scriptable with no open choices — the fix/mechanic is obvious from the item text and the
  code.
- **Do NOT decide; queue as a design question instead** (step 4 — `status: design`, add to
  `design_questions`): new quest narrative or flavor, **reward amounts / reward type /
  loot**, difficulty & balance tuning, pricing, NPC personality or lore, and anything where
  a reasonable admin might pick differently than you would. When you queue one, **write your
  suggested answer into the question text** so the admin can bulk-approve or adjust — e.g.
  `"Proposed: reward = Ring of Barahir (+2 CON, 3000gp). Approve, or set a different reward?"`
  with `status: open`, `answer: null`. Propose freely; **do not act** on the proposal until
  the admin answers. (This is the only sanctioned way to "propose ideas": as questions/tasks
  on the *existing* item — never as a new `ideas:` entry; see Hard rules.)

When in doubt about whether something is a judgment call, it is — queue it. A shipped-but-
bland quest is worse than one held for a one-line admin decision.

Work the item following the existing docs ([CLAUDE-recipes.md](CLAUDE-recipes.md),
[CLAUDE-gotchas.md](CLAUDE-gotchas.md), [CLAUDE-nwscript.md](CLAUDE-nwscript.md), etc.).
Autopilot-specific rules:

- **No coordinate-picking.** Never choose positions/locations in a `.git.json` for *new*
  content — placement is the admin's call in the toolset. Instead:
  - Script against a waypoint: `GetWaypointByTag("AP_<item-id>_<n>")` (tag convention:
    `AP_` + the roadmap item id **with hyphens stripped** (toolset tags drop them — a
    2026-07-14 mismatch left two quests spawning nothing), abbreviated if needed to
    respect tag limits, + an index, e.g. `AP_riddlegame_1` for item `riddle-game`).
  - Add a **`manual_steps`** entry on the roadmap item telling the admin to create/place a
    waypoint with that tag, with a suggested area and purpose, and say what stays broken
    in-game until it exists.
  - Code defensively: if the waypoint doesn't exist yet, the feature should no-op
    gracefully, not error — the build ships before the waypoint is placed.
  - *Exceptions* (these are fine): pins managed by `bin/gen-map-notes.py`, edits to
    **existing** placed instances, and coordinates copied from an existing instance in the
    same area (e.g. swapping a creature at a spot that's already occupied).
- **Server-side-dependent items.** If the item needs a server.env / NWNX flag flip, an
  Anvil C# plugin build + DLL deploy, or a server restart to take effect: implement the
  repo-safe part fully, record the server-side step as a `manual_steps` entry, and ship
  the item as `manual`. The admin completes the deploy step later and promotes it.
- **New blueprints → file into the palette + name the palette path.** If the item
  creates a new item/creature/placeable blueprint, run
  `python3 bin/file-palette-orphans.py --apply` **before the test build** — it files the
  blueprint at its **`PaletteID` home** in `*palcus.itp.json` (the category whose `ID`
  matches the blueprint's `PaletteID`, matching what the toolset does), and the
  `check_palette_coverage` smoke gate will otherwise **abort the repack** (step 6). Never
  hand-place a palette leaf in a category that disagrees with the blueprint's `PaletteID`
  — the toolset relocates it on the next save. It's standalone, **not** a wiki refresh.
  Then, whenever a `manual_steps` entry asks the admin to place or find that blueprint in
  the toolset, **include its palette category path** (the `Top > Sub > …` value, from
  `bin/gen-palette-map.py` / `palette_map.json`) so the admin isn't hunting through
  hundreds of palette folders.
- **New NPCs — unique appearance + gear-matching proficiency feats.** When the item
  creates a new creature blueprint (`.utc.json`):
  - **Give it a deliberately unique `Appearance_Type`.** Don't default to the appearance of
    a nearby/related NPC — a wall of identical models is exactly the "bland/repetitive"
    outcome to avoid. **Clone the value from a real creature** (never guess the numeric id —
    a wrong value renders as the invisible-model fallback with no error; see
    [CLAUDE-blueprints.md](CLAUDE-blueprints.md) "Appearance constants"), and pick one
    *distinct* from the other NPCs the player meets in that area — cross-check
    `module-index/creature_index.json` (`appearance_id`) for local collisions.
  - **Match proficiency feats to the equipped gear.** Any NPC shipping with equipped
    weapons/armor **must** carry the matching proficiency feats in its `FeatList`, or the
    module's Jasperre AI **strips the gear at spawn** (the NPC appears unarmed/unarmored).
    This bit the `fighter-line-early` and `rogue-line-early` UAT passes. Include Armor
    Proficiency (Light/Medium/Heavy) + Shield Proficiency for the armor tier, and Weapon
    Proficiency (Simple/Martial/Exotic) for the weapon. **Verify the feat ids against a real
    `.utc.json` that already equips that gear** — copy them, don't recall the numbers. (See
    [CLAUDE-recipes.md](CLAUDE-recipes.md) "Add a new NPC creature".)
- **Placing an existing NPC elsewhere = a second *instance*, never a deep copy.** "Copy
  NPC X into area Y" means adding another instance of the **same** `.utc` blueprint to the
  target `.git.json` — only an explicit "deep copy" justifies duplicating the blueprint.
  Duplicating by default mints an indistinguishable palette leaf and an orphan that drifts,
  and no gate catches it (CLAUDE.md; recipe in [CLAUDE-recipes.md](CLAUDE-recipes.md)).
- **Editing an existing placed instance → sync the blueprint too.** Instances don't track
  their blueprint, but respawn does: `se_respawn_inc.nss` rebuilds a dead static creature
  from the `.utc`, so any instance-only override silently reverts after the creature's first
  death. `tests/check_divergent_creatures.py` **aborts the repack** on name/faction/
  conversation/combat-stat/equipment/inventory/droppability divergence — there is **no
  allowlist**, so "fix it later" is not an option. Prefer syncing the instance to the
  blueprint (or the blueprint to the instance if the change is meant for every placement);
  `bin/split-divergent-creatures.py` is the last resort, since splitting mints a blueprint.
  Loot droppability specifically: a `Dropable` disagreement gives loot that works exactly
  once per reboot — see [CLAUDE-loot-divergence-audit.md](CLAUDE-loot-divergence-audit.md).
- **New/changed areas or transitions → re-run `python3 bin/gen-map-notes.py` (then
  `--apply`)** so destination map-note pins stay in sync. Idempotent, not a wiki refresh.
- **Boss creatures (CR > 60) → regenerate the registry.** The "Roll of the Fallen" registry
  block in `brd_db.nss` is auto-generated by `bin/gen-boss-registry.py` from the CR>60
  single-instance rule — **never hand-edit the block**; re-run the generator and let
  `tests/check_boss_registry.py` pass. See [CLAUDE-boss-tracker.md](CLAUDE-boss-tracker.md).
- **New creature that is meant to travel** (wanderer, scripted plot mover) needs
  `NO_LEASH = 1` as a local int, or the area leash yanks it home and
  `tests/check_spawn_leash.py` complains. Ordinary creatures need nothing.
- **`.nss` source must be pure ASCII** — `tests/check_ascii_nss.py` aborts the repack on a
  stray em dash or smart quote in a comment. Write `--`, not `—`.
- **New journal quest → set the category `Comment` directives.** A new journal category in
  `module.jrl.json` with no Comment lands ungrouped at the bottom of the wiki's Quests
  index. Add `@group 'Name'` (+ `@order N`, and `@group-order N` if it is a new group) —
  the full directive table is in CLAUDE.md, "Quest wiki directives". It's a plain JSON
  field; no toolset step and no `manual_steps` entry needed.
- **Never hand-edit season-scoped strings** (wiki URL, connect host/port, module/server
  name, worker name, the Well of Eru season signs) — they are owned by
  `bin/season-brand.py` and gated by `tests/check_season_brand.py`.
- **Admin-only features must have an in-game trigger.** The admin has **no DM client**:
  never ship something that has to be fired with `dm_runscript`, a DM chat command, or the
  DM console. Wire the trigger into the rest menu's **Admin Options** (`can_admin` tier,
  `_restemo_admin.nss` StartingConditional) or another existing surface — or make it
  self-arming by resolving `Admin_CanAdmin()` once and caching it. Gate on the
  `Admin_Can*()` helpers from `admin_db.nss`; never write a new CD-key literal. A bare
  `.nss` only a DM can invoke is not a delivered feature (CLAUDE.md, "Admin authorization").
- **Reward-and-take safety — re-check possession at grant time.** Any script that grants a
  reward **and** consumes/takes a player item is exposed to the *drop-item farm*: a player
  reaches the reward reply holding the required item, **drops it while the conversation is
  still open**, collects the reward, then picks the item back up — repeating forever. The
  DLG StartingConditional is **not** enough (it passed before the drop). The action script
  must **re-verify at grant time** that the player still has the item —
  `GetItemPossessedBy(oPC, sTag)` + `GetIsObjectValid(...)` (or the `HasItem()` helper, a
  stack re-count, or an advance-only persistent stage / daily cooldown) — and bail before
  any reward if it's gone. Mirror the shape in `unpacked/q_arc_finish.nss`. The
  `tests/check_reward_exploit.py` smoke gate flags reward-and-take scripts that lack this
  guard and **aborts the repack** (step 6); a reviewed-safe exception carries an inline
  `// reward-exploit-ok: <reason>` marker. Also add a non-farmability UAT check to
  `manual_steps` (e.g. `"UAT: drop the token mid-conversation on the reward node — the
  reward must NOT be granted"`). See also [CLAUDE-nwscript.md](CLAUDE-nwscript.md)
  "Reward-and-take (anti-farm)".

### 3b. Keep `docs.manual/` in sync

After implementing, check whether any manual page under `docs.manual/` describes the
system you just changed, and update it **in the same code commit** (step 7.1). Editing
`docs.manual/` is *not* a wiki refresh — it's source; the daily refresh copies it into
`docs/`.

- **`Quest Ideas.html` is a burndown doc.** When a quest idea from it (or from
  `Quest Ideas.md`) ships: **remove** the idea from `Quest Ideas.html` and integrate the
  finished quest into `QuestGuide.html` (where it's found, how it works, rewards — match
  the page's existing structure). The goal is to retire `Quest Ideas.html` entirely as
  its contents ship; it is the only manual page meant to shrink.
- **`QuestGuide.html` is player-facing; `QuestGuide-DM-Notes.md` is the admin half.** When a quest
  ships or changes, write the player-facing walkthrough (giver, where, steps, reward) into
  `docs.manual/QuestGuide.html` **and** add a row to its summary table — and put everything
  internal (script resrefs, blueprint/dialog filenames, campaign-DB names and keys, `AP_*`
  waypoint tags, roadmap item ids, open points, UAT steps) into `QuestGuide-DM-Notes.md` instead.
  **Never** put a `dm-note`, a waypoint tag, a roadmap id, or an "admin action required" line in
  the public page — and never badge a quest as needing a waypoint there; use `Working` (the only
  other badge is `In Development`, for content that is genuinely unbuilt), and track the placement
  in the item's `manual_steps`.
- **`Customizations.html` especially** must track changes to player-facing customization
  systems (merit shop, housing, forge, gem socketing pointers, etc.) — if the item
  touches one of those, update the relevant section.
- Likewise for the other topical pages when the item touches their system:
  `CasterGear.html`, `Gem-Socketing.html`, `LegendaryFeats.html`, `LevelingGuide.html`,
  `MeaningWave.html`, `boss-updates.html`.
- **Never touch `docs.manual/Roadmap.html` by hand** — it's generated
  (`bin/gen-roadmap.py` in step 7.3, plus the admin's background service).
- New pages only if genuinely warranted, starting from `ManualPageTemplate.html`; don't
  create a page for a minor tweak — a sentence in an existing page beats a new one.

### 4. Escape hatch: design questions

If the item turns out to be under-specified, needs an admin decision (mechanics, balance,
lore, pricing, UX), or can't be done without choices only the admin should make:

1. Set the item's `status: design`. **Never demote it to `planned`** — that loses the
   pipeline position and hides the blocker.
2. Append the blocking question(s) to the item's `design_questions` list, each with
   `status: open` and `answer: null`. Put them **only** there — `notes` is player-facing.
3. **Leave all partial work and progress notes intact.** Commit whatever partial work is
   safe to commit (it must still build).
4. Commit the roadmap change, then go back to step 1 and pick the next item.

**Resuming a blocked item is all-or-nothing:** only pick it back up once **every** entry in
its `design_questions` has `status: answered` **and** every `manual_steps` entry with
`blocker: true` has `status: done`. If even one is still outstanding, skip it and choose
another item — never resume partially.

### 5. Escape hatch: too big

If the item is legitimate but can't be finished this iteration: append a dated progress
summary to the item's `notes`, leave it `confirmed`, commit whatever partial work is safe
to commit (it must still build — run step 6 on partial work too), and continue it next
iteration. Don't let one oversized item stall the whole loop for many iterations — after
~2 stalled iterations, treat it as a design question (step 4), with the scope problem
written up as the `design_questions` entry.

### 6. Test build

```
nwn-manager repack        # full path if not on PATH: ~/GIT/nwn_manager/bin/nwn-manager
```

**Bare `nwn-manager repack` only** — it builds `dist/<name>.mod` (+ OneDrive copy) and
runs the gates: script compilation, dialog-integrity, `tests/check_boss_registry.py`, and
the smoke tests. It does **not** touch the live server. Never use the
`repack-homers-lotr*` deploy wrappers — those install into the live server's module
folder.

The build must pass before shipping. On failure: fix and rebuild; if unfixable, take an
escape hatch (revert the working tree to the last good state first if needed).

For **wiki-related items** only, a local `bin/refresh-homers-lotr-wiki` run is allowed
*as validation* — inspect the regenerated `docs/` locally, but don't try to publish;
the daily reboot/refresh cycle reconciles and publishes `docs/`.

### 7. Ship

1. **Commit the code** on `main` (this repo commits straight to main — no branches/PRs),
   including any `docs.manual/` sync edits from step 3b.
   This must be the *final* commit made after the item is fully done: a background
   auto-committer ("Auto Wiki Activity Refresh") may snapshot the working tree mid-work,
   and the hash recorded in the roadmap must be the real completion commit. Message
   format: `<Item title or short name>: <what changed> (roadmap: <item-id>)`.
   Immediately after, update `autopilot-wip.md`: `stage: shipping`, `commit:` this hash.
2. **Update the roadmap item** per CLAUDE-roadmap.md's agent rules:
   - `status: manual` **by default**, with every outstanding admin toolset step written
     into `manual_steps` (one string per step: waypoint tag + area + suggested spot +
     what spawns there + what breaks until it's placed). Set `status: implemented`
     **only if you can confirm with certainty that zero manual toolset steps remain** —
     when uncertain, choose `manual`. Never `awarded`.
   - `commit:` the hash from step 1
   - `date:` **always set to today's actual date** (`YYYY-MM-DD` — check the real current
     date, don't guess or leave the original report date)
   - `notes`: append a `Fixed YYYY-MM-DD` line (what/why/how), **plus testing/UAT
     notes** — what the admin should verify in-game before promoting to `awarded`.
   - **Wiring due-diligence — do this BEFORE marking `implemented`.** A clean build
     proves nothing *runs*: an orphaned script (attached to no event hook/NPC/conversation)
     or one that looks up a mismatched tag compiles fine and silently does nothing — this
     has already shipped ~15 invisible "done" quests here. Verify end-to-end:
     1. every new `.nss` is actually invoked from somewhere — a `module.ifo.json` event
        hook, an NPC/placeable/trigger event-script field, a conversation `Active`/`Script`,
        `ExecuteScript`, or a module override (grep the resref to prove a caller exists);
     2. every new `.dlg` is referenced by some blueprint's `Conversation` field;
     3. every `GetWaypointByTag`/`GetObjectByTag` string literal exactly matches a real
        `Tag` (or the tag in its `manual_steps` entry) **and is hyphen-less**
        (see the tag convention in "No coordinate-picking" above);
     4. for a waypoint-gated item that is **invisible in-game until the admin places the
        waypoint** (the giver NPC/placeable is script-spawn-only), say so explicitly in the
        UAT note — e.g. `"blocked in-game until AP_prestigehub_1 is placed"` — so it is not
        mistaken for working during UAT. (Server-side-dependent items are different: the
        code IS wired in the module, so they ship `implemented` per the rule below.)
3. **Roadmap commit** (same procedure for rebalance/escape-hatch commits):
   `python3 bin/gen-roadmap.py --check`, then `python3 bin/gen-roadmap.py`, commit
   `roadmap.yaml` + `docs.manual/Roadmap.html` together. Do **not** run the wiki refresh.
   Reset `autopilot-wip.md` to `id: none` (clear `started`/`stage`/`commit`/`files`/
   `notes`) — it's gitignored (local machine state only, see "Session-boundary safety
   net"), so this reset is just a plain file write, not part of any commit.
4. **Push** to `origin/main` after each shipped item so nothing sits unpushed.

### 8. Loop

Go back to step 1. Between iterations, self-pace with ScheduleWakeup if running under
`/autopilot` (most work is synchronous, so iterations usually chain directly; use a long
fallback wakeup ~1800s only when waiting on something).

## Session-boundary safety net

`autopilot-wip.md` (repo root, machine-maintained — see step 3, **gitignored**: it's
local-machine state, not something that needs to travel with the repo) is the mechanical
backup for a session that gets cut off with no chance to clean up (killed process, host
reboot, context limit hit mid-turn). Claude Code exposes no signal to the model for
"you're about to run out of context" — compaction is transparent — but it does fire two
hook events we use as a dumb, reliable last resort:

- **`PreCompact`** — fires just before context compaction. The nearest thing to a "98%"
  warning that actually exists.
- **`SessionEnd`** — fires when the session terminates.

Both are wired in `.claude/settings.json` to `bin/autopilot-safety-commit <event-name>`.
That script **only** acts when `autopilot-wip.md` shows an active item (`id:` not `none`)
**and** its `files:` line names paths that actually changed — it stages exactly those
paths and nothing else, then commits. It is a no-op during ordinary interactive sessions,
and it never runs a blanket `git add -A` (tested empirically: that would have swept in
unrelated untracked work sitting in the tree at the time, not just the current item's
files). It can't write rich handoff notes — that needs model judgment — so the live
`notes:` line kept during step 3 is the real handoff; the hook's job is only to make sure
nothing in the manifest is lost to an uncommitted tree.

## Admin hand-off: `design_questions` and `manual_steps`

There is **no `admin-action-required.md`** — it was retired. Everything the admin needs to
act on lives in the two internal fields on the roadmap item itself, so the admin can filter
`status: design` and `status: manual` from the website service instead of reading a file.

- **`manual_steps`** — toolset/deploy work only the admin can do, **plus the UAT script**.
  Each entry is `{step, status, blocker}`:
  - `status` is `open` | `wip` | `done`; new steps are always `open`.
  - `blocker: true` marks work the item genuinely cannot ship without — a missing waypoint
    that makes the quest unreachable. A UAT check is **not** a blocker. Omit the flag when
    false. Never write "Blocker:" into the step text or into `notes`; set the flag.
  - For a waypoint step give tag + area + suggested spot + what spawns there + what stays
    broken until it is placed. The tag MUST be hyphen-less and byte-for-byte identical to
    the string the script looks up (item `riddle-game` → `AP_riddlegame_1`, never
    `AP_riddle-game_1`) — a mismatch means the waypoint is placed but never found, i.e. the
    feature is dead on arrival. When one waypoint gates many quests (e.g. a quest-hub NPC),
    say so and put it first, so the admin places the highest-leverage one first.
  - **Name areas by their full toolset Name, then the resref in parens** — e.g.
    `"Minas Tirith: The Keep (area005)"`, not just `area005`. The toolset's area list sorts
    by **Name**, so a bare resref sends the admin hunting. Get the Name from
    `module-index/area_index.json` (or the area's `.are.json` `Name` field). Do this in every
    `manual_steps` and `design_questions` line that references an area. (Waypoint-tag string
    literals stay hyphen-less and byte-identical — that rule is unchanged.)
  - **Appearance/gear UAT for every new NPC or item blueprint.** Whenever the item creates a
    new `.utc` (creature) or `.uti` (item), add a `manual_steps` UAT entry asking the admin
    to log in and **visually verify how it looks** — one step per blueprint, `status: open`,
    `blocker: false`. For NPCs, the check must also confirm the **gear stays equipped** (the
    Jasperre-AI proficiency trap), e.g. `"UAT appearance: spawn <resref> in <Full Area Name
    (resref)> and confirm the model looks right AND its weapon/armor stay equipped (not
    stripped)."`
  - Write the UAT script here too, **one step per check**, not as a paragraph in `notes`.
- **`design_questions`** — blocking questions, each `{question, status: open, answer: null}`.
- **`impl_notes`** — the technical record: root cause, scripts/resrefs/DB tables touched,
  design deviations, gates that passed. This is where everything that used to be written as
  a `<b>Fixed YYYY-MM-DD:</b>` block in `notes` now goes.

`notes` is the **player-facing release note** and nothing else — a few sentences in
release-note voice, linking to `QuestGuide.html#<anchor>` or `Customizations.html#<anchor>`
for detail. Never put a UAT script, a resref, a script name or a design question in it. The
agent only ever *appends* to the internal lists; the admin answers questions, does the work,
and flips the statuses.

Note the save-time gate: an item in `implemented` / `awarded` with an unfinished blocker
step is a **validation error**. If blocking work remains, the item belongs in `manual`.

## Hard rules — never do these

- **Never set `status: awarded`** or otherwise mark an item done — merit credit is the
  admin's manual call.
- **Never deploy to the live server**: no `repack-homers-lotr*` wrappers, no copying
  `.mod`/`.ncs`/DLLs into server folders.
- **Never reboot or shut down the live server** — don't touch `bin/reboot-on-empty` or
  its control files.
- **Never publish the wiki**: `bin/refresh-homers-lotr-wiki` is allowed only as local
  validation for a wiki item; leave `docs/`/`module-index/` for the daily cycle.
- **Never create new `ideas:` entries** in `roadmap.yaml` — even for follow-up work you
  discover, and even when "proposing an idea." You *may* propose freely, but only **as
  tasks/questions attached to an existing item**: a `design_question` (with your suggested
  answer in the text) or a `manual_steps`/`impl_notes` note. Those queue for the admin's
  bulk approval without minting a new backlog row. A brand-new `ideas:` entry is always the
  admin's call — leave follow-ups you can't attach to a current item for them.
- **Never implement a legendary feat without the admin's explicit, per-feat sign-off.**
  The `ll-feats-*` backlog items and [CLAUDE-legendary-feats-triage.md](CLAUDE-legendary-feats-triage.md)
  read like a settled plan; **they are unreviewed proposals**. `FEATS` is append-only and a
  feat's row index becomes its id in every save the moment someone takes it, so a wrong
  name, number or prerequisite cannot be withdrawn cleanly. Only the feats explicitly listed
  as approved in [CLAUDE-legendary-feats.md](CLAUDE-legendary-feats.md) may be built.
  Picking up an `ll-feats-*` content item (anything past `ll-feats-picker`) therefore means:
  set `status: design` and file **one `design_question` per feat** — name, effect, exact
  numbers, prerequisites, your recommendation — then move on. Building the *machinery*
  (picker, plumbing, generators) is fine; building the *content* is not. Also never
  hand-edit `hak_2da/feat.2da` or `tlk/lotr.tlk` — edit the generator table and re-run it.
- **Never edit the `meta:`/`redemption:`/`housing:`/`epics:`/`players:` blocks** of
  `roadmap.yaml`. If the item you shipped carries an `epic:` key, leave it alone — the
  epic's progress, date, status and credit are all derived from its children.
- **Never hard-code CD keys or secrets** anywhere under `unpacked/` (see CLAUDE.md — a
  gitignored file still gets packed into the `.mod`).
- **Gitignore new build artifacts before creating them** — the auto-committer will
  otherwise commit them.

## Stopping

Stop when:

- the only remaining active items are `planned`/`unlikely` (nothing left in
  `confirmed`/`wip`/`soon`/`later`), or
- compute/time runs out.

**Running out of `Defect`/`Exploit` items is NOT a stop condition.** If the active
tiers still hold `Enhancement`s — even if they all look design-heavy — keep the loop
flowing: rebalance (promote `wip`/`soon`/`later` up, §2), work each promoted item, and
when one hits a creative / power-balance / reward / roster call, **park it in `design`
with a `design_questions` entry that proposes a concrete answer** for the admin to
approve or tweak (§4), then move on to the next. Don't halt just because the remaining
work needs decisions — turn those decisions into decision-ready proposals. (The admin
calls this the "under consideration" state; use `design`, never `planned`, so the item
keeps its pipeline position and stays in the admin's review filter.)

On stop: make sure the working tree is committed and pushed, then report the session
summary (items shipped, items moved to `design`/`manual`, count of pending admin actions)
in your final message — it is not written to any file. If running under `/autopilot`
dynamic pacing, end the loop (ScheduleWakeup `stop: true`).
