// lootlab_lvdn1.nss - Loot Lab: lower the loot level by 1.
// Roadmap: lo-loot-core. Loot Lab action (emotewand.dlg Entry 19, Admin Options -> [Admin] Loot Lab). See lootlab_inc.nss.
#include "lootlab_inc"

void main()
{
    LL_AdjustLevel(-1);
}
