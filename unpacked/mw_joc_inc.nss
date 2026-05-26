// mw_joc_inc -- increment Jocko Willink's quiz score on a correct answer.
void main()
{
    object oPC = GetPCSpeaker();
    SetLocalInt(oPC, "mw_joc_score", GetLocalInt(oPC, "mw_joc_score") + 1);
}
