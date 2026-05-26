// mw_joc_unl -- pass-entry action: unlock Jocko Willink.
#include "mw_unlock_inc"
void main()
{
    object oPC = GetPCSpeaker();
    MW_Unlock(oPC, "jocko");
    DeleteLocalInt(oPC, "mw_joc_score");
}
