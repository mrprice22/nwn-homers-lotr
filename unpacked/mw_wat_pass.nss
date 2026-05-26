// mw_wat_pass -- conditional: did the PC pass Alan Watts's quiz? Threshold 4/5.
int StartingConditional() { return GetLocalInt(GetPCSpeaker(), "mw_wat_score") >= 4; }
