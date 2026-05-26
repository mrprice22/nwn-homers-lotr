//::///////////////////////////////////////////////
//:: FileName at_kashan04
//:://////////////////////////////////////////////
//:://////////////////////////////////////////////
//:: Created By: Script Wizard
//:: Created On: 10/26/02 11:05:55 AM
//:://////////////////////////////////////////////
void main()
{
    object oPC = GetPCSpeaker();

    // Anti-exploit: only mark delivery successful if the item is actually present.
    // at_071 checks kashan_gave_item before granting the reward.
    object oItemToTake = GetItemPossessedBy(oPC, "Troyspin");
    if (!GetIsObjectValid(oItemToTake))
    {
        FloatingTextStringOnCreature(
            "You must have the item in your possession.", oPC, FALSE);
        return;
    }

    DestroyObject(oItemToTake);
    SetLocalInt(oPC, "kashan_gave_item", 1);
}
