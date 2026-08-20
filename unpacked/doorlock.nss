// doorlock - OnOpen auto-close + re-lock, module baseline delay.
// The lock hangs off the door actually being shut, so it can never end up
// standing open AND locked. See door_inc.nss.
#include "door_inc"

void main()
{
    DoorAutoClose(8.0, TRUE);
}
