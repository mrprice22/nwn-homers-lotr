//::///////////////////////////////////////////////
//:: sp_devgate - StartingConditional for dev-tool conversations
//::
//:: Shows the dialogue when dev tools are enabled for this realm (SP_DEV_TOOLS,
//:: see bin/season-profile.py), OR to a DM anywhere.
//::
//:: THE DM CLAUSE IS NOT A LOOPHOLE, it is the point. There are two Ping Pong
//:: NPCs and they are identical to the engine - same resref, same tag, same
//:: conversation. One stands in the Well of Eru and must not exist in a live
//:: season; the other is in "House of Homer" (area tag HouseofDispair), a
//:: DM-only build room that no area transition leads to. Gating purely on
//:: SP_DEV_TOOLS disabled BOTH, which took a working admin facility away in
//:: season 2 with nothing said about it.
//::
//:: A DM already has every power this dialogue offers, through the DM client.
//:: Letting them use the builder grants nothing they could not otherwise do,
//:: while a non-DM in a live season sees no conversation at all.
//::
//:: This is the guard that holds when the module-load purge does not, as it did
//:: not at the season 2 launch - DestroyObject() silently refuses a Plot
//:: creature. Keep both: onmoduleload removes the player-facing copy, this
//:: makes any surviving copy inert to non-DMs.
//:://////////////////////////////////////////////
#include "season_prof_inc"

int StartingConditional()
{
    if (SP_DEV_TOOLS) return TRUE;
    return GetIsDM(GetPCSpeaker());
}
