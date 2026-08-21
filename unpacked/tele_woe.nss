// tele_woe - Rest-menu "To. The Well of Eru." teleport. Before sending the PC to
// the Well of Eru, it records their current spot as slot 0 and arms the return
// (merit unlock 102), so the "Return to last Well-of-Eru point" option brings
// them back here exactly once.
//
// This is the ONLY path that arms the return: death/respawn does not touch
// tele_state, so dying never counts as a Well-of-Eru teleport.
//
// THE JUMP GOES THROUGH Tele_DoJump, NOT THE OLD _teleportpvp BODY.
//
// This script used to be a faithful copy of the legacy _teleportpvp reply
// script, which did three things that cost the player their buff ICONS on
// arrival (roadmap bard-song-issues-round-2, UAT):
//
//   * EffectDisappear on the PC. It vanishes and re-materializes the creature,
//     so the client tears the character object down and builds it again - and
//     the effect-icon list it rebuilds is only refilled by an AREA LOAD. Walking
//     through a door into the Well kept every icon; this teleport did not, which
//     is exactly the asymmetry the report described. tele_db.nss already refused
//     to use EffectDisappear for a second reason: it leaves the PC
//     non-commandable, so a queued ActionJumpToLocation silently never runs.
//   * TWO jumps - to the "pvp" waypoint first and then, a second later, to
//     "secondchance". The second hop is WITHIN the destination area, so it moves
//     the character with no area load behind it to resync the client.
//   * Fire-and-forget VFX applied as PERMANENT effects ON THE PC, which is how a
//     character accumulates junk in its effect list, one pair per teleport,
//     until it logs out.
//
// The buffs themselves were never affected - the character sheet stayed correct
// throughout, and re-casting could not restore the icon because the spell really
// was still running and its own "already applied" guard correctly refused.
//
// Destination is unchanged: the "secondchance" waypoint, where the old two-hop
// jump left the player.
#include "tele_db"
void main()
{
    object oPC = GetPCSpeaker();

    // Remember where they were and arm a single return.
    Tele_SaveSlot(oPC, 0);
    Tele_SetArmed(oPC, TRUE);

    object oWP = GetWaypointByTag("secondchance");
    if (!GetIsObjectValid(oWP))
    {
        SendMessageToPC(oPC, "[Teleport] The Well of Eru is not reachable right now.");
        return;
    }

    // Depart dark, arrive in the light - the two bursts the old script played,
    // now as instant effects either side of the jump.
    Tele_DoJump(oPC, GetLocation(oWP), VFX_FNF_LOS_EVIL_30, VFX_FNF_LOS_NORMAL_30);
}
