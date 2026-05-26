// mw_cam_inc -- increment Joseph Campbell's quiz score on a correct answer.
void main()
{
    object oPC = GetPCSpeaker();
    SetLocalInt(oPC, "mw_cam_score", GetLocalInt(oPC, "mw_cam_score") + 1);
}
