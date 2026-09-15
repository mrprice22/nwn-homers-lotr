// Summoned Mummy Reaper heartbeat -- it goes when its summoner goes
//:: (roadmap: gandalfs-mummys)
//
// OnHeartbeat for npc_mreaper.utc and wtop_mreaper.utc, the two reapers an NPC
// caster conjures through x2_s2_mumdust.nss. Runs the stock AI heartbeat first
// and adds exactly one thing on top of it.
//
// A summoned reaper no longer crumbles on a timer -- the admin's call after UAT:
// it stands until something kills it. That leaves one way for a fight to end
// with mummies still walking around: the summoner dies and his conjured bodies
// outlive him. So the reaper watches its own summoner (MDUST_MASTER, set at
// creation by the summon path) and unsummons itself when he is gone or dead.
//
// The check is on the CREATURE, not on the summoner's death script: every NPC
// caster in the module shares x2_def_ondeath, and the Weathertop court's sweep
// (wtop_chase.nss, WtopChaseClearSummons) is area-scoped and stays as it is.
// With at most two reapers alive per area, one local read per six seconds is
// not a cost worth avoiding.
//
// A reaper with no MDUST_MASTER local -- a hand-placed one, or a player's
// henchman reaper, which is a different blueprint anyway -- falls straight
// through: this script only ever acts on something the summon path created.

#include "mumdust_inc"

void main()
{
    // Stock AI heartbeat, unchanged.
    ExecuteScript("x2_def_heartbeat", OBJECT_SELF);

    object oSelf = OBJECT_SELF;

    // Not a script summon: nothing to do. The marker is an int, not the object
    // local below, precisely because it survives the summoner's destruction.
    if (!GetLocalInt(oSelf, MDUST_SUMMONED)) return;

    // Validity first -- GetIsDead on a destroyed object is not a useful answer.
    object oMaster = GetLocalObject(oSelf, MDUST_MASTER);
    if (GetIsObjectValid(oMaster) && !GetIsDead(oMaster)) return;

    AssignCommand(oSelf, ClearAllActions());
    ApplyEffectToObject(DURATION_TYPE_INSTANT,
        EffectVisualEffect(VFX_IMP_UNSUMMON), oSelf);
    ApplyEffectToObject(DURATION_TYPE_INSTANT, EffectDisappear(), oSelf);
}
