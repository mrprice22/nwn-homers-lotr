// mw_jun_pass -- conditional: did the PC pass Carl Jung's quiz? Threshold 4/5.
int StartingConditional() { return GetLocalInt(GetPCSpeaker(), "mw_jun_score") >= 4; }
