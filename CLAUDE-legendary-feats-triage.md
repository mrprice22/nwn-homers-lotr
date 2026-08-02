# Legendary Feats — draft triage

The one-time pass over `docs.manual/Draft/LegendaryFeats.html` that
[CLAUDE-legendary-feats.md](CLAUDE-legendary-feats.md) calls for at the top of
phase 5. **The draft is a wish list, not a spec**; this file is the spec's
skeleton — for every entry, the route it takes, or why it is cut.

Done once, on 2026-08-01, so nobody re-derives "can NWN even do that?" per feat.
When a category story starts, read its section here first.

> ## ⚠ NOTHING BELOW IS APPROVED
>
> **Every legendary feat needs the admin's explicit sign-off before it is
> implemented** — its name, effect, numbers and prerequisites, feat by feat,
> **in every category on this page without exception**. Not just the sections
> under active discussion.
>
> This document is *my* proposal for what is buildable and what each thing would
> cost. The admin has reviewed only what they have commented on directly; the
> routes, the cuts and every number here are open. **A section this file calls
> cheap, or recommends building next, is still unapproved** — a build order is
> not a licence.
>
> The reason it is a hard gate and not a courtesy: **`FEATS` in
> `bin/gen-legendary-feats.py` is append-only.** A feat's row index becomes its
> id in every save game the moment a character takes it, so a name or a number
> that ships wrong cannot be taken back cleanly.
>
> Building the *machinery* for a category unprompted is fine. Building the
> *content* is not.

## The routes

| Code | Route | What it costs |
|---|---|---|
| **RAW** | Base ability score write (`LEGFEAT_KIND_RAW`). | Nothing new — shipped. |
| **EFF** | One permanent supernatural effect, a case in `LegFeat_ApplyOne`. | A few lines. Rebuilt at login by `LegFeat_ApplyAll` already. |
| **EFF\*** | An effect whose *size* depends on the character (e.g. a DEX modifier), so it must be recomputed, not just re-applied. | `LegFeat_ApplyAll` already runs at login; a level/equip hook is the extra piece. |
| **HOOK** | A combat or skill event: `NWNX_Events` (`ON_CREATURE_ATTACK`, `ON_USE_SKILL`), the module's `OnPlayerDying`/`OnPlayerDeath`, or an existing on-hit path. | A new handler script per feat, plus the subscription. Real work. |
| **SPELL** | Branch in a spell script on `GetHasFeat()`. **The module holds only 13 `nw_s0_*` scripts** — the rest resolve from game data, so the upgrade means copying the stock script into `unpacked/` first, which takes ownership of it forever. | Moderate per feat, and a maintenance tail. |
| **CUT** | The behaviour is engine-owned and not reachable from script. Either dropped or reshaped into something that is; the reshape is named in the row. |  |

Two rules that fall out of the survey and are worth stating once:

- **Prefer EFF.** A feat that is one permanent effect costs a case statement and
  is impossible to get subtly wrong. Anything reshaped from CUT/HOOK into EFF is
  a win even at some loss of flavour, and the draft's numbers are not sacred.
- **A SPELL feat takes ownership of a stock script.** Copying `nw_s0_*` into
  `unpacked/` means this module now maintains Bioware's spell forever, including
  through any future patch. That is the real price of the 41-feat
  `ll-feats-spell-upgrades` story, and it is why it sits sixth in the order.

## Duplicates, resolved

- **Legendary Shadow Step** appears in *Ki & Mystic* (Hide 35+, Monk 20+) and in
  *Exotic* (Hide 35+, Rogue **or** Monk 20+) with the same effect. **One feat**,
  the Exotic prerequisite (the broader one) — it ships with
  `ll-feats-ki-perform-skill`, and the Exotic section loses its second row.
- **The four Bard feats** (*Silver Tongue*, *Illusionist*, *Cutting Words*,
  *Inspiration*) are listed verbatim in both *Performance & Support* and
  *Hybrid Caster Feats → Bard*. **One set**, shipping with
  `ll-feats-ki-perform-skill`; `ll-feats-hybrid-pure` covers Paladin and Ranger
  only.
