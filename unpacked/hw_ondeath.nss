// hw_ondeath - Harvest of Shadows: a monster a PC killed may leave a pumpkin.
//
// ExecuteScript'd on the dying creature from bst_ondeath.nss, after its "no PC
// was involved" early return - so summons, traps and DM kills never get here.
// Skeletons never drop one (that is where pumpkins come FROM).

#include "hw_inc"

void main()
{
    if (HW_Phase() != HW_PHASE_ACTIVE) return;
    object oCre = OBJECT_SELF;
    if (HW_IsSkeleton(oCre)) return;
    object oArea = GetArea(oCre);
    if (!GetIsObjectValid(oArea) || HW_AreaExcluded(GetResRef(oArea))) return;
    if (Random(100) >= HW_KillChancePct()) return;

    int nTier = HW_AreaTier(GetResRef(oArea));
    HW_SpawnPumpkin(HW_Scatter(GetLocation(oCre), 1.0, 3.0),
                    nTier == 0 ? "town" : "cursed");
}
