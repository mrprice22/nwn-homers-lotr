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
#include "ll_xp_inc"
#include "season_prof_inc"
#include "nwnx_events"

// XP tracing, for verifying the award curve in game. Gated on SP_DEV_TOOLS so it
// is on for the dev/test realm and OFF for a live season automatically -- this
// fires on every XP write for every player and would fill a live log. Deliberately
// NOT a hand-set flag: dev and production share one source tree and season-promote
// copies dev's over production's, so a "remember to switch it off before promoting"
// constant is one forgotten step away from shipping.
//
// Reading the output:
//   * no [xpdbg] line after a kill -> the ENGINE awarded nothing (the original
//     defect: xptable.2da had no row past level 40).
//   * "cap:engine_kill"     -> an engine award was clamped to XP_KILL_CAP.
//   * gain>0 but XP does not move -> this handler ate it: SkipEvent ran but
//     SetEventResult was not applied on this stack.
void XpDbg(object oPC, string sWhere, int nOld, int nNew, int nMult)
{
    if (!SP_DEV_TOOLS) return;
    WriteTimestampedLogEntry("[xpdbg] " + sWhere +
        " pc=" + GetName(oPC) +
        " hd=" + IntToString(GetHitDice(oPC)) +
        " old=" + IntToString(nOld) +
        " new=" + IntToString(nNew) +
        " gain=" + IntToString(nNew - nOld) +
        " mult=" + IntToString(nMult));
}

void main()
{
    object oPC = OBJECT_SELF;
    if (!GetIsPC(oPC)) return;

    int nNew = StringToInt(NWNX_Events_GetEventData("XP"));
    int nOld = GetXP(oPC);

    // Banked-XP withdrawal in progress: leave it untouched.
    if (GetLocalInt(oPC, "boost_no_xp"))
    {
        XpDbg(oPC, "skip:no_xp_flag", nOld, nNew, -1);
        return;
    }

    int nGain = nNew - nOld;
    if (nGain <= 0)                         // only scale increases
    {
        XpDbg(oPC, "skip:non_positive", nOld, nNew, -1);
        return;
    }

    // HARD CAP on a single kill, applied BEFORE the boost so a boosted kill tops
    // out at 2 x XP_KILL_CAP and never more (admin, 2026-08-13).
    //
    // Only the ENGINE overpays: its award peaks at 9,000 (xptable.2da's global
    // peak 600 x XPScale/10), which a level 1-3 character collects from anything
    // CR 21+. The legendary curve is already capped at XP_KILL_CAP and arrives
    // via Boost_GiveXPNoBoost, which returns above.
    //
    // A delta strictly inside (XP_KILL_CAP, XP_ENGINE_MAX] is therefore an engine
    // award: nothing in unpacked/ grants in that window, and a script grant
    // marked xp_script (quest XP -- see nw_i0_tool.nss) is excluded outright. Big
    // deliberate grants (bank withdrawals, mw_finale's 50,000, code_redeem) are
    // all above XP_ENGINE_MAX and pass through untouched.
    int bCapped = FALSE;
    if (nGain > XP_KILL_CAP && nGain <= XP_ENGINE_MAX
        && !GetLocalInt(oPC, "xp_script"))
    {
        nGain = XP_KILL_CAP;
        bCapped = TRUE;
        XpDbg(oPC, "cap:engine_kill", nOld, nNew, -1);
    }

    int nMult = Boost_Mult(oPC);
    if (nMult <= 1)                         // no active boost
    {
        if (!bCapped)                       // nothing to change: let it stand
        {
            XpDbg(oPC, "pass:unboosted", nOld, nNew, nMult);
            return;
        }
        nMult = 1;
    }

    XpDbg(oPC, bCapped ? "cap+boost:applied" : "boost:applied", nOld, nNew, nMult);
    NWNX_Events_SkipEvent();
    NWNX_Events_SetEventResult(IntToString(nOld + nGain * nMult));
}
