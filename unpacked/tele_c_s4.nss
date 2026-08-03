// tele_c_s4 - Conditional: show save-slot 4 when this CD Key owns merit
// unlock 106.
#include "merit_redeem"
int StartingConditional()
{
    return Merit_TeleOwned(GetPCPublicCDKey(GetPCSpeaker()), 106);
}
