// sc_cp_on -- StartingConditional: is the party actually running?
//
// Gates the "hand over my favours" REPLY rather than a greeting, so a crasher
// can still talk to the penguin and opt out after the party is over. Opting out
// must never depend on the party being on: the slot has to be releasable at any
// time or an account is stuck on whichever character used it last.
#include "cp_inc"
int StartingConditional()
{
    return CP_IsOn();
}
