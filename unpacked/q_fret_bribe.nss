// Ferny's Return -- the player takes the impostor's bribe (Ferny's stash
// coin) instead of fighting. Advances to stage 2 with outcome "bribed"; the
// impostor slips out of Bree shortly after the deal is struck.
void main()
{
    object oPC = GetPCSpeaker();
    if (GetCampaignInt("fret", "stage", oPC) == 1)
    {
        SetCampaignInt("fret", "stage", 2, oPC);
        SetCampaignInt("fret", "outcome", 2, oPC);
        AddJournalQuestEntry("ferny_return", 2, oPC, FALSE, FALSE);
    }
    GiveGoldToCreature(oPC, 75);

    // He keeps his word about one thing: he's gone.
    DestroyObject(OBJECT_SELF, 8.0);
}
