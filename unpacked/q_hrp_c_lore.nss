// q_hrp_c_lore - the Lore shortcut on Della's cipher: a learned PC (Lore
// rank 8+, items and ability included) reads the road-cant at a glance and
// skips the hint-and-guess path. (roadmap: harper-scout-quest)
#include "q_hrp_inc"

int StartingConditional()
{
    return GetSkillRank(SKILL_LORE, GetPCSpeaker()) >= QHRP_LORE_DC;
}
