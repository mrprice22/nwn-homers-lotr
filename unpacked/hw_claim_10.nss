// hw_claim_10 - hw_board.dlg reply: the PC picks hw26_ring. hw_board_claim does
// every check and the hand-over.
void main()
{
    object oPC = GetPCSpeaker();
    SetLocalString(oPC, "hw_pick", "hw26_ring");
    ExecuteScript("hw_board_claim", oPC);
}
