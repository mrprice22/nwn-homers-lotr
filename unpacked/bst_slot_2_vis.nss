// bst_slot_2_vis - conditional: show bestiary list slot 2 only when populated.
int StartingConditional()
{
    return GetLocalString(GetPCSpeaker(), "bst_slot_2_resref") != "";
}
