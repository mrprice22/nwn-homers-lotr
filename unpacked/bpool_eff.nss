// bpool_eff.nss - NWNX_ON_EFFECT_REMOVED_AFTER handler for the bonus ledger.
//
// WHY THIS EXISTS: the ledger has to recalculate when a bonus ENDS, not only
// when one starts. Registration and login were the only rebuild points in the
// first build, and UAT found both halves of what that misses - a bard song that
// ended early left its attack bonus behind, and a respawn's wholesale
// RemoveEffects took the PERMANENT feat bonuses away with nothing to put them
// back. An effect ending is exactly the event this subscribes to.
//
// THIS RUNS FOR EVERY EFFECT REMOVAL ON THE SERVER, so the first line has to be
// the cheap one. BPOOL_LIVE is set only while a creature actually carries a
// ledger entry, so anyone who has never been buffed costs a single GetLocalInt
// and nothing else - the same discipline LEGFEAT_ATK_VAR uses in devcrit_atk.
//
// TWO REENTRANCY GUARDS, because rebuilding the ledger STRIPS our own effect and
// that strip fires this very event:
//
//   BPOOL_BUSY  - set across a rebuild and cleared on the next frame. This is
//                 the guard that actually binds; without it every rebuild
//                 schedules another one, forever.
//   CUSTOM_TAG  - our render carries the channel tag, so a removal wearing it is
//                 our own churn by definition. Cheap second line of defence in
//                 case the busy window is ever missed.
//
// BPOOL_PENDING debounces the storm: a death strips dozens of effects in one
// frame and every one of them lands here. One revalidate is enough.

#include "nwnx_events"
#include "bonus_pool_inc"

void main()
{
    // OBJECT_SELF is the target of the effect (NWNX effect events).
    object oTarget = OBJECT_SELF;

    if (!GetLocalInt(oTarget, BPOOL_LIVE)) return;   // the hot path ends here
    if (GetLocalInt(oTarget, BPOOL_BUSY))  return;   // our own rebuild
    if (GetLocalInt(oTarget, BPOOL_PENDING)) return; // already queued this frame

    string sTag = NWNX_Events_GetEventData("CUSTOM_TAG");
    if (sTag == BPOOL_TAG_ATTACK || sTag == BPOOL_TAG_DAMAGE) return;

    // Deferred, and not by zero: at death the engine is still working through
    // its strip when the first removal fires. Revalidating mid-strip would read
    // a half-cleared creature - the song's witness still present, the pooled
    // effect about to be removed again - and would have to be redone anyway.
    SetLocalInt(oTarget, BPOOL_PENDING, TRUE);
    DelayCommand(1.0, BPool_Revalidate(oTarget));
}
