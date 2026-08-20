//::///////////////////////////////////////////////
//:: FileName at_007_key
//:://////////////////////////////////////////////
//:: Gondor Scribe -- the "claim your key" node.
//::
//:: The key moved from quest accept to the head turn-in, which would otherwise
//:: strand every character who finished the quest before that change: the head
//:: is consumed, so there is no second turn-in to trigger the grant. This node
//:: is gated by sc_annukey (finished, never drew a key) and hands it over once.
//::
//:: WOS_GiveKey is itself once-ever, so this cannot mint a second key even if
//:: the node is somehow reached twice.
//:://////////////////////////////////////////////
#include "wos_inc"

void main()
{
    WOS_GiveKey(GetPCSpeaker());
}
