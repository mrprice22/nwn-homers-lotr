# Legendary Feats — architecture and build order

Feats selectable only at character level 60, the second half of the
`legendary-levels` epic (levels 41–60 themselves already shipped — see
`README.md` "Levels 41–60").

Design draft: `docs.manual/Draft/LegendaryFeats.html` (~139 feats + 18 dominion
cantrip toggles + 11 pure-class packages). The draft is a **wish list, not a
spec** — expect a triage pass, not a transcription.

This document records the architecture and the order the pieces must be built in,
so the sequencing does not have to be re-derived. Roadmap items: `ll-feats-tlk`,
`ll-feats-2da`, `ll-feats-picker`, then the seven `ll-feats-*` category stories.

## Checkpoint — 2026-08-03 (third session)

**The martial replacement set is built: nine feats, rows 1125–1133, taking the
pool from 9 to 18.** The admin approved the reviewed table wholesale on
2026-08-03 (the sign-off the second-session checkpoint was waiting for). Built
but **not yet published** — the TLK, hak, nwsync, repack and restart still have
to run, and until they do the new rows read as blank names.

Shipped: **Juggernaut** (four immunity effects plus a disarm hook),
**Grip** (+4 AB / +6 dodge AC, conditional on a weapon in each hand),
**Marksman** (+1 attack, conditional on a bow or crossbow),
**Bulwark** (−10 damage behind a shield), **Riposte** (1/round counter-attack),
**Reaping** (+2/+2 per kill, stacks 5), **Wrath** (+1 damage per 5% health
missing, max +20), **Quarry** (+50% vs a favoured enemy below half health),
**Sundering** (−3 target AC per hit, stacks 3, capped at real armour+shield AC).

### The three new pieces of machinery, and why each is shaped that way

- **`legfeat_atk_inc.nss`** — the attacker-side feats (Wrath, Quarry, Sundering,
  Reaping), called from `devcrit_atk.nss`, which is the module's *only* sight of
  an attack result. Two rules govern it, both load-bearing:
  - **Entry is one `GetLocalInt`.** `LEGFEAT_ATK_VAR` is set by
    `LegFeat_ArmHooks` only on a character who holds one of the four. That read
    is the entire cost these feats impose on every other attack on the server.
  - **The damage struct is read-only in there.** `devcrit_atk` owns it and calls
    `NWNX_Damage_SetAttackEventData` once, on the critical path only — so a
    bonus written into the struct from the hook would be silently dropped on
    every ordinary hit and double-counted on criticals. The feats apply their
    damage as a separate `EffectDamage` instead, which also renders honestly in
    the combat log.
- **`legfeat_dmg.nss`** — the defender-side feats (Bulwark, Riposte), registered
  **per character** with `NWNX_Damage_SetDamageEventScript` and only on someone
  holding one of the two. Bulwark runs here rather than on `OnDamaged` because
  the damage event is *after* the engine has finished with DR, resistance and
  immunity: it is the one layer nothing can resist around, and it is why Bulwark
  can prevent a killing blow.
- **`legfeat_disarm.nss`** — the engine has no `IMMUNITY_TYPE_` for disarm, so
  the only way to make a weapon unstrikable is to skip
  `NWNX_ON_DISARM_BEFORE`. That is why Juggernaut is an effect feat with one
  hook bolted on rather than a pure effect feat. A second subscriber alongside
  `disarm_catch` is fine — NWNX_Events runs them all.

All three are switched on **and off** by **`LegFeat_ArmHooks`**, called at the
end of `LegFeat_ApplyAll`. It must clear as readily as it sets: without the else
branches, a character who respecs out of Bulwark keeps the damage script, and
keeps the reduction.

**New gate**, negative-tested: every HOOK feat read by a *gated* hook must be
named in `LegFeat_ArmHooks`. The existing payload gate proves a reader exists;
this one proves the reader is ever reached. A handler that never runs looks
exactly like a handler that does not exist.

### Two of the twelve were NOT built, and both need an answer

They are recorded as `design_questions` on `ll-feats-ability-martial`:

- **Legendary Warcry** — its trigger does not exist. Intimidate is not an
  activated skill in NWN, and `NWNX_ON_USE_SKILL_*` only fires for skills a
  player actually activates. Proposal: re-base it on **Taunt**, keeping every
  number and the Intimidate 25+ prerequisite.
- **Legendary Called Shot** — "loses its −4 attack penalty" is engine-owned and
  cannot be scripted away; the penalty is applied inside the engine's own Called
  Shot resolution. The doubled-and-extended effects on a failed Discipline check
  *are* buildable on `NWNX_ON_USE_FEAT_AFTER`. Proposal: ship the second half
  and reword the feat, or cut it and let Sundering carry the role.

**Next after publishing and UAT:** `ll-feats-defense` — thirteen single-effect
feats, still unreviewed, and it needs two numbers from the admin (Legendary
Toughness rounds to +40 or +60 HP; Spell Immunity ships as six rows or not at
all).

