//::///////////////////////////////////////////////
//:: Default On Attacked
//:: NW_C2_DEFAULT5
//:: Copyright (c) 2001 Bioware Corp.
//:://////////////////////////////////////////////
/*
    If already fighting then ignore, else determine
    combat round
*/
//:://////////////////////////////////////////////
//:: Created By: Preston Watamaniuk
//:: Created On: Oct 16, 2001
//:://////////////////////////////////////////////

#include "nw_i0_generic"

void main()
{
    object oMON = OBJECT_SELF;
    int Black = FALSE;
    if (d20()+GetAbilityModifier(ABILITY_INTELLIGENCE,oMON)>15 || GetHitDice(oMON)>50)
        {
        Black=TRUE;
        }

    if(GetFleeToExit()) {
        // Run away!
        ActivateFleeToExit();
    } else if (GetSpawnInCondition(NW_FLAG_SET_WARNINGS)) {
        // We give an attacker one warning before we attack
        // This is not fully implemented yet
        SetSpawnInCondition(NW_FLAG_SET_WARNINGS, FALSE);

        //Put a check in to see if this attacker was the last attacker
        //Possibly change the GetNPCWarning function to make the check
    } else {
        object oAttacker = GetLastAttacker();
        // Never retaliate against our own side. A stray hit from an ally used
        // to flip us onto a friend, and the NW_ATTACK_MY_TARGET shout below
        // then spread that to the whole faction (roadmap
        // wtop-court-combat-defects). Treated as "no valid attacker".
        if (GetIsObjectValid(oAttacker)
            && (GetFactionEqual(oAttacker, OBJECT_SELF) || GetIsFriend(oAttacker)))
            oAttacker = OBJECT_INVALID;
        if (!GetIsObjectValid(oAttacker)) {
        }else if (GetTag(oAttacker) == "x2_s_bblade" && Black == TRUE)
        {
        FloatingTextStringOnCreature("You think im that stupid",oMON,FALSE);
        }
            // Don't do anything, invalid attacker or spots black blade

       else if (!GetIsFighting(OBJECT_SELF)) {
            // We're not fighting anyone else, so
            // start fighting the attacker
            if(GetBehaviorState(NW_FLAG_BEHAVIOR_SPECIAL)) {
                SetSummonHelpIfAttacked();
                DetermineSpecialBehavior(oAttacker);
            } else if (GetArea(oAttacker) == GetArea(OBJECT_SELF)) {
                SetSummonHelpIfAttacked();
                DetermineCombatRound(oAttacker);
            }

            //Shout Attack my target, only works with the On Spawn In setup
            SpeakString("NW_ATTACK_MY_TARGET", TALKVOLUME_SILENT_TALK);

            //Shout that I was attacked
            SpeakString("NW_I_WAS_ATTACKED", TALKVOLUME_SILENT_TALK);
        }
    }


    if(GetSpawnInCondition(NW_FLAG_ATTACK_EVENT))
    {
        SignalEvent(OBJECT_SELF, EventUserDefined(EVENT_ATTACKED));
    }


}
