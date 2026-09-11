// Tag-based item script for jb_jukebox (the Jukebox).
//
// The module sets MODULE_SWITCH_ENABLE_TAGBASED_SCRIPTS in onmoduleload.nss, so
// the OnActivateItem hook (dmfi_activate) dispatches to this file purely because
// its name matches the item's tag. Nothing has to be registered anywhere.
#include "x2_inc_switches"

void main()
{
    if (GetUserDefinedItemEventNumber() != X2_ITEM_EVENT_ACTIVATE) return;
    object oPC = GetItemActivator();
    AssignCommand(oPC, ActionStartConversation(oPC, "jb_conv", TRUE, FALSE));
}
