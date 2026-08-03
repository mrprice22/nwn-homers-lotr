// bst_slot_4_vis - conditional: show bestiary list slot 4 only when populated.
int StartingConditional()
{
    return GetLocalString(GetPCSpeaker(), "bst_slot_4_resref") != "";
}
