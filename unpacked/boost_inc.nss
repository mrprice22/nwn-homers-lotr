// boost_inc.nss -- Apply the premium 2x gold/XP buff at reward call sites.
//
// Include this ONLY in scripts that grant creature-kill or quest-turn-in gold/XP.
// Do NOT include it in bank or merchant scripts: withdrawing banked gold/XP and
// selling items must never be multiplied. See boost_db.nss for the subscription
// model; the hot path here just reads the cached absolute expiry timestamps.

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

void Boost_GiveXP(object oPC, int nBase)
{
    GiveXPToCreature(oPC, nBase * Boost_Mult(oPC));
}

// ------------------------------------------------------------
// Kill-XP top-up. The bulk of creature XP is granted by the hak scripts
// party_xp / pwfxp (no source in this repo), so we can't multiply inside them.
// Instead snapshot each recipient's XP just before running the hak grant, then
// top up the extra (mult-1)*delta afterwards. Recipients are the killer's party
// (same set party_xp distributes to).

void Boost_SnapshotPartyXP(object oKiller)
{
    if (!GetIsObjectValid(oKiller)) return;
    object oMember = GetFirstFactionMember(oKiller, TRUE);
    while (GetIsObjectValid(oMember))
    {
        SetLocalInt(oMember, "boost_xp_pre", GetXP(oMember));
        SetLocalInt(oMember, "boost_xp_seen", 1);
        oMember = GetNextFactionMember(oKiller, TRUE);
    }
}

void Boost_TopupPartyXP(object oKiller)
{
    if (!GetIsObjectValid(oKiller)) return;
    object oMember = GetFirstFactionMember(oKiller, TRUE);
    while (GetIsObjectValid(oMember))
    {
        if (GetLocalInt(oMember, "boost_xp_seen"))
        {
            int nMult = Boost_Mult(oMember);
            if (nMult > 1)
            {
                int nDelta = GetXP(oMember) - GetLocalInt(oMember, "boost_xp_pre");
                if (nDelta > 0) GiveXPToCreature(oMember, nDelta * (nMult - 1));
            }
            DeleteLocalInt(oMember, "boost_xp_pre");
            DeleteLocalInt(oMember, "boost_xp_seen");
        }
        oMember = GetNextFactionMember(oKiller, TRUE);
    }
}
