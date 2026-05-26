// mw_joc_reset -- clear Jocko Willink's quiz score (run on accept reply).
void main() { DeleteLocalInt(GetPCSpeaker(), "mw_joc_score"); }
