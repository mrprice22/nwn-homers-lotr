// graf_use.nss - OnUsed for the graffiti pedestal (tag graf_pedestal).
// Same shape as cbd_use.nss: set the menu's state up, then let the placeable's
// own Conversation field open the window.
#include "graf_inc"
void main()
{
    object oPC = GetLastUsedBy();
    if (!GetIsPC(oPC)) return;

    Graf_InitDb();

    if (!Graf_ClaimOk(oPC))
    {
        SendMessageToPC(oPC, "Someone else is working the stone just now. "
            + "Give them a few minutes.");
        return;
    }

    SetLocalInt(oPC, "graf_mode", 0);
    SetLocalInt(oPC, "graf_page_off", 0);
    Graf_Summary(oPC);
    ActionStartConversation(oPC, "", TRUE, FALSE);
}
