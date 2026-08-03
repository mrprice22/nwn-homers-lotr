// tele_c_s3 - Conditional: show save-slot 3 when this CD Key owns merit
// unlock 105.
#include "merit_redeem"
int StartingConditional()
{
    return Merit_TeleOwned(GetPCPublicCDKey(GetPCSpeaker()), 105);
}
