// graf_vis_3.nss - StartingConditional: is menu slot 3 filled this page?
// One set of nine slots serves both the category list and the appearance list;
// graf_mode says which is showing.
int StartingConditional()
{
    return GetLocalString(GetPCSpeaker(), "graf_slot_3") != "";
}
