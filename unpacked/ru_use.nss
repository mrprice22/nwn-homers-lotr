// ru_use - Recent Updates sign OnUsed: open the menu (validated vs in testing).
#include "ru_db"
void main()
{
    object oPC = GetLastUsedBy();
    if (!GetIsPC(oPC)) return;
    RU_BuildMenu(oPC);
    ActionStartConversation(oPC, "", TRUE, FALSE);
}
