#include "zep_inc_craft"

void main() {
    // In EndConverAbort context GetPCSpeaker() returns OBJECT_INVALID.
    // Fall back to the reference stored on the NPC, then to OBJECT_SELF
    // for placeable/self-conversation sessions where OBJECT_SELF is the PC.
    object oPC = GetPCSpeaker();
    if (!GetIsObjectValid(oPC))
        oPC = GetLocalObject(OBJECT_SELF, "ZEP_CR_PC");
    if (!GetIsObjectValid(oPC) && GetIsPC(OBJECT_SELF))
        oPC = OBJECT_SELF;
    ZEP_StopCraft(oPC, FALSE);
}
