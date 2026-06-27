// ru_use — Recent Updates sign OnUsed: prime page 1 and open the conversation.
#include "ru_db"
void main()
{
    object oPC = GetLastUsedBy();
    if (!GetIsPC(oPC)) return;
    SetLocalInt(oPC, "ru_page_off", 0);
    RU_BuildPage(oPC);
    ActionStartConversation(oPC, "", TRUE, FALSE);
}
