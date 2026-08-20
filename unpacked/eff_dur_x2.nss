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
// A LINKED effect is re-applied AS A LINK. Its components all share one id and
// RemoveEffectById takes every one of them, so the copy has to be rebuilt from all of
// them, not from the first one that matched. Getting this wrong destroys N-1 of N
// components silently -- see the long comment in X2Dur_ReTime.
//
// Stacks with the Extend metamagic (Extended buffs become 4x base) -- intended.
//
// Debug: set the module local int "x2dur_debug" to log one line per doubling.
//
// DEFERRED, and that is the whole point of the second half of this script.
// This subscriber fires INSIDE the caller's VM frame, and NWN charges a nested
// execution's instructions to the parent. Curse Song walks a colossal sphere
// applying a 7-component linked debuff per hostile (x2_s2_cursesong.nss), so the
// inline version cost targets x components x the true-effect scan below, all on
// one budget -- the reported "X2_S2_CurseSong / eff_dur_x2 TOO MANY INSTRUCTIONS"
// pair (roadmap curse-song-too-many-instructions). The same overrun is what got
// devcrit_eff deleted; see the note in onmoduleload.nss. So main() does only the
// cheap event-data guards and hands the scan + remove + reapply to
// X2Dur_ReTime() on a DelayCommand, which runs as its own script situation with
// its own fresh instruction budget. Same discipline as bpool_eff.nss.
//
// Deferring is safe because the effect is identified by its UNIQUE_ID, not by a
// handle: if it is gone by the time the deferred pass runs (dispelled, target
// died, target left), no true-effect matches the id and the pass is a no-op.

#include "nwnx_events"
#include "nwnx_effect"

// Backstop. A target carrying more true-effects than this is pathological; the
// scan is skipped rather than allowed to become the next budget overrun. Logged
// under x2dur_debug so it is visible if it ever trips.
const int X2DUR_MAX_SCAN = 250;

// The scan + remove + reapply, run on its own instruction budget. sUID is the
// UNIQUE_ID of the effect that fired the event; fDur its original duration.
void X2Dur_ReTime(object oTarget, string sUID, float fDur, object oCreator, string sSpellId)
{
    if (!GetIsObjectValid(oTarget))
        return;

    int nDebug = GetLocalInt(GetModule(), "x2dur_debug");
    int nCount = NWNX_Effect_GetTrueEffectCount(oTarget);

    if (nCount > X2DUR_MAX_SCAN)
    {
        if (nDebug)
            WriteTimestampedLogEntry("[x2dur] SKIPPED target=" + GetName(oTarget) +
                " trueEffects=" + IntToString(nCount) + " over X2DUR_MAX_SCAN");
        return;
    }

    // ONE pass that COLLECTS THE WHOLE LINK. This is the part that has to be right.
    //
    // A LINKED effect surfaces as several true-effects that ALL SHARE ONE id, and
    // RemoveEffectById removes every one of them. This script used to re-apply only the
    // FIRST matching component, so a link went in with N components and came back with
    // 1 -- the other N-1 were destroyed outright. That is what broke Curse Song down to
    // nothing but its attack decrease, Bard Song down to the ledger's attack and damage,
    // and Taunt and Wounding Whispers to nothing at all (reported by -Methonash- and
    // Sync). It also predates all of that: it is the same corruption behind roadmap
    // improved-invis-issues-part2, and the spell-id exclusions in main() are patches
    // over it. It only stopped being invisible when the work moved off the caller's
    // instruction budget -- before that the script was being KILLED by TOO MANY
    // INSTRUCTIONS on exactly these paths, and dying before the remove+re-apply was the
    // only thing keeping the link whole.
    //
    // Note NWNX_Effect_GetTrueEffect resolves with __NWNX_Effect_ResolveUnpack(FALSE),
    // i.e. bLink = FALSE, so each component comes back with its link fields cleared and
    // PackEffect gives a single UNLINKED effect. The link cannot be recovered from one
    // component -- it has to be rebuilt from all of them, which is what this does:
    // collect every component sharing the id and EffectLinkEffects them back together in
    // index order (which is application order, so the rebuilt link keeps the original
    // component order).
    //
    // The pass doubles as the link-sensitive guard (improved invisibility, invisibility,
    // concealment, sanctuary, etherealness), which relies on the ENGINE's own link and
    // must never be rebuilt by us. Bailing part-way through the collect costs nothing
    // because nothing is applied until after the loop. Use GetEffectType (script
    // EFFECT_TYPE_* constants), NOT e.nType (raw engine enum).
    // See docs.manual/Customizations.html#spell-duration.
    effect eAll;
    int bHave  = FALSE;
    int nParts = 0;
    int i;

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

        // Faithful per-component copy. nSubType (extraordinary/supernatural), nSpellId
        // and the creator all ride along in the unpacked struct, so ExtraordinaryEffect
        // status, dispel attribution and the GetHasSpellEffect(GetSpellId(), ...)
        // "already sung on" guards keep working on the rebuilt link.
        e.fDuration = fDur * 2.0;                    // cosmetic; the apply param rules
        effect eComponent = NWNX_Effect_PackEffect(e);

        if (!bHave)
        {
            eAll  = eComponent;
            bHave = TRUE;
        }
        else
        {
            eAll = EffectLinkEffects(eAll, eComponent);
        }
        nParts++;
    }

    if (!bHave)
        return;     // effect already gone -- see the header note on deferral

    // The busy flag has to be set HERE, around the synchronous apply, not around the
    // DelayCommand that scheduled us -- our own re-applied copy fires the event again
    // on this very stack, and main() must see the flag set when it does.
    SetLocalInt(oTarget, "x2dur_busy", TRUE);
    NWNX_Effect_RemoveEffectById(oTarget, sUID);
    ApplyEffectToObject(DURATION_TYPE_TEMPORARY, eAll, oTarget, fDur * 2.0);
    DeleteLocalInt(oTarget, "x2dur_busy");

    if (nDebug)
        WriteTimestampedLogEntry("[x2dur] target=" + GetName(oTarget) +
            " creator=" + GetName(oCreator) +
            " spellId=" + sSpellId +
            " parts=" + IntToString(nParts) +
            " dur=" + FloatToString(fDur, 0, 1) +
            " -> " + FloatToString(fDur * 2.0, 0, 1));
}

