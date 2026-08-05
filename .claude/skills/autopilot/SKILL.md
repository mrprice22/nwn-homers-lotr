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
   blueprint, run `python3 bin/file-palette-orphans.py --apply` (files it into the toolset
   palette — the `check_palette_coverage` gate aborts the repack otherwise) and put the
   palette category path in its `manual_steps`. Files (`roadmap.yaml`, git) are the only
   loop state — never conversation history.
   - **Build mechanical, queue creative.** Autonomously implement only `Defect`/`Exploit`/
     no-choice items; route reward amounts, balance, new-quest flavor, and NPC lore to a
     `design_question` on the item (with your suggested answer in the text) — don't decide
     them.
   - **New NPCs:** give a **unique `Appearance_Type`** (clone, don't guess) and put the
     **proficiency feats that match the equipped gear** in `FeatList`, or the Jasperre AI
     strips it (`fighter-line-early` / `rogue-line-early` trap).
   - **New NPC or item → add an appearance UAT `manual_steps` entry** (look right? gear
     stays equipped?), naming any area by its **full toolset Name + resref** (the toolset
     sorts areas by Name).
   - **Legendary feats need per-feat admin sign-off.** Any `ll-feats-*` *content* item goes
     to `design` with one `design_question` per feat (name/effect/numbers/prereqs +
     your recommendation) — never build unapproved feat content; `FEATS` row ids are
     permanent. Machinery/plumbing is fine.
   - **Editing an existing placed instance? sync its blueprint** (respawn reverts overrides;
     `check_divergent_creatures.py` aborts the repack, no allowlist). "Place NPC X in area Y"
     = a second **instance**, never a duplicated `.utc`.
   - **Admin-only features need an in-game trigger** — the admin has no DM console; gate on
     `Admin_Can*()` and hang the trigger off the rest menu's Admin Options or self-arm it.
   - **Reward-and-take scripts must re-check `GetItemPossessedBy`/`HasItem` at grant time**
     (not just the DLG conditional) or players farm them by dropping the item mid-
     conversation; the `check_reward_exploit.py` gate enforces this.
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
