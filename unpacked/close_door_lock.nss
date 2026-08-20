// close_door_lock - OnOpen auto-close + re-lock for locked doors, on the short
// delay. The lock hangs off the door actually being shut. See door_inc.nss.
//
// Only ever assign this to a door whose key SURVIVES the unlock. A door with
// AutoRemoveKey set eats the key on first use, so re-locking it strands the
// player behind a lock they can no longer open; those get plain close_door.
#include "door_inc"

void main()
{
    DoorAutoClose(5.0, TRUE);
}
