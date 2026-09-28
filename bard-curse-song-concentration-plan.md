# Investigation: `bard-curse-song-not-lowering-concentration-skill`

## Context
Sync (**Bard 30**) curses the Rancid Skinner (`creature023_2`, Dol Guldur). Examine shows
the boss is cursed, yet **every** Taunt check reads **DC 124**, and Sync saw the same 124 on
*other* caster bosses. The dev wiki gives the Skinner a total Concentration of 125 (90 ranks,
+25 Con, +10 belt), so a working −18 should read 107.

## Established (source + Sync's answers)
- **The ladder is not the cause.** Bard 30 with Perform ≥6 is always −2 or worse, and −18 at
  Perform 80+ (`x2_s2_cursesong.nss`).
- **The boss is not removing or resisting the skill penalty.** It has no skill-decrease
  immunity, no Restoration or dispel, no Skill Focus feats, and no module script adds skills
  at spawn (`x2_def_spawn` → `nw_c2_default9`). The curse is visibly on it.
- **The DC is not a roll.** It is constant across taunts.
- **The module has no Taunt hook.** No NWNX skill/use-skill handler exists, so the Taunt DC is
  pure engine.
- **The same 124 on several bosses points at a ceiling, not this boss's own value.** 27
  creatures at CR ≥60 have an estimated Concentration of 124 or more (e.g. Drider Mage ~168,
  Dol Guldur Gate Keeper ~140, Gwathdor Lord ~137). Cursed, those would still be well above
  124, so an identical 124 on all of them can't be their real totals.

## Two remaining explanations — one measurement separates them
- **1. The curse doesn't reduce the engine's Concentration total.** Possible causes:
  - the `eff_dur_x2.nss` remove-and-rebuild of the PC-created link mangles the
    `EffectSkillDecrease(SKILL_ALL_SKILLS, 18)` component
  - the engine nets `SKILL_ALL_SKILLS` oddly against a specific item bonus
- **2. The curse works, but the engine's Taunt DC doesn't track the total.** The DC is capped
  or clamped near 124, so any target at or above the cap always shows 124, cursed or not.
  That is engine behaviour, not a script bug.

## Plan
1. **Admin-only diagnostic in `unpacked/x2_s2_cursesong.nss`.** Nothing `#include`s this spell
   script, so a plain repack is safe.
   - Resolve `Admin_CanAdmin(OBJECT_SELF)` (`#include "admin_db"`) **once**, before the sphere
     walk. That keeps within the instruction budget from `curse-song-too-many-instructions`.
   - Tell the singer the tier once: Bard level, Perform, and the skill value.
   - Per cursed target, record `GetSkillRank(SKILL_CONCENTRATION, oTarget)` before the apply.
   - After `DelayCommand(1.0, …)` (past the deferred `eff_dur_x2` rebuild), report
     `before → after`.
   - Also list each `EFFECT_TYPE_SKILL_DECREASE` on the target, with `GetEffectInteger(e,0)`
     (skill) and `GetEffectInteger(e,1)` (amount). This is a real builtin, `nwscript.nss:12375`.
   - Non-admins pay nothing.
2. **Ship it to dev** with `bin/rebuild-and-arm` and commit to main.
3. **UAT (admin Bard 30+, Perform 80+), curse and taunt:**
   - the **Skinner** (~125)
   - a **low-Concentration target** (well under 124, e.g. a Dol Guldur minion)
   - one **high** caster (e.g. Drider Mage / Gate Keeper)

   Compare the diagnostic's "after" with the Taunt DC on each.
4. **Resolve:**
   - **after ≈ before (or the effect params are wrong)** → explanation 1.
     - Fix the cause: `eff_dur_x2.nss` if the component comes back wrong (confirm with module
       int `x2dur_debug`), otherwise also link an explicit
       `EffectSkillDecrease(SKILL_CONCENTRATION, nSkill)`.
     - Re-UAT Bard Song and Taunt too, since `eff_dur_x2` is global.
     - Roadmap: `implemented` + `commit:` + notes + a `uat` step.
   - **after = before − 18, but the Taunt DC stays at 124 on high targets and tracks the total
     on the low one** → explanation 2, an engine Taunt DC cap. The curse is working.
     - Report back with the numbers.
     - Decide with the admin whether to accept it (reply to Sync, set the item to `unlikely`
       with a note, maybe a "Looks like a bug — isn't" Customizations entry), or to override
       Taunt through an NWNX hook. The latter is a bigger design call and gets its own item.
   - Either way, drop the diagnostic afterwards, or keep it admin-gated.
   - Any roadmap edit goes through `bin/roadmap-apply-patch.py`, then `bin/roadmap-lint.py`.

## Verification
- The repack gates pass.
- On dev, an admin singer gets the tier line plus a before/after line and the effect params
  per cursed hostile, and non-admins see nothing new.
- The three-target comparison in step 3 separates explanation 1 from explanation 2.
