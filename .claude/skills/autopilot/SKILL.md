---
name: autopilot
description: Run the unattended roadmap autopilot loop — pick roadmap.yaml items, implement, test-build, commit, update the roadmap, and repeat until compute runs out. Use when the user says "autopilot", "run the roadmap loop", or "work the backlog unattended".
---

# Autopilot

Read **CLAUDE-autopilot.md** (repo root) and execute its loop exactly. Summary of what
you're signing up for (the runbook is authoritative — read it in full before starting):

1. Pick one `confirmed` roadmap item (rebalance tiers per the runbook's quotas when
   `confirmed` is empty).
2. Implement it — no coordinate-picking (use `AP_<item-id>_<n>` waypoints +
   `admin-action-required.md`); escape hatches for design questions (→ `planned`) and
   oversized items.
3. Test-build with **bare `nwn-manager repack`** (never the deploy wrappers).
4. Ship: final code commit → roadmap item to `implemented` with `commit:`/`date:`/UAT
   notes → `gen-roadmap.py` → commit yaml + Roadmap.html → push to origin/main.
5. Repeat until only `planned`/`unlikely` items remain or compute runs out, then write a
   session summary into `admin-action-required.md`.

Honor every **hard rule** in the runbook: never `awarded`, never deploy to / restart the
live server, never publish the wiki, never invent new `ideas:` entries.

Pacing: work is synchronous, so chain iterations directly in one turn where possible.
Use ScheduleWakeup only as a long fallback (~1800s) if genuinely waiting on something,
and end the loop with `stop: true` when the runbook's stop condition is met.
