// merit_npc_init - Reply action: load the speaker's merit stats into custom tokens
// before the stats/rewards entry node renders.
#include "merit_db"
void main()
{
    Merit_SetNpcTokens(GetPCSpeaker());
}
