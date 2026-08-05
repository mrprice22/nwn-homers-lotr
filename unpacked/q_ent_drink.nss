// The Thirteenth Ent (roadmap: thirteenth-ent)
// Tag-based item script for the Draught of the Ent (item tag q_ent_drink,
// blueprint q_ent_drght). Single-use Unique Power Self Only, so the engine
// consumes the horn cup on drinking.
//
// The draught writes a PERMANENT +1 Strength / +1 Constitution into the
// character's BASE ability scores (NWNX_Creature_SetRawAbilityScore, the same
// route legfeat_inc.nss uses for its RAW-kind picks) and exports the
// character so the new base scores are written through to the .bic.
//
// ANTI-FARM - this is the correctness property of the whole quest. The gain
// is permanent, so it is gated on an advance-only questcddb key
// (ENT_DRUNK_K): the FIRST drink stamps it, and every later cup on that
// character is refused before a single point is applied. The key is keyed on
// GetObjectUUID and lives in a campaign DB, so it survives relogs, reboots
// and module rebuilds. The draught is separately handed out at most once per
// character (ENT_DRAUGHT_K, stamped in ENT_GrantDraught), so a second cup can
// only ever come from another character or a DM.
#include "x2_inc_switches"
#include "q_ent_inc"
#include "nwnx_creature"

void main()
{
    if (GetUserDefinedItemEventNumber() != X2_ITEM_EVENT_ACTIVATE)
        return;

    object oPC = GetItemActivator();
    if (!GetIsObjectValid(oPC) || !GetIsPC(oPC))
        return;

    if (QCD_LastStamp(oPC, ENT_DRUNK_K) != 0)
    {
        ENT_Tell(oPC, "You have drunk of the Ent once already. A second "
                    + "draught is only water and leaf-mould to you.");
        SetExecutedScriptReturnValue(X2_EXECUTE_SCRIPT_END);
        return;
    }

    QCD_Stamp(oPC, ENT_DRUNK_K);

    NWNX_Creature_SetRawAbilityScore(oPC, ABILITY_STRENGTH,
        NWNX_Creature_GetRawAbilityScore(oPC, ABILITY_STRENGTH) + 1);
    NWNX_Creature_SetRawAbilityScore(oPC, ABILITY_CONSTITUTION,
        NWNX_Creature_GetRawAbilityScore(oPC, ABILITY_CONSTITUTION) + 1);
    ExportSingleCharacter(oPC);

    ApplyEffectToObject(DURATION_TYPE_INSTANT,
        EffectVisualEffect(VFX_IMP_IMPROVE_ABILITY_SCORE), oPC);
    ENT_Tell(oPC, "You drink. Something under your ribs takes root and holds. "
                + "(+1 Strength and +1 Constitution, permanently.)");

    SetExecutedScriptReturnValue(X2_EXECUTE_SCRIPT_END);
}
