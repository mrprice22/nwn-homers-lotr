// bst_slot_5_vis - conditional: show bestiary list slot 5 only when populated.
int StartingConditional()
{
    return GetLocalString(GetPCSpeaker(), "bst_slot_5_resref") != "";
}
