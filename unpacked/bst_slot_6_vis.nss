// bst_slot_6_vis - conditional: show bestiary list slot 6 only when populated.
int StartingConditional()
{
    return GetLocalString(GetPCSpeaker(), "bst_slot_6_resref") != "";
}
