// door_inc.nss - the one real auto-close implementation for doors.
//
// WHY THIS EXISTS
//
// Eleven near-identical hand-written auto-close scripts had accumulated, each
// with its own hard-coded DelayCommand and its own idea of when to re-lock.
// Retuning "how long does a door stay open" therefore meant editing eleven
// files and getting every one of them right. Szescian82 reported the door into
// Theoden's hall (edoras2hall / hall2edoras, both on close_door) shutting too
// fast and asked for roughly +3s module-wide - roadmap item door-opening-time.
//
// Now the timing lives here and each OnOpen script is a two-line wrapper.
//
// THE RETRY IS NOT OPTIONAL
//
// ActionCloseDoor FAILS SILENTLY when a creature is standing in the doorway -
// the action is simply dropped, and the door then stays open until somebody
// closes it by hand. A bare DelayCommand(5.0, ActionCloseDoor(OBJECT_SELF))
// queues exactly one attempt, so on a quiet server it looks like it works and
// on a populated one the same door in the same build stays open. That was a
// real reported defect; the retry is the fix. Bounded on purpose - one close at
// the configured delay, then up to DOOR_CLOSE_RETRIES more at DOOR_CLOSE_RETRY
// apart - so a door blocked forever by a parked NPC does not spin all session.
//
// RE-LOCKING HANGS OFF THE DOOR ACTUALLY BEING SHUT
//
// The old lock-on-a-second-timer pattern (close at 2.0, SetLocked at 2.5) runs
// those two independently, so a close that failed against a blocked doorway
// still locked the door - leaving it standing open AND locked, which then
// refuses to close normally. Locking only once GetIsOpen is FALSE makes that
// state unreachable.
//
// Only ever pass bRelock to a door whose key SURVIVES the unlock. A door with
// AutoRemoveKey set eats the key on first use, so re-locking it strands the
// player behind a lock they can no longer open; those get a plain close.
//
// PER-DOOR OVERRIDE
//
// Set the local float DOOR_CLOSE_DELAY on a door instance (toolset: Variables
// tab) to give that one door a different delay. Anything > 0.0 wins over the
// script's default - no twelfth script needed.

// Module baseline: how long a normal door stays open. Was 5.0 before the
// door-opening-time bump.
const float DOOR_CLOSE_DELAY_DEFAULT = 8.0;

// Gap between retry attempts, and how many retries after the first close.
const float DOOR_CLOSE_RETRY   = 6.0;
const int   DOOR_CLOSE_RETRIES = 5;

// Name of the per-door override variable.
const string DOOR_CLOSE_DELAY_VAR = "DOOR_CLOSE_DELAY";

float DoorGetCloseDelay(float fDefault);
void  DoorTryClose(int nLeft, int bRelock);
void  DoorAutoClose(float fDefault = DOOR_CLOSE_DELAY_DEFAULT, int bRelock = FALSE);

// Per-door override if one is set, else the caller's default.
float DoorGetCloseDelay(float fDefault)
{
    float fDelay = GetLocalFloat(OBJECT_SELF, DOOR_CLOSE_DELAY_VAR);
    if (fDelay > 0.0) return fDelay;
    return fDefault;
}

void DoorTryClose(int nLeft, int bRelock)
{
    // Already shut - by us, by a player, or the door is gone.
    if (!GetIsOpen(OBJECT_SELF))
    {
        // Shut, so it is safe to re-lock.
        if (bRelock) SetLocked(OBJECT_SELF, TRUE);
        return;
    }

    ClearAllActions();
    ActionCloseDoor(OBJECT_SELF);

    if (nLeft > 0)
        DelayCommand(DOOR_CLOSE_RETRY, DoorTryClose(nLeft - 1, bRelock));
}

// Call from a door's OnOpen. Closes after the configured delay, retrying while
// the doorway is blocked, and re-locks only once the door is actually shut.
void DoorAutoClose(float fDefault, int bRelock)
{
    DelayCommand(DoorGetCloseDelay(fDefault), DoorTryClose(DOOR_CLOSE_RETRIES, bRelock));
}
