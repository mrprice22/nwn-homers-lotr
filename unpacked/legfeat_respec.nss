// legfeat_respec.nss — "let me choose my legendary feats again".
//
// Conversation action script. On Ping Pong (_pc_builder_v1) for now; the node is
// gated by legfeat_cond so only a level-60 character sees it, and the same
// script will serve wherever the node is moved to later.
//
// Hands every legendary feat back — the feat AND its base ability points — and
// reopens the picker with the full allotment. The character's level does not
// change. Players re-pick as the feat pool grows and as their gear changes,
// rather than rerolling and levelling to 60 again.
#include "legfeat_nui"

void main()
{
    object oPC = GetPCSpeaker();
    if (!GetIsObjectValid(oPC)) oPC = OBJECT_SELF;
    if (!GetIsPC(oPC)) return;

    if (!LegFeat_Respec(oPC)) return;   // refused; it has already said why

    // Delayed so the conversation has closed — a NUI window opened underneath
    // an open dialogue is one the player cannot reach.
    DelayCommand(1.0, ExecuteScript("legfeat_open", oPC));
}
