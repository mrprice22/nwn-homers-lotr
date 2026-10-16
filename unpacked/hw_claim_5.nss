// hw_claim_5 - hw_board.dlg reply: the PC picks hw26_shroud. hw_board_claim does
// every check and the hand-over.
void main()
{
    object oPC = GetPCSpeaker();
    SetLocalString(oPC, "hw_pick", "hw26_shroud");
    ExecuteScript("hw_board_claim", oPC);
}
