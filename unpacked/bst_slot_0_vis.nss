// bst_slot_0_vis - conditional: show bestiary list slot 0 only when populated.
int StartingConditional()
{
    return GetLocalString(GetPCSpeaker(), "bst_slot_0_resref") != "";
}
