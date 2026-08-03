// bst_slot_7_vis - conditional: show bestiary list slot 7 only when populated.
int StartingConditional()
{
    return GetLocalString(GetPCSpeaker(), "bst_slot_7_resref") != "";
}
