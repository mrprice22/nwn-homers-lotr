# divine-might-divine-wrath — proposal: resistible divine damage for everyone + two legendary feats

_Status: proposal, 2026-09-24. Roadmap item `divine-might-divine-wrath`. Nothing here is built; the legendary feats need the admin's explicit sign-off per feat before anything is appended to `FEATS`._

## Context

Roadmap item `divine-might-divine-wrath` (-Methonash-, `planned`) asks that **Divine Might
and Divine Wrath damage and duration scale with Strength**. The Discord thread adds:
- Rajmund, Sync and Balendin want **more Divine Wrath uses** (1 per 10 Divine Champion levels).
- Balendin warns about balance: Monk/Pal/CoT/WM must not become the only build.
- Tukwut asked that it **stop bypassing divine resistance/immunity**, and the admin agreed
  that is a fair trade.

The admin confirmed from the NWN wiki that both abilities use `EffectDamageIncrease`,
which **ignores damage resistance and immunity**. On 2026-09-24 the admin decided that
**everyone** gets the resistible version, not only feat holders.

The Legendary Feat approval rule still applies: nothing is added to `FEATS` until the
admin signs off on each feat's name, numbers and prerequisites.

### How they work today
| | Divine Might (stock `x0_s2_divmight`) | Divine Wrath (`unpacked/x2_s2_divwrath.nss`, forked) |
|---|---|---|
| Damage | +CHA mod divine, unresistable | +3 → +17 divine by DC level, unresistable |
| Duration | CHA mod rounds. **Not** doubled: `eff_dur_x2.nss` skips it to avoid breaking linked effects | CHA mod rounds, doubled by `eff_dur_x2` |
| Uses | Spends 1 Turn Undead use | 1/day |

## Part A: resistible Divine Might and Divine Wrath for everyone (a balance change)

The damage moves off `EffectDamageIncrease`. The ability now records the amount on the
caster while its effect lasts, and every hit that lands applies a separate
`EffectDamage(n, DAMAGE_TYPE_DIVINE)` to the target. Divine resistance and immunity apply
to it, the combat log shows it on its own line, and the `DAMAGE_BONUS_*` +20 ceiling no
longer applies. This is the same pattern as Legendary Wrath and Legendary Quarry
(`unpacked/legfeat_atk_inc.nss`).

- **New `unpacked/divdmg_inc.nss`** (small; included by the attack script):
  - `const string DIVDMG_VAR = "divdmg"` is the gate local int on the attacker, set only
    while Might or Wrath is up.
  - `DivDmg_OnAttack(data)`: returns if no damage landed (reuse the `LegFeatAtk_Total`
    "fields are -1 not 0" logic; move it into a shared place or duplicate it with a note).
    For each source (`divdmg_might`, `divdmg_wrath` local ints): if
    `GetHasSpellEffect(SPELL_DIVINE_MIGHT / 622)` is still true, apply its
    `EffectDamage(DIVINE)`. Otherwise delete that local. When both are gone, delete
    `DIVDMG_VAR`. Expiry, dispel and death are all handled lazily by the next attack, so
    no timer is needed.
  - Might and Wrath stack when both are up, as two separate damage instances.
- **`unpacked/devcrit_atk.nss`**: add one gate next to the existing ones:
  `if (GetLocalInt(OBJECT_SELF, DIVDMG_VAR)) DivDmg_OnAttack(data);`. Keep the "one
  GetLocalInt per attack" rule it documents. Monsters that use Divine Might go through
  the same server-wide hook, so this applies to them too.
- **New override `unpacked/x0_s2_divmight.nss`**, extracted from stock with
  `nwn_resman_cat`, with a MODULE FORK header naming the roadmap id. Remove
  `eDamage1`. Keep the linked `VFX_DUR_CESSATE_POSITIVE` as a supernatural effect for
  the duration, so `GetHasSpellEffect` and `GetHasFeatEffect(413)` still work. Set
  `divdmg_might` and `DIVDMG_VAR`. Keep the Turn Undead decrement and the
  `eff_dur_x2` exclusion.
- **`unpacked/x2_s2_divwrath.nss`**: remove `eDamage` from the link. Saves, DR and the
  pooled AB stay as they are. Store `nDamageB` as a **number** (3/5/7/…/17), because it
  is currently a `DAMAGE_BONUS_*` constant, into `divdmg_wrath`, and set `DIVDMG_VAR`.
  Keep the 621/622 witness note.
- **Consolation for everyone (no feat needed).** The goal is that a character who never
  takes a legendary feat is **only worse off against targets with divine resistance or
  immunity**. Against anything else, they come out ahead of today:
  - **Divine Might lasts 2 × CHA mod rounds.** This is the doubling every other PC buff
    already gets from `eff_dur_x2`, which Might was only excluded from because of the
    linked-effect bug. The doubling is done in the script, so that fix stays intact.
  - **Divine Wrath damage goes up by +3 at every tier**, from 3/5/7/9/11/13/15/17 to
    6/8/10/12/14/16/18/20. The +20 cap is gone, so no tier has to be clipped.
  - Neither ability's per-hit bonus has a ceiling any more. A CHA mod above 20 now counts
    in full.
- **Docs**: add a `<h3 id="divine-might-wrath">` section to
  `docs.manual/Customizations/Combat.html`. This is a combat rule that differs from
  stock NWN. Then run `python3 bin/gen-customizations-hub.py`.

