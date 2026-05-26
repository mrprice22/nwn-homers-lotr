// mw_aur_inc -- increment Marcus Aurelius's quiz score on a correct answer.
void main()
{
    object oPC = GetPCSpeaker();
    SetLocalInt(oPC, "mw_aur_score", GetLocalInt(oPC, "mw_aur_score") + 1);
}
