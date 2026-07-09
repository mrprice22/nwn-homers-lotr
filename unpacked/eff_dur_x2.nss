// eff_dur_x2 -- Double the duration of every temporary effect a player (or a
// player-mastered associate) creates.
//
// Subscribed to NWNX_ON_EFFECT_APPLIED_AFTER in onmoduleload.nss. Fires once for
// every Temporary or Permanent effect applied to any object server-wide (visual
// effects and item properties do not fire this event). OBJECT_SELF is the effect
// target.
//
// Scope: effects whose CREATOR is a PC, OR a creature whose master is a PC -- so
// buffs a PC casts, potions they drink, debuffs they inflict, AND buffs cast by
// their Meaningwave henchmen / summons / familiars all last twice as long. Ordinary
// monsters have no master, so hostile NPC effects are left alone.
//
// Re-timing: an effect's real end-time is its expiry fields, NOT m_fDuration, and
// NWNX_Effect_ReplaceEffect* copy the expiry verbatim (they do not recompute it from
// duration). So we instead REMOVE the just-applied effect and RE-APPLY a faithful
// copy with double the seconds -- ApplyEffectToObject derives a fresh, doubled expiry
// from the duration parameter. The copy keeps the original creator (PackEffect bakes
// m_oidCreator), so dispel/attribution are preserved.
//
// Stacks with the Extend metamagic (Extended buffs become 4x base) -- intended.
//
// Debug: set the module local int "x2dur_debug" to log one line per doubling.

#include "nwnx_events"
#include "nwnx_effect"

void main()
{
    object oTarget = OBJECT_SELF;

    // Our own re-applied copy fires this event again; never double it twice.
    // ApplyEffectToObject applies synchronously, so this flag is set while the
    // nested event runs.
    if (GetLocalInt(oTarget, "x2dur_busy"))
        return;

    // Only timed effects have a duration to extend.
    if (StringToInt(NWNX_Events_GetEventData("DURATION_TYPE")) != DURATION_TYPE_TEMPORARY)
        return;

    // Scope: created by a PC, or by a PC-mastered associate (henchman/summon/familiar).
    object oCreator = StringToObject(NWNX_Events_GetEventData("CREATOR"));
    if (!GetIsPC(oCreator) && !GetIsPC(GetMaster(oCreator)))
        return;

    float fDur = StringToFloat(NWNX_Events_GetEventData("DURATION"));
    if (fDur <= 0.0)
        return;

    // Divine Might / Divine Shield build their buff as EffectLinkEffects (attack+damage,
    // AC+visual) just like the invisibility family below -- remove+reapply splits the
    // link, so the mechanical bonus can revert to its natural duration while whatever
    // GetHasFeatEffect() reads to block re-casting stays doubled. Confirmed by
    // disassembling the vanilla x0_s2_divmight/x0_s2_divshield scripts. Leave both at
    // natural duration rather than risk the same corruption.
    int nSpellId = StringToInt(NWNX_Events_GetEventData("SPELL_ID"));
    if (nSpellId == SPELL_DIVINE_MIGHT || nSpellId == SPELL_DIVINE_SHIELD)
        return;

    // The invisibility/illusion family is also applied as LINKED effects (see the
    // effect-type guard in the loop below). The type guard alone is NOT enough:
    // Improved Invisibility links its EffectInvisibility with a duration visual, and
    // the linked components share the same effect id, so the loop's "inspect the first
    // matching component" check can land on the non-excluded visual, bypass the guard,
    // strip the whole link via RemoveEffectById, and reapply only one component --
    // exactly the corruption reported in roadmap item improved-invis-issues-part2.
    // Exclude the whole spell by id up front (the same approach that fixed Divine
    // Might/Shield), which also covers item-cast sources (potions/wands/scrolls) since
    // they carry the spell id. Direct script-applied invis with no spell id is still
    // caught by the effect-type guard below.
    if (nSpellId == SPELL_IMPROVED_INVISIBILITY ||
        nSpellId == SPELL_INVISIBILITY ||
        nSpellId == SPELL_INVISIBILITY_SPHERE ||
        nSpellId == SPELL_SANCTUARY ||
        nSpellId == SPELL_ETHEREAL_VISAGE ||
        nSpellId == SPELL_ETHEREALNESS)
        return;

    string sUID = NWNX_Events_GetEventData("UNIQUE_ID");

    // UNIQUE_ID and the unpacked sID are both std::to_string(m_nID), so this matches
    // the exact effect that just fired.
    int nCount = NWNX_Effect_GetTrueEffectCount(oTarget);
    int i;

    // Guard pass: a LINKED effect surfaces as several true-effects that all share the
    // same id. Link-sensitive effects (improved invisibility, invisibility, concealment,
    // sanctuary, etherealness) rely on the engine link staying intact -- our
    // remove+reapply would split it and corrupt it (e.g. attacking would strip the
    // concealment instead of just dropping invisibility). So scan EVERY component that
    // shares this id and bail if ANY of them is link-sensitive -- inspecting only the
    // first matching component is not enough, since the excluded component may not be
    // the one the loop hits first. Use GetEffectType (script EFFECT_TYPE_* constants),
    // NOT e.nType (raw engine enum). See docs.manual/Customizations.html#spell-duration.
    for (i = 0; i < nCount; i++)
    {
        struct NWNX_EffectUnpacked e = NWNX_Effect_GetTrueEffect(oTarget, i);
        if (e.sID != sUID)
            continue;

        int nFx = GetEffectType(NWNX_Effect_PackEffect(e));
        if (nFx == EFFECT_TYPE_INVISIBILITY ||
            nFx == EFFECT_TYPE_IMPROVEDINVISIBILITY ||
            nFx == EFFECT_TYPE_CONCEALMENT ||
            nFx == EFFECT_TYPE_SANCTUARY ||
            nFx == EFFECT_TYPE_ETHEREAL)
            return;
    }

    // Apply pass: re-time the matching effect.
    for (i = 0; i < nCount; i++)
    {
        struct NWNX_EffectUnpacked e = NWNX_Effect_GetTrueEffect(oTarget, i);
        if (e.sID != sUID)
            continue;

        e.fDuration = fDur * 2.0;                 // cosmetic; the apply param below rules
        effect eNew = NWNX_Effect_PackEffect(e);  // faithful copy, keeps creator

        SetLocalInt(oTarget, "x2dur_busy", TRUE);
        NWNX_Effect_RemoveEffectById(oTarget, sUID);
        ApplyEffectToObject(DURATION_TYPE_TEMPORARY, eNew, oTarget, fDur * 2.0);
        DeleteLocalInt(oTarget, "x2dur_busy");

        if (GetLocalInt(GetModule(), "x2dur_debug"))
            WriteTimestampedLogEntry("[x2dur] target=" + GetName(oTarget) +
                " creator=" + GetName(oCreator) +
                " spellId=" + NWNX_Events_GetEventData("SPELL_ID") +
                " dur=" + FloatToString(fDur, 0, 1) +
                " -> " + FloatToString(fDur * 2.0, 0, 1));

        break;
    }
}