## Checkpoint — 2026-08-01 (second session)

**Phases 1–4 are done. Phase 5 has started: the triage pass is complete and the
first two effect feats are approved, published and awaiting UAT.** A new session should
read this section, then
[CLAUDE-legendary-feats-triage.md](CLAUDE-legendary-feats-triage.md).

### The rule that overrides everything else here

**Never implement a legendary feat without the admin's explicit approval of that
specific feat** — name, effect, numbers, prerequisites. **This covers every
category, without exception**: martial, defensive, arcane, divine, ki,
performance, skills, exotic, spell upgrades, dominion, hybrid. Not just the ones
under active discussion, and not just the ones with open design questions.

The triage document and the `ll-feats-*` backlog read like a settled plan; they
are proposals. As of the end of this session the admin has reviewed **only** the
martial replacement set and the Shadow Bomb / Second Wind / Dominion decisions
below — **everything else in the triage document is unreviewed**, including the
defensive tranche this file recommends building next. Recommending an order is
not approval to build it.

**Building machinery unprompted is fine; building content is not.**

> **Approved and published 2026-08-01:** *Legendary Prowess* and *Legendary
> Onslaught*, after being retuned in the same session (see below). They are the
> first feats to go through this approval gate — everything else in the triage
> document is still unreviewed.

### Built and published this session

- **Prerequisites** (`prereq` / `prereq_text` on `Feat` → generated
  `LegFeat_MeetsPrereq` / `LegFeat_PrereqAt`), enforced in both the picker and
  `LegFeat_Take`.
- **The first two `LEGFEAT_KIND_EFFECT` feats**, rows 1122-1123, **approved:**
  - *Legendary Prowess* — +5 attack bonus. Prereq **BAB 35+ and Epic Prowess**.
  - *Legendary Onslaught* — +1 attack per round, **melee and unarmed only**.
    Prereq **BAB 30+ and Monk level 30+**. The pool's first CONDITIONAL feat.
- **Two new gates** in `tests/check_legendary_feats.py`, both negative-tested.

**Published** — TLK, hak, nwsync, repack and restart all ran. **The UAT step
that matters most is the relog check**: these are the first effect feats, so
they are the first real exercise of the login re-apply path, and it has not been
exercised in game yet. Remaining UAT is on `ll-feats-ability-martial`.

### Decisions taken this session (do not relitigate)

- **Pure-class passive packages: cut.** The 3/2/1 allotment is the pure-class
  reward; further pure-class support will be **items**, not feats. Consequently
  **no feat may test for purity** — rewrite the draft's `<class> level 60`
  prerequisites (purity tests in disguise at a cap of 60) to `<class> level 30+`.
- **Activated feats do not need `spells.2da`** — a bound token item plus a tag
  case in `dmfi_activate.nss` (the Horn of the Fell Beast pattern). But **item
  activation costs ~2 in-game turns, so it is unusable for reflexive combat
  abilities.** Automatic triggers for those; tokens only for stance-like choices.
- **Legendary Shadow Step is replaced by Legendary Shadow Bomb** — automatic at
  35% HP, `EffectCutsceneParalyze` in a radius (unresistable, and identical to
  normal paralysis otherwise, so victims are helpless and sneak-attackable), 90s
  cooldown, hits allies too, bosses not exempt, snapshot at trigger. **Never
  build it out of `EffectTimeStop`, which is module-wide.**
- **Legendary Second Wind** — automatic at 25% HP, **full heal**, once per rest,
  no after-effect. Reset the per-rest use on the **Force Rest actions**, never
  `REST_FINISHED`.
- **Dominion** — trinket + NUI element picker, usable in combat, 3 selections per
  rest, and the window always opens because reverting to stock damage types is
  free. The draft's eight missing cantrips are no longer needed.
- **The martial set has a reviewed replacement list** for the six engine-owned
  cuts, plus ranged and party-support feats the draft lacked entirely. Full table
  with agreed numbers and prerequisites is in the triage doc.

### The blocker in front of the martial set

**The NWNX Damage plugin needs enabling**, and the admin has not yet said yes.
Nothing in the current plugin set can tell a script that a hit was a critical, or
that an attack landed — `NWNX_Events` has no attack-resolution event and stock
NWScript never exposes the result. `NWNX_Damage_AttackEventData` does
(`iAttackResult` 3 = critical, 10 = devastating; plus `bRangedAttack`,
`bKillingBlow`, `iToHitRoll`, and modifiable per-type damage).

The include is already staged at `.nwnx_includes/nwnx_damage.nss` and the server
runs `nwnxee/unified`, so enabling is: copy it into `unpacked/`, set
`NWNX_DAMAGE_SKIP=n`, restart. **Caution: the damage event intercepts every point
of damage on the server**, so it wants its own gate and a handler that returns
early when nothing applies.

