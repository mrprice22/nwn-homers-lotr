void main() {
    object oPC = GetPCSpeaker();
    object oNPC = OBJECT_SELF;
    SetLocalObject(oPC, "ZEP_CR_NPC", oNPC);
    // Store the PC on the NPC so EndConverAbort can find it (GetPCSpeaker() is invalid there)
    SetLocalObject(oNPC, "ZEP_CR_PC", oPC);
    AssignCommand(oPC, ActionStartConversation(oNPC, "x0_skill_ctrap", TRUE, FALSE));
}