- **The Pure Class Passive Bonuses table restates the pick lists.** Nearly every
  entry in it is a feat that already exists elsewhere on the page. **Cut in
  full** — see that section below, along with the no-purity-tests rule that came
  with the decision and binds every category story.

That is **139 draft entries → 132 distinct feats** before any cuts.

---

## Ability Scores (6) — shipped

All **RAW**. Live since phase 2/3. The only feats in the pool that write the
`.bic`, and the reason `LEGFEAT_KIND_RAW` exists.

## Martial (23) — `ll-feats-ability-martial`

| Feat | Route | Note |
|---|---|---|
| Legendary Assault → **Legendary Prowess** | **EFF** | `EffectAttackIncrease(5)`. Renamed and re-gated 2026-08-01: **BAB 35+ and Epic Prowess**, because BAB 20 is free at this level cap. **Approved and published 2026-08-01.** |
| Legendary Onslaught | **EFF (conditional)** | `EffectModifyAttacks(1)`, **melee and unarmed only** — the melee counterpart to Legendary Marksman. Re-gated 2026-08-01: **BAB 30+ and Monk level 30+** (a class level, stated outright, rather than Flurry of Blows — which is monk-only and so said "monk" without saying it). **Approved and published 2026-08-01.** |
| Legendary Weapon Finesse | **EFF\*** | `EffectDamageIncrease` sized from the DEX modifier. Recompute on login and level; it will also apply to ranged, which is a widening the draft did not ask for — accept or restrict via HOOK. |
| Legendary Sneak (+3d6) | **EFF\*** | Not an effect: grant three stock `FEAT_EPIC_IMPROVED_SNEAK_ATTACK_*` with `NWNX_Creature_AddFeat`. Needs a third kind — a feat that grants engine feats — and a revoke path that removes exactly those and no others. |
| Legendary Rage | **SPELL** | Rage is an impact script (`nw_s2_rage`); copy and branch. The Barbarian chain is the draft's own "nearly mandatory", so it is worth the ownership. |
| Legendary Fury (revive at 50%) | **HOOK** | Module already has `OnPlayerDying`/`OnPlayerDeath`. The easiest HOOK in the set — good first one. |
| Legendary Bloodlust | **HOOK** | HP-threshold watch on `OnDamaged`. |
| Legendary Weapon Mastery (+5 dmg with EWS weapon) | **HOOK** | Equip-time: on `OnPlayerEquipItem`, apply the effect iff the wielded weapon matches an EWS feat the character holds. Reshape to "while wielding" rather than per-hit. |
| Legendary Overwhelm (crit stun) | **HOOK** | `NWNX_Events` `ON_CREATURE_ATTACK`, criticals only. |
| Legendary Intimidate | **HOOK** | `ON_USE_SKILL`. |
| Legendary Bleeding Wound | **HOOK** | On-hit vs favoured enemy; pairs with Legendary Hunter. |
| Legendary Vital Strike | **HOOK** | On-hit, once per round. |
| Legendary Cutpurse | **HOOK** | Pickpocket event. |
| Legendary Momentum | **HOOK** | Per-target consecutive-hit counter; the most state of any martial feat. |
| Legendary Power Attack (+3/point) | **CUT → HOOK** | The multiplier is engine-owned. Reshape: flat damage while `GetActionMode(ACTION_MODE_POWER_ATTACK)` is on, polled on the existing heartbeat. |
| Legendary Whirlwind (hits twice) | **CUT → HOOK** | Whirlwind is engine-resolved. Reshape via a feat-use event, or cut. |
| Legendary Hunter (Favoured Enemy +4) | **CUT → HOOK** | The favoured-enemy bonus is a fixed engine value. Reshape as on-hit bonus damage vs the favoured races. |
| Legendary Cleave (unlimited) | **CUT** | The per-round cleave limit is engine-owned and there is no clean reshape — an on-kill free attack is a different feat. |
| Legendary Ambidexterity (full off-hand modifier) | **CUT** | Off-hand damage halving is engine-owned. |
| Legendary Devastating Critical (+4 DC) | **CUT** | The DC formula is engine-owned. |
| Legendary Knockdown (size bump) | **CUT** | Size comparison is engine-owned. |
| Legendary Precision (any-size dual wield) | **CUT** | Two-weapon penalties are engine-owned. |
| Legendary Parry (negate one attack) | **CUT** | No script sees an attack before it resolves. |

