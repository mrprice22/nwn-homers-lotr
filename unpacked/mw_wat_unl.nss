// mw_wat_unl -- pass-entry action: unlock Alan Watts.
#include "mw_unlock_inc"
void main()
{
    object oPC = GetPCSpeaker();
    MW_Unlock(oPC, "watts");
    DeleteLocalInt(oPC, "mw_wat_score");
}
