// bst_slot_1_vis - conditional: show bestiary list slot 1 only when populated.
int StartingConditional()
{
    return GetLocalString(GetPCSpeaker(), "bst_slot_1_resref") != "";
}
