// Ferny's Return (roadmap: ferny-return) -- StartingConditional for the
// Guardian of Bree's rumor reply. Shown only before the quest has started.
// Quest state persists per character in the "fret" campaign DB (stage 0-3).
int StartingConditional()
{
    return GetCampaignInt("fret", "stage", GetPCSpeaker()) == 0;
}
