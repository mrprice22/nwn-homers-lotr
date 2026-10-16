// hw_claim_7 - hw_board.dlg reply: the PC picks hw26_lantern. hw_board_claim does
// every check and the hand-over.
void main()
{
    object oPC = GetPCSpeaker();
    SetLocalString(oPC, "hw_pick", "hw26_lantern");
    ExecuteScript("hw_board_claim", oPC);
}
