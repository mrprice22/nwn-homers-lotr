//::///////////////////////////////////////////////
//:: sc_glsn_have
//:: Gloison's Heirloom - turn-in gate.
//:: Returns TRUE when the speaking PC carries the stolen
//:: heirloom (item tag "GloisonsFamilyStone").
//:://////////////////////////////////////////////
int StartingConditional()
{
    return GetIsObjectValid(GetItemPossessedBy(GetPCSpeaker(), "GloisonsFamilyStone"));
}
