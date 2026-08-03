// bst_slot_3_vis - conditional: show bestiary list slot 3 only when populated.
int StartingConditional()
{
    return GetLocalString(GetPCSpeaker(), "bst_slot_3_resref") != "";
}
