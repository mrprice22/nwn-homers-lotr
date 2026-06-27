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
    Tele_DoJump(oPC, GetLocation(oLeader));
}
