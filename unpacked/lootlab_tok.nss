// lootlab_tok.nss - StartingConditional on every link into the Loot Lab menu:
// refreshes the level / rarity-floor tokens (6450 / 6451) before it is shown.
// Roadmap: lo-loot-core. Loot Lab action (emotewand.dlg Entry 19, Admin Options -> [Admin] Loot Lab). See lootlab_inc.nss.
#include "lootlab_inc"

int StartingConditional()
{
    LL_SetTokens(GetPCSpeaker());
    return TRUE;
}
