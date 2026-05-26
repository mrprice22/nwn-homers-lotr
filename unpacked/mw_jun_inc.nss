// mw_jun_inc -- increment Carl Jung's quiz score on a correct answer.
void main()
{
    object oPC = GetPCSpeaker();
    SetLocalInt(oPC, "mw_jun_score", GetLocalInt(oPC, "mw_jun_score") + 1);
}
