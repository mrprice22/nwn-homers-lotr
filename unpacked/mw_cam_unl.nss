// mw_cam_unl -- pass-entry action: unlock Joseph Campbell.
#include "mw_unlock_inc"
void main()
{
    object oPC = GetPCSpeaker();
    MW_Unlock(oPC, "campbell");
    DeleteLocalInt(oPC, "mw_cam_score");
}
