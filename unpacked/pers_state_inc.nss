// pers_state_inc — fix the relog-heals-and-rests exploit.
//
// Snapshots the PC's current HP, remaining spell slots (per multiclass
// + spell level) and remaining uses on a fixed list of daily-use feats
// (including epic spells, which are feats in NWN). Restores the
// snapshot on next client-enter, undoing the engine's automatic
// "rested" reset.
//
// Persistence rides on NWNX_Object_*Int with bPersist=TRUE — the same
// pattern the HGLL leveler uses (see commit 08cb4571).
//
// Death is still handled by the existing deathamulet path
// (ondeath020.nss + the deathamulet check in hgll_cliententer.nss).
// PersState_Restore deliberately skips HP restoration when the saved
// HP is <= 0 so the deathamulet path is the sole arbiter of death.

#include "nwnx_creature"   // still used for GetFeatRemainingUses / Set
#include "nwnx_object"     // SetInt persistence + SetCurrentHitPoints
#include "nwnx_player"     // UpdateCharacterSheet

const string PERS_HP            = "pers_hp";
const string PERS_HP_VALID      = "pers_hp_valid";
const string PERS_MSP_PREFIX    = "pers_msp_";     // + "<class>_<level>_<idx>"
                                                   // 0 = not snapshotted,
                                                   // 1 = snapshotted not-ready,
                                                   // 2 = snapshotted ready
const string PERS_FEAT_PREFIX   = "pers_feat_";    // + "<featId>"

// Daily-use feats to track. Edit this single array to add more
// (PRC-style epic spells, custom HGLL high-level feats, etc.).
const int PERS_FEAT_COUNT = 14;
int PersState_FeatId(int i)
{
    switch (i)
    {
        case  0: return FEAT_STUNNING_FIST;
        case  1: return FEAT_SMITE_EVIL;
        case  2: return FEAT_SMITE_GOOD;
        case  3: return 411;   // FEAT_BARDIC_MUSIC (not in stock nwscript)
        case  4: return FEAT_WILD_SHAPE;
        case  5: return FEAT_TURN_UNDEAD;
        case  6: return FEAT_KI_DAMAGE;
        case  7: return FEAT_QUIVERING_PALM;
        // Epic spells — feat IDs verified in j_inc_constants.nss.
        case  8: return 874;   // FEAT_EPIC_SPELL_MUMMY_DUST
        case  9: return 875;   // FEAT_EPIC_SPELL_DRAGON_KNIGHT
        case 10: return 876;   // FEAT_EPIC_SPELL_HELLBALL
        case 11: return 877;   // FEAT_EPIC_SPELL_EPIC_MAGE_ARMOR
        case 12: return 878;   // FEAT_EPIC_SPELL_RUIN
        case 13: return 990;   // FEAT_EPIC_SPELL_EPIC_WARDING
    }
    return -1;
}

// Polymorphed Shifters: pc_export_inc skips them to avoid stat
// corruption. We do the same for HP capture (their morphed HP would
// stomp the real value).
int PersState_IsShifterMorphed(object oPC)
{
    if (GetLevelByClass(CLASS_TYPE_SHIFTER, oPC) <= 0) return FALSE;
    effect ef = GetFirstEffect(oPC);
    while (GetEffectType(ef) != EFFECT_TYPE_INVALIDEFFECT)
    {
        if (GetEffectType(ef) == EFFECT_TYPE_POLYMORPH) return TRUE;
        ef = GetNextEffect(oPC);
    }
    return FALSE;
}

