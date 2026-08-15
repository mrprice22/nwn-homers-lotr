// close_door - OnOpen auto-close for doors. Shuts the door a few seconds after
// it is opened, and KEEPS TRYING until it is actually shut.
//
// The old body was a bare DelayCommand(5.0, ActionCloseDoor(OBJECT_SELF)). That
// queues the close exactly once, and ActionCloseDoor FAILS SILENTLY when a
// creature is standing in the doorway - the action is dropped and the door then
// stays open until somebody closes it by hand. On a quiet server nothing is ever
// in the frame and it looks like it works; on a populated one the same door in
// the same build stays open. That is the whole reported defect (doors staying
// open on the live realm but not on test), so the retry is the fix, not the
// coverage.
//
// Bounded on purpose: one close at 5s, then up to 5 more at 6s apart (~35s), so
// a door blocked forever by a parked NPC does not spin for the whole session.

void TryClose(int nLeft);

void TryClose(int nLeft)
{
    // Already shut - by us, by a player, or the door is gone. Nothing to do.
    if (!GetIsOpen(OBJECT_SELF)) return;

    ClearAllActions();
    ActionCloseDoor(OBJECT_SELF);

    if (nLeft > 0) DelayCommand(6.0, TryClose(nLeft - 1));
}

void main()
{
    DelayCommand(5.0, TryClose(5));
}
