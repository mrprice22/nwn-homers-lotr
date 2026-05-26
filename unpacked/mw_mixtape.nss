// Tag-based item script for mw_mixtape (Akira's Mixtape).
// Fires via OnActivateItem → kpb_on_activate → tag-based dispatch.
#include "x2_inc_switches"

void main()
{
    if (GetUserDefinedItemEventNumber() != X2_ITEM_EVENT_ACTIVATE) return;
    object oPC = GetItemActivator();
    AssignCommand(oPC, ActionStartConversation(oPC, "mw_mixtape_use", TRUE, FALSE));
}
