// Action: stop the jukebox and give the area its own music back.
//
// This clears the room's QUEUE as well as silencing it. Calling JB_Stop alone
// would look broken from the admin's side: the paid queue would still be there
// and the next reconcile - the next person to walk up to the placeable - would
// start it playing again. An admin stopping a room means the room stops.
//
// Nothing is refunded. That is a deliberate gap and not an oversight: this is
// an admin override, it is not reachable by a player, and a refund path would
// need to decide what a half-played song is worth.
#include "jb_db"

void main()
{
    JB_ClearQueue(GetArea(GetPCSpeaker()));
}
