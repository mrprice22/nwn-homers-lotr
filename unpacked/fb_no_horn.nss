// StartingConditional: TRUE when the PC speaker does NOT carry the Horn of the
// Fell Beast. Fires the Kallrist forge's refusal greeting (the fallback forge
// greeting sits below it in the StartingList for horn-bearers).
int StartingConditional()
{
    return !GetIsObjectValid(GetItemPossessedBy(GetPCSpeaker(), "HornFellBeast"));
}
