// mw_q_chk -- StartingConditional on the intro: route to the "already unlocked"
// line if this PC has already earned this guide. Guide derived from the NPC tag.
#include "mw_unlock_inc"
int StartingConditional()
{
    return MW_IsUnlocked(GetPCSpeaker(), MW_GuideFromTag());
}
