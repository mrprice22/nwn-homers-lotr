// close_door_lock - OnOpen auto-close + re-lock for locked doors. Same retrying
// close as close_door (see that script for why a single ActionCloseDoor is not
// enough), but the SetLocked hangs off the door actually being shut.
//
// The old body was DelayCommand(2.0, ActionCloseDoor) + DelayCommand(2.5,
// SetLocked). Those two are independent, so a close that failed against a
// blocked doorway still locked the door - leaving it standing open AND locked,
// which then refuses to close normally. Locking only once GetIsOpen is FALSE
// makes that state unreachable.
//
// Only ever assign this to a door whose key SURVIVES the unlock. A door with
// AutoRemoveKey set eats the key on first use, so re-locking it strands the
// player behind a lock they can no longer open; those get plain close_door.

void TryClose(int nLeft);

void TryClose(int nLeft)
{
    if (!GetIsOpen(OBJECT_SELF))
    {
        // Shut - safe to re-lock.
        SetLocked(OBJECT_SELF, TRUE);
        return;
    }

    ClearAllActions();
    ActionCloseDoor(OBJECT_SELF);

    if (nLeft > 0) DelayCommand(6.0, TryClose(nLeft - 1));
}

void main()
{
    DelayCommand(2.0, TryClose(5));
}
