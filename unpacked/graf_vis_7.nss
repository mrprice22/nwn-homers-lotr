// graf_vis_7.nss - StartingConditional: is menu slot 7 filled this page?
// One set of nine slots serves both the category list and the appearance list;
// graf_mode says which is showing.
int StartingConditional()
{
    return GetLocalString(GetPCSpeaker(), "graf_slot_7") != "";
}
