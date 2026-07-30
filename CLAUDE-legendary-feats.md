# Legendary Feats — architecture and build order

Feats selectable only at character level 60, the second half of the
`legendary-levels` epic (levels 41–60 themselves already shipped — see
`README.md` "Levels 41–60").

Design draft: `docs.manual/Draft/LegendaryFeats.html` (~139 feats + 18 dominion
cantrip toggles + 11 pure-class packages). The draft is a **wish list, not a
spec** — expect a triage pass, not a transcription.

**Status: not started.** Nothing in this document exists yet. It records the
architecture and the order the pieces must be built in, so the sequencing does
not have to be re-derived. Roadmap items: `ll-feats-tlk`, `ll-feats-2da`,
`ll-feats-picker`, then the seven `ll-feats-*` category stories.

## The core idea: feats are inert tokens

A legendary feat row in `feat.2da` carries **name, description and icon only**.
It has no engine mechanic. Every effect is applied server-side by script:

| Effect shape | How |
|---|---|
| Ability score bonus | Item property on the PC's skin (the `npcbuffgear` pattern) |
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

- `bin/build-lotr-tlk` (new) — house generator style: dry-run default,
  `--apply`, idempotent, owned string table at the top of the script, modelled
  on `bin/gen-caster-slots.py`. Uses `~/.nimble/bin/nwn_tlk` (present; same
  toolchain as the `nwn_erf` that `build-lotr-rules-hak` already uses) to
  convert `tlk/cep.tlk` → JSON, append our entries **strictly above CEP's last
  index**, write `tlk/lotr.tlk`.
- **`tlk/cep.tlk` holds 7213 entries (0–7212)**, so our block starts at custom
  index **7213** — i.e. strref `16777216 + 7213 = 16784429` as written into a
  2DA (custom-TLK strrefs are offset by `0x01000000`).
- **Invariant: every pre-existing CEP index keeps its value.** A one-entry shift
  silently repoints CEP-sourced names and descriptions across the entire module,
  and nothing else would catch it. `tests/check_lotr_tlk.py` (new) asserts
  `lotr.tlk[0..7212] == cep.tlk` and that our block matches the generator's
  table — **importing** the generator rather than re-transcribing the strings,
  the lesson `tests/check_epic_tables.py` already encodes in its docstring.
- `unpacked/module.ifo.json`: `Mod_CustomTlk` `"cep"` → `"lotr"`.
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
to the module and change the column count. Extract the real base with the
`nwn_resman_extract` recipe in `README.md` ("Rebuild from scratch").

- Our rows therefore append at **1116**.
- `bin/gen-legendary-feats.py` (new) owns rows 1116+; rows 0–1115 stay
  byte-identical and the gate asserts it. **One feat-definition table at the top
  of the script is the single source of truth** — it drives both the 2DA rows
  and the TLK strings that `bin/build-lotr-tlk` consumes, so a name exists once.
- Add `feat.2da` to `RULES_2DA` in `bin/build-lotr-rules-hak` **and** update
  that script's header comment, which says "ALL ELEVEN of" — the list and the
  prose are both load-bearing there.
- Gate: `tests/check_legendary_feats.py`, following
  `tests/check_epic_tables.py`'s import-the-generator idiom and its
  `read_2da()` helper.
- Payload for this phase: **only the six `#ability-scores` feats** (e.g.
  *Legendary Strength*, +6 STR). Simplest possible content, and it exercises the
  whole chain including the skin-item-property application path.

### Phase 3 — the picker NUI

- `legfeat_nui_*.nss` (open / event / include). Follow `pl_nui_evt.nss` (party
  loot roll) and `dye_nui_*` — the repo's two NUI precedents — and respect the
  two traps already recorded against them: the **16-character resref limit** and
  **no `&` reference parameters** in `nw_inc_nui`.
- **Trigger:** `NWNX_ON_LEVEL_UP_AFTER`, already subscribed in
  `unpacked/onmoduleload.nss`, firing the picker when `GetHitDice() == 60`.
- **Re-entry:** a rest-menu option (the `_restemo_*.nss` StartingConditional
  pattern) shown only while unspent picks remain, so a dismissed or
  half-finished picker is recoverable.
- **Allotment** computed from class levels per the table above; feats granted
  with `NWNX_Creature_AddFeat`.
- **Persistence:** campaign DB `legfeatdb`, keyed on `GetObjectUUID()`, holding
  picks granted and picks remaining. Shape it like `bestiarydb` / `meritdb`. A
  relog must not re-grant.
- **Re-apply effects at login.** The *feat* persists in the `.bic`; its
  *effects* do not. Every legendary feat a PC holds needs its effect or skin
  property re-applied on client enter. This is the piece most likely to be
  forgotten, and it fails silently — the character sheet just quietly stops
  showing the bonus.

### Phase 4 — end-to-end UAT

On level-60 test characters of each shape (pure Fighter, pure Wizard, mixed):
picker pops, allotment correct, pick applies, the bonus shows on the character
sheet, relog keeps it, rest reopens the picker while picks remain, and the
engine's own feat page never lists a legendary feat. **No category story starts
until this passes.**

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
bin/build-lotr-tlk --apply          # phase 1 only, when strings change
bin/gen-legendary-feats.py --apply  # when feat rows change
bin/build-lotr-rules-hak --install
bin/refresh-nwsync
nwn-manager repack                  # required whenever unpacked/ changed
bin/server-restart
```

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
