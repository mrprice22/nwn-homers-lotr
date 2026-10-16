// hw26_scythe - The Hollow King's Scythe, OnHit (tag-based X2 item event).
//
// Runs from the stock x2_s3_onhitcast through the "OnHit: Unique Power" item
// property, with OBJECT_SELF the wielder. When a blow kills, 20% of the time a
// Pumpkin-Born Skeleton rises to fight for the wielder for 2 minutes - at most
// three at once.

#include "hw_inc"
#include "x2_inc_switches"

void HW_ScytheCheck(object oPC, object oVictim, location l)
{
    if (GetIsObjectValid(oVictim) && !GetIsDead(oVictim)) return;
    if (Random(100) >= 20) return;
    int nMine = 0;
    int n = 1;
    object o = GetNearestObjectByTag(HW_TAG_ALLY, oPC, n);
    while (GetIsObjectValid(o))
    {
        if (GetLocalObject(o, "hw_owner") == oPC) nMine++;
        n++;
        o = GetNearestObjectByTag(HW_TAG_ALLY, oPC, n);
    }
    if (nMine >= 3) return;
    HW_SpawnAllySkeletons(oPC, l, 1, 120.0);
}

void main()
{
    if (GetUserDefinedItemEventNumber() != X2_ITEM_EVENT_ONHITCAST) return;
    object oPC = OBJECT_SELF;
    object oVictim = GetSpellTargetObject();
    if (!GetIsPC(oPC) || GetObjectType(oVictim) != OBJECT_TYPE_CREATURE) return;
    if (GetLocalInt(oVictim, "hw_scy_seen")) return;
    // Only judge each victim once, just after its killing blow can have landed.
    DelayCommand(0.3, HW_ScytheCheck(oPC, oVictim, GetLocation(oVictim)));
    if (GetCurrentHitPoints(oVictim) <= 0) SetLocalInt(oVictim, "hw_scy_seen", 1);
}
