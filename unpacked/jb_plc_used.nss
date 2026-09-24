// jb_plc_used.nss - OnUsed for the player jukebox placeable (jb_jukebox_plc).
//
// Same shape as graf_use.nss: a placeable does NOT auto-start its Conversation
// when it is used, so OnUsed has to open it explicitly. Passing "" uses the
// placeable's own Conversation field (jb_conv) rather than naming it twice.
//
// The menu scripts all read GetPCSpeaker() and GetArea(oPC), never OBJECT_SELF,
// so jb_conv works unchanged whether the speaker is the PC (the admin item's
// self-conversation) or this placeable. That is why this phase needs no new
// menu code at all.
//
// The NUI song browser replaces the conversation here in a later phase; the
// blueprint does not change when it does.
void main()
{
    object oPC = GetLastUsedBy();
    if (!GetIsPC(oPC)) return;

    ActionStartConversation(oPC, "", TRUE, FALSE);
}
