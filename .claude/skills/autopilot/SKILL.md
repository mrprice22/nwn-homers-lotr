---
name: autopilot
description: Run the unattended roadmap autopilot loop — pick roadmap.yaml items, implement, test-build, commit, update the roadmap, and repeat until compute runs out. Use when the user says "autopilot", "run the roadmap loop", or "work the backlog unattended".
---

# Autopilot

Read **CLAUDE-autopilot.md** (repo root) and execute its loop exactly. Summary of what
you're signing up for (the runbook is authoritative — read it in full before starting):

0. **Reconcile first**: check `autopilot-wip.md` + `git status` for a previous run cut
   off mid-item before picking anything new (see the runbook's step 0).
1. Pick one `confirmed` roadmap item (rebalance tiers per the runbook's quotas when
   `confirmed` is empty).
2. Implement it **in a fresh `general-purpose` subagent** (fresh context per item; inline
   only for trivial one-liners) — no coordinate-picking (use hyphen-stripped
   `AP_<item-id>_<n>` waypoints — item `riddle-game` → tag `AP_riddlegame_1`, **never**
   `AP_riddle-game_1`; the script literal and the item's `manual_steps` entry must match
   exactly); escape hatches for design questions (→ `design` + `design_questions`, never
   `planned`) and oversized items. After creating any new item/creature/placeable
   blueprint, run `python3 bin/gen-palette-map.py` and put the palette category path in
   its `manual_steps`. Files (`roadmap.yaml`, git) are the only loop state — never
   conversation history.
3. Test-build with **bare `nwn-manager repack`** (never the deploy wrappers).
4. Ship: final code commit → roadmap item to `manual` (with `manual_steps`) — or
   `implemented` only if zero manual toolset steps remain — with `commit:`, `date:` set to
   today's actual date, and UAT notes → `gen-roadmap.py` → commit yaml + Roadmap.html →
   push to origin/main.
5. Repeat until only `planned`/`unlikely` items remain or compute runs out, then report a
   session summary in your final message.

Honor every **hard rule** in the runbook: never `awarded`, never deploy to / restart the
live server, never publish the wiki, never invent new `ideas:` entries.

Pacing: work is synchronous, so chain iterations directly in one turn where possible.
Use ScheduleWakeup only as a long fallback (~1800s) if genuinely waiting on something,
and end the loop with `stop: true` when the runbook's stop condition is met.