**Six CUTs, and that is the honest count.** Martial is the worst section for
this: it asks the engine's combat resolver for things the resolver does not
expose. The section still yields ~17 feats, which is more than enough for a
pick-two allotment.

### Martial replacements — design-reviewed 2026-08-01

Proposed to replace the six engine-owned cuts and to widen a section that had
nothing for ranged builds and nothing that helped a party. **Design-reviewed
and revised by the admin; still pending final per-feat sign-off** before any of
it reaches `FEATS` (see the banner at the top of this file).

| Feat | Effect | Route | Prereq |
|---|---|---|---|
| **Legendary Juggernaut** | Immune to knockdown, entangle, paralysis, slow **and disarm** | EFF + `NWNX_ON_DISARM_BEFORE` skip | BAB 20+, Discipline 30+ |
| **Legendary Riposte** | Once per round, when attacked in melee, a parry roll against the attacker's AB returns your weapon damage. No stance — you keep attacking normally | HOOK (`ON_MELEE_ATTACKED`, event 5003) | **60 ranks** in Parry (ranks, not modified skill) |
| **Legendary Butcher** | **+5 dice** of bonus physical damage on a critical, typed to the weapon's base type (bludgeoning / piercing / slashing). Die size scales with the weapon: **d6** small, **d8** medium, **d10** large. **Stacks with the reworked Devastating Critical's +3 dice** — a large weapon with both lands **+8d10** | HOOK (crits) — **needs the NWNX Damage plugin, see below** | **Devastating Critical** (any weapon) |
| **Legendary Reaping** | Each kill grants +2 AB / +2 damage for 12s, stacks to 5 | HOOK | Great Cleave, BAB 35+ |
| **Legendary Grip** | +4 AB and +6 AC while wielding a weapon in each hand | HOOK (equip) | Ambidexterity, Improved Two-Weapon Fighting, Weapon Finesse |
| **Legendary Bulwark** | Flat reduction applied *after* all DR, resistance and % immunity, while a shield is equipped | HOOK (`ON_DAMAGED`) | Shield Proficiency, BAB 15+ |
| **Legendary Marksman** | One extra ranged attack per round with a bow or crossbow; stacks with Rapid Shot | HOOK (equip) | Rapid Shot, Point Blank Shot, BAB 30+ |
| **Legendary Quarry** | +50% damage vs favoured enemies below **50%** HP | HOOK | Ranger level 30+ |
| **Legendary Wrath** | +1 physical damage (equipped weapon's type) per 5% health missing — up to +20 | HOOK (`ON_DAMAGED`) | CON 21+ |
| **Legendary Warcry** | A **passed Intimidate check** gives allies within 10m +4 AB and +4 saves for 3 rounds; 60s cooldown | HOOK (`ON_USE_SKILL_AFTER`) | Intimidate 25+ |
| **Legendary Sundering** | Landed physical attacks (melee or ranged, not spells) cut target AC by 3, stacking to 3; **total capped at the target's base armour+shield AC ignoring enchantment**; further hits refresh the oldest stack | HOOK | BAB 35+, Called Shot |
| **Legendary Called Shot** | Called Shot loses its −4 AB. On a failed Discipline check the stock effects double and add: LEG −40% speed and −4 DEX plus knockdown, ARM disarm plus −4 AB. 8 rounds, stacks 3. Targets immune to knockdown/disarm still resist those parts | HOOK (`ON_USE_FEAT`) | BAB 35+, Called Shot |

> ### The martial hooks want the NWNX **Damage** plugin
>
> **Nothing in the current plugin set can tell a script that a hit was a
> critical.** `NWNX_Events` (checked against the installed `nwnx_events.nss`)
> carries `ATTACK_TARGET_CHANGE`, the two attack-of-opportunity pairs and
> `INPUT_ATTACK_OBJECT` — no attack *resolution* event — and stock NWScript
> exposes `GetLastAttacker` / `GetLastDamager` / `GetLastWeaponUsed` but never
> the attack result. Inferring a critical from the size of the damage is a guess,
> and a wrong one whenever a buff changes.
>
> **`NWNX_Damage` is the tool**, and it is an enable, not new architecture: the
> include is **already staged in this repo** at
> `.nwnx_includes/nwnx_damage.nss`, and the server runs the `nwnxee/unified`
> image, which ships every standard plugin. House procedure: copy the include
> into `unpacked/`, set `NWNX_DAMAGE_SKIP=n` in `server.env`, restart.
> Forgetting the env flip gives per-call "Plugin not loaded" errors and nothing
> else.
>
> `NWNX_Damage_AttackEventData` is close to purpose-built for this set:
>
> ```
> iAttackResult    1=hit 2=parried 3=CRITICAL 4=miss 5=resisted
>                  7=auto hit 8=concealed 9=miss chance 10=DEVASTATING CRIT
> bRangedAttack    bKillingBlow    iSneakAttack    iAttackNumber
> iToHitRoll  iToHitModifier       per-type damage, all modifiable
> ```
>
> It pays for itself across the whole martial set, and **retires two compromises
> already accepted in this document**:
>
> - **Butcher** reads `iAttackResult == 3` (and 10) — a real critical flag
>   instead of a guess from damage size.
> - **Sundering** gets an exact "this attack landed" plus `bRangedAttack`, which
>   is precisely its trigger condition.
> - **Bulwark loses its killing-blow caveat entirely.** The plugin modifies
>   damage *before* it applies, so the flat reduction can prevent a lethal hit
>   rather than healing the difference back afterwards. **If the plugin lands,
>   drop the public-documentation warning that was going to accompany it.**
> - **Riposte gets the exact attack roll** (`iToHitRoll + iToHitModifier`)
>   instead of approximating the DC from the attacker's base attack bonus.
> - **Wrath** and **Quarry** get per-type damage data for their scaling.
>
> **The caution, and it is not small:** the damage event script intercepts *every
> point of damage on the server*. A bug in it is a bug in all combat, not just
> in legendary feats. It wants its own gate and a deliberately boring handler
> that returns early for characters holding none of these feats.

Design notes worth keeping:

- **Keen and Butcher do not interact, and no `Legendary Improved Critical` is
  needed.** Keen widens the *threat range*; Butcher raises *critical damage*.
  They stack by construction. An earlier draft of this file proposed a feat that
  stamped Keen onto the player's weapon — **discard that idea**: keen is cheap
  and plentiful in this module, so the feat would have been near-worthless, and
  writing to player gear collides with the forge for no gain.
- **Butcher's bonus is typed physical on purpose**, so it is subject to the
  target's physical damage reduction like any other weapon damage. Against a
  heavily armoured target a fair slice of it will be eaten. That is the intended
  behaviour, not an oversight — and it is why Sundering exists.
- **Butcher is half of a larger change, not a feat on its own.** The rework of
  the *stock* Devastating Critical — save-or-die out, **+3 size-scaled dice** in
  — is roadmap item **`devcrit-roll`**, asked for by players, and Butcher is
  built on top of it: same dice, same typing, +5 more, stacking. **Build
  `devcrit-roll` first**; Butcher is a small addition once it exists, and
  meaningless before it. Weapon size comes from
  `Get2DAString("baseitems", "WeaponSize", …)` — NWScript has no
  `GetWeaponSize`.
- **`BAB 20+` is not a prerequisite at level 60** — levels 21-60 hand out +1 BAB
  every 2 levels, so everyone has it. A martial prerequisite that means anything
  has to be **30+ or 35+** (a pure level-60 Fighter reaches 40, and what
  separates builds is levels 1-20).
- **The Sundering cap is the good part of the design.** Capping the reduction at
  the target's *base* armour+shield AC makes the feat scale with how armoured
  the target is, rather than being a flat debuff that trivialises lightly
  armoured enemies.
- **Bulwark cannot stop a killing blow.** `ON_DAMAGED` runs after the damage
  lands, so a hit that reaches 0 HP resolves first. Accepted — **and it must be
  stated in the public feat documentation**, not just here.
- **`ON_MELEE_ATTACKED` fires on the attempt, not the hit**, and only for melee.
  That suits Riposte (you parry an attack, not a wound) and matches stock Parry
  being melee-only.

### Legendary Shadow Bomb — replaces the draft's Shadow Step

The draft's teleport is dropped: a scripted blink risks landing a player in
geometry they cannot escape, and the module has no safe-point data to blink to.
What survives is the *moment* — the escape from a closing fight.

> **Trigger:** a hit drops you below 35% HP. **90-second cooldown.**
> Everything within the radius except you is frozen for 3 seconds. When it ends
> you gain 50% concealment for 1 round.

- **It does not discriminate.** Hostiles, neutrals, henchmen, summons **and your
  own party** are caught. Bombs do not pick sides — and the cost is real: it can
  freeze your healer at the exact moment you are at 35% HP, and frozen allies
  are helpless while frozen too. That cost is the point; do not quietly exempt
  the party later.
- **Bosses are NOT exempt**, and the freeze is meant to punch through the
  freedom-of-movement and hold/paralysis/petrification immunities bosses carry.
  **`EffectCutsceneParalyze` is exactly this effect** — the engine documents it
  as "identical to `EffectParalyze` except that it cannot be resisted", which
  buys both halves at once: unresistable *and* carrying paralysis's combat
  consequences, so anyone frozen is helpless, loses their Dexterity bonus and
  can be sneak attacked. Watch for the one thing the engine cannot promise: a
  boss whose *script* strips effects on a heartbeat will still shrug it off.
  That is a UAT item, not an engine question.
- **Snapshot at trigger time.** Anyone who walks into the radius during the 3
  seconds is unaffected — which falls out naturally from resolving the shape
  once, rather than maintaining an area of effect.
- **It must not turn allied factions hostile.** Apply the effects with a source
  that is not the player, so the engine does not read a hostile act against a
  friendly and start a war in a town.
- **VFX:** `VFX_FNF_SMOKE_PUFF` at the point of detonation plus `VFX_DUR_DARKNESS`
  for the duration.

**Never build this out of `EffectTimeStop`.** That effect is module-wide — it
freezes every player in every area, which is why it is banned here, and the
engine shipping `EffectTimeStopImmunity` as the only escape confirms there is no
scoped version of it.

## Defensive & Survival (16) — `ll-feats-defense`

The best section in the draft: **eleven of sixteen are one effect each.** This
is the cheapest large tranche in the whole pool and a strong candidate to ship
next.

| Feat | Route | Note |
|---|---|---|
| Legendary Resilience | **EFF** | `EffectRegenerate(10, 6.0)`. |
| Legendary Dodge | **EFF** | `EffectACIncrease(5, AC_DODGE_BONUS)`. |
| Legendary Armor Skin | **EFF** | `EffectACIncrease(4, AC_NATURAL_BONUS)`. |
| Legendary Damage Reduction | **EFF** | `EffectDamageReduction(10, DAMAGE_POWER_PLUS_FIVE)`. |
| Legendary Fortitude / Iron Will / Lightning Reflexes | **EFF** ×3 | `EffectSavingThrowIncrease(SAVING_THROW_*, 6)`. |
| Legendary Death Ward | **EFF** | Two effects in one case: death immunity + negative-energy immunity. |
| Legendary Sanctified Body | **EFF** | Disease + poison + ability-drain immunity. |
| Legendary Spell Immunity (one school) | **EFF** | Needs a school choice, so it is really six feats (one per school) or a sub-picker. Ship as six rows — the picker is already a list. |
| Legendary Uncanny Dodge | **EFF** | Stock feats exist (`FEAT_UNCANNY_DODGE_*`); grant route, same as Legendary Sneak. |
| Legendary Toughness (+50 HP) | **EFF\*** | `EffectTemporaryHitpoints` is the only permanent-effect HP route and behaves wrongly (consumed first, not restored on heal). Prefer granting stock Epic Toughness feats — +50 is 2½ of them, so round to +60 (3×) or +40 (2×). **Decide the number, do not fake the mechanic.** |
| Legendary Evasion (elemental) | **CUT → EFF** | Evasion's trigger is engine-owned. Reshape as flat elemental resistance. |
| Legendary Diehard (to −20) | **CUT** | The unconscious threshold is engine-owned. |
| Legendary Discipline (auto-fail knockdown) | **CUT → EFF** | Reshape as a large `EffectSkillIncrease(SKILL_DISCIPLINE)`, which reaches the same place through the rules. |
| Legendary Slippery Mind (reroll Will) | **CUT** | No script sees a save before it resolves. |
| Legendary Fate's Hand | **HOOK** | `OnPlayerDying`; shares the handler with Legendary Fury. |

## Arcane (17) + Divine (15) — `ll-feats-arcane-divine`

Settle the **caster-level-scaling-vs-feat** balance question (`ll-cls-progression`)
before starting; roughly a third of this section is "+1 caster level"-shaped and
may already be covered there.

- **EFF:** Legendary Spell Penetration, Legendary Spell DC, Legendary Spellcraft,
  Legendary Divine Penetration, Legendary Divine Shield (CHA-sized, so EFF\*),
  Legendary Aura (party-wide, so an area re-application, not one effect),
  Legendary Sanctified Body (dupe of the defensive row — one feat).
- **SPELL:** Legendary Timestop, Legendary Wish, Legendary Empower, Legendary
  Spell Shaping, Legendary Shapeshift and its three dependants (Primal Wrath,
  Nature's Grasp, Wild Surge), Legendary Mass Healing, Legendary Turning,
  Legendary Wrath of God, Legendary Spontaneous Recovery.
- **HOOK:** Legendary Spellsword, Legendary Counterspell, Legendary Arcane Shield,
  Legendary Spell Thief, Legendary Intercession, Legendary Smite, Legendary Holy
  Wrath, Legendary Arcane Recovery, Legendary Spell Echo.
- **CUT:** Legendary Caster (+1 caster level — engine-owned; the module's caster
  level comes from `ll-cls-progression`, so put it there or nowhere), Legendary
  Metamagic (slot costs are engine-owned), Legendary Battle Mage (casting AoO is
  engine-owned), Legendary Concentration (interruption is engine-owned).

**Legendary Shapeshift is the keystone of the Druid half** — three other feats
name it as a prerequisite, and shapeshift already collides with
`sd_filter_inc.nss` (which destroys the creature-armour item on shift; that
collision is why legendary bonuses are effects and not skin properties). Do it
first in this section or not at all.

## Ki & Mystic (4) + Performance (7) + Skills (5) + Exotic (2) — `ll-feats-ki-perform-skill`, `ll-feats-exotic`

Small and mostly cheap; the natural **second or third** tranche.

- **EFF:** Legendary Iron Body (`EffectSpellResistanceIncrease(5)`), Legendary
  Perform (`EffectSkillIncrease`), Legendary Ki Strike (damage-type/DR bypass via
  an on-hit or an unarmed damage effect — verify which), Legendary Lore.
- **SPELL:** Legendary Wholeness (Wholeness of Body is an impact script),
  Legendary Silver Tongue, Legendary Illusionist, Legendary Cutting Words,
  Legendary Inspiration.
- **HOOK:** Legendary Wordstrike, Legendary Maestro, Legendary Heal,
  Legendary Persuade, and:
  - **Legendary Shadow Step → replaced by Legendary Shadow Bomb** (see the
    martial section above). Automatic on dropping below 35% HP, no teleport, no
    activation.
  - **Legendary Second Wind — automatic, approved in design.** Triggers at 25%
    HP: **a full heal**, once per rest, no fatigue or after-effect. Reset the
    per-rest use on the **Force Rest actions**, never `REST_FINISHED` — this
    module cancels the engine's rest at `REST_STARTED`, which is precisely the
    bug that ate UAT round 3.
- **CUT → EFF:** Legendary Tumble (AoO avoidance is engine-owned; reshape as a
  large Tumble skill bonus), Legendary Hide (stealth checks are engine-owned;
  reshape as a large Hide/Move Silently bonus).

> **Activated feats — resolved 2026-08-01, and the first answer was wrong.** An
> inert `feat.2da` row is not activatable (`ReqAction` is 0 on every generated
> row, on purpose), and I first read that as needing a `spells.2da` entry — a
> second generator and a second hak table. **It does not.** The module's
> `OnActivateItem` (`dmfi_activate.nss`) already dispatches by item tag to a
> script: the Dye Kit, the bestiary book, the ammo bench and the **Horn of the
> Fell Beast** all work this way, and the Horn is the exact precedent — an
> activated item with a cooldown and per-character state in a campaign DB.
>
> So an activated legendary feat is: a bound token item granted with the feat,
> carrying *Cast Spell: Unique Power (Self Only)*, plus a tag case in
> `dmfi_activate`. No new 2DA, no new hak table. The cost is a `.uti`, a script,
> grant/revoke wired into `LegFeat_ApplyOne`/`LegFeat_RevokeAll`, and an
> anti-drop guard so the token cannot be sold, lost or duplicated.
>
> **Prefer an automatic trigger anyway where one reads the same** — an automatic
> feat has no token to lose and no inventory slot to explain. The token route is
> for the feats where the *choice of moment* is the whole point.

## Legendary Spell Feats (41) — `ll-feats-spell-upgrades`

**All SPELL, and each one takes ownership of a stock spell script.** 41 feats ≈
35 scripts this module would maintain forever. That is the whole story of this
item and the reason it is sixth.

Recommendation: **do not ship this as one story.** Take the sub-sections that
touch scripts already in `unpacked/` or already owned — Summons (`nw_s0_summon`
is present, and `summon_boost.nss` already scales summons, so check the two do
not multiply), Tenser's (`nw_s0_tenstrans`), Time Stop (`nw_s0_timestop`),
Polymorph/Shapechange — and leave the rest until the pool needs the breadth.

Specific hazards found:

- **Legendary Nature's Alliance / Call of the Wild / Summon IX / Mummy Dust /
  Dragon Knight** all stack on top of `summon_boost.nss`, which already gives
  summons a permanent undispellable boost scaled by class level and focus feats.
  Doubling a summon *and* boosting it is not the number anyone intends.
- **Legendary Energy Drain (4 negative levels)** is a *player-cast* upgrade, but
  read `LegFeat_HasNegativeLevels` before touching anything drain-related — the
  revoke path defers on any negative level, and that guard exists for a reason.
- **Legendary Vampiric Touch** ("permanent max HP increase up to +50") is a
  permanent character change from a repeatable spell. **Cut it** — it is a
  grind-a-max-stat button, the same shape as the re-pick stat farm.
- **Legendary Web / Legendary Planar Binding** ("permanent until dispelled",
  "serves indefinitely") leave persistent objects on a persistent server. Cap
  them or cut them.

## Dominion (3 feats, 18 cantrip toggles) — `ll-feats-dominion`

Genuinely last, and the estimate in the draft is optimistic. It needs:

1. **Six cantrips that do not exist** (Sonic Snap, Void Touch, Holy Spark,
   Shadow Bolt, Frost of Faith, Thunder Word, Thorn Whip, Verdant Surge — eight,
   in fact, counting the two Druid ones). Each is a `spells.2da` row plus a
   script — the same missing machinery as the activated-feats gap above.
2. **A damage-type override on every damaging spell**, which means the SPELL
   route applied to the entire damage list at once, not per feat.

**The toggle mechanism is settled (2026-08-01): a trinket, not cantrips.** A
bound token item whose Unique Power opens an element-picker NUI —

- **usable in combat**, deliberately;
- **3 element selections per rest**;
- **the window always opens, even with selections spent**, because reverting to
  stock damage types is free and unlimited. The cost is on *committing* to an
  element, not on backing out.

So the eight missing cantrips are not needed and point 1 above falls away. Point
2 remains the real work. Note the trinket carries the same ~2-turn activation
delay that ruled item activation out for reflexive feats — tolerable for
switching a stance, and the same window can also hang off the rest menu for
free out-of-combat switching if that delay grates.

## Pure Class Passive Bonuses (11) — CUT, decided 2026-08-01

**Cut in full, by the admin's call.** Every line in the draft's table restated
feats from the pick lists — "Fighter: +5 AB, +5 damage with EWS weapons, bonus
attack per round" is Legendary Prowess + Weapon Mastery + Onslaught, granted
rather than chosen — and handing a pure Fighter its picks for free is what left
the question "so what are its three picks *for*?" with no answer.

**The 3 / 2 / 1 allotment IS the pure-class reward.** Nothing else in this
system pays for purity, and further pure-class support is a separate future
effort: **pure-class items**, not feats.

### The rule that falls out of it, and it binds every category story

**No legendary feat may test for purity.** Not in a prerequisite, not in the
picker, not in its effect. A feat is available on its own merits to whoever
meets its prerequisites, whatever else they levelled.

This is a real edit to the draft, not a formality — the draft leans on purity
constantly, and reads it into prerequisites that do not say so out loud:

- **`Bard level 60`, `Paladin level 60`, `Ranger level 60`, `Wizard or Sorcerer
  level 60`, `Druid level 60`, `Fighter level 60`** are purity tests in
  disguise. At a level cap of 60, "60 levels of Bard" *means* pure Bard.
  **Rewrite every one of them to a threshold a multiclass can reach** — the
  house form is `<class> level 30+`, which is what the rest of the draft already
  uses for the same feats' siblings.
- **Class-level prerequisites themselves stay.** "Monk level 30+" on a ki feat
  is not a purity gate, it is the feat asking for the class it belongs to, and a
  30/30 Monk/Rogue qualifying for it is the intended behaviour.
- **The Dominion tier's "full 9-spell-level casters only"** was likewise
  expressed as level 60 in one class. Express it as what it actually means —
  enough caster levels to hold 9th-level slots — or drop the restriction.

## Where the pool actually lands

| Section | Draft | Distinct | After cuts | Cheap (RAW/EFF) |
|---|---|---|---|---|
| Ability Scores | 6 | 6 | 6 | 6 ✔ shipped |
| Martial | 23 | 23 | 17 | 2 ✔ shipped, +2 |
| Defensive | 16 | 16 | 15 | 13 |
| Arcane + Divine | 32 | 31 | 27 | 7 |
| Ki / Performance / Skills / Exotic | 18 | 13 | 13 | 6 |
| Spell upgrades | 41 | 41 | 38 | 0 |
| Dominion | 3 | 3 | 3 | 0 |
| Pure-class packages | 11 | 0 | 0 (cut) | 0 |
| **Total** | **150** | **133** | **119** | **34** |

**Suggested order, revised from the design's** (which was written before this
pass): Defensive next, not Arcane — thirteen effect feats for the cost of
thirteen case statements, and the pool needs breadth more than it needs depth
while there are eight feats in it.
