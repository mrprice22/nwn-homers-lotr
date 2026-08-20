// close_door - OnOpen auto-close for ordinary doors. Shuts the door after the
// module baseline delay and KEEPS TRYING until it is actually shut.
// Implementation and the reasoning behind it: door_inc.nss.
#include "door_inc"

void main()
{
    DoorAutoClose(8.0);
}
