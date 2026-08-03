// cbd_use - Hall of Champions sign OnUsed: open the menu.
#include "cbd_db"
void main()
{
    object oPC = GetLastUsedBy();
    if (!GetIsPC(oPC)) return;
    Cbd_InitDb();
    DeleteLocalInt(oPC, "cbd_mode");
    SetLocalInt(oPC, "cbd_off", 0);
    ActionStartConversation(oPC, "", TRUE, FALSE);
}
