void main()
{
    object oPC = GetPCSpeaker();

    // Anti-exploit: verify the ring is still in inventory before granting a reward.
    // Dropping the ring before clicking this reply would otherwise yield the reward
    // without consuming the item.
    int bFoundRing = FALSE;
    object CI = GetFirstItemInInventory(oPC);
    while (GetIsObjectValid(CI))
    {
        if (GetTag(CI) == "StolenRing")
        {
            DestroyObject(CI);
            bFoundRing = TRUE;
        }
        CI = GetNextItemInInventory(oPC);
    }

    if (!bFoundRing)
    {
        FloatingTextStringOnCreature(
            "You must have the stolen ring in your possession.", oPC, FALSE);
        return;
    }

    int Chooser = d3(1);
    SetLocalInt(oPC, "gdreward", Chooser);
}
