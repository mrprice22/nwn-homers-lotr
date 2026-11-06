// gem_drop.nss - Loot Overhaul Phase 5: one random socket gem onto OBJECT_SELF
// (a container or a corpse), at loot level GEM_DROP_LVL with tier floor
// GEM_DROP_FLOOR (locals the caller sets on OBJECT_SELF - loot_inc
// Loot_DropSocketGem).  A separate script so the gem tables (socket_data_inc)
// stay out of loot_inc and the thirty container wrappers that include it.
#include "gem_inc"

void main()
{
    object oDest = OBJECT_SELF;
    int nLvl = GetLocalInt(oDest, "GEM_DROP_LVL");
    int nFloor = GetLocalInt(oDest, "GEM_DROP_FLOOR");
    DeleteLocalInt(oDest, "GEM_DROP_LVL");
    DeleteLocalInt(oDest, "GEM_DROP_FLOOR");
    Gem_Drop(nLvl, nFloor, oDest);
}
