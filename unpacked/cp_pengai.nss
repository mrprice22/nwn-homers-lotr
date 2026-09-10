// cp_pengai -- Crash Party: what a party penguin does with itself.
//
// Self-scheduling per-creature loop, started by cp_pengspawn.nss. Ends by simply
// not rescheduling when the penguin is gone, so CLEAR ALL needs to know nothing
// about it.
//
// The penguins wander, rummage in the barrels for a drink, drink it, belch,
// fall over, and occasionally announce that it is party time. None of it does
// anything mechanical -- no combat, no effects on players, nothing that touches
// another creature's action queue.
//
// ## Cost, deliberately
//
// This turns the creature dial from inert load into ACTIVE load: 25 penguins per
// press, each waking every 10-25s to queue a couple of actions, plus the pathing
// that wandering implies. That is closer to what real players cost and is the
// point of the dial -- but it does mean the creature dial now measures more than
// it did when they just stood there, so a reading taken before this change is
// not comparable with one taken after.
//
// The interval is deliberately long and the work per tick deliberately small.
// Do not add a search here that walks every object in the area.

#include "cp_inc"

const float CP_PENG_HUNT_RANGE = 15.0;

void CP_Belch(object oPeng)
{
    AssignCommand(oPeng, PlaySound(CP_BelchSound(Random(10))));
}

void main()
{
    object oPeng = OBJECT_SELF;
    if (!GetIsObjectValid(oPeng) || GetIsDead(oPeng)) return;

    int nRoll = Random(100);

    if (nRoll < 30)
    {
        // Aimless wandering. ActionRandomWalk keeps going on its own until
        // something clears it, so the next tick's ClearAllActions ends it.
        ClearAllActions();
        ActionRandomWalk();
    }
    else if (nRoll < 55)
    {
        // Go and have a rummage. The barrels the object dial spawns are stocked
        // with ale by cp_dial_item, so this is a real search that usually finds
        // something -- and when there are no barrels the penguin just shrugs.
        object oBarrel = GetNearestObjectByTag(CP_KEG_TAG, oPeng, 1);
        if (GetIsObjectValid(oBarrel)
            && GetDistanceBetween(oPeng, oBarrel) <= CP_PENG_HUNT_RANGE)
        {
            ClearAllActions();
            ActionMoveToObject(oBarrel, FALSE, 1.5);
            ActionPlayAnimation(ANIMATION_LOOPING_GET_LOW, 1.0, 3.0);
            ActionDoCommand(SpeakString("*rummages hopefully*"));
            ActionPlayAnimation(ANIMATION_FIREFORGET_DRINK, 1.0);
            ActionDoCommand(CP_Belch(oPeng));
        }
        else
        {
            ClearAllActions();
            ActionPlayAnimation(ANIMATION_LOOPING_LOOK_FAR, 1.0, 4.0);
        }
    }
    else if (nRoll < 70)
    {
        ClearAllActions();
        ActionPlayAnimation(ANIMATION_FIREFORGET_DRINK, 1.0);
        ActionDoCommand(CP_Belch(oPeng));
    }
    else if (nRoll < 82)
    {
        // Over it goes.
        ClearAllActions();
        ActionPlayAnimation(ANIMATION_LOOPING_PAUSE_DRUNK, 1.0, 2.0);
        ActionPlayAnimation(ANIMATION_LOOPING_DEAD_FRONT, 1.0, IntToFloat(Random(4) + 3));
        ActionDoCommand(SpeakString("*falls over*"));
    }
    else if (nRoll < 92)
    {
        ClearAllActions();
        switch (Random(4))
        {
            case 0: SpeakString("PaRtY TiMe!!"); break;
            case 1: SpeakString("Where's me drink gone?"); break;
            case 2: SpeakString("*hic*"); break;
            default: SpeakString("This is the BEST party."); break;
        }
        ActionPlayAnimation(ANIMATION_FIREFORGET_VICTORY2, 1.0);
    }
    else
    {
        ClearAllActions();
        ActionPlayAnimation(ANIMATION_LOOPING_PAUSE_TIRED, 1.0, 5.0);
    }

    DelayCommand(IntToFloat(Random(16) + 10), ExecuteScript("cp_pengai", oPeng));
}
