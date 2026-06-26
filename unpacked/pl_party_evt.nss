// pl_party_evt — runs on NWNX_ON_PARTY_ACCEPT_INVITATION_AFTER and
// NWNX_ON_PARTY_TRANSFER_LEADERSHIP_AFTER (subscribed in onmoduleload.nss).
// OBJECT_SELF is the player who triggered the event (the joiner / new leader).
// We re-announce the current party loot settings in green to the whole party so
// a new member, a brand-new leader, and everyone after a leadership change all
// see the active rules. Leader-initiated setting changes announce themselves.
#include "inc_partyloot"

void main()
{
    object oPC = OBJECT_SELF;
    if (!GetIsPC(oPC)) return;

    // Small delay so faction membership / leadership has settled before we read
    // GetFactionLeader and iterate the party.
    DelayCommand(0.5, PL_BroadcastSettings(oPC));
}
