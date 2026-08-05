// The Thirteenth Ent (roadmap: thirteenth-ent)
// StartingConditional: this character has already woken Leaflock.
#include "q_ent_inc"

int StartingConditional()
{
    return ENT_IsRestored(GetPCSpeaker());
}
