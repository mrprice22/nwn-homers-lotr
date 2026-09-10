// trashfairy -- the Well of Eru's litter picker. Creature heartbeat.
//
// The Well is the module's hub: everyone passes through it, all day, and
// whatever gets left on its floor stays there until a reboot. One plot,
// DM-speed, commoner-faction fairy walks the room picking things up. Originally
// (Undead Waiter, 2002) that was the whole script -- nearest ITEM, walk, pick
// up, destroy.
//
// ## What it was missing: the bags
//
// It only ever looked at OBJECT_TYPE_ITEM, and most of the mess in a busy hub is
// not loose items. When a container is destroyed -- a smashed Crash Party ale
// barrel, a looted crate -- the engine does not scatter its contents on the
// floor, it drops a CONTAINER PLACEABLE holding them, tagged "BodyBag". Same for
// anything that dies carrying droppable gear. The fairy walked straight past
// every one of them, so a party that smashed thirty barrels left thirty bags
// standing in the hub until the next reboot.
//
// "BodyBag" is the engine's exact tag for these, which is why d_cleartrash.nss,
// s_cleartrash.nss and cleanup.nss all key on that one string, and why
// Jasperre's AI declares it as BODY_BAG "exact tag of default body bags". If a
// bag ever slips past this, check its tag before widening the test: matching
// "any placeable with an inventory" would eat house chests, the forge's staging
// containers and every merchant crate in the room.
//
// ## Two speeds, because a party is not a normal Tuesday
//
// Walking to one object per heartbeat is the charm of the thing, and it is also
// completely inadequate to a room with two hundred pieces of debris in it: at
// six seconds each she would still be tidying up tomorrow. So above
// TF_BULK_AT pieces of litter she stops walking and clears them where they
// stand, up to TF_BULK_MAX a beat, with a puff of smoke each. Below it she goes
// back to strolling.
//
// The litter count comes from the PREVIOUS heartbeat (TF_BULK on herself), so
// each beat is a single bounded pass over the area rather than one pass to count
// and another to act. Six seconds of staleness in a decision about tidying is
// not a problem worth a second scan.
//
// ## What counts as litter: it is on the FLOOR, or it is a bag
//
// An item with a possessor is not litter. The area object list includes items
// that are inside containers, so a bare "nearest item" test reaches into the
// Donations Chest (x2_easy_Chest2ff) and the chest beside it and quietly empties
// them, one item per heartbeat, with nobody watching. GetItemPossessor is the
// whole guard: valid means it is in a chest or on somebody, and it is not hers.
//
// That is a structural test rather than a list of protected tags on purpose --
// a new chest in the hub is protected the day it is placed, without anyone
// remembering to come back here.
//
// ## Two things it must not touch
//
// * Anything tagged cp_load* -- the Crash Party stress dials' spawned load. The
//   dials are a measurement, and a fairy quietly deleting the thing being
//   measured would make the numbers a lie. CLEAR ALL owns that cleanup.
// * A bag younger than TF_BAG_GRACE beats. Somebody killed something and is
//   walking over to loot it; snatching it out from under them is worse than the
//   litter. Loose items keep the original instant policy -- that behaviour is
//   old, understood, and players already treat this floor as a bin.
//
// She also honours the module-wide CT_DISABLED switch, the same one
// d_cleartrash.nss and s_cleartrash.nss read, so one flag stands every cleaner
// in the module down at once. That is the flag to set before a measured run: the
// scan itself is bounded and cheap, but a load test wants nothing else touching
// the room.
//
// The scan is capped at TF_SCAN_MAX objects a beat. The cap is generous rather
// than tight on purpose -- a stepping test on an object is nearly free, while a
// cap low enough to sit inside a crowded hub would let a few hundred barrels at
// the front of the list starve the bags behind them forever.

const string TF_AGE  = "TF_AGE";        // heartbeats a given bag has been sat there
const string TF_BULK = "TF_BULK";       // was the room a tip last beat?

const int TF_BAG_GRACE = 10;            // ~1 minute at a 6s heartbeat
const int TF_SCAN_MAX  = 400;           // objects examined per beat, hard bound
const int TF_BULK_AT   = 15;            // litter count that switches to bulk mode
const int TF_BULK_MAX  = 25;            // removals per beat in bulk mode

// Never-touch list.
//
// cp_load* is the Crash Party stress dials' spawned load (prefix test, so a new
// kind of load object is protected the moment it is added -- same rule and same
// reason as CP_IsLoadTag).
//
// The plot flag is the other one: a plot item lying on the floor is far more
// likely to be a quest item somebody fumbled than it is to be rubbish, and the
// fairy destroying it is unrecoverable. She leaves it where it is.
int TF_IsProtected(object oObj)
{
    if (GetStringLeft(GetTag(oObj), 7) == "cp_load") return TRUE;
    if (GetPlotFlag(oObj)) return TRUE;
    return FALSE;
}

