// mw_aur_unl -- pass-entry action: unlock Marcus Aurelius.
#include "mw_unlock_inc"
void main()
{
    object oPC = GetPCSpeaker();
    MW_Unlock(oPC, "aurelius");
    DeleteLocalInt(oPC, "mw_aur_score");
}
