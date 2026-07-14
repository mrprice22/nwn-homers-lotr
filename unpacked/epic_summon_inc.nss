//::///////////////////////////////////////////////
//:: Epic summon helper  (Mummy Reaper / Dragon Knight)
//:: epic_summon_inc
//:://////////////////////////////////////////////
/*
    Lets the epic summons (Mummy Dust -> "mummyreaper", Dragon Knight ->
    "epicdragonknight") coexist with a normal summon.

    The NWN engine gives a master only ONE ASSOCIATE_TYPE_SUMMONED slot: casting
    any EffectSummonCreature auto-unsummons the previous one, so an epic summon
    and a summon-animal spell can never be out together. To get a second,
    independent slot we put the epic summons on the HENCHMAN slot instead
    (CreateObject + AddHenchman) -- the same pattern the Meaningwave guide system
    uses (mw_unlock_inc.nss: MW_SummonGuide / MW_DismissActiveGuide).

    Result:
      - Epic slot  (henchman)  : Mummy Reaper OR Dragon Knight, mutually
                                 exclusive -- EpicSummon_Cast dismisses the prior
                                 epic before creating the new one.
      - Normal slot (summoned) : unchanged; the engine still allows only one
                                 summon-animal at a time.
      - Epic + normal can be out at the same time (different slots).

    The epic blueprints are FactionID 2 (Commoner) -- non-hostile to PCs -- so
    AddHenchman produces a friendly follower whose henchman AI fights the
    master's enemies. No faction change needed.
*/
//:://////////////////////////////////////////////

// PC local that tracks that PC's current epic henchman.
const string EPIC_SUMMON_OBJ = "EPIC_SUMMON_OBJ";
// Marker set on the epic creature itself.
const string EPIC_SUMMON_TAG = "EPIC_SUMMON";
// Local object on the epic creature pointing back at its master, so the
// heartbeat orphan check (epic_summon_hb.nss) can clear the PC's tracking
// local after the party/dismiss flow has already severed GetMaster().
const string EPIC_SUMMON_OWNER = "EPIC_SUMMON_OWNER";

// Remove oPC's current epic summon (if any) and clear the tracking local.
void EpicSummon_Dismiss(object oPC)
{
    object oOld = GetLocalObject(oPC, EPIC_SUMMON_OBJ);
    if (GetIsObjectValid(oOld))
    {
        RemoveHenchman(oPC, oOld);
        AssignCommand(oOld, ClearAllActions());
        ApplyEffectToObject(DURATION_TYPE_INSTANT,
            EffectVisualEffect(VFX_IMP_UNSUMMON), oOld);
        ApplyEffectToObject(DURATION_TYPE_INSTANT, EffectDisappear(), oOld);
    }
    DeleteLocalObject(oPC, EPIC_SUMMON_OBJ);
}

// Timed-expiry callback -- runs assigned to the epic creature (OBJECT_SELF), so
// it dies harmlessly with the creature if it was already killed/dismissed.
// Re-checks that this is still the PC's tracked epic so a newer summon (cast
// before this one expired) is never clobbered.
void EpicSummon_Expire(object oPC)
{
    object oSelf = OBJECT_SELF;
    if (GetLocalObject(oPC, EPIC_SUMMON_OBJ) != oSelf) return;
    RemoveHenchman(oPC, oSelf);
    DeleteLocalObject(oPC, EPIC_SUMMON_OBJ);
    ApplyEffectToObject(DURATION_TYPE_INSTANT,
        EffectVisualEffect(VFX_IMP_UNSUMMON), oSelf);
    ApplyEffectToObject(DURATION_TYPE_INSTANT, EffectDisappear(), oSelf);
}

// Cast an epic summon: dismiss any existing epic, then spawn sResRef as a
// timed henchman of oPC at lLoc with the given summon visual.
void EpicSummon_Cast(object oPC, string sResRef, location lLoc,
                     float fDuration, int nSummonVFX)
{
    // One epic at a time: clear the previous Mummy/Dragon Knight first.
    EpicSummon_Dismiss(oPC);

    object oEpic = CreateObject(OBJECT_TYPE_CREATURE, sResRef, lLoc);
    if (!GetIsObjectValid(oEpic))
    {
        FloatingTextStringOnCreature(
            "Summon failed (blueprint " + sResRef + " missing).", oPC, FALSE);
        return;
    }

    AddHenchman(oPC, oEpic);
    SetLocalInt(oEpic, EPIC_SUMMON_TAG, 1);
    SetLocalObject(oEpic, EPIC_SUMMON_OWNER, oPC);
    SetLocalObject(oPC, EPIC_SUMMON_OBJ, oEpic);

    ApplyEffectToObject(DURATION_TYPE_INSTANT,
        EffectVisualEffect(nSummonVFX), oEpic);

    // Timed like a summon -- henchmen do not auto-expire, so schedule removal
    // on the creature's own action queue.
    AssignCommand(oEpic, DelayCommand(fDuration, EpicSummon_Expire(oPC)));
}
