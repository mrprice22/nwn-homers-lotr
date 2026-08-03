// prsg_c_sum.nss - summary-line token setter (roadmap: prestige-trainer-hub).
// Fills custom token 6381 with the orders that would hear the PC's name as
// they stand today, then always shows the line.
#include "prsg_inc"

int StartingConditional()
{
    SetCustomToken(PRSG_TOKEN_LIST, PRSG_QualifyList(GetPCSpeaker()));
    return TRUE;
}
