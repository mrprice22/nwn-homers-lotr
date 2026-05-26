// mw_aur_pass -- conditional: did the PC pass Marcus Aurelius's quiz? Threshold 4/5.
int StartingConditional() { return GetLocalInt(GetPCSpeaker(), "mw_aur_score") >= 4; }
