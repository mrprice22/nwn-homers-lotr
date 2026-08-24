// pet_timeout -- the action taken when the petrification countdown runs out.
// ExecuteScript'd on the PC by bleeding.nss (petrifyCheck) after
// PETRIFY_TIMEOUT seconds of unbroken EFFECT_TYPE_PETRIFY.
//
// WHY THIS IS A SEPARATE SCRIPT AND NOT INLINE IN THE HEARTBEAT
//
// bleeding.nss is Mod_OnHeartbeat: it runs bleedCheck + petrifyCheck for EVERY
// PC plus WS_Tick() on every pulse. A live fight is a far heavier pulse than a
// solo statue click in an empty castle, and a heartbeat that hits the
// instruction limit aborts SILENTLY mid-loop -- which looks exactly like "the
// statue rig works, the basilisk does not" (roadmap
// petrification-respawn-defect-round-5). Handing the tail off with
// ExecuteScript gives it its own instruction budget, so the timeout action can
// never be the thing the heartbeat runs out of room for.
//
// WHY IT RESURRECTS BEFORE IT KILLS
//
// Round 4's finding stands: a client does NOT refresh a death window it is
// already showing. The engine popped one with Respawn greyed out
// (PopUpDeathGUIPanel(oPC, FALSE, TRUE, 40579)) the moment stock
// DoPetrification turned the PC to stone, so ondeath020's later
// PopUpDeathGUIPanel(oPC, TRUE, TRUE, ...) lands on a window that is already up
// and changes nothing on screen. Round 4 answered that by respawning the player
// outright; the admin's call for round 5 is that a working Respawn button is
// what the player should get instead.
//
// So the sequence forces a NEW window rather than trying to refresh the old one:
//
//   1. strip the stone,
//   2. EffectResurrection -- the PC is alive, which is what makes the client
//      CLOSE the stale death panel,
//   3. half a second later, EffectDeath -- a real death down the normal
//      pipeline, so Mod_OnPlrDeath (ondeath020) runs its death-amulet + BIC
//      export and opens a FRESH panel with Respawn enabled.
//
// The half-second alive window is deliberate. It is the only lever that clears
// the client's stale GUI without the module moving the player itself. Do not
// "simplify" it away.

#include "season_prof_inc"

// Long enough for the client to process the resurrection and drop the death
// window, short enough that nothing meaningful can happen in it.
const float PET_KILL_DELAY = 0.5;

// Remove the petrification. RemoveEffect on ANY component of a linked effect
// drops the whole link, so this also takes the VFX_DUR_CESSATE_NEGATIVE that
// stock DoPetrification links to the EffectPetrify. Returns how many were
// removed -- a zero on a PC the watcher said was stone is the signature of an
// effect we cannot reach from script.
int PetTimeoutStrip(object o)
{
    int nRemoved = 0;
    effect e = GetFirstEffect(o);
    while (GetIsEffectValid(e))
    {
        if (GetEffectType(e) == EFFECT_TYPE_PETRIFY)
        {
            RemoveEffect(o, e);
            nRemoved++;
        }
        e = GetNextEffect(o);
    }
    return nRemoved;
}

int PetTimeoutStillStone(object o)
{
    effect e = GetFirstEffect(o);
    while (GetIsEffectValid(e))
    {
        if (GetEffectType(e) == EFFECT_TYPE_PETRIFY) return TRUE;
        e = GetNextEffect(o);
    }
    return FALSE;
}

// Dev-realm trace. Every step of the tail reports, so a basilisk run that still
// hangs names the step that failed instead of leaving us guessing between the
// strip, the resurrect, the kill and the panel.
void PetTimeoutTrace(object oPC, string sStage)
{
    if (!SP_DEV_TOOLS) return;
    WriteTimestampedLogEntry("[petrify] " + sStage +
        " pc=" + GetName(oPC) +
        " isDead=" + IntToString(GetIsDead(oPC)) +
        " stillStone=" + IntToString(PetTimeoutStillStone(oPC)) +
        " hp=" + IntToString(GetCurrentHitPoints(oPC)));
}

void PetTimeoutKill(object oPC)
{
    ApplyEffectToObject(DURATION_TYPE_INSTANT, EffectDeath(), oPC);
    PetTimeoutTrace(oPC, "timeout killed");
}

void main()
{
    object oPC = OBJECT_SELF;
    if (!GetIsObjectValid(oPC)) return;

    PetTimeoutTrace(oPC, "timeout enter");

    int nStripped = PetTimeoutStrip(oPC);

    if (SP_DEV_TOOLS)
        WriteTimestampedLogEntry("[petrify] timeout strip pc=" + GetName(oPC) +
            " stripped=" + IntToString(nStripped) +
            " stillStone=" + IntToString(PetTimeoutStillStone(oPC)) +
            " area=" + GetTag(GetArea(oPC)));

    // Alive, so the client tears down whatever death window it is holding.
    ApplyEffectToObject(DURATION_TYPE_INSTANT, EffectResurrection(), oPC);
    PetTimeoutTrace(oPC, "timeout resurrected");

    // Then a real death, which pops a fresh panel through ondeath020.
    DelayCommand(PET_KILL_DELAY, PetTimeoutKill(oPC));

    // ondeath020 opens the panel at +2.5s off the death; look here to confirm
    // the PC is actually dead by the time that lands.
    DelayCommand(PET_KILL_DELAY + 3.0, PetTimeoutTrace(oPC, "timeout post-panel"));
}
