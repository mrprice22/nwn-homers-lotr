// pet_respawn -- ExecuteScript'd on the PC a few seconds after the
// petrification timeout has killed them (bleeding.nss, petrifyCheck).
//
// WHY THE TIMEOUT RESPAWNS THE PLAYER INSTEAD OF ASKING THEM TO
//
// The engine pops its own death window the moment stock DoPetrification turns
// a PC to stone, with bRespawnButtonEnabled = FALSE. That window is ALREADY
// OPEN on the client two minutes later when the timeout kills them, and a
// second PopUpDeathGUIPanel does not refresh a panel the client is already
// showing -- so the player sat looking at a greyed-out Respawn button until
// they relogged. That is rounds 3 and 4 of this defect
// (petrification-respawn-defect-round-4); re-popping the panel is the lever
// that does not work. Resurrecting them does: the engine closes the death
// window when the PC is alive again, whatever state the client's GUI is in.
//
// Run as a separate script, NOT inlined into the heartbeat: respawn_inc drags
// in nw_i0_plot and legfeat_inc, and bleeding.nss is the module OnHeartbeat.
// ExecuteScript gives that weight its own instruction budget.

#include "respawn_inc"
#include "season_prof_inc"

void main()
{
    object oPC = OBJECT_SELF;

    // Somebody raised them inside the grace window -- their rescue wins, and we
    // do not yank a rescued player across the module to the bind point.
    if (!GetIsDead(oPC))
    {
        if (SP_DEV_TOOLS)
            WriteTimestampedLogEntry("[petrify] auto-respawn SKIPPED (already alive) pc=" + GetName(oPC));
        return;
    }

    if (SP_DEV_TOOLS)
        WriteTimestampedLogEntry("[petrify] auto-respawn pc=" + GetName(oPC));

    LOTR_RespawnPC(oPC);
}
