// StartingConditional: TRUE when the PC speaker carries the Horn of the Fell
// Beast (tag HornFellBeast). Gates the Kallrist Crypt forge -- the smith Kalrun
// only wakes for one who bears the horn looted from the crypt guardian.
int StartingConditional()
{
    return GetIsObjectValid(GetItemPossessedBy(GetPCSpeaker(), "HornFellBeast"));
}
