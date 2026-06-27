// tele_c_s5 — Conditional: show save-slot 5 when this CD Key owns merit
// unlock 107.
#include "merit_redeem"
int StartingConditional()
{
    return Merit_TeleOwned(GetPCPublicCDKey(GetPCSpeaker()), 107);
}
