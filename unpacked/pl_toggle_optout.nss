// pl_toggle_optout - rest-menu action: toggle this PC's opt-out of party loot
// rolls. Persisted per-character in the campaign DB.
#include "inc_partyloot"

void main()
{
    object oPC = GetPCSpeaker();
    int bNow = !PL_IsOptedOut(oPC);
    SetCampaignInt(PL_DB, "optout", bNow, oPC);

    string sMsg = bNow
        ? "You have OPTED OUT of party loot rolls. You will no longer be prompted to roll."
        : "You have OPTED IN to party loot rolls.";
    SendMessageToPC(oPC, ColorString(sMsg, COLOR_GREEN));
}
