// tele_c_return — Conditional: show the Well-of-Eru return teleport only when
// this CD Key owns unlock 102, a return point is saved, and it is armed (i.e.
// the player has teleported to the Well of Eru and not yet returned).
#include "merit_redeem"
#include "tele_db"
int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return Merit_TeleOwned(GetPCPublicCDKey(oPC), 102)
        && Tele_GetArmed(oPC)
        && Tele_HasSlot(oPC, 0);
}
