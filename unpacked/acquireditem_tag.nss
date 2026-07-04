#include "nw_i0_plotwizard"
#include "bdm_include"
#include "inc_partyloot"
void main()
{
    // PLOT WIZARD MANAGED CODE BEGINS
    // PLOT WIZARD MANAGED CODE ENDS
    object oItem = GetModuleItemAcquired();

    if (GetIsPC(GetItemPossessor(oItem)))
    {
        SetLocalInt(oItem, "PCItem", 1);
    }
    BDM_ModuleItemAcquired();

    // Party loot roll: if a PC picks up a valuable item with other eligible
    // party members in the area, prompt a Need/Greed/Pass NUI roll.
    PL_OnItemAcquired();

    // Glorfindel's Curative: advance the journal as each of the three
    // ingredients is collected. Count-based so any pickup order works.
    string sTag = GetTag(oItem);
    if (sTag == "Athelas" || sTag == "StonefromArathorn" || sTag == "EssenseofIceDrake")
    {
        object oPC = GetModuleItemAcquiredBy();
        if (GetIsPC(oPC) && GetLocalInt(oPC, "glorquestgiven") == 1)
        {
            int nCount = 0;
            if (GetIsObjectValid(GetItemPossessedBy(oPC, "Athelas")))            nCount++;
            if (GetIsObjectValid(GetItemPossessedBy(oPC, "StonefromArathorn")))  nCount++;
            if (GetIsObjectValid(GetItemPossessedBy(oPC, "EssenseofIceDrake")))  nCount++;
            if (nCount >= 1 && nCount <= 3)
                AddJournalQuestEntry("glorfindel_potion", nCount + 1, oPC, FALSE, FALSE);
        }
    }

    // Paths of the Dead: acquiring the Flame of the West (Tag "narsil") by
    // looting it -- rather than receiving it honourably from Aragorn -- records
    // the "took it by force" path. The honourable grant (q_potd_reward) sets a
    // transient flag we consume here so it is not double-counted.
    if (GetTag(oItem) == "narsil")
    {
        object oPC = GetModuleItemAcquiredBy();
        if (GetIsPC(oPC))
        {
            if (GetLocalInt(oPC, "potd_honourable"))
            {
                DeleteLocalInt(oPC, "potd_honourable");
            }
            else if (GetCampaignInt("potd", "granted", oPC) == 0)
            {
                SetCampaignInt("potd", "granted", 1, oPC);
                AddJournalQuestEntry("paths_of_the_dead", 30, oPC, FALSE, FALSE);
            }
        }
    }
}
