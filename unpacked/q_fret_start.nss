// Ferny's Return (roadmap: ferny-return) -- the player accepts the Guardian
// of Bree's request to investigate Bill Ferny's house. Persists per character
// (campaign DB "fret") and spawns the impostor at the admin-placed waypoint.
void main()
{
    object oPC = GetPCSpeaker();
    if (GetCampaignInt("fret", "stage", oPC) == 0)
    {
        SetCampaignInt("fret", "stage", 1, oPC);
        AddJournalQuestEntry("ferny_return", 1, oPC, FALSE, FALSE);
    }

    // Spawn the impostor in billfernyshouse. No-ops gracefully until the
    // admin places waypoint AP_ferny_return_1 (see admin-action-required.md),
    // and never double-spawns.
    object oWP = GetWaypointByTag("AP_ferny_return_1");
    if (GetIsObjectValid(oWP) && !GetIsObjectValid(GetObjectByTag("fret_impostor")))
        CreateObject(OBJECT_TYPE_CREATURE, "fret_impostor", GetLocation(oWP));
}
