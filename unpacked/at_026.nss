//::///////////////////////////////////////////////
//:: FileName at_026
//:://////////////////////////////////////////////
//:://////////////////////////////////////////////
//:: Created By: Script Wizard
//:: Created On: 10/8/2002 1:59:18 AM
//:://////////////////////////////////////////////
void main()
{
    object oPC = GetPCSpeaker();

    // Verify both items are present before taking either.
    // Players can drop items between the dialog condition check and clicking this
    // node - taking one then failing on the other would be an exploit.
    object oHelm = GetItemPossessedBy(oPC, "HelmoftheWarlord");
    object oHead = GetItemPossessedBy(oPC, "MutantsHead");

    if (!GetIsObjectValid(oHelm))
    {
        FloatingTextStringOnCreature(
            "Oops! It looks like you're missing the Helm of the Warlord.", oPC, FALSE);
        return;
    }
    if (!GetIsObjectValid(oHead))
    {
        FloatingTextStringOnCreature(
            "Oops! It looks like you're missing The Mutant's Head.", oPC, FALSE);
        return;
    }

    // Both confirmed present - take them and set the flag for at_024.
    DestroyObject(oHelm);
    DestroyObject(oHead);
    SetLocalInt(oPC, "elrond_gave_items", 1);
}