## Part B: two legendary feats (need sign-off)

| # | Name | Effect | Route | Prereq |
|---|---|---|---|---|
| 1134 | **Legendary Divine Might** | Divine Might deals **CHA mod + STR mod** resistible divine damage per hit (no +20 cap now) and lasts **2 × (CHA mod + STR mod) rounds** | `hook`: branch in `x0_s2_divmight.nss` | Divine Might; **Strength 28+ (base)**; **Charisma 18+ (base)**; **BAB 35+** |
| 1135 | **Legendary Champion's Wrath** | **+1 Divine Wrath use per 10 Divine Champion levels** (up to 5/day at DC 40). Duration becomes **CHA mod + STR mod rounds** (still doubled). Damage stays at the part-A table | `hook`: branch in `x2_s2_divwrath.nss` + rest reset | **Divine Champion level 30+**; **Charisma 20+ (base)**; Strength 24+ (base) |

The prerequisites are set so each feat takes a real build commitment. Every numeric clause
reads the **base** score, so gear can't be used to meet it. BAB 35 is what a pure 3/4-BAB
level-60 character has, and the martial feats already use that gate. DC 30 is three-quarters
of the class cap of 40, which leaves room for 10 levels of Paladin or other classes. A
Monk/Pal/CoT/WM splash build does not qualify.

Naming: the drafted pool already has a *Legendary Divine Wrath* (`llf-divine-wrath`, a Cleric dominion damage-type override), so the Divine Champion feat here is **Legendary Champion's Wrath** to keep the two distinct.

Why this split: Might carries the Strength damage the player asked for, and Wrath carries
uptime (uses and duration). Wrath already reaches +17, and part A makes both resistible,
which answers Balendin's balance point. Each feat also costs a level-60 pick.

Example, a feat holder with STR +15 and CHA +8:
- Might: today +8 for 8 rounds; without the feat, +8 for 16 rounds; with it, +23 for
  46 rounds.
- Wrath: today 16 rounds; with the feat, 46 rounds (after doubling), and up to 5 casts
  a day at DC 40.

- **`bin/gen-legendary-feats.py`**: append two `Feat(kind="hook", category="Divine")`
  entries. The list is append-only, so they become rows 1134/1135. Clauses:
  - Base-ability clauses use the same form as Legendary Wrath's CON clause.
  - `REQ_BAB(35)`.
  - `Req("Divine Might", "GetHasFeat(FEAT_DIVINE_MIGHT, oPC)")`.
  - `Req("Divine Champion level", "GetLevelByClass(CLASS_TYPE_DIVINECHAMPION, oPC)", 30)`.
  Run `--apply`. Kind `hook` means `LegFeat_ApplyAll` leaves them alone.
- **Extra Wrath uses**: after a cast, if `extras used < DC level / 10`, call
  `IncrementRemainingFeatUses(OBJECT_SELF, FEAT_DIVINE_WRATH)` and increment the counter.
  This refunds the use just spent, so the engine's max-uses cap is never exceeded and no
  2DA change is needed. Reset the counter on `REST_EVENTTYPE_REST_FINISHED` in
  `unpacked/on_mod_rest.nss`. Persist it where `unpacked/pers_state_inc.nss` persists
  feat uses (it already tracks feat uses), so a relog cannot refill the extras.
- Run `python3 bin/gen-legendary-feats-doc.py`.

## Roadmap, release, publish

- Patch with `bin/roadmap-apply-patch.py`, then run `bin/roadmap-lint.py`:
  - `status: manual`, `commit:`, `date:`.
  - `docs:` pointing at the Combat anchor.
  - `notes` that **say plainly that Divine Might/Wrath are now resisted by divine
    resistance/immunity for everyone**, alongside the new feats.
  - `impl_notes` covering hak + TLK + NWSync.
  - `uat` steps, with `tester:` set to "paladin with Divine Might" and "Divine Champion 20+".
- Dev only: run `bin/publish-and-arm`, because the feat rows and TLK change. The new
  include is new and `devcrit_atk.nss` changes itself, so a plain repack picks both up.
  **Any later edit to `divdmg_inc.nss` needs `repack-homers-lotr-clean`.**
- Promoting to season 2 needs the admin's explicit go-ahead and a release note, since this
  is a nerf to every existing paladin/DC.

## Verification

- Repack gates pass: `tests/check_legendary_feats.py`, `check_customizations_hub.py`,
  and compile.
- `strings` on the packed `devcrit_atk.ncs` / `x0_s2_divmight.ncs` / `x2_s2_divwrath.ncs`
  shows the new locals.
- UAT on dev:
  - Cast Divine Might and hit the Combat Dummy: a separate divine damage line appears per hit.
  - Hit a divine-immune target: it takes no divine damage. Then give it partial divine
    resistance and check the damage is reduced.
  - Let the buff expire and hit again: no divine line.
  - Cast Might and Wrath together: both lines appear.
  - Feat holders: check the damage and the timer. Spend Wrath until the extras run out,
    rest and see them come back, and relog mid-day to confirm they do not refill.

- Check the consolation: without the feat, Might's timer shows 2 × CHA rounds, and
  Wrath at DC 35+ shows +20 per hit against a non-resistant target.

## To confirm at sign-off
- The feat prerequisites and numbers in the Part B table.
- The consolation package: Might's doubled duration and Wrath's +3 per tier.