Feats blocked on it: **Butcher, Sundering, Quarry, Wrath**, and **Bulwark** gets
strictly better with it (damage reduced *before* it lands, so it can prevent a
killing blow).

### The next thing to build is not a legendary feat

**`devcrit-roll`** (roadmap, promoted to `wip`) — a player request from Piskan,
now designed and **a prerequisite for Legendary Butcher**:

- Devastating Critical stops being save-or-die and becomes **+3 dice** of bonus
  physical damage typed to the weapon; **Butcher adds +5 more, stacking**.
- **Die size scales with weapon size** — d6 small, d8 medium, d10 large, so a
  large weapon with both lands **+8d10**. Weapon size comes from
  `Get2DAString("baseitems", "WeaponSize", …)`; NWScript has no `GetWeaponSize`.
- **Symmetric: it applies to NPCs and players alike.**
- **Suppressing the instant kill is a second mechanism** — the engine applies it
  as an `EffectDeath`, not as damage, so the damage event cannot stop it. Use
  `NWNX_ON_EFFECT_APPLIED_BEFORE` + `NWNX_Events_SkipEvent()`, discriminated by a
  short-lived flag the attack event sets when `iAttackResult == 10`. The module
  already subscribes the `_AFTER` half of that event for `eff_dur_x2`.
- **It must ship with an audit of every crit-immune NPC and the source of each
  immunity.** First pass measured: 91 item blueprints grant it, 181 of 777
  creature blueprints carry one, no script applies it, and it is concentrated in
  `npcbuffgear*` (~75 creatures) and `bossring`/`dontdropbossring` (~41) — so
  removing it is a handful of item edits, not a 181-creature sweep.

Then `remove-crit-immunity` (the same rework from the boss angle) becomes
reviewable.

### Suggested order from here

1. `devcrit-roll` + the NWNX Damage enable (unblocks four martial feats).
2. **`ll-feats-defense`** — 13 of its 16 feats are a single permanent effect, the
   cheapest breadth available while the pool holds eight feats.
3. The reviewed martial replacement set.

## Checkpoint — 2026-08-01 (first session)

**Phases 1–3 are built, published and working in game. The machinery is done;
what is left is content.** Three UAT rounds ran the same day, each finding
defects that are now fixed (phase 4 below records what they were and why —
worth reading before touching any of this, because most of them are the kind
that get reintroduced by someone working from the design alone).

Confirmed in game:

- CEP names still read correctly after the TLK swap (phase 1).
- No legendary feat appears on the engine's own level-up feat page.
- Reaching 60 opens the picker; taking a feat works; the feat and its name,
  description and icon read correctly.
- The green login nudge reports outstanding picks.
- Force Rest reopens the picker while picks remain.
- The admin reset tool removes feats and clears records.

**Not yet confirmed in game** — all shipped and gated, none exercised. A new
session should either drive these or ask for them before starting content:

- Base score, not buff: the sheet's *base* column rises, in plain text, and it
  stacks on a character already at the gear enchantment cap.
- Relog does not double a base-score bonus (that would mean the login path is
  re-applying a RAW feat — permanent and cumulative).
- Revoke on relevel (pure → multiclass) and on a real drop below 60, with base
  scores returning to exactly their pre-pick values.
- **Energy drain does not revoke** — the case that must not be got wrong.
- Re-pick round trip: swap feats three or four times and confirm the scores
  return to the same numbers each time (upward drift is the stat farm).
- Re-picking refused while polymorphed; the Ping Pong node absent below 60.

### Where to pick up (superseded — see the second-session checkpoint above)

**Phase 5, content.** The triage pass is done —
[CLAUDE-legendary-feats-triage.md](CLAUDE-legendary-feats-triage.md) carries the
route for every one of the draft's 139 entries, the duplicates resolved, and the
cuts. **Read the relevant section of it before starting any category story**; it
is what stops "can NWN even do that?" being re-derived per feat.

Adding a feat is: append to `FEATS` in `bin/gen-legendary-feats.py`, `--apply`,
write the behaviour (a case in `LegFeat_ApplyOne` for an effect feat), publish.
The table is append-only and drives the 2DA rows, the TLK strings and
`unpacked/legfeat_ids_inc.nss` together.

Both of the design threads the last session flagged are now closed:

- **`LEGFEAT_KIND_EFFECT` is exercised.** *Legendary Prowess* (`+5 AB`) and
  *Legendary Onslaught* (`+1 attack/round`) are the first two, and the first real
  test of the login re-apply path. **Confirm that path in game before adding
  more effect feats** — every one after them rides on it.
