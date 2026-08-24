#!/usr/bin/env python3
"""Build gate: every module-owned attack/damage bonus goes through the ledger.

Same-type attack-bonus effects do not stack in NWN - the engine applies the
HIGHEST and discards the rest - so a bonus applied outside
unpacked/bonus_pool_inc.nss does not merely fail to stack: it SUPPRESSES every
pooled bonus smaller than itself, for as long as it lasts. That is how Legendary
Prowess's permanent +5 silently swallowed Bard Song and the whole attack half of
Legendary Grip (roadmap: bard-legendary-prowess-conflict).

The failure mode is why this is a gate and not a review note. A new
EffectAttackIncrease compiles, runs, looks correct in isolation, and breaks
something in a different file that nobody is testing at the time.

  1. No module-owned script applies EffectAttackIncrease / EffectDamageIncrease
     directly. The ledger is the only place, plus the exemptions below, each of
     which has to state its reason here.
  2. The ledger's damage channel converts through BPool_DamageConst.
     EffectDamageIncrease takes a DAMAGE_BONUS_* CONSTANT, not a flat int - raw
     7 is 1d6 and raw 10 is 2d6 - so a flat int there silently turns a promised
     bonus into dice. This is exactly what was wrong with Legendary Reaping's
     4th and 5th stacks before they were pooled.
  3. Every source key constant appears in the BPool_SourceAt walk, and the count
     matches BPOOL_SRC_COUNT. A key that is stored but never walked is a bonus
     that is recorded and never applied - invisible from the game.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
UNPACKED = ROOT / "unpacked"
POOL = "bonus_pool_inc.nss"

# Scripts allowed to apply an attack/damage bonus directly, each with the reason.
# Adding a name here is a deliberate decision to sit outside the ledger; it is
# not a way to silence the gate.
EXEMPT = {
    # Stock/CEP library code the module ships but does not own. Rewriting these
    # would fork half of BioWare's spell set for no gain: they are cast by NPCs
    # and by players from stock spells, and they collide with the pool the same
    # way any stock Bless does - accepted, and documented in impl_notes.
    "x2_inc_itemprop.nss": "stock CEP library: the DAMAGE_BONUS_* mapping itself",
    "nw_i0_generic.nss": "stock BioWare AI library",
    "x2_i0_spells.nss": "stock BioWare spell library",
    "x0_i0_spells.nss": "stock BioWare spell library",
    # Shayan's Subrace Engine applies its per-subrace attack modifier as a
    # SLOT-typed pair (ATTACK_BONUS_ONHAND + ATTACK_BONUS_OFFHAND) and mirrors
    # it with EffectAttackDecrease for negative subraces. The ledger models a
    # single flat MISC bonus and no decreases, so pooling this would change what
    # the third-party engine does, not just where it does it.
    "sha_subr_methds.nss": "third-party subrace engine: slot-typed bonuses and "
                           "symmetric decreases the flat ledger does not model",
    # Unreferenced alternate bard song implementation - nothing executes it (the
    # only mention in the tree is a comment in nw_s2_bardsong). Left in place as
    # found; pooling dead code would just be noise.
    "nifty_i0_bard.nss": "dead code: no caller anywhere in unpacked/",
    "sas_include.nss": "third-party library; its bonuses are DICE (Random/1d6), "
                       "which cannot be summed into a flat ledger total",
    # Tenser's Transformation links its attack bonus to EffectPolymorph so the
    # two live and die together. Pooled, the bonus would outlive a polymorph
    # that ended early (dispel, death, shape change) because the ledger's timer
    # would still be running. Left alone deliberately.
    "nw_s0_tenstrans.nss": "attack bonus is linked to EffectPolymorph and must "
                           "end exactly when the form does",
}

# Scripts allowed to apply a DAMAGE bonus directly but NOT an attack bonus: the
# seven stock buff spells forked into the module for spell-ab-prowess-stack.
# Their attack halves are pooled; their damage halves deliberately are not.
# Damage-bonus effects of DIFFERENT damage types already stack in the engine, so
# there is no defect to fix on that channel, and pooling would flatten this
# spell's slashing/magical/divine into the pool's bludgeoning and change what
# damage reduction eats.
DAMAGE_ONLY_REASON = ("forked buff spell: attack half is pooled, damage half "
                      "stays engine-typed to keep its damage type")
EXEMPT_DAMAGE = {
    "nw_s0_prayer.nss": DAMAGE_ONLY_REASON,
    "nw_s0_warcry.nss": DAMAGE_ONLY_REASON,
    "x0_s0_divfav.nss": DAMAGE_ONLY_REASON,
    "x2_s2_divwrath.nss": DAMAGE_ONLY_REASON,
}

# The forked buff spells, and the ledger source key each one must register
# under. A fork that stops registering is a spell whose attack bonus silently
# disappears altogether - strictly worse than the bug this fixed.
POOLED_SPELLS = {
    "nw_s0_bless.nss": "BPOOL_SRC_BLESS",
    "nw_s0_aid.nss": "BPOOL_SRC_AID",
    "nw_s0_prayer.nss": "BPOOL_SRC_PRAYER",
    "nw_s0_warcry.nss": "BPOOL_SRC_WARCRY",
    "x0_s0_divfav.nss": "BPOOL_SRC_DIVFAV",
    "nw_s0_divpower.nss": "BPOOL_SRC_DIVPOW",
    "x2_s2_divwrath.nss": "BPOOL_SRC_DIVWRA",
}

APPLY_RE = re.compile(r"^[^/\n]*\b(EffectAttackIncrease|EffectDamageIncrease)\s*\(",
                      re.M)

errors = []


def read(path):
    try:
        return path.read_text(encoding="latin-1")
    except OSError as exc:
        errors.append(f"cannot read {path}: {exc}")
        return ""


# --- 1. nothing applies a bonus outside the ledger --------------------------
for path in sorted(UNPACKED.glob("*.nss")):
    if path.name == POOL or path.name in EXEMPT:
        continue
    hits = APPLY_RE.findall(read(path))
    if path.name in EXEMPT_DAMAGE:
        hits = [h for h in hits if h != "EffectDamageIncrease"]
    if hits:
        errors.append(
            f"{path.name} calls {'/'.join(sorted(set(hits)))} directly. Register "
            f"the amount with BPool_Set(...) instead - an unpooled bonus "
            f"suppresses every pooled bonus smaller than itself. If it genuinely "
            f"cannot be pooled, add it to EXEMPT in this file with the reason.")

# --- 2. the ledger converts damage through the constant mapping -------------
pool = read(UNPACKED / POOL)

if not re.search(r"EffectDamageIncrease\s*\(\s*nConst\s*,", pool):
    errors.append(
        f"{POOL}: the damage channel must pass a DAMAGE_BONUS_* constant from "
        f"BPool_DamageConst, not a flat int. A flat int turns the pooled total "
        f"into dice (7 = 1d6, 10 = 2d6).")

if "BPool_DamageConst(nTotal)" not in pool:
    errors.append(
        f"{POOL}: BPool_Rebuild no longer converts the total through "
        f"BPool_DamageConst.")

if "DAMAGE_BONUS_20" not in pool:
    errors.append(
        f"{POOL}: the DAMAGE_BONUS_20 clamp is gone. The engine cannot express a "
        f"flat damage bonus above +20 and the mapping must not fall through.")

# --- 3. every source key is walked by the rebuild ---------------------------
keys = re.findall(r"^const string (BPOOL_SRC_\w+)\s*=", pool, re.M)
walk = re.search(r"string BPool_SourceAt\(int nIndex\)\s*\{(.*?)\n\}", pool, re.S)
walked = set(re.findall(r"return (BPOOL_SRC_\w+);", walk.group(1))) if walk else set()

for key in keys:
    if key not in walked:
        errors.append(
            f"{POOL}: {key} is declared but never returned by BPool_SourceAt, so "
            f"BPool_Total never adds it - the bonus would be stored and never "
            f"applied.")

count = re.search(r"^const int\s+BPOOL_SRC_COUNT\s*=\s*(\d+)", pool, re.M)
if not count:
    errors.append(f"{POOL}: BPOOL_SRC_COUNT is missing.")
elif int(count.group(1)) != len(keys):
    errors.append(
        f"{POOL}: BPOOL_SRC_COUNT is {count.group(1)} but {len(keys)} source keys "
        f"are declared. BPool_Total loops to the count, so a low value silently "
        f"drops the last source(s) from every total.")

# --- 3c. every pooled buff spell registers, and can be seen to end -----------
# A pooled spell needs BOTH halves: the registration (or its bonus is gone
# altogether, which is worse than the bug) and a witness spell id (or the entry
# can only be ended by its backstop timer, stranding the bonus after a dispel,
# a death or an early end).
witness_walk = re.search(r"int BPool_WitnessAt\(int nIndex\)\s*\{(.*?)\n\}", pool, re.S)
witnessed = witness_walk.group(1) if witness_walk else ""

for name, key in sorted(POOLED_SPELLS.items()):
    src = UNPACKED / name
    if not src.is_file():
        errors.append(
            f"unpacked/{name} is missing. It is the module's fork of a stock "
            f"buff spell; without it the game falls back to the stock script "
            f"and the spell's attack bonus is invisible behind Legendary "
            f"Prowess again.")
        continue
    body = read(src)
    if f"BPool_SpellAttack(" not in body or key not in body:
        errors.append(
            f"{name} no longer registers its attack bonus with "
            f"BPool_SpellAttack(..., {key}, ...). The fork removed the bonus "
            f"from the effect link, so a fork that does not register grants "
            f"NOTHING.")
    if key not in pool:
        errors.append(f"{POOL}: {key} is gone but {name} still registers it.")

src_index = {k: int(n) for n, k in
             re.findall(r"case (\d+):\s*return (BPOOL_SRC_\w+);",
                        walk.group(1) if walk else "")}
for key in re.findall(r"^const string (BPOOL_SRC_\w+)", pool, re.M):
    if key in POOLED_SPELLS.values():
        idx = src_index.get(key)
        if idx is not None and f"case {idx}:" not in witnessed:
            errors.append(
                f"{POOL}: {key} (source index {idx}) has no witness spell id in "
                f"BPool_WitnessAt. A buff spell's entry must end when the "
                f"spell's own effect does - the backstop timer is 3x the "
                f"duration and is not a clock.")

# --- 3d. the pooled effect is rendered OUT of any spell context ---------------
# An effect is stamped with the spell id of the script that creates it, and the
# registrants are spell/feat scripts: Bard Song (411) calls BardSong_Pool
# mid-song, War Cry (373) calls BPool_SpellAttack mid-cast. Rendered inline, the
# ledger's PERMANENT effect wears that spell's identity, and then it satisfies
# the ledger's own witness (GetHasSpellEffect(411) is true forever), satisfies
# the song's "already sung on" guard, and is swept by the RemoveSpellEffects()
# at the top of nw_s0_warcry - which would strip every source's bonus at once.
# Deferring the apply gives it a script situation with no spell context.
if not re.search(r"DelayCommand\s*\(\s*0\.0\s*,\s*BPool_Render\s*\(", pool):
    errors.append(
        f"{POOL}: BPool_Rebuild must render through DelayCommand(0.0, "
        f"BPool_Render(...)). Applied inline it inherits the calling spell's id, "
        f"which makes the pooled effect its own witness and puts it in reach of "
        f"RemoveSpellEffects(GetSpellId(), ...) in the spell forks.")
elif "ApplyEffectToObject" not in (
        re.split(r"\nvoid\s+\w+", pool.split("void BPool_Render", 1)[-1])[0]):
    errors.append(
        f"{POOL}: BPool_Render does not apply the effect - the deferred render is "
        f"where the pooled bonus actually reaches the creature.")

# --- 4. the ledger recalculates when a bonus ENDS, not only when one starts ---
# Without this wiring the ledger is write-only: a song that ended early leaves
# its bonus behind, and a respawn's RemoveEffects takes the permanent feat
# bonuses away with nothing to put them back. Both were found in UAT.
modload = read(UNPACKED / "onmoduleload.nss")
if not re.search(r"NWNX_Events_SubscribeEvent\(\s*NWNX_ON_EFFECT_REMOVED_AFTER\s*,"
                 r'\s*"bpool_eff"\s*\)', modload):
    errors.append(
        "onmoduleload.nss does not subscribe bpool_eff to "
        "NWNX_ON_EFFECT_REMOVED_AFTER - the ledger would never notice a bonus "
        "ending, so an ended bard song keeps its attack bonus.")

if not (UNPACKED / "bpool_eff.nss").is_file():
    errors.append("unpacked/bpool_eff.nss is missing.")
else:
    handler = read(UNPACKED / "bpool_eff.nss")
    # The recursion guard is the one that actually binds: a rebuild strips our
    # own effect, which fires this same event.
    if "BPOOL_BUSY" not in handler:
        errors.append(
            "bpool_eff.nss dropped the BPOOL_BUSY guard. Rebuilding the ledger "
            "strips our own effect and fires this event - without the guard "
            "every rebuild schedules another one, forever.")
    if "x2dur_busy" not in handler:
        errors.append(
            "bpool_eff.nss dropped the x2dur_busy guard. The duration doubler "
            "re-times a buff by removing it and re-applying it on the same "
            "stack; revalidating off the remove half reads the witness in the "
            "one instant it is deliberately absent and drops a live bonus "
            "(roadmap bard-song-issues-round-2).")
    if "BPOOL_LIVE" not in handler:
        errors.append(
            "bpool_eff.nss dropped the BPOOL_LIVE guard. This runs for every "
            "effect removal on the server; the guard is what keeps it free for "
            "creatures that carry no bonus.")

# The respawn itself moved out of mod_respawn.nss into respawn_inc.nss
# (LOTR_RespawnPC) so the petrification timeout could reuse it - roadmap
# petrification-respawn-defect-round-4. Round 5 took that second caller back out
# (pet_respawn.nss is deleted; the petrification timeout gives the player a
# working Respawn button instead of moving them), so mod_respawn.nss is once
# again the only caller. The wholesale RemoveEffects() stayed in respawn_inc.nss,
# so that is still the file this gate has to follow.
respawn_inc = read(UNPACKED / "respawn_inc.nss")

if "RemoveEffects" not in respawn_inc:
    errors.append(
        "respawn_inc.nss no longer calls RemoveEffects() - the respawn "
        "implementation has moved again. Point the two checks below at "
        "whichever file now strips a respawning character's effects, or they "
        "are guarding nothing.")

if "BPool_ClearTransient" not in respawn_inc:
    errors.append(
        "respawn_inc.nss no longer clears transient ledger entries. Its "
        "RemoveEffects() strips the song's witness effect, so without this the "
        "song's bonus would be re-rendered onto a character who no longer has "
        "the song.")

if "LegFeat_ApplyAll" not in respawn_inc:
    errors.append(
        "respawn_inc.nss no longer re-applies legendary feats after its "
        "wholesale RemoveEffects() - respawning silently strips every "
        "EFFECT-kind legendary feat until the character's next login.")

for caller in ("mod_respawn.nss",):
    if "LOTR_RespawnPC" not in read(UNPACKED / caller):
        errors.append(
            f"{caller} no longer calls LOTR_RespawnPC(). Every respawn has to "
            "go through the one implementation in respawn_inc.nss - a "
            "hand-rolled second copy is how the legendary-feat strip came back.")

if errors:
    print("check_bonus_pool: FAILED", file=sys.stderr)
    for e in errors:
        print(f"  - {e}", file=sys.stderr)
    sys.exit(1)

print(f"check_bonus_pool: ok ({len(keys)} pooled sources, "
      f"{len(EXEMPT)} documented exemption(s))")
sys.exit(0)
