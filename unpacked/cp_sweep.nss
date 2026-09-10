// cp_sweep -- Crash Party: destroy every DM-spawned load object.
//
// Called from the DM console's CLEAR ALL lever and once from onmoduleload.nss
// (so a crash or restart mid-event cannot strand a field of debris).
//
// ## What this does NOT do
//
// It NEVER touches a player's inventory. Chaos items handed out at the party are
// the player's to keep forever -- there is no reclaim, no expiry at the end of
// the event, and no code path anywhere that removes one. The ONLY thing that
// removes a cp_* item is that item spending its last charge, in its owner's own
// hands. Keep the filter below exactly as narrow as it is: tag equality against
// CP_LOAD_TAG, creatures and placeables only.
//
// Returns nothing; writes the count to the caller via a module local so the
// console can report it.

#include "cp_inc"

void main()
{
    int nKilled = 0;

    object oArea = GetFirstArea();
    while (GetIsObjectValid(oArea))
    {
        object oObj = GetFirstObjectInArea(oArea);
        while (GetIsObjectValid(oObj))
        {
            object oNext = GetNextObjectInArea(oArea);   // step before destroying

            if (CP_IsLoadTag(oObj))
            {
                int nType = GetObjectType(oObj);
                if (nType == OBJECT_TYPE_CREATURE || nType == OBJECT_TYPE_PLACEABLE)
                {
                    SetPlotFlag(oObj, FALSE);
                    // 4th arg matters: without it this defaults to OBJECT_SELF
                    // (the module) and silently does nothing to the target.
                    SetIsDestroyable(TRUE, FALSE, FALSE, oObj);
                    DestroyObject(oObj);
                    nKilled++;
                }
            }

            oObj = oNext;
        }
        oArea = GetNextArea();
    }

    SetLocalInt(GetModule(), "CP_SWEPT", nKilled);
}