void main()
{
    object oTarget = OBJECT_SELF;

    // Our own re-applied copy fires this event again; never double it twice.
    // X2Dur_ReTime sets this flag across its apply, and that apply is synchronous,
    // so the flag is set while the nested event runs.
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
    string sSpellId = NWNX_Events_GetEventData("SPELL_ID");
    int nSpellId = StringToInt(sSpellId);
    if (nSpellId == SPELL_DIVINE_MIGHT || nSpellId == SPELL_DIVINE_SHIELD)
        return;

    // The invisibility/illusion family is also applied as LINKED effects (see the
    // effect-type guard in X2Dur_ReTime). The type guard alone is NOT enough:
    // Improved Invisibility links its EffectInvisibility with a duration visual, and
    // the linked components share the same effect id, so a "inspect the first matching
    // component" check can land on the non-excluded visual, bypass the guard, strip the
    // whole link via RemoveEffectById, and reapply only one component -- exactly the
    // corruption reported in roadmap item improved-invis-issues-part2. Exclude the whole
    // spell by id up front (the same approach that fixed Divine Might/Shield), which also
    // covers item-cast sources (potions/wands/scrolls) since they carry the spell id.
    // Direct script-applied invis with no spell id is still caught by the effect-type
    // guard in X2Dur_ReTime.
    if (nSpellId == SPELL_IMPROVED_INVISIBILITY ||
        nSpellId == SPELL_INVISIBILITY ||
        nSpellId == SPELL_INVISIBILITY_SPHERE ||
        nSpellId == SPELL_SANCTUARY ||
        nSpellId == SPELL_ETHEREAL_VISAGE ||
        nSpellId == SPELL_ETHEREALNESS)
        return;

    // UNIQUE_ID and the unpacked sID are both std::to_string(m_nID), so this identifies
    // the exact effect that just fired, and survives the hand-off below.
    string sUID = NWNX_Events_GetEventData("UNIQUE_ID");

    // Everything expensive happens off this frame. See the header.
    DelayCommand(0.0, X2Dur_ReTime(oTarget, sUID, fDur, oCreator, sSpellId));
}
