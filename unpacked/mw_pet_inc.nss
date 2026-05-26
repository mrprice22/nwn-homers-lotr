// mw_pet_inc -- increment Peterson quiz score on a correct answer.
void main()
{
    object oPC = GetPCSpeaker();
    SetLocalInt(oPC, "mw_pet_score", GetLocalInt(oPC, "mw_pet_score") + 1);
}
