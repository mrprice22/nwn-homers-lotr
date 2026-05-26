// * Takes eggs from player
#include "m3plotinclude"
void main()
{
    object oPC = GetPCSpeaker();

    // Anti-exploit: player can drop eggs mid-conversation to keep them.
    if (!PlayerHasEggs(oPC))
    {
        FloatingTextStringOnCreature(
            "You must have the dragon eggs in your possession.", oPC, FALSE);
        return;
    }

    SetLocalInt(GetModule(), "NW_G_M3Q04PLOTKLAUTH", 99);
    SetLocalObject(OBJECT_SELF, "M3Q04CKLAUTHPLOT", oPC);
    TakeEggs(oPC);
    CreateItemOnObject("M3Q04H07_Lock", oPC);
    AddJournalQuestEntry("M3Q04_H07_KLAU", 20, oPC);
    SetLocalInt(OBJECT_SELF, "NW_G_M3Q4HC_1EGG", 1);
}
