// StartingConditional on the jukebox's one entry node.
//
// Builds the menu here rather than in an action script because a conditional is
// evaluated BEFORE the node's text is rendered -- which is what guarantees the
// <CUSTOM70xx> tokens are populated by the time the player reads them, both on
// the first open and on every loop back after a selection.
#include "jb_inc"

int StartingConditional()
{
    JB_BuildMenu(GetPCSpeaker());
    return TRUE;
}
