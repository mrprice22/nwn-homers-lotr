// tele_leader — Rest-menu teleport to your party leader (merit unlock 101).
#include "tele_db"
void main()
{
    object oPC = GetPCSpeaker();
    object oLeader = GetFactionLeader(oPC);
    if (oLeader == oPC || !GetIsObjectValid(oLeader))
    {
        SendMessageToPC(oPC, "[Teleport] You are your own party leader - nowhere to go.");
        return;
    }
    Tele_DoJump(oPC, GetLocation(oLeader), VFX_FNF_LOS_HOLY_30, VFX_IMP_HOLY_AID);
}
