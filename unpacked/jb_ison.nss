// StartingConditional: is the jukebox currently overriding THIS area's music?
// Gates the "Stop the music" option, which is meaningless otherwise.
#include "jb_inc"

int StartingConditional()
{
    return JB_IsOn(GetArea(GetPCSpeaker()));
}