- **Prerequisites are implemented.** A `Feat` carries `prereq` (an NWScript
  boolean expression over `oPC`, rendered verbatim into `LegFeat_MeetsPrereq`)
  and `prereq_text` (what the picker shows). The generator refuses to run with
  one and not the other. Enforced **twice**: the picker greys the row and shows
  "Requires: …" in the effect column, and `LegFeat_Take` re-checks — the window
  is a client-side snapshot, so it is the server-side check that binds.
  Ability prerequisites must read **base** scores; a requirement met by swapping
  a belt on for one button press is not a requirement.

Both of the questions the triage raised are now **answered** (2026-08-01):

- **Activated feats do not need `spells.2da`.** The module's `OnActivateItem`
  (`dmfi_activate.nss`) already dispatches by item tag — the Dye Kit, the
  bestiary book and the Horn of the Fell Beast all work that way. An activated
  legendary feat is a bound token item carrying *Unique Power (Self Only)* plus
  a tag case, granted and revoked alongside the feat. Prefer an automatic
  trigger where one reads the same; use a token only where the choice of moment
  is the point.
- **The pure-class passive packages are cut.** The **3 / 2 / 1 allotment is the
  pure-class reward**, and further pure-class support will be *items*, not
  feats.

**The rule that came with that second decision, and it binds every category
story: no legendary feat may test for purity** — not in a prerequisite, not in
the picker, not in its effect. The draft's `<class> level 60` prerequisites are
purity tests in disguise at a cap of 60 and must be rewritten to a threshold a
multiclass can reach (house form: `<class> level 30+`). Class-level
prerequisites themselves are fine — "Monk level 30+" asks for the class the feat
belongs to, and a 30/30 Monk/Rogue qualifying is intended.

## The core idea: feats are inert tokens

A legendary feat row in `feat.2da` carries **name, description and icon only**.
It has no engine mechanic. Every effect is applied server-side by script:

| Effect shape | How |
|---|---|
| Ability score bonus | A write to the character's **base** score (`NWNX_Creature_SetRawAbilityScore` + `ExportSingleCharacter`, the `mw_mixtape_con.nss` route). Applied **once**, never re-applied at login. Not an effect and not a skin item property — see phase 3. |
| Bonus attack, AC, regen, immunity | Permanent supernatural `Effect*` re-applied at login (e.g. `EffectModifyAttacks(1)` for *Legendary Onslaught*) |
| Spell behaviour change | Branch in the relevant spell script on `GetHasFeat()` |
| Passive rule change | Wherever that rule already lives in `unpacked/` |

This is what makes the draft's "NWN can't express that in a 2DA" entries
tractable — extra attacks per round, rerolled saves and unlimited Cleave are
scripting problems, not 2DA problems. It also means **`feat.2da` never gates
anything**: prerequisites, class restrictions and the allotment are all enforced
by the picker, in script, where they can be arbitrarily expressive.

Corollary, and the easiest bug to ship: **the engine must never offer a
legendary feat on its own level-up feat page.** The picker is the only grant
path. A feat reachable from both is a double-grant.

## Allotment

At level 60, **in addition to** the normal level-60 feat the engine already
grants through the standard level-up UI:

| Character | Legendary picks |
|---|---|
| Mixed class | 1 |
| Pure class | 2 |
| Pure Fighter | 3 |

Fighter gets three because bonus feats are its whole identity and it has no
magic fallback.

Picks are **not** permanent: a player may re-choose them at any time from a
conversation node, and the allotment is re-derived (and revoked) whenever the
character's class makeup or level changes. See "Re-picking" and "Revoking" under
phase 3.

> **This reverses an earlier decision.** `ll-feats-2da` used to record that the
> legendary picks *replace* the standard level-60 feat selection. They do not —
> they are additional. The draft page's `#allotments` table is also older still
> (pure-only, no mixed-class row). Both have been corrected; don't reintroduce
> either from an old note.

## Build order

Each phase ships and is verified on its own. The ordering is not stylistic —
phases 1 and 2 both have silent, repo-wide failure modes that must not be
diagnosed on top of each other.

### Phase 1 — `lotr.tlk` (hard prerequisite)

`feat.2da`'s NAME and DESCRIPTION columns are **strref-only**. The repo's
standing "use inline strings, skip the TLK" policy (`CLAUDE-gotchas.md`) covers
GFF `cexolocstring`s and does not help here. NWN allows exactly one custom TLK
and the module currently uses CEP's (`module.ifo.json` → `Mod_CustomTlk: "cep"`),
so ours must be built *from* `cep.tlk`, not alongside it.

- `bin/build-lotr-tlk` — house generator style: dry-run default, `--apply`,
  `--install`, idempotent, owned string table at the top of the script, modelled
  on `bin/gen-caster-slots.py`. Uses `~/.nimble/bin/nwn_tlk` (present; same
  toolchain as the `nwn_erf` that `build-lotr-rules-hak` already uses) to
  convert `tlk/cep.tlk` → JSON, append our entries **strictly above CEP's last
  index**, write `tlk/lotr.tlk`. `tlk/` is gitignored, so the generated TLK is a
  local build artefact and the script is the thing under version control.
