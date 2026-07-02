// boost_inc.nss -- premium 2x gold/XP buff helpers.
//
// GOLD is boosted at the call site: reward scripts call Boost_GiveGold. Bank
// withdrawals and merchant sales call GiveGoldToCreature directly, so they stay
// un-boosted.
//
// XP is boosted centrally, NOT here: the NWNX_ON_SET_EXPERIENCE_BEFORE handler
// (boost_xp_evt.nss) doubles every positive XP delta while a boost is active.
// The ONE thing that must be shielded from it is banked XP (deposit->withdraw
// would otherwise pay out 2x) -- bank XP scripts call Boost_GiveXPNoBoost, which
// raises a per-PC "boost_no_xp" flag the handler honours.
//
// See boost_db.nss for the subscription model; Boost_Mult just reads the cached
// absolute expiry timestamps.

#include "boost_db"

// 2 if the player currently benefits from any boost (their personal chain OR the
// server-wide chain is active), else 1. Cheap: two indexed reads, no reconcile.
int Boost_Mult(object oPC)
{
    if (!GetIsPC(oPC)) return 1;
    int nNow = Boost_Now();

    sqlquery qs = SqlPrepareQueryCampaign(BOOST_DB,
        "SELECT server_active_until FROM boost_state WHERE id=1");
    if (SqlStep(qs) && SqlGetInt(qs, 0) > nNow) return BOOST_MULT;

    sqlquery qp = SqlPrepareQueryCampaign(BOOST_DB,
        "SELECT personal_active_until FROM player_boost WHERE cdkey=@k");
    SqlBindString(qp, "@k", GetPCPublicCDKey(oPC));
    if (SqlStep(qp) && SqlGetInt(qp, 0) > nNow) return BOOST_MULT;

    return 1;
}

void Boost_GiveGold(object oPC, int nBase)
{
    GiveGoldToCreature(oPC, nBase * Boost_Mult(oPC));
}

// Grant XP that must NEVER be boosted (banked XP withdrawals). Raises the
// boost_no_xp flag so boost_xp_evt.nss leaves this write at face value. The
// SET_EXPERIENCE BEFORE event fires synchronously inside GiveXPToCreature, so a
// set-flag / grant / clear-flag sequence fully brackets it.
void Boost_GiveXPNoBoost(object oPC, int nXP)
{
    SetLocalInt(oPC, "boost_no_xp", 1);
    GiveXPToCreature(oPC, nXP);
    DeleteLocalInt(oPC, "boost_no_xp");
}
