// Forge Warden: revert ALL illegal gear to stock blueprints and, when that
// leaves the PC clean, release them to the Well of Eru. Items with no known
// blueprint stay illegal - the dialog branches to a remains-unlawful entry
// (gated by forge_ward_c_il) and the player must strip those by hand.
//
// The work is chunked: ForgeBeginRevertAll queues the inventory and
// forge_scan_step (mode 2) reverts ONE item per delayed step, tallying
// blueprint-less items into FORGE_RVT_FAIL and doing the release itself when
// the queue drains clean. Doing it synchronously here is what caused TOO MANY
// INSTRUCTIONS on a large inventory - which stranded the player in the Pit
// Prison, because this is the script that lets them out.
#include "forge_inc"

void main()
{
    object oPC = GetPCSpeaker();
    ForgeLog("forge_ward_rva: " + GetName(oPC) + " requested revert-all");
    ForgeBeginRevertAll(oPC);
}
