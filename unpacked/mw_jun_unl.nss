// mw_jun_unl -- pass-entry action: unlock Carl Jung.
#include "mw_unlock_inc"
void main()
{
    object oPC = GetPCSpeaker();
    MW_Unlock(oPC, "jung");
    DeleteLocalInt(oPC, "mw_jun_score");
}
