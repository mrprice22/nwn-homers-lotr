// mw_cam_pass -- conditional: did the PC pass Joseph Campbell's quiz? Threshold 4/5.
int StartingConditional() { return GetLocalInt(GetPCSpeaker(), "mw_cam_score") >= 4; }
