// cbd_has_prev — sign: is there a page before the current one?
#include "cbd_db"
int StartingConditional() { return GetLocalInt(GetPCSpeaker(), "cbd_off") > 0; }