- **`cep.tlk` is sparse — the block starts at 41101, not 7213.** Its header
  declares `StringCount = 41101` (indices 0–41100); only **7213** of those
  carry text, at index 0 and then 30000–41100. An earlier draft of this document
  said 7213/strref 16784429, which was the JSON entry *count* mistaken for the
  entry *range* — appending there would land inside CEP's own block and repoint
  roughly 7000 CEP strings. The real first owned strref is
  `16777216 + 41101 = `**`16818317`** (custom-TLK strrefs are offset by
  `0x01000000`). `bin/build-lotr-tlk` re-reads `StringCount` at build time and
  hard-errors rather than silently re-basing if `cep.tlk` ever changes.
- **`OWNED_STRINGS` is append-only.** Index = `BLOCK_START + position`; once a
  strref is baked into a 2DA row it must never move, so never insert, reorder or
  delete — blank an obsolete string in place instead.
- **Invariant: every pre-existing CEP index keeps its value.** A one-entry shift
  silently repoints CEP-sourced names and descriptions across the entire module,
  and nothing else would catch it. `tests/check_lotr_tlk.py` asserts
  `lotr.tlk[0..41100] == cep.tlk`, that our block matches the generator's table,
  that nothing sits above it, and that `Mod_CustomTlk` reads `lotr` — **importing**
  the generator rather than re-transcribing the strings, the lesson
  `tests/check_epic_tables.py` already encodes in its docstring. It is wired into
  `tests/smoke-test`, so a drifted TLK aborts the repack. On a machine without
  `tlk/cep.tlk` or `nwn_tlk` it warns and passes rather than blocking the build
  on game data it cannot reach.
- `unpacked/module.ifo.json`: `Mod_CustomTlk` `"cep"` → `"lotr"`. **Done — which
  means the module now hard-depends on `lotr.tlk` being installed and synced.**
  Until the repack + nwsync below happen, the flipped `.ifo` is committed but not
  live; once they do, a client without `lotr.tlk` reads blank CEP names.
- **A `.mod` repack is required.** `bin/refresh-nwsync` runs without
  `--with-module` and only reads the `.mod` to discover its hak/tlk dependency
  list, so the nwsync manifest will not carry `lotr.tlk` until the module is
  repacked.
- **Verify this phase alone, with no feat rows**: install, nwsync, repack,
  restart, then confirm in game that CEP item and creature names still read
  correctly.

### Phase 2 — `feat.2da` plumbing + six proof feats

**Base the table on stock, not on `hak_2da/feat.2da`.** That file is a
byte-identical copy of the one inside `cep2_add_feats.hak` — **a hak the module
does not load** (`Mod_HakList` has no `cep2_add_feats`). It is a reference
extract, 24,771 rows and 44 columns. The module actually resolves the **stock**
`feat.2da`: **1116 rows (0–1115, last `PLAYER_TOOL_10`) and 43 columns**.
Building on the CEP copy would silently add ~23,000 CEP weapon-of-choice feats
to the module and change the column count. `hak_2da/feat.2da` **now holds the
stock-based generated table**; the CEP copy it replaced is recoverable from
`cep2_add_feats.hak` if it is ever wanted as a reference again.

- Our rows therefore append at **1116**, and the six proof feats occupy
  **1116–1121**.
- `bin/gen-legendary-feats.py` owns rows 1116+; rows 0–1115 stay byte-identical
  (CRLF included — the table uses CRLF, and rewriting it with bare LF makes
  every base row differ) and the gate asserts it. **One feat-definition table at
  the top of the script is the single source of truth** — it drives both the 2DA
  rows and the TLK strings `bin/build-lotr-tlk` consumes, so a name exists once,
  and each row's strrefs are *derived* from where the TLK builder actually places
  that string rather than written down twice. `--from-stock PATH` reseeds the
  base while keeping our rows; extract a fresh one with `nwn_resman_cat`
  (`nwn_resman_extract -p feat` also works but sweeps thousands of unrelated
  resources and takes minutes).
- `feat.2da` is in `RULES_2DA` in `bin/build-lotr-rules-hak`, whose header
  comment and `README.md`'s "Rebuild from scratch" recipe both now say **twelve**
  — the list and the prose are equally load-bearing there.
- Gate: `tests/check_legendary_feats.py`, following
  `tests/check_epic_tables.py`'s import-the-generator idiom and its
  `read_2da()` helper. It asserts the stock base shape, that our rows match the
  generator, that every one carries `ALLCLASSESCANUSE = 0`, that no
  `cls_feat_*.2da` lists one, that the strrefs match the TLK block, and that
  `feat.2da` is actually in the hak's content list. Wired into `tests/smoke-test`.
