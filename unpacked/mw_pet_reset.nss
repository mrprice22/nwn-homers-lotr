// mw_pet_reset -- clear Peterson's quiz score (run when starting / retrying).
void main() { DeleteLocalInt(GetPCSpeaker(), "mw_pet_score"); }
