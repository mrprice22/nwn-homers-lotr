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

object   CP_DmUser();
int      CP_DmGate(object oPC);
int      CP_DmFromRestMenu();
object   CP_Venue();
object   CP_DialAnchor(object oPC);
int      CP_LoadCount(object oArea = OBJECT_INVALID);
int      CP_LoadCountFor(object oAnchor);
location CP_ScatterNear(location lAt, float fRadius = 6.0);

// Who is working the console, whichever surface they used.
//
// Every lever exists twice: as a placard in the control room (OnUsed, so
// GetLastUsedBy) and as a line in the rest menu's Admin Options (a conversation
// action, so GetPCSpeaker). One resolver means one script per lever instead of
// two that can drift apart. Same shape wm_report.nss uses.
object CP_DmUser()
{
    object oPC = GetLastUsedBy();
    if (!GetIsObjectValid(oPC)) oPC = GetPCSpeaker();
    return oPC;
}

// Which of the two surfaces pulled the lever.
//
// GetPCSpeaker() is only valid inside a conversation, which is what the rest
// menu's Admin Options is; the control-room placards are OnUsed handlers where
// it is invalid. That is the test rather than "is GetLastUsedBy valid", because
// a conversation owned by a placeable can still answer GetLastUsedBy.
int CP_DmFromRestMenu()
{
    return GetIsObjectValid(GetPCSpeaker());
}

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

// What a dial spawns AROUND, which is not the same for the two surfaces.
//
// From the control room the answer is the venue waypoint: the console is a
// windowless room the admin is standing in, so load spawned "here" would be
// invisible and would measure the wrong area.
//
// From the rest menu the admin is standing wherever they are actually testing,
// usually in the middle of the party, and walking back to a waypoint to see the
// thing they just spawned is pure friction -- so the anchor is the admin. That
// also makes the dials usable at an impromptu venue, which is the whole point of
// having the levers in the rest menu at all.
//
// Returns OBJECT_INVALID only when the console path has no waypoint to use; the
// callers report that and spawn nothing rather than dumping load in the control
// room.
object CP_DialAnchor(object oPC)
{
    if (CP_DmFromRestMenu() && GetIsObjectValid(oPC)) return oPC;
    return GetWaypointByTag("cp_venue_wp");
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
int CP_LoadCount(object oArea = OBJECT_INVALID)
{
    if (!GetIsObjectValid(oArea)) oArea = CP_Venue();
    if (!GetIsObjectValid(oArea)) return 0;

    int n = 0;
    object oObj = GetFirstObjectInArea(oArea);
    while (GetIsObjectValid(oObj))
    {
        if (CP_IsLoadTag(oObj)) n++;
        oObj = GetNextObjectInArea(oArea);
    }
    return n;
}

// The cap counts the venue AND wherever this press is aimed.
//
// The rest-menu dials can spawn away from the Well of Eru, so counting only the
// venue would hand out a fresh 400 in every room the admin walks into. Counting
// every area instead would mean walking ~287 areas twice per press, during the
// exact test whose numbers that walk would pollute -- so it is these two, which
// is where a dial has actually put anything. CLEAR ALL stays module-wide
// (cp_sweep), so nothing spawned anywhere is ever stranded.
int CP_LoadCountFor(object oAnchor)
{
    object oVenue = CP_Venue();
    object oHere  = GetArea(oAnchor);

    int n = CP_LoadCount(oVenue);
    if (GetIsObjectValid(oHere) && oHere != oVenue) n += CP_LoadCount(oHere);
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
