//::///////////////////////////////////////////////
//:: Epic summon heartbeat  (Mummy Reaper / Dragon Knight)
//:: epic_summon_hb
//:://////////////////////////////////////////////
/*
    OnHeartbeat for the epic summon blueprints (mummyreaper.utc,
    epicdragonknight.utc). Runs the standard henchman heartbeat AI, then
    fixes the "dismissed but left standing" defect (roadmap:
    epic-summon-unsummon):

    Epic summons live on the HENCHMAN slot (see epic_summon_inc.nss), and
    kicking a henchman via the party/dismiss flow only severs the master
    link -- the engine never destroys the creature the way it does a real
    ASSOCIATE_TYPE_SUMMONED. Detect the orphaned state (marker set, no
    master) and unsummon properly: clear the owner's tracking local, play
    the unsummon visual, and disappear.

    Real Meaningwave henchmen and other companions are untouched -- this
    script is only wired to the two epic summon blueprints, and the check
    additionally requires the EPIC_SUMMON_TAG marker that only
    EpicSummon_Cast sets.
*/
//:://////////////////////////////////////////////

#include "epic_summon_inc"

void main()
{
    // Standard henchman heartbeat AI (stock resource, resolved by resman).
    ExecuteScript("x0_ch_hen_heart", OBJECT_SELF);

    object oSelf = OBJECT_SELF;
    if (!GetLocalInt(oSelf, EPIC_SUMMON_TAG)) return;
    if (GetIsObjectValid(GetMaster(oSelf))) return;

    // Orphaned: the master link was severed outside EpicSummon_Dismiss /
    // EpicSummon_Expire (party-kick, or any other RemoveHenchman path).
    // Clear the owner's tracking local if it still points at us so a later
    // EpicSummon_Cast/Dismiss doesn't chase a stale reference.
    object oOwner = GetLocalObject(oSelf, EPIC_SUMMON_OWNER);
    if (GetIsObjectValid(oOwner)
        && GetLocalObject(oOwner, EPIC_SUMMON_OBJ) == oSelf)
    {
        DeleteLocalObject(oOwner, EPIC_SUMMON_OBJ);
    }

    AssignCommand(oSelf, ClearAllActions());
    ApplyEffectToObject(DURATION_TYPE_INSTANT,
        EffectVisualEffect(VFX_IMP_UNSUMMON), oSelf);
    ApplyEffectToObject(DURATION_TYPE_INSTANT, EffectDisappear(), oSelf);
}
