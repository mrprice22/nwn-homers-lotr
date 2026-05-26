// mw_mck_unl -- pass-entry action: unlock Terence McKenna.
#include "mw_unlock_inc"
void main()
{
    object oPC = GetPCSpeaker();
    MW_Unlock(oPC, "mckenna");
    DeleteLocalInt(oPC, "mw_mck_score");
}