// A bag holding a plot item is left alone entirely -- same reasoning as the plot
// flag above, one level down. Emptying the rest and leaving the item on the floor
// would be tidier and would also be the fairy deciding, on her own, to unpack
// somebody's quest reward.
int TF_HoldsPlotItem(object oBag)
{
    object oItem = GetFirstItemInInventory(oBag);
    while (GetIsObjectValid(oItem))
    {
        if (GetPlotFlag(oItem)) return TRUE;
        oItem = GetNextItemInInventory(oBag);
    }
    return FALSE;
}

// Destroy a bag and everything in it. DestroyObject on a container leaves its
// contents to the engine, which is how one bag becomes several.
void TF_Trash(object oObj)
{
    if (GetObjectType(oObj) == OBJECT_TYPE_PLACEABLE)
    {
        object oItem = GetFirstItemInInventory(oObj);
        while (GetIsObjectValid(oItem))
        {
            object oNext = GetNextItemInInventory(oObj);   // step before destroying
            SetPlotFlag(oItem, FALSE);
            DestroyObject(oItem);
            oItem = oNext;
        }
    }
    SetPlotFlag(oObj, FALSE);
    DestroyObject(oObj);
}

void main()
{
    if (GetLocalInt(GetModule(), "CT_DISABLED")) return;

    object oSelf = OBJECT_SELF;
    int bBulk = GetLocalInt(oSelf, TF_BULK);

    int nSeen = 0, nLitter = 0, nCleared = 0;
    object oTarget = OBJECT_INVALID;
    float fBest = 0.0;

    object oObj = GetFirstObjectInArea();
    while (GetIsObjectValid(oObj) && nSeen < TF_SCAN_MAX)
    {
        object oNext = GetNextObjectInArea();   // step before anything is destroyed
        nSeen++;

        int nType = GetObjectType(oObj);
        int bIsBag = (nType == OBJECT_TYPE_PLACEABLE && GetTag(oObj) == "BodyBag");

        if ((nType != OBJECT_TYPE_ITEM && !bIsBag) || TF_IsProtected(oObj))
        {
            oObj = oNext;
            continue;
        }

        // In a chest, in a bag, or in somebody's pack: not litter, not hers.
        if (nType == OBJECT_TYPE_ITEM && GetIsObjectValid(GetItemPossessor(oObj)))
        {
            oObj = oNext;
            continue;
        }

        // Bags get their grace period; loose items are fair game on sight.
        if (bIsBag)
        {
            if (TF_HoldsPlotItem(oObj))
            {
                oObj = oNext;
                continue;
            }

            int nAge = GetLocalInt(oObj, TF_AGE) + 1;
            SetLocalInt(oObj, TF_AGE, nAge);
            if (nAge < TF_BAG_GRACE)
            {
                oObj = oNext;
                continue;
            }
        }

        nLitter++;

        if (bBulk)
        {
            if (nCleared < TF_BULK_MAX)
            {
                ApplyEffectAtLocation(DURATION_TYPE_INSTANT,
                    EffectVisualEffect(VFX_FNF_SMOKE_PUFF), GetLocation(oObj));
                TF_Trash(oObj);
                nCleared++;
            }
        }
        else
        {
            float fDist = GetDistanceBetween(oSelf, oObj);
            if (!GetIsObjectValid(oTarget) || fDist < fBest)
            {
                oTarget = oObj;
                fBest = fDist;
            }
        }

        oObj = oNext;
    }

    SetLocalInt(oSelf, TF_BULK, nLitter > TF_BULK_AT);

    if (bBulk || !GetIsObjectValid(oTarget)) return;

    // Only order her about when she is idle. Actions QUEUE, and a heartbeat is
    // faster than a walk across the Well -- the original script posted a fresh
    // walk every six seconds whether or not she had finished the last one, so
    // the queue grew and she spent the evening fetching things that had already
    // been picked up.
    if (GetCurrentAction(oSelf) != ACTION_INVALID) return;

    // The original behaviour otherwise, now with bags in scope: walk over, and
    // pick an item up before destroying it so she is visibly the one who took it.
    ActionMoveToObject(oTarget);
    if (GetObjectType(oTarget) == OBJECT_TYPE_ITEM)
    {
        ActionPickUpItem(oTarget);
        ActionDoCommand(DestroyObject(oTarget));
    }
    else
    {
        ActionDoCommand(TF_Trash(oTarget));
    }
}
