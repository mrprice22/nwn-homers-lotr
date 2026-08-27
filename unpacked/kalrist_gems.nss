// kalrist_gems - OnOpen restock for the Kallrist Crypt gem chest
// (area kallristcryptupp, placeable tag KAL_GEM_CHEST).
//
// The chest shipped with exactly one set of the four riddle gems embedded in
// the area instance and NO refill script at all, so the second party of a
// reset found it empty and the elemental-pillar puzzle was unsolvable until
// the next reboot. Roadmap: kallrist-crypt-quest-only-doable-once-per-server-
// reset. (The gem blueprints did not exist either - bluegem/greengem/redgem/
// yellowgem .uti were missing, so no script could have minted one; they were
// recreated alongside this file.)
//
// Modelled on athelasrespawn.nss, the module's quest-item OnOpen refill, with
// two deliberate differences:
//
//   * TOP-UP, NOT WIPE. athelasrespawn destroys the whole inventory and
//     recreates it. Here that would destroy anything a player parked in the
//     chest, and it would let one player open-take-open-take a fresh set of
//     four every cooldown. Instead we keep the first gem of each tag, destroy
//     only DUPLICATE gems, create only the MISSING ones, and never touch a
//     foreign item. The chest therefore holds at most one of each gem.
//   * kalrist_riddle.nss clears CS_Opened on a successful solve, so the party
//     after a solve is restocked on their next open rather than waiting out
//     the cooldown below.
//
// The gems are Cost 0 with no item properties - there is nothing to farm here.
// The cooldown only stops open-spam churn.

// Seconds between restocks. Matches athelasrespawn.nss, the existing
// precedent for refilling a quest item (~25 minutes).
const int KALG_RESPAWNTIME = 1500;

void main()
{
    // Same clock idiom as athelasrespawn / chest_respawner: seconds into the
    // game day, with the midnight-wrap guard.
    int nNow  = GetTimeSecond() + 60 * GetTimeMinute() + 3600 * GetTimeHour();
    int nLast = GetLocalInt(OBJECT_SELF, "CS_Opened");

    // Cooldown elapsed, or the game clock wrapped past midnight.
    int bReady = (nNow > nLast + KALG_RESPAWNTIME) || (nLast > nNow);
    if (!bReady) return;

    int bBlue = FALSE, bGreen = FALSE, bRed = FALSE, bYellow = FALSE;

    object oItem = GetFirstItemInInventory();
    while (GetIsObjectValid(oItem))
    {
        string sTag = GetTag(oItem);
        int bDupe = FALSE;

        if (sTag == "BlueGem")
        {
            if (bBlue) bDupe = TRUE; else bBlue = TRUE;
        }
        else if (sTag == "GreenGem")
        {
            if (bGreen) bDupe = TRUE; else bGreen = TRUE;
        }
        else if (sTag == "RedGem")
        {
            if (bRed) bDupe = TRUE; else bRed = TRUE;
        }
        else if (sTag == "YellowGem")
        {
            if (bYellow) bDupe = TRUE; else bYellow = TRUE;
        }

        // Duplicate riddle gem - the chest never holds more than one of each.
        // Anything that is not a riddle gem is left strictly alone.
        if (bDupe)
        {
            SetPlotFlag(oItem, FALSE);
            DestroyObject(oItem, 0.0);
        }

        oItem = GetNextItemInInventory();
    }

    if (!bBlue)   CreateItemOnObject("bluegem",   OBJECT_SELF, 1);
    if (!bGreen)  CreateItemOnObject("greengem",  OBJECT_SELF, 1);
    if (!bRed)    CreateItemOnObject("redgem",    OBJECT_SELF, 1);
    if (!bYellow) CreateItemOnObject("yellowgem", OBJECT_SELF, 1);

    SetLocalInt(OBJECT_SELF, "CS_Opened", nNow);
}
