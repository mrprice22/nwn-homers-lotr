// sc_delay_lock - OnOpen auto-close + re-lock on a short delay.
// The lock hangs off the door actually being shut. See door_inc.nss.
#include "door_inc"

void main()
{
    DoorAutoClose(6.0, TRUE);
}
