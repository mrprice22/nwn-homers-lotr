// boost_xp_evt.nss -- NWNX_ON_SET_EXPERIENCE_BEFORE handler for the premium 2x
// XP boost. Subscribed in onmoduleload.nss.
//
// The event fires on every XP write for a player (engine combat XP, GiveXP,
// RewardPartyXP, SetXP). Event data "XP" is the NEW ABSOLUTE total. We double
// only positive gains, and only while the player has an active boost:
//   newTotal = oldTotal + gain * BOOST_MULT
//
// Excluded:
//   * boost_no_xp flag set  -> banked-XP withdrawals (Boost_GiveXPNoBoost); the
//     deposit->withdraw path must pay out at face value, never 2x.
//   * non-positive delta     -> level drain, XP-bank deposit (SetXP to 0), etc.

#include "boost_inc"
#include "nwnx_events"

void main()
{
    object oPC = OBJECT_SELF;
    if (!GetIsPC(oPC)) return;

    // Banked-XP withdrawal in progress: leave it untouched.
    if (GetLocalInt(oPC, "boost_no_xp")) return;

    int nNew = StringToInt(NWNX_Events_GetEventData("XP"));
    int nOld = GetXP(oPC);
    int nGain = nNew - nOld;
    if (nGain <= 0) return;                 // only scale increases

    int nMult = Boost_Mult(oPC);
    if (nMult <= 1) return;                 // no active boost

    NWNX_Events_SkipEvent();
    NWNX_Events_SetEventResult(IntToString(nOld + nGain * nMult));
}
