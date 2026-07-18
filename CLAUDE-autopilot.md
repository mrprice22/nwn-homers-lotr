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

Work the item following the existing docs ([CLAUDE-recipes.md](CLAUDE-recipes.md),
[CLAUDE-gotchas.md](CLAUDE-gotchas.md), [CLAUDE-nwscript.md](CLAUDE-nwscript.md), etc.).
Two autopilot-specific rules:

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

**Resuming a `design` item is all-or-nothing:** only pick it back up once **every** entry
in its `design_questions` has `status: answered`. If even one is still `open`, skip it and
choose another item — never resume partially on a subset of answered questions.

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

- **`manual_steps`** — toolset/deploy work only the admin can do. One string per step:
  waypoint tag + area + suggested spot + what spawns there + what stays broken until it is
  placed. The tag MUST be hyphen-less and byte-for-byte identical to the string the script
  looks up (item `riddle-game` → `AP_riddlegame_1`, never `AP_riddle-game_1`) — a mismatch
  means the waypoint is placed but never found, i.e. the feature is dead on arrival. When
  one waypoint gates many quests (e.g. a quest-hub NPC), say so and put it first, so the
  admin places the highest-leverage one first.
- **`design_questions`** — blocking questions, each `{question, status: open, answer: null}`.

Never put either kind of content in `notes` — that field is player-facing. The agent only
ever *appends* to these lists; the admin answers questions, does the work, and flips the
status.

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
  discover. Note follow-ups in the current item's `notes` or `manual_steps`
  instead.
- **Never edit the `meta:`/`redemption:`/`housing:` blocks** of `roadmap.yaml`.
- **Never hard-code CD keys or secrets** anywhere under `unpacked/` (see CLAUDE.md — a
  gitignored file still gets packed into the `.mod`).
- **Gitignore new build artifacts before creating them** — the auto-committer will
  otherwise commit them.

## Stopping

Stop when:

- the only remaining active items are `planned`/`unlikely` (nothing left in
  `confirmed`/`wip`/`soon`/`later`), or
- compute/time runs out.

On stop: make sure the working tree is committed and pushed, then report the session
summary (items shipped, items moved to `design`/`manual`, count of pending admin actions)
in your final message — it is not written to any file. If running under `/autopilot`
dynamic pacing, end the loop (ScheduleWakeup `stop: true`).
