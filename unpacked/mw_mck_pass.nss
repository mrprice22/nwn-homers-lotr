// mw_mck_pass -- conditional: did the PC pass Terence McKenna's quiz? Threshold 4/5.
int StartingConditional() { return GetLocalInt(GetPCSpeaker(), "mw_mck_score") >= 4; }