- Payload for this phase: **only the six `#ability-scores` feats**
  (*Legendary Strength* … *Charisma*, +6 each). Simplest possible content. The
  rows themselves stay inert — a `feat.2da` row cannot do anything; phase 3 is
  what applies the +6, and it does so by writing the base score (see
  `LEGFEAT_KIND_RAW`), not the skin item property this document originally
  planned.

### Phase 3 — the picker NUI

The files, and what each owns:

| File | Owns |
|---|---|
| `legfeat_ids_inc.nss` | **Generated** by `bin/gen-legendary-feats.py`. Feat ids, names, descriptions, the ability/bonus each ability feat carries, and each feat's prerequisite (`LegFeat_MeetsPrereq` / `LegFeat_PrereqAt`). No script hand-types a row number. |
| `legfeat_db.nss` | `legfeatdb` — `legfeat_alloc` (picks granted, per character) and `legfeat_pick` (one row per feat taken). Keyed on `GetObjectUUID()`. |
| `legfeat_inc.nss` | Allotment, `LegFeat_Take`, and the effects. |
| `legfeat_nui.nss` | The window. Carries `LEGFEAT_SUBTITLE`, the one line of tunable text under the header — see `README.md` "Tuning the picker's subtitle" for the length budget and why it is `NuiText`. |
| `legfeat_evt.nss` | Its click handler (`NuiCreate`'s `sEventScript`). |
| `legfeat_open.nss` | The one entry point — re-derives the allotment, opens the window. |
| `legfeat_lvl.nss` | `NWNX_ON_LEVEL_UP_AFTER` **and** `_LEVEL_DOWN_AFTER` handler. |
| `legfeat_respec.nss` | Player re-pick — hands the feats *and* their base points back, reopens the picker, level unchanged. Node on Ping Pong (`_pc_builder_v1`), gated by `legfeat_cond`. |
| `legfeat_cond.nss` | StartingConditional: level-60 only, writes nothing. |
| `legfeat_reset.nss` | Admin test tool — rest menu → `[Admin Options]`. Puts a character back to "never had a legendary feat"; a feat added by NWNX lives in the `.bic` and nothing else removes one. See `README.md` "Resetting a character's legendary feats". |

- **Trigger:** `NWNX_ON_LEVEL_UP_AFTER` **and** `_LEVEL_DOWN_AFTER` →
  `legfeat_lvl`, subscribed in `onmoduleload.nss`. Level is read with
  `LegFeat_TrueLevel`, never `GetHitDice` (see "Revoking"). It opens the picker on a
  **2-second delay**: at `_AFTER` the engine is still finishing the level-up with
  its own UI on screen, and a NUI window opened into that is one the player
  cannot interact with.
- **Re-entry: hook Force Rest, not the rest event.** The module cancels the
  engine's own rest at `REST_STARTED` in order to open the rest menu — the log
  reads "Resting. / Cancelled Rest." — so **`REST_FINISHED` is not a path a
  player reaches by resting.** `ew_forcerest.nss` and `forcerest.nss` (the two
  Force Rest actions) open the picker directly, 2-second delay so the
  conversation has closed. `on_mod_rest.nss` keeps a `REST_FINISHED` hook as a
  fallback; both firing is harmless, since `LegFeat_Open` destroys any existing
  window before building a new one. UAT round 2 shipped the `REST_FINISHED` hook
  alone and nothing happened, with no error — that is what the cancelled rest
  looks like from the outside. A green login nudge covers characters that were
  already 60 when the feature shipped.
- **Allotment** computed from class levels per the table above; granted with
  `NWNX_Creature_AddFeat`. `LegFeat_EnsureAllotment` writes a computed value
  rather than incrementing, so re-firing it from any path is harmless.
- **Two kinds of benefit, and the difference is load-bearing.** The generator
  tags each feat `LEGFEAT_KIND_RAW` or `LEGFEAT_KIND_EFFECT`:
  - **RAW** writes the character's **base** ability score and is saved in the
    `.bic`. Applied exactly once, at the pick, followed by
    `ExportSingleCharacter`. **Never re-applied at login** — that would stack
    another +6 into the character every session, silently and permanently.
    `tests/check_legendary_feats.py` asserts `LegFeat_ApplyAll` skips them.
  - **EFFECT** is a permanent supernatural effect tagged `LEGFEAT_EFF`, rebuilt
    on every login by `LegFeat_ApplyAll`, which clears the tag first so it is
    idempotent. Nothing uses it yet; phase 5 content will.
- **Re-apply EFFECT feats at login** — `mod_cliententer.nss`,
  `DelayCommand(6.5, …)`. The *feat* persists in the `.bic`; a supernatural
  *effect* does not. This is the piece most likely to be forgotten and it fails
  silently, so the gate asserts the call is there (with `//` comments stripped
  first — the first version of that check happily matched the comment explaining
  the call).

#### Re-picking, and the exploit it must not become

Players may re-choose their legendary feats at any time from a conversation node
(Ping Pong for now — the scripts do not care where the node lives). Level is not
touched. This exists so the pool can grow and gear can change without a reroll.

**Handing a feat back has to be exactly as complete as taking it: the feat AND
its base ability points.** `LegFeat_Respec` goes through `LegFeat_RevokeAll`,
which undoes both from the pick records, so a swap nets to zero. A re-pick path
that removed the feat but left the points would be a repeatable stat farm — the
gate asserts the call is still there. Re-picking (and taking) is refused while
polymorphed: base scores are swapped out in that state, so the write would land
on a body about to be replaced.

#### Revoking: the two triggers, and the one false positive that must not happen

`LegFeat_EnsureAllotment` re-derives the entitlement on **every** call (level up,
level down, login, rest, picker open). The first build wrote the allotment row
once and never looked again, so a pure barbarian who took 2 picks and relevelled
to 59 barbarian / 1 bard kept both — a two-minute exploit with the level setter
on this server.

Every pick is revoked when:

1. **The class composition changed.** Compared via a **class signature** —
   sorted class ids with levels, *no level numbers* (`"36"`, `"1,36"`), built by
   walking class ids in order because NWScript has no arrays. Excluding levels is
   what stops 59 → 60 reading as a change, and the signature alone determines the
   allotment.
2. **The character is no longer level 60.** Death XP loss can take a 60 back to
   59. The allotment row is dropped too, so the picks are re-earned on the way up
   rather than banked.

**Energy drain is not a level loss**, and treating it as one would strip a
permanent feat because a wraith touched someone. Two independent guards:

- The level is judged from **class levels** (`LegFeat_TrueLevel`, summing
  `GetLevelByPosition`), which no effect can touch — deliberately not
  `GetHitDice`.
- If the character carries any `EFFECT_TYPE_NEGATIVELEVEL`, **no revoke decision
  is made at all**. It re-runs at the next login or level event, so deferring
  costs nothing.

Revoking takes the feat back (`NWNX_Creature_RemoveFeat`) *and* subtracts the
base-score points, floored at 3 so a relevel that rebuilt the scores underneath
us cannot produce nonsense, then exports the character.

### Phase 4 — end-to-end UAT

On level-60 test characters of each shape (pure Fighter, pure Wizard, mixed):
picker pops, allotment correct, pick applies, the bonus shows on the character
sheet, relog keeps it, rest reopens the picker while picks remain, and the
engine's own feat page never lists a legendary feat. **No category story starts
until this passes.**

**Round 1 (2026-08-01) found four defects, all fixed.** They are recorded here
because three of them are the kind that would be reintroduced by someone reading
only the design:

1. **The allotment was never re-checked** — see "Revoking" above.
2. **Rest did not reopen the picker.** It shipped as a rest-menu conversation
   node; the wanted behaviour was the window simply coming back on rest.
3. **The ability bonus was a buff, not a base-score change.** An
   `EffectAbilityIncrease` renders green with a buff icon and **counts against
   the server's maximum enchantment ability bonus**, so a character already at
   the gear cap gained nothing at all from the feat. Hence `LEGFEAT_KIND_RAW`.
4. **The picker was cramped** — an unsized list group with an unconstrained
   description label sized itself to the description text, so it occupied a
   fraction of the window, grew a horizontal scrollbar and clipped the header to
   "You may choose 2 leg". Every child now has an explicit width, the group has
   an explicit size, and it scrolls vertically only.

The level-up half of the "never on the engine's feat page" check passed on
2026-08-01: with the hak and TLK live, a level-up offered no legendary feat.

**Round 2 — `sqlite error: not prepared` on every level-up, and no picker.** A
missing schema migration, not the layout work and not the DB wipe it was blamed
on. `class_sig` was added to `legfeat_alloc` after the first build, and
`CREATE TABLE IF NOT EXISTS` does not add a column to a table that already
exists, so every statement naming it failed to **prepare** — no allotment
written, picker never opened. `LegFeat_InitDb` now `ALTER`s it behind a
`pragma_table_info` guard, the `bst_db.nss` idiom. **Relying on a DB wipe to
carry a schema change was the mistake**; the schema self-heals now, and it should
stay that way — a live server cannot be wiped.

**Round 3 — Force Rest did nothing, silently.** The re-entry hung off
`REST_EVENTTYPE_REST_FINISHED`, which no player reaches: the module cancels the
engine's own rest at `REST_STARTED` to open the rest menu. The evidence was in a
screenshot from round 1 — "Resting. / Cancelled Rest." in the combat log — and
was read past. See the re-entry bullet under phase 3. **Anything else that ever
wants to happen "on rest" in this module belongs on the Force Rest actions, not
the rest event.**

Also added during these rounds, neither in the original plan:

- **The admin reset tool** (`legfeat_reset.nss`, rest menu → `[Admin Options]`).
  A feat added by NWNX lives in the `.bic` and nothing else in game removes one,
  so testing the pool was otherwise a one-way trip. `README.md` "Resetting a
  character's legendary feats".
- **The player re-pick** (see above). Requested mid-UAT so players can follow a
  growing feat pool and changing gear without rerolling to 60.

### Phase 5+ — content, one category per release

**Triage: done, 2026-08-01.**
[CLAUDE-legendary-feats-triage.md](CLAUDE-legendary-feats-triage.md) is the
output — per-feat routes (RAW / EFF / HOOK / SPELL / CUT), the duplicates
resolved, and where the pool actually lands (133 distinct feats, ~119 after
cuts, 34 of them one effect each). It also **revises the order below**: take
**Defensive next, not Arcane** — thirteen of its sixteen feats are a single
permanent effect, which is the cheapest breadth available while the pool has
eight feats in it.

**Built from martial so far (unpublished):** *Legendary Prowess* and
*Legendary Onslaught*,
the two feats in that section that are one effect each. The rest of the martial
list needs a combat hook, a spell script, or is engine-owned and cut — the
triage says which for each.


**Adding a feat, mechanically:** append an entry to `FEATS` in
`bin/gen-legendary-feats.py` (append-only — a row index is a feat id baked into
save games, and the strings sit at fixed TLK indices), run
`python3 bin/gen-legendary-feats.py --apply`, write the behaviour, then publish
per the sequence at the bottom of this document. The generator updates the 2DA
rows, the TLK strings and `unpacked/legfeat_ids_inc.nss` together; the gate
fails the repack if any of the three drifts.

Set `kind="raw_ability"` only for base-score feats. Everything else is
`"effect"`, which means `LegFeat_ApplyOne` needs a branch for whatever that feat
does and `LegFeat_ApplyAll` will rebuild it at login.

Start with a **single triage pass over the whole draft**, classifying every feat
as: plain effect / item property / spell-script branch / needs NWNX / cut. Also
dedupe — *Legendary Shadow Step* appears in both Ki and Exotic with different
prereqs, and the four Bard hybrid feats are duplicated verbatim in Performance &
Support. Then, easiest mechanics first:

1. `ll-feats-ability-martial` (23 martial)
2. `ll-feats-defense` (16)
3. `ll-feats-ki-perform-skill` (16) + `ll-feats-exotic` (2)
4. `ll-feats-arcane-divine` (32) — settle the caster-level-scaling-vs-feat
   balance question first
5. `ll-feats-hybrid-pure` — hybrid caster feats plus the 11 auto-granted
   pure-class packages, which largely restate feats already in the pick lists
   and need an overlap triage
6. `ll-feats-spell-upgrades` (41 across six sub-sections) — the biggest lift,
   spell-script work per upgrade; check against `unpacked/summon_boost.nss` so
   summon upgrades don't stack into nonsense
7. `ll-feats-dominion` — capstone tier, and **six of its cantrips do not exist
   as spells**, so they'd have to be authored first

## Publish sequence

Same as any hak change, plus the TLK:

```
python3 bin/gen-legendary-feats.py --apply   # when feat rows change
bin/build-lotr-tlk --apply --install         # feat names/descriptions live here
bin/build-lotr-rules-hak --install
bin/refresh-nwsync
nwn-manager repack                           # required whenever unpacked/ changed
bin/server-restart
```

A script-only change (anything under `unpacked/`) needs the repack and restart
but not the hak or TLK steps. `legfeat_ids_inc.nss` is generated into
`unpacked/`, so a feat-table edit touches both halves.

**Run the feat generator before the TLK builder** — the TLK block ends with the
feat strings, so a name change has to reach `FEATS` first. Publish the hak and
the TLK **together**: the rows point at strrefs that exist only in ours, so a
client with one and not the other reads blank feat names.

Clients holding a stale hak or TLK read the old tables. A `.mod` repack is
required for the TLK swap and for any script change; a hak-only edit is not.

## Never

- **Never implement a legendary feat without the admin's explicit approval of
  that feat** — name, effect, numbers and prerequisites, feat by feat. The
  triage document and the `ll-feats-*` backlog read like a settled plan; they are
  unreviewed proposals. `FEATS` is append-only and a feat's row index is its id
  in every save game the moment someone takes it, so a wrong name or number
  cannot be withdrawn cleanly. Building the machinery unprompted is fine;
  building the content is not.
- Never hand-edit `hak_2da/feat.2da` or `tlk/lotr.tlk` — edit the generator's
  table and re-run it, exactly as with `bin/gen-caster-slots.py`.
- Never re-extract `feat.2da` from the game data over the generated file; that
  silently drops every legendary row.
- Never build on `hak_2da/feat.2da` (the unloaded CEP `cep2_add_feats` copy).
- Never renumber or reorder existing `cep.tlk` entries in `lotr.tlk`.
- Never let a legendary feat become selectable on the engine's level-up page.
