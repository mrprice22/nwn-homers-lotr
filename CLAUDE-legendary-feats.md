# Legendary Feats — architecture and build order

Feats selectable only at character level 60, the second half of the
`legendary-levels` epic (levels 41–60 themselves already shipped — see
`README.md` "Levels 41–60").

Design draft: `docs.manual/Draft/LegendaryFeats.html` (~139 feats + 18 dominion
cantrip toggles + 11 pure-class packages). The draft is a **wish list, not a
spec** — expect a triage pass, not a transcription.

**Status: phases 1-3 built; phase 1 UAT passed, phases 2-3 in UAT (first round
found four defects, all fixed — see phase 4).**
Phase 1 (`bin/build-lotr-tlk`, `tests/check_lotr_tlk.py`, the `Mod_CustomTlk`
swap) is verified in game. Phase 2 (`bin/gen-legendary-feats.py`, the stock-based
`hak_2da/feat.2da` with six proof rows, `tests/check_legendary_feats.py`, the hak
wiring) and phase 3 (the picker NUI, `legfeat_*.nss`, the level-60 trigger, the
rest-menu re-entry, `legfeatdb`, and the login re-apply) are built and gated but
not yet seen in game — phase 4 is that UAT. Content (phase 5+) has not started.

Phase 2's half of the level-up check is already done: on 2026-08-01, with the hak
and TLK live, a level-up offered no legendary feat on the engine's own feat page.

This document records the architecture and the order the pieces must be built in,
so the sequencing does not have to be re-derived. Roadmap items: `ll-feats-tlk`,
`ll-feats-2da`, `ll-feats-picker`, then the seven `ll-feats-*` category stories.

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
magic fallback. Picks are permanent.

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
  (*Legendary Strength* … *Charisma*, +6 each). Simplest possible content.
  **The effects are not applied yet** — the skin-item-property path is written in
  phase 3 alongside the picker that grants the feats and the login hook that
  re-applies them. Phase 2's rows are inert by design: taking one shows the name,
  description and icon and changes nothing.

### Phase 3 — the picker NUI

The files, and what each owns:

| File | Owns |
|---|---|
| `legfeat_ids_inc.nss` | **Generated** by `bin/gen-legendary-feats.py`. Feat ids, names, descriptions, and the ability/bonus each ability feat carries. No script hand-types a row number. |
| `legfeat_db.nss` | `legfeatdb` — `legfeat_alloc` (picks granted, per character) and `legfeat_pick` (one row per feat taken). Keyed on `GetObjectUUID()`. |
| `legfeat_inc.nss` | Allotment, `LegFeat_Take`, and the effects. |
| `legfeat_nui.nss` | The window. |
| `legfeat_evt.nss` | Its click handler (`NuiCreate`'s `sEventScript`). |
| `legfeat_open.nss` | The one entry point — re-derives the allotment, opens the window. |
| `legfeat_lvl.nss` | `NWNX_ON_LEVEL_UP_AFTER` **and** `_LEVEL_DOWN_AFTER` handler. |
| `legfeat_reset.nss` | Admin test tool — rest menu → `[Admin Options]`. Puts a character back to "never had a legendary feat"; a feat added by NWNX lives in the `.bic` and nothing else removes one. See `README.md` "Resetting a character's legendary feats". |

- **Trigger:** `NWNX_ON_LEVEL_UP_AFTER` → `legfeat_lvl`, subscribed in
  `onmoduleload.nss`, firing when `GetHitDice() >= 60`. It opens the picker on a
  **2-second delay**: at `_AFTER` the engine is still finishing the level-up with
  its own UI on screen, and a NUI window opened into that is one the player
  cannot interact with.
- **Re-entry:** finishing a rest reopens the picker while picks remain
  (`on_mod_rest.nss`, on `REST_EVENTTYPE_REST_FINISHED`, 2-second delay). Force
  Rest goes through the same event, since `ew_forcerest` calls `ForceRest`. This
  replaced a rest-menu conversation node, which UAT judged the wrong shape — the
  window should just come back. A login nudge covers characters that were already
  60 when the feature shipped.
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

### Phase 5+ — content, one category per release

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

- Never hand-edit `hak_2da/feat.2da` or `tlk/lotr.tlk` — edit the generator's
  table and re-run it, exactly as with `bin/gen-caster-slots.py`.
- Never re-extract `feat.2da` from the game data over the generated file; that
  silently drops every legendary row.
- Never build on `hak_2da/feat.2da` (the unloaded CEP `cep2_add_feats` copy).
- Never renumber or reorder existing `cep.tlk` entries in `lotr.tlk`.
- Never let a legendary feat become selectable on the engine's level-up page.
