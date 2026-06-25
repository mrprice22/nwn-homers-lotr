// Show the "strike the planned enchantments" commit reply only when the plan is
// non-empty AND the planned result would be lawful (worth within the player's
// effective ceiling and at most the legal property count). This is what keeps a
// forge from ever producing an illegal item.
#include "forge_inc"

int StartingConditional()
{
    object oPC = GetPCSpeaker();
    return ForgeStagePlanIsLawful(oPC, GetLocalObject(oPC, "FORGE_STG_ITEM"));
}
