// mw_joc_pass -- conditional: did the PC pass Jocko Willink's quiz? Threshold 4/5.
int StartingConditional() { return GetLocalInt(GetPCSpeaker(), "mw_joc_score") >= 4; }
