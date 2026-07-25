// ll_leveler_gone — OnUsed for the retired legendary-leveler statue in the
// Legendary Levelling Area.
//
// Levels 41-60 are now real levels on the published XP table
// (hak_2da/exptable.2da), so the old HGLL leveler conversation is gone
// (roadmap: ll-hgll-remove-scripts). This stub replaces its OnUsed hook so the
// statue explains itself instead of silently pointing at a deleted script.
// The whole area is scheduled for removal (roadmap: ll-hgll-retire-area);
// delete this file with it.

void main()
{
    object oPC = GetLastUsedBy();
    if (!GetIsPC(oPC)) return;

    SendMessageToPC(oPC, "The statue is silent. Levels 41 to 60 are now earned "
        + "like every other level - keep gaining experience and you will level "
        + "up wherever you stand.");
}
