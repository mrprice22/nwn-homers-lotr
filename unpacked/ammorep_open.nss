// Quiver of Endless Flight: activation entry point, dispatched by tag from
// dmfi_activate.nss (Mod_OnActvtItem).
//
// Primes the menu cues HERE, before ActionStartConversation, because the root
// entry's text is rendered before any script on the entry itself would run -
// the same ordering trap documented in forge_stg_open.nss.
#include "ammorep_inc"

void main()
{
    object oPC = OBJECT_SELF;
    if (!GetIsPC(oPC)) return;

    object oQuiver = AmmoRep_GetQuiver(oPC);
    if (!GetIsObjectValid(oQuiver)) return;

    if (AmmoRep_UsesLeft(oQuiver) < 1)
    {
        DestroyObject(oQuiver);
        FloatingTextStringOnCreature(
            "The quiver is spent; it crumbles to dust.", oPC, FALSE);
        return;
    }

    AmmoRep_Scan(oPC);
    AssignCommand(oPC,
        ActionStartConversation(oPC, "ammorep_conv", TRUE, FALSE));
}
