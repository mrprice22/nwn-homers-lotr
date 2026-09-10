// cp_crown -- Crash Party: Crown of Cacophony. Wave 2. WORN item.
//
// Dispatched by cp_equip.nss / cp_unequip.nss, which set CP_WORN_ON before
// calling; OBJECT_SELF is the wearer.
//
// While it is on your head it makes a random noise every few seconds. That is
// the whole feature.
//
// ## Charges are spent per EQUIP, not per noise
//
// A charge per pulse would burn a generous-looking 300 down to fifteen minutes
// of wear, and players are never told the count, so the item would feel like it
// broke at random. One charge per time you put it on is predictable, survives
// the "use it until it breaks" promise, and makes 150 an enormous number rather
// than a stingy one.
//
// The noise chain is self-scheduling and guarded exactly like the tankard's:
// ONE chain per wearer, keyed on a timestamp rather than a flag, because
// creature locals are saved into the .bic while the DelayCommand that would
// clear a flag is not.

#include "cp_inc"

const string CP_CROWN_ON   = "CP_CROWN_ON";
const string CP_CROWN_NEXT = "CP_CROWN_NEXT";

string CP_CrownNoise()
{
    switch (Random(8))
    {
        case 0: return "as_an_rooster1";
        case 1: return "as_an_cow1";
        case 2: return "as_an_dogbark6";
        case 3: return "as_an_catscrech2";
        case 4: return "as_an_crow1";
        case 5: return "as_pl_belchingm1";
        case 6: return "as_an_owlhoot1";
    }
    return "as_an_ratssqeak1";
}

void main()
{
    object oPC = OBJECT_SELF;
    if (!GetIsPC(oPC)) return;

    // --- taken off -------------------------------------------------------
    if (!GetLocalInt(oPC, "cp_worn_on"))
    {
        if (GetLocalInt(oPC, CP_CROWN_ON))
        {
            DeleteLocalInt(oPC, CP_CROWN_ON);
            DeleteLocalInt(oPC, CP_CROWN_NEXT);
            SendMessageToPC(oPC, "The crown comes off and a merciful silence falls.");
        }
        return;
    }

    // --- put on ----------------------------------------------------------
    object oItem = CP_FindItem(oPC, "cp_crown");
    if (!GetIsObjectValid(oItem)) return;

    if (!CP_ConsumeUse(oItem, CP_ItemCharges(7),
            "The crown gives one last strangled honk and falls to pieces."))
        return;

    SetLocalInt(oPC, CP_CROWN_ON, TRUE);
    SendMessageToPC(oPC, "The crown settles onto your head and begins, quietly, to make noises.");

    if (CP_Now() >= GetLocalInt(oPC, CP_CROWN_NEXT))
    {
        int nDelay = Random(4) + 3;
        SetLocalInt(oPC, CP_CROWN_NEXT, CP_Now() + nDelay + 5);
        DelayCommand(IntToFloat(nDelay), ExecuteScript("cp_crowntick", oPC));
    }
}
