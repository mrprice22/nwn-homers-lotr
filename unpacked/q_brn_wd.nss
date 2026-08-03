// q_brn_wd - Beorn's Garden warg OnDeath wrapper (roadmap: beorns-garden)
// Blueprint OnDeath for q_brn_warg (the hive-angered garden wargs). Skins a
// pelt for the killing PC while the quest is active, then chains the
// standard death script. Bestiary-safe: bst_install stores this script as
// bst_orig_death at spawn (via nw_c2_default9), so bst_ondeath records the
// kill first and chains here via ExecuteScript.
#include "q_brn_inc"

void main()
{
    object oPC = BRN_OwningPC(GetLastKiller());
    if (GetIsObjectValid(oPC)
        && BRN_IsActive(oPC)
        && BRN_CountPelts(oPC) < BRN_NEED_PELTS)
    {
        CreateItemOnObject(BRN_PELT_TAG, oPC, 1);
        FloatingTextStringOnCreature("You skin a warg pelt from the raider ("
            + IntToString(BRN_CountPelts(oPC)) + " of "
            + IntToString(BRN_NEED_PELTS) + ").", oPC, FALSE);
    }
    ExecuteScript("nw_c2_default7", OBJECT_SELF);
}
