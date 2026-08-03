// bst_slot_8_vis - conditional: show bestiary list slot 8 only when populated.
int StartingConditional()
{
    return GetLocalString(GetPCSpeaker(), "bst_slot_8_resref") != "";
}
