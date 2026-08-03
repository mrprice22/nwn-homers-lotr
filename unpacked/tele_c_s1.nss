// tele_c_s1 - Conditional: show save-slot 1 when this CD Key owns merit
// unlock 103.
#include "merit_redeem"
int StartingConditional()
{
    return Merit_TeleOwned(GetPCPublicCDKey(GetPCSpeaker()), 103);
}
