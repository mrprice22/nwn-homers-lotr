//::///////////////////////////////////////////////
//:: sp_devgate - StartingConditional for dev-tool conversations
//::
//:: Shows the dialogue when dev tools are enabled for this realm (SP_DEV_TOOLS,
//:: see bin/season-profile.py), OR to a whitelisted admin anywhere.
//::
//:: The admin test is Admin_CanAdmin - the SAME admindb CD-key whitelist that
//:: gates the rest menu's Admin Options and its teleport to House of Homer
//:: (_restemo_admin.nss / _cdkey.nss). It must be the same check: the only way
//:: to reach that room is that teleport, so anyone standing in front of this
//:: NPC already passed it. A different test can only disagree, and it did -
//:: this used GetIsDM(), which is TRUE only for an actual DM-client login, so
//:: an admin who reached the room as a normal player found the NPC mute.
//::
//:: Whitelisted keys live in the admindb campaign database (admins.can_admin),
//:: seeded out of band by bin/seed-admindb.sh; they never ship inside the .mod.
//::
//:: WHY THIS EXISTS AT ALL. There are two Ping Pong NPCs, identical to the
//:: engine - same resref, same tag, same conversation. One stands in the Well
//:: of Eru and must not exist in a live season; onmoduleload destroys that one
//:: by area tag. The other is in "House of Homer" (HouseofDispair), a DM-only
//:: build room no area transition leads to, and it stays. This gate is what
//:: makes any surviving copy inert to a non-admin, and it is the guard that
//:: holds when the purge does not - as it did not at the season 2 launch,
//:: because DestroyObject() silently refuses a Plot creature.
//:://////////////////////////////////////////////
//:: The test itself now lives in sp_devgate_inc so the level-setting script
//:: cannot drift from it - see that file for what happened when it did.
#include "sp_devgate_inc"

int StartingConditional()
{
    return SP_DevToolsFor(GetPCSpeaker());
}
