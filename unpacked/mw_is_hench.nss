// mw_is_hench -- dialogue Active conditional.
// Returns TRUE only when the NPC is currently summoned as a henchman.
int StartingConditional()
{
    return GetIsObjectValid(GetMaster());
}
