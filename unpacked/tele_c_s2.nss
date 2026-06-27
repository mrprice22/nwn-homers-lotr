// tele_c_s2 — Conditional: show save-slot 2 when this CD Key owns merit
// unlock 104.
#include "merit_redeem"
int StartingConditional()
{
    return Merit_TeleOwned(GetPCPublicCDKey(GetPCSpeaker()), 104);
}
