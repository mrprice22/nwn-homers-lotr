// mw_pet_pass -- dialogue link conditional: did the PC pass Peterson's quiz?
// Threshold: 4 of 5 correct.
int StartingConditional()
{
    return GetLocalInt(GetPCSpeaker(), "mw_pet_score") >= 4;
}
