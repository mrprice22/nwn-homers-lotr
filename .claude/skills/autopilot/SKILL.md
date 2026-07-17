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
   `AP_riddle-game_1`; the script literal and the `admin-action-required.md` entry must
   match exactly — + `admin-action-required.md`); escape hatches for design questions (→ `planned`) and
   oversized items. Files (`roadmap.yaml`, `admin-action-required.md`, git) are the only
   loop state — never conversation history.
3. Test-build with **bare `nwn-manager repack`** (never the deploy wrappers).
4. Ship: final code commit → roadmap item to `implemented` with `commit:`, `date:` set to
   today's actual date, and UAT notes → `gen-roadmap.py` → commit yaml + Roadmap.html →
   push to origin/main.
5. Repeat until only `planned`/`unlikely` items remain or compute runs out, then write a
   session summary into `admin-action-required.md`.

Honor every **hard rule** in the runbook: never `awarded`, never deploy to / restart the
live server, never publish the wiki, never invent new `ideas:` entries.

Pacing: work is synchronous, so chain iterations directly in one turn where possible.
Use ScheduleWakeup only as a long fallback (~1800s) if genuinely waiting on something,
and end the loop with `stop: true` when the runbook's stop condition is met.
