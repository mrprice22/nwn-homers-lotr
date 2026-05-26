// mw_wat_inc -- increment Alan Watts's quiz score on a correct answer.
void main()
{
    object oPC = GetPCSpeaker();
    SetLocalInt(oPC, "mw_wat_score", GetLocalInt(oPC, "mw_wat_score") + 1);
}
