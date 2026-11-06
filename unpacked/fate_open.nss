// fate_open.nss - open the Shard of Fate bonus-roll prompt (Loot Overhaul
// Phase 7, lo-fate-token).  OBJECT_SELF = the PC; loot_ondeath stores the offer
// in FATE_P_* on the PC and runs this with ExecuteScript.  See fate_inc.

#include "fate_inc"

void main()
{
    object oPC = OBJECT_SELF;
    if (!GetIsPC(oPC) || GetIsDM(oPC)) return;
    Fate_Offer(oPC);
}
