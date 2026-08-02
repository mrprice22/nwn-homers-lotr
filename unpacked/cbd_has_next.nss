// cbd_has_next — sign: is there a page after the current one?
#include "cbd_db"
int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return (GetLocalInt(oPC, "cbd_off") + CBD_PAGE) < GetLocalInt(oPC, "cbd_total");
}