void PersState_Snapshot(object oPC)
{
    if (!GetIsPC(oPC) || GetIsDM(oPC)) return;

    if (!PersState_IsShifterMorphed(oPC))
    {
        NWNX_Object_SetInt(oPC, PERS_HP, GetCurrentHitPoints(oPC), TRUE);
        NWNX_Object_SetInt(oPC, PERS_HP_VALID, 1, TRUE);
    }

    int nClass, nLevel, i;
    for (nClass = 0; nClass <= 3; nClass++)
    {
        int nClassType = GetClassByPosition(nClass + 1, oPC);
        if (nClassType == CLASS_TYPE_INVALID) continue;
        for (nLevel = 0; nLevel <= 9; nLevel++)
        {
            // Prepared casters: snapshot the per-slot Ready flag using
            // stock APIs. NWNX_Creature_GetRemainingSpellSlots in this
            // build returns 0 unconditionally, so we can't rely on it.
            int nCount = GetMemorizedSpellCountByLevel(oPC, nClassType, nLevel);
            for (i = 0; i < nCount; i++)
            {
                int bReady = GetMemorizedSpellReady(oPC, nClassType, nLevel, i);
                NWNX_Object_SetInt(oPC,
                    PERS_MSP_PREFIX + IntToString(nClassType) + "_"
                        + IntToString(nLevel) + "_" + IntToString(i),
                    bReady ? 2 : 1, TRUE);
            }
        }
    }

    for (i = 0; i < PERS_FEAT_COUNT; i++)
    {
        int nFeat = PersState_FeatId(i);
        if (nFeat < 0 || !GetHasFeat(nFeat, oPC)) continue;
        int nUses = NWNX_Creature_GetFeatRemainingUses(oPC, nFeat);
        NWNX_Object_SetInt(oPC,
            PERS_FEAT_PREFIX + IntToString(nFeat),
            nUses, TRUE);
    }
}

void PersState_Restore(object oPC)
{
    if (!GetIsPC(oPC) || GetIsDM(oPC)) return;

    int nClass, nLevel, i;
    for (nClass = 0; nClass <= 3; nClass++)
    {
        int nClassType = GetClassByPosition(nClass + 1, oPC);
        if (nClassType == CLASS_TYPE_INVALID) continue;
        for (nLevel = 0; nLevel <= 9; nLevel++)
        {
            int nCount = GetMemorizedSpellCountByLevel(oPC, nClassType, nLevel);
            for (i = 0; i < nCount; i++)
            {
                int nState = NWNX_Object_GetInt(oPC,
                    PERS_MSP_PREFIX + IntToString(nClassType) + "_"
                        + IntToString(nLevel) + "_" + IntToString(i));
                if (nState == 0) continue; // never snapshotted
                int bSavedReady = (nState == 2);
                // Engine restores all prepared slots to ready on enter;
                // only flip back to not-ready those the snapshot says
                // were spent. Don't go the other way (snap back to
                // ready) — we only ever take spells away, never give.
                if (!bSavedReady && GetMemorizedSpellReady(oPC, nClassType, nLevel, i))
                    SetMemorizedSpellReady(oPC, nClassType, nLevel, i, FALSE);
            }
        }
    }

    for (i = 0; i < PERS_FEAT_COUNT; i++)
    {
        int nFeat = PersState_FeatId(i);
        if (nFeat < 0 || !GetHasFeat(nFeat, oPC)) continue;
        int nUses = NWNX_Object_GetInt(oPC, PERS_FEAT_PREFIX + IntToString(nFeat));
        // GetInt returns 0 for unset keys, which would zero out fresh
        // PCs that never logged out. Use the total-uses ceiling as a
        // proxy for "was this snapshotted?": only restore if the saved
        // value is strictly less than current (engine just gave them
        // full uses on enter — if our saved value is the same or
        // higher there's nothing to take away).
        int nCur = NWNX_Creature_GetFeatRemainingUses(oPC, nFeat);
        if (nUses < nCur) NWNX_Creature_SetFeatRemainingUses(oPC, nFeat, nUses);
    }

    // HP last. Skip when the snapshot was never taken or the saved
    // value is <= 0 (death — let the deathamulet handle it).
    // Direct NWNX HP set bypasses DR/resistance and is exact regardless
    // of where the engine's post-login heal has landed by now.
    if (NWNX_Object_GetInt(oPC, PERS_HP_VALID) == 1)
    {
        int nSaved = NWNX_Object_GetInt(oPC, PERS_HP);
        if (nSaved > 0 && nSaved < GetCurrentHitPoints(oPC))
            NWNX_Object_SetCurrentHitPoints(oPC, nSaved);
    }

    // Force the client's character sheet / spellbook UI to redraw so
    // restored spell-slot and feat-use counts are visible immediately.
    NWNX_Player_UpdateCharacterSheet(oPC);
}
