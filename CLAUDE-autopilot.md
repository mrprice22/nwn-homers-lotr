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
  previous one: `roadmap.yaml`, `admin-action-required.md`, and git are the entire loop
  state — never depend on conversation history for what's done or in flight. Keep
  per-item exploration lean: use `module-index/` and `docs/` for lookups instead of
  reading raw `unpacked/` JSON, and don't pull large files into context when a targeted
  read will do.
- **Fresh context per item — delegate implementation to a subagent.** The orchestrating
  session runs the loop bookkeeping (select, rebalance, roadmap edits, commits, pushes)
  and launches a `general-purpose` subagent (synchronous, `run_in_background: false`) to
  do step 3 for each item. Each subagent starts with a clean context window — the
  equivalent of `/clear` between items. The subagent's brief must include: the item's
  `id`/`title`/`notes`, an instruction to read `CLAUDE.md` + `CLAUDE-autopilot.md` first,
  the no-coordinate-picking and hard rules, and what to report back (see step 3). Small,
  obviously-mechanical items (a typo fix, a single-value tweak) may be done inline by the
  orchestrator instead — don't pay a subagent spin-up for a one-liner.

## The loop

Each iteration works exactly **one** item, end to end:

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
item's `notes`** including testing/UAT notes, and any **admin-action-required entries**
(waypoints, deploy steps, design questions). The orchestrator then does the roadmap
bookkeeping (steps 4/5/7.2–7.4) from that report — it never trusts "done" without the
subagent citing a passing build and a commit hash.

Work the item following the existing docs ([CLAUDE-recipes.md](CLAUDE-recipes.md),
[CLAUDE-gotchas.md](CLAUDE-gotchas.md), [CLAUDE-nwscript.md](CLAUDE-nwscript.md), etc.).
Two autopilot-specific rules:

- **No coordinate-picking.** Never choose positions/locations in a `.git.json` for *new*
  content — placement is the admin's call in the toolset. Instead:
  - Script against a waypoint: `GetWaypointByTag("AP_<item-id>_<n>")` (tag convention:
    `AP_` + the roadmap item id, abbreviated if needed to respect tag limits, + an index).
  - Log a **Toolset action** in `admin-action-required.md` (see format below) telling the
    admin to create/place a waypoint with that tag, with a suggested area and purpose.
  - Code defensively: if the waypoint doesn't exist yet, the feature should no-op
    gracefully, not error — the build ships before the waypoint is placed.
  - *Exceptions* (these are fine): pins managed by `bin/gen-map-notes.py`, edits to
    **existing** placed instances, and coordinates copied from an existing instance in the
    same area (e.g. swapping a creature at a spot that's already occupied).
- **Server-side-dependent items.** If the item needs a server.env / NWNX flag flip, an
  Anvil C# plugin build + DLL deploy, or a server restart to take effect: implement the
  repo-safe part fully, log the server-side step as a Toolset/admin action in
  `admin-action-required.md`, and still ship the item as `implemented`. The admin
  completes the deploy step later.

### 4. Escape hatch: design questions

If the item turns out to be under-specified, needs an admin decision (mechanics, balance,
lore, pricing, UX), or can't be done without choices only the admin should make:

1. Write the blocking question(s) into the **Design questions** section of
   `admin-action-required.md`, referencing the item id.
2. Append the same question(s) to the item's `notes` (keep the original text intact).
3. Move the item to `planned` (under consideration).
4. Commit the roadmap change, then go back to step 1 and pick the next item.

### 5. Escape hatch: too big

If the item is legitimate but can't be finished this iteration: append a dated progress
summary to the item's `notes`, leave it `confirmed`, commit whatever partial work is safe
to commit (it must still build — run step 6 on partial work too), and continue it next
iteration. Don't let one oversized item stall the whole loop for many iterations — after
~2 stalled iterations, treat it as a design question (step 4) with a note explaining the
scope problem.

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

1. **Commit the code** on `main` (this repo commits straight to main — no branches/PRs).
   This must be the *final* commit made after the item is fully done: a background
   auto-committer ("Auto Wiki Activity Refresh") may snapshot the working tree mid-work,
   and the hash recorded in the roadmap must be the real completion commit. Message
   format: `<Item title or short name>: <what changed> (roadmap: <item-id>)`.
2. **Update the roadmap item** per CLAUDE-roadmap.md's agent rules:
   - `status: implemented` (never `awarded`)
   - `commit:` the hash from step 1
   - `date:` **always set to today's actual date** (`YYYY-MM-DD` — check the real current
     date, don't guess or leave the original report date)
   - `notes`: append a `Fixed YYYY-MM-DD` line (what/why/how), **plus testing/UAT
     notes** — what the admin should verify in-game before promoting to `awarded`.
3. **Roadmap commit** (same procedure for rebalance/escape-hatch commits):
   `python3 bin/gen-roadmap.py --check`, then `python3 bin/gen-roadmap.py`, commit
   `roadmap.yaml` + `docs.manual/Roadmap.html` together. Do **not** run the wiki refresh.
4. **Push** to `origin/main` after each shipped item so nothing sits unpushed.

### 8. Loop

Go back to step 1. Between iterations, self-pace with ScheduleWakeup if running under
`/autopilot` (most work is synchronous, so iterations usually chain directly; use a long
fallback wakeup ~1800s only when waiting on something).

## `admin-action-required.md` (repo root)

Created and maintained by the loop; the **admin deletes entries** as they're completed —
the agent only appends (and may update its own still-pending entries). Format:

```markdown
# Admin actions required

_Appended by autopilot; delete entries as you complete them._

## Session summaries
- **YYYY-MM-DD**: shipped <n> items (<ids>), moved <n> to under-consideration (<ids>),
  <n> pending actions below.

## Toolset / placement actions
- [ ] **<roadmap-item-id>** (YYYY-MM-DD): create waypoint tag `AP_<...>` in
  <suggested area> — <purpose>. Also: <env flip / Anvil deploy / restart step, if any>.

## Design questions
- [ ] **<roadmap-item-id>** (YYYY-MM-DD): <the blocking question(s)>. Item moved to
  under-consideration; answer and drag it back to a working lane to reactivate.
```

Every entry references the roadmap item `id` so the two stay linked.

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
  discover. Note follow-ups in the current item's `notes` or `admin-action-required.md`
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

On stop: make sure the working tree is committed and pushed, then write a session summary
line into `admin-action-required.md` (items shipped, items moved to under-consideration,
count of pending admin actions) and commit that too. If running under `/autopilot`
dynamic pacing, end the loop (ScheduleWakeup `stop: true`).
