// _spfailexit - OnExit for the `spellfailarea` trigger (the Well of Eru's
// no-casting zone). Clears the flag and takes the spell-failure effect back off.
//
// RESTART THE WALK AFTER EVERY REMOVAL. RemoveEffect() inside a GetFirstEffect /
// GetNextEffect walk invalidates that walk, which is how the old version could
// leave an effect behind - and a leftover permanent 100% spell failure follows
// the player out of the Well and into the rest of the world. NWScript has no
// arrays to collect matches into, so the fix is to remove one and start the walk
// again. The effect list is short and there should only ever be ONE match now
// that _spfailenter refuses to stack them; SPFAIL_MAX_STRIP is the backstop for
// characters who still carry a stack from before that fix.
const int SPFAIL_MAX_STRIP = 16;

void main()
{
    object oExiting = GetExitingObject();
    DeleteLocalInt(oExiting, "SPFAIL_ZONE");

    int nPass = 0;
    int bRemoved = TRUE;

    while (bRemoved && nPass < SPFAIL_MAX_STRIP)
    {
        bRemoved = FALSE;
        nPass++;

        effect eFail = GetFirstEffect(oExiting);
        while (GetIsEffectValid(eFail))
        {
            if (GetEffectType(eFail) == EFFECT_TYPE_SPELL_FAILURE &&
                GetEffectDurationType(eFail) == DURATION_TYPE_PERMANENT)
            {
                RemoveEffect(oExiting, eFail);
                bRemoved = TRUE;
                break;              // the walk is now stale - start it again
            }
            eFail = GetNextEffect(oExiting);
        }
    }
}
