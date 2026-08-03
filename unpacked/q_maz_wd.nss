// q_maz_wd - Wraith of the Twentieth Plot OnDeath (roadmap:
// twentieth-plot-mazarbul). Advances every party-member PC in the area who
// is at stage 2 to stage 3 (party-aware kill credit, same pattern as
// Ferny's Return / The Miller's Other Son). Quest state lives in the
// "maz20" campaign DB per character, so it survives relogs and reboots.
// Bestiary-safe: bst_install stores this script as bst_orig_death at spawn
// (via nw_c2_default9), so bst_ondeath records the kill first and chains
// here; we chain the standard death script last.
#include "q_maz_inc"

void main()
{
    object oPC = MAZ_OwningPC(GetLastKiller());
    if (GetIsObjectValid(oPC))
    {
        object oArea = GetArea(OBJECT_SELF);
        object oMember = GetFirstFactionMember(oPC, TRUE);
        while (GetIsObjectValid(oMember))
        {
            if (GetArea(oMember) == oArea && MAZ_GetStage(oMember) == 2)
            {
                MAZ_SetStage(oMember, 3);
                AddJournalQuestEntry(MAZ_QUEST, 3, oMember, FALSE, FALSE);
                FloatingTextStringOnCreature(
                    "The wraith is destroyed. Return to Frar's shade in the "
                    + "Chamber of Records.", oMember, FALSE);
            }
            oMember = GetNextFactionMember(oPC, TRUE);
        }
    }
    ExecuteScript("nw_c2_default7", OBJECT_SELF);
}
