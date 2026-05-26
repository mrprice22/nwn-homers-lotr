// mw_pet_unl -- pass-entry action: grant Peterson as a guide.
#include "mw_unlock_inc"
void main()
{
    object oPC = GetPCSpeaker();
    MW_Unlock(oPC, "peterson");
    DeleteLocalInt(oPC, "mw_pet_score");
}
