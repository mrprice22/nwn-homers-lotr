// mw_mck_inc -- increment Terence McKenna's quiz score on a correct answer.
void main()
{
    object oPC = GetPCSpeaker();
    SetLocalInt(oPC, "mw_mck_score", GetLocalInt(oPC, "mw_mck_score") + 1);
}
