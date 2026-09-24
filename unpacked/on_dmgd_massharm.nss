#include "nw_i0_generic"

// Will save DC to halve Mass Harm. Negative-energy immunity (Shadow Shield)
// still blocks it outright.
const int MH_SAVE_DC = 60;

void harm()
{
    effect eVis = EffectVisualEffect(246);
    int nDamage = d100(5) + 100;
    location lSelf = GetLocation(OBJECT_SELF);

    // Iterate the whole sphere. The old loop condition stopped at the first
    // object that was OBJECT_SELF, so everyone after the Balrog was skipped.
    object oTarget = GetFirstObjectInShape(SHAPE_SPHERE, RADIUS_SIZE_COLOSSAL, lSelf);
    while (GetIsObjectValid(oTarget))
    {
        if (oTarget != OBJECT_SELF && GetIsEnemy(oTarget) && !GetIsDead(oTarget))
        {
            int nThis = nDamage;
            if (WillSave(oTarget, MH_SAVE_DC, SAVING_THROW_TYPE_NEGATIVE, OBJECT_SELF))
                nThis = nDamage / 2;
            ApplyEffectToObject(DURATION_TYPE_INSTANT, eVis, oTarget);
            DelayCommand(1.0, ApplyEffectToObject(DURATION_TYPE_INSTANT,
                EffectDamage(nThis, DAMAGE_TYPE_NEGATIVE), oTarget));
        }
        oTarget = GetNextObjectInShape(SHAPE_SPHERE, RADIUS_SIZE_COLOSSAL, lSelf);
    }
}


void main()
{


// OnDamaged fires once per hit taken, so an uncapped roll here scaled with
// the party's attacks per round and stacked several harms in one round.
// Cap it at one chance per round.
if (!GetLocalInt(OBJECT_SELF, "MH_COOLDOWN"))
   {
   SetLocalInt(OBJECT_SELF, "MH_COOLDOWN", 1);
   DelayCommand(6.0, DeleteLocalInt(OBJECT_SELF, "MH_COOLDOWN"));
   if (d10() >= 9)
       harm();
   }




    if(GetFleeToExit())
    {
        // We're supposed to run away, do nothing
    }
    else if (GetSpawnInCondition(NW_FLAG_SET_WARNINGS))
    {
        // don't do anything?
    }
    else
    {
        object oDamager = GetLastDamager();
        if (!GetIsObjectValid(oDamager))
        {
            // don't do anything, we don't have a valid damager
        }
        else if (!GetIsFighting(OBJECT_SELF))
        {   // If we're not fighting, determine combat round
            if(GetBehaviorState(NW_FLAG_BEHAVIOR_SPECIAL))
            {
                DetermineSpecialBehavior(oDamager);
            } else
            {
                if(!GetObjectSeen(oDamager)
                   && GetArea(OBJECT_SELF) == GetArea(oDamager))
                   {
                    // We don't see our attacker, go find them
                    ActionMoveToLocation(GetLocation(oDamager), TRUE);
                    ActionDoCommand(DetermineCombatRound());
                }
               else
                {
                    DetermineCombatRound();
                }
            }
        }
        else
        {
            // We are fighting already -- consider switching if we've been
            // attacked by a more powerful enemy
            object oTarget = GetAttackTarget();
            if (!GetIsObjectValid(oTarget))
                oTarget = GetAttemptedAttackTarget();
            if (!GetIsObjectValid(oTarget))
                oTarget = GetAttemptedSpellTarget();

            // If our target isn't valid
            // or our damager has just dealt us 25% or more
            //    of our hp in damager
            // or our damager is more than 2HD more powerful than our target
            // switch to attack the damager.
            if (!GetIsObjectValid(oTarget)
                || (
                    oTarget != oDamager
                    &&  (
                         GetTotalDamageDealt() > (GetMaxHitPoints(OBJECT_SELF) / 4)
                         || (GetHitDice(oDamager) - 2) > GetHitDice(oTarget)
                         )
                    )
                )
            {
                // Switch targets
                DetermineCombatRound(oDamager);
            }
        }
    }

    // Send the user-defined event signal
    if(GetSpawnInCondition(NW_FLAG_DAMAGED_EVENT))
    {
        SignalEvent(OBJECT_SELF, EventUserDefined(EVENT_DAMAGED));
    }
}
