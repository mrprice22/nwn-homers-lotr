// disarm_catch -- when an NPC disarms a player, catch the weapon into the PC's
// pack instead of letting it drop to the ground (where it can despawn on area
// cleanup or be scooped up by the NPC's AI -- a permanent weapon loss).
//
// Subscribed in onmoduleload.nss to BOTH NWNX_ON_DISARM_BEFORE and
// NWNX_ON_DISARM_AFTER. For both events OBJECT_SELF is the creature being
// disarmed. Event data: DISARMER_OBJECT_ID (object), FEAT_ID (int, normal vs
// improved -- unused here), ACTION_RESULT (int, AFTER only: did the disarm land).
//
// Two phases, because after the disarm the right-hand slot is already empty:
//   BEFORE -- snapshot the wielded weapon object onto the PC. The disarmed weapon
//             keeps the SAME object id once it hits the ground (the same reason
//             NPC AI can walk to and re-pick-up a disarmed weapon), so the saved
//             reference stays valid; do nothing else -- the disarm may still miss.
//   AFTER  -- if the disarm succeeded, move that saved weapon into the PC's pack.
//
// Scope (confirmed with the requester, roadmap id npc-disarm-despawn):
//   * Players only -- a player-controlled henchman/summon disarmed by an NPC keeps
//     vanilla drop-to-ground.
//   * PvP untouched -- when the disarmer is a PC we do nothing, preserving standard
//     NWN behavior (unarmed-strike-to-enemy-pack, weapon-size disarm rules, etc.).
//   * Full pack -> fall back to today's behavior (weapon left on the ground).
//
// We never touch the disarm combat resolution itself, so attack-of-opportunity,
// weapon-size bonuses/penalties and normal-vs-improved disarm are all unchanged.

#include "nwnx_events"

const string DISARM_CATCH_VAR = "disarm_catch";

void main()
{
    object oPC = OBJECT_SELF;

    // Only ever act for players being disarmed.
    if (!GetIsPC(oPC)) return;

    string sEvent = NWNX_Events_GetCurrentEvent();

    if (sEvent == NWNX_ON_DISARM_BEFORE)
    {
        // PvP: a player disarming a player keeps standard NWN behavior. Also make
        // sure we don't leave a stale snapshot from an ignored attempt.
        object oDisarmer = StringToObject(NWNX_Events_GetEventData("DISARMER_OBJECT_ID"));
        if (GetIsPC(oDisarmer))
        {
            DeleteLocalObject(oPC, DISARM_CATCH_VAR);
            return;
        }

        // Snapshot the wielded weapon so we can find it once it drops.
        SetLocalObject(oPC, DISARM_CATCH_VAR, GetItemInSlot(INVENTORY_SLOT_RIGHTHAND, oPC));
        return;
    }

    if (sEvent == NWNX_ON_DISARM_AFTER)
    {
        object oWeap = GetLocalObject(oPC, DISARM_CATCH_VAR);
        DeleteLocalObject(oPC, DISARM_CATCH_VAR);

        // Only a landed disarm actually dropped the weapon.
        if (StringToInt(NWNX_Events_GetEventData("ACTION_RESULT")) != TRUE) return;

        // Nothing to catch (no snapshot -- e.g. PvP disarmer -- or already gone).
        if (!GetIsObjectValid(oWeap)) return;

        // Copy into the PC's pack (TRUE keeps local vars). When the pack is full
        // the copy does not end up possessed by the PC -- same detection pattern as
        // merit_redeem.nss. Reconcile so exactly one instance survives, never a dupe.
        object oCopy = CopyItem(oWeap, oPC, TRUE);
        if (GetIsObjectValid(oCopy) && GetItemPossessor(oCopy) == oPC)
        {
            DestroyObject(oWeap); // delivered to pack; remove the ground original
            SendMessageToPC(oPC, "Your disarmed weapon was returned to your pack.");
        }
        else
        {
            if (GetIsObjectValid(oCopy)) DestroyObject(oCopy); // no duplicate on the ground
            // Leave oWeap on the ground = standard behavior.
            SendMessageToPC(oPC, "Your pack was too full to catch your disarmed weapon -- it fell to the ground.");
        }
        return;
    }
}
