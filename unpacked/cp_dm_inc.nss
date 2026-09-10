// cp_dm_inc -- Crash Party: shared plumbing for the DM control-room console.
//
// Every lever in the control room routes through CP_DmGate() first. The console's
// EXISTING billboards (dmpc, dm_block_char) are ungated legacy that rely on the
// area being unreachable; nothing new is built that way. Gate pattern copied from
// hm_cheat_chest.nss.
//
// ## The stress dials
//
// These, not the player items, are the actual load test. Ten people with wands is
// a normal Saturday on this box; a dial you can turn up one notch at a time and
// switch off instantly is what produces an attributable number. That matches the
// runbook's "add load in steps rather than all at once" (CLAUDE-crash-party.md).
//
// Every dial is HARD CAPPED and everything it spawns carries CP_LOAD_TAG, so one
// lever removes all of it. Load creatures are spawned with NO_LEASH so they are
// not bounced home by leash_to_area, and carry nothing droppable and nothing
// real -- a pickpocketable spawned NPC is the classic duplication bug.

#include "cp_inc"
#include "admin_db"

const int CP_DIAL_STEP = 25;    // objects added per press
const int CP_DIAL_CAP  = 400;   // total live cp_load objects, all dials combined

int      CP_DmGate(object oPC);
object   CP_Venue();
int      CP_LoadCount();
location CP_ScatterNear(location lAt, float fRadius = 6.0);

// TRUE means "allowed"; sends the refusal itself when not.
int CP_DmGate(object oPC)
{
    if (!GetIsObjectValid(oPC) || !GetIsPC(oPC)) return FALSE;
    if (GetIsDM(oPC)) return TRUE;
    if (Admin_CanAdmin(oPC)) return TRUE;
    SendMessageToPC(oPC, "That console does not answer to you.");
    return FALSE;
}

// Where load is spawned: the party venue, resolved by tag so it is not hardcoded
// to a position. The Well of Eru is chosen because it is the hub AND because it
// is not one of the 65 areas running d_cleartrash.nss, which sweeps every object
// in the area for every object that enters, with no GetIsPC guard -- spawning
// hundreds of objects into one of those would measure the sweep, not the server.
object CP_Venue()
{
    return GetObjectByTag("TheWellofEru");
}

// COUNT THE OBJECTS, do not trust a tally.
//
// A running counter drifts: anything that removes a load object by a route other
// than the CLEAR ALL lever -- an area cleanup, a DM deleting one by hand, a
// script that tidies placeables -- leaves the tally high. Drift in this
// direction is the bad direction: the cap starts refusing to spawn while the
// venue is visibly empty, mid-event, with no way to explain it.
//
// Walking one area per press is cheap (it happens on a lever press, not a
// frame), it is always right, and it makes the number cp_count reports the
// actual number of things standing in the venue.
int CP_LoadCount()
{
    object oArea = CP_Venue();
    if (!GetIsObjectValid(oArea)) return 0;

    int n = 0;
    object oObj = GetFirstObjectInArea(oArea);
    while (GetIsObjectValid(oObj))
    {
        if (GetTag(oObj) == CP_LOAD_TAG) n++;
        oObj = GetNextObjectInArea(oArea);
    }
    return n;
}

// Spread spawned load around the venue instead of stacking it on one point.
//
// Not cosmetic: a heap of objects sharing one position is not the load a real
// crowd produces. Scattered objects sit in different tiles, wake different parts
// of the AI update list and give the pathing code something to do, which is
// closer to what the dial is meant to be simulating.
location CP_ScatterNear(location lAt, float fRadius = 6.0)
{
    object oArea = GetAreaFromLocation(lAt);
    vector v = GetPositionFromLocation(lAt);
    float fAng = IntToFloat(Random(360));
    float fDist = fRadius * IntToFloat(Random(100)) / 100.0;
    v.x += fDist * cos(fAng);
    v.y += fDist * sin(fAng);
    return Location(oArea, v, IntToFloat(Random(360)));
}
