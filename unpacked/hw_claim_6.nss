// hw_claim_6 - hw_board.dlg reply: the PC picks hw26_gaunt. hw_board_claim does
// every check and the hand-over.
void main()
{
    object oPC = GetPCSpeaker();
    SetLocalString(oPC, "hw_pick", "hw26_gaunt");
    ExecuteScript("hw_board_claim", oPC);
}
