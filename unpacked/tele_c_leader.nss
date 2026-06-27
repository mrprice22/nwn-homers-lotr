// tele_c_leader — Conditional: show the party-leader teleport when this CD Key
// owns merit unlock 101.
#include "merit_redeem"
int StartingConditional()
{
    return Merit_TeleOwned(GetPCPublicCDKey(GetPCSpeaker()), 101);
}
