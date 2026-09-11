// Action: stop the jukebox and give the area its own music back.
#include "jb_inc"

void main()
{
    JB_Stop(GetArea(GetPCSpeaker()));
}
