// ll_xp_inc.nss -- kill XP for the legendary tier (character levels 41-60).
//
// WHY THIS EXISTS (roadmap: ll-xp-award-balance)
//
// Raising the level cap to 60 extended exptable.2da, which is the COST of a
// level. It did not extend xptable.2da, which is the AWARD for a kill, and that
// table is stock: 40 rows (levels 1-40) x 41 columns (CR 0-40). Kill XP is
// xptable.2da[earned level][CR] x XPScale x party penalty, so a level 41+
// character indexes a row that does not exist and the engine awards ZERO. That
// was measured in game: a level 55 character killing endgame content gained
// nothing at all, which made levels 41-60 unfinishable by combat.
//
// Fixing it in the 2DA would need 20 new rows AND columns out to CR 1461 plus a
// hak rebuild and an nwsync/client publish, and a 2DA cannot express a level
// gate -- so the award is paid here in script instead, and xptable.2da stays
// stock and deliberately out of hak_2da/RULES_2DA.
//
// THE GATE. Below level 41 the engine still pays normally, so this must not.
// LLXP_MIN_LEVEL is the first level the engine stops paying at; paying at or
// below 40 would double up with the engine's own award.
//
// THE BOOST. The premium 2x boost is applied HERE rather than by the usual
// NWNX_ON_SET_EXPERIENCE_BEFORE handler, because at the level-60 ceiling the
// engine clamps the write and the boosted remainder would be silently lost
// before it could be banked. We read the multiplier ourselves, split the total
// between sheet and bank, and hand the sheet portion to Boost_GiveXPNoBoost so
// boost_xp_evt.nss does not double it a second time.

#include "boost_inc"

// THE FORMULA -- a CR-versus-level curve, not a flat CR one.
//
// What the engine does below 41: award = xptable.2da[level][min(CR,40)] x
// XPScale/10. That table is stock and authored at slider 10, so Mod_XPScale 150
// means x15, and its level-40 row saturates at 400 -- which is where the familiar
// 6,000 per kill comes from (400 x 15). The important part is that the table is
// indexed by LEVEL as well as CR: at level 20 a CR 10 mob pays 4.2 while CR 27+
// pays the full 600. You outgrow content. That is the property continued here.
//
// The curve: each level has a difficulty tier, the CR at which a kill pays the
// full award.
//
//     tier(L) = LLXP_TIER_BASE x LLXP_TIER_STEP ^ (L - LLXP_MIN_LEVEL)
//     r       = CR / tier(L)
//     award   = PEAK                              when r >= 1
//               FLOOR                             when r <= KNEE
//               FLOOR + (PEAK-FLOOR) x f^KNEE_EXP otherwise,
//                                                 f = (r-KNEE)/(1-KNEE)
//
// tier(41) is 40, so level 41 pays exactly what level 40 paid for the same
// CR 40+ kill and the boundary is seamless at the top of the range. By level 50
// you need CR 162 for full value, by 60 CR 770 -- which walks a player from the
// Wold/Ettenmoors tier up through Mordor and Gondor rather than letting one zone
// carry the whole band.
//
// KNEE_EXP > 1 makes the ramp convex, so on-tier content stays clearly the best
// use of time even though below-tier content still pays something.
//
// KNOWN BOUNDARY STEP: softening the knee (admin's call 2026-08-13) necessarily
// pays below-tier content MORE than the engine does at level 40 -- a CR 30 mob
// pays 60 at level 40 and ~2,450 at level 41. The window is self-closing: by
// level 44 that same mob is under the knee again and back to 60. This was
// accepted deliberately so low-tier content stays farmable for a few levels
// after 40 instead of dying at the boundary.
//
// BALANCE, APPROVED BY THE ADMIN 2026-08-13 ("option A"). Roughly 9.5 hours solo
// unboosted for 41->60, ~4.8 with the 2x boost, at 90 kills/hour.
//
// A 20-hour target was considered first and abandoned as arithmetically
// impossible alongside the other requirements. 41->60 costs 2,752,200 XP, so at
// the 6,000 cap the floor is 459 kills == 5.1 hours if every kill pays full. 20
// hours needs 1,800 kills, i.e. an average of 1,529 -- only 25% of the cap --
// which means most kills must NOT pay full. That directly contradicts wanting
// full value to be reachable on farmable content, and softening the knee pushes
// the average UP, shortening the band rather than lengthening it. The only lever
// that delivers 20 hours is raising the 41-60 cost curve in exptable.2da, which
// de-levels every existing 41+ character, so it was declined.
//
// tier(60) is 300 because that is what is actually FARMABLE. Measured from
// module-index/creature_index.json against module-index/bosses.json: non-boss
// endgame content tops out at CR 701, and above CR 800 all six instances are
// registry bosses on respawn timers. There are 54 farmable non-boss instances at
// CR 300+. An earlier tuning put tier(60) at 770 and was rejected for exactly
// this reason -- full value was boss-only, i.e. not farmable at all.
//
// THE ANCHORS. The whole 1-60 curve is fitted to four numbers the admin chose
// directly (2026-08-13). The first two live in hak_2da/xptable.2da, the last two
// here:
//
//     level  1, CR  5 ->   2,000      level  1, CR 30 -> 6,000 (full)
//     level 21, CR  5 ->     100      level 41, CR 30 ->   500
//
// Those pin the tier ladder to 30 (L1) -> 99.8 (L21) -> 150 (L41) -> 300 (L60)
// and both exponents. LLXP_TIER_BASE is the L41 anchor and LLXP_TIER_STEP is
// (300/150)^(1/19); LLXP_KNEE_EXP is solved from the level 41 / CR 30 anchor.
// Change an anchor and BOTH halves have to be refitted together, or the 40->41
// boundary stops being monotonic.
//
// KNOWN CONSEQUENCE, accepted 2026-08-13: pinning CR 30 to 500 at level 41 drags
// the whole low-CR end of the legendary band down with it. A fresh level 41
// fighting its natural Wold/Ettenmoors content (CR 45-80) is paid 964-2,350, not
// the flat 6,000 it used to get, and full value needs CR 150. Steepening this way
// does NOT lengthen the band (still ~9.9 h): the top of every column is
// unchanged, so an optimising player farms CR 200+ and is unaffected. What it
// changes is that low-CR farming stops being viable.
//
// RETUNING: LLXP_TIER_STEP is the grind dial. Re-run the calibration against
// creature_index.json + bosses.json before changing it, and record the new target
// on the roadmap item; the target is a balance decision, not an implementation
// detail (see CLAUDE-autopilot.md, "The target IS the balance decision").
// MODULE-WIDE HARD CAP on a single kill, BEFORE the 2x boost -- so a boosted kill
// pays at most 12,000 and an unboosted one at most 6,000. Admin decision
// 2026-08-13: "6k XP HARD CAP, period." This binds BOTH award paths:
//   * levels 41-60, where LLXP_PEAK below is this cap; and
//   * levels 1-40, where the ENGINE pays up to 9,000 and boost_xp_evt.nss clamps
//     it back down (a level 1-3 character killing anything CR 21+ is paid the
//     table's global peak of 600 x 15 = 9,000).
const int   XP_KILL_CAP    = 6000;

// The most the engine can possibly pay for one kill: xptable.2da's global peak
// (600) x Mod_XPScale/10 (15). boost_xp_evt.nss uses this to tell an engine kill
// award apart from a script grant without every grant site needing a flag --
// nothing in unpacked/ grants between XP_KILL_CAP and this (the literals jump
// from 5,000 straight to 10,000), so a delta inside that window is an engine
// award. Re-check that gap if Mod_XPScale ever changes.
const int   XP_ENGINE_MAX  = 9000;

const int   LLXP_MIN_LEVEL = 41;      // first level the engine pays nothing at
const int   LLXP_PEAK      = XP_KILL_CAP;   // per kill, BEFORE the boost
const int   LLXP_FLOOR     = 60;      // what the level-40 row pays for trash
const float LLXP_TIER_BASE = 150.0;   // CR paying full value at LLXP_MIN_LEVEL
const float LLXP_TIER_STEP = 1.03716; // tier growth per level -- THE GRIND DIAL
const float LLXP_KNEE      = 0.05;    // fraction of tier where the ramp starts
const float LLXP_KNEE_EXP  = 1.41;    // >1 keeps on-tier content dominant

// The CR that pays the full award at this character level.
float LlXp_Tier(int nLevel)
{
    if (nLevel < LLXP_MIN_LEVEL) nLevel = LLXP_MIN_LEVEL;
    return LLXP_TIER_BASE * pow(LLXP_TIER_STEP, IntToFloat(nLevel - LLXP_MIN_LEVEL));
}

// Cumulative XP for character level 60 -- exptable.2da's top real row. Also
// transcribed in grant_lvl60.nss, code_redeem.nss (XP_LEVEL_60) and the fallback
// switch in _build_lvl_inc.nss; tests/check_epic_tables.py cross-checks them
// against the 2DA, so retune all of them together or the gate fails the build.
const int   LLXP_LEVEL_60_XP = 3581000;

// Family XP reserve, shared with the XP bank. Same campaign DB and key that
// bank_xp_deposit.nss writes on retirement and the xp_withdraw_* scripts read.
const string LLXP_BANK_DB = "bankdb";

// The award for this CR at this character level, before the boost and before any
// ceiling split.
int LlXp_Award(int nLevel, float fCR)
{
    float fR = fCR / LlXp_Tier(nLevel);
    if (fR >= 1.0)       return LLXP_PEAK;
    if (fR <= LLXP_KNEE) return LLXP_FLOOR;

    float fF = pow((fR - LLXP_KNEE) / (1.0 - LLXP_KNEE), LLXP_KNEE_EXP);
    return LLXP_FLOOR + FloatToInt(IntToFloat(LLXP_PEAK - LLXP_FLOOR) * fF);
}

// Pay one contributor for one kill. Safe to call for any PC at any level: it is
// a no-op below LLXP_MIN_LEVEL, where the engine is still paying.
void LlXp_GiveKillXP(object oPC, float fCR)
{
    if (!GetIsPC(oPC) || GetIsDM(oPC)) return;

    int nLevel = GetHitDice(oPC);
    if (nLevel < LLXP_MIN_LEVEL) return;

    int nTotal = LlXp_Award(nLevel, fCR) * Boost_Mult(oPC);
    if (nTotal <= 0) return;

    // Split at the level-60 ceiling. Room can be negative if a character is
    // somehow above the ceiling (a legacy grant), so clamp before using it.
    int nRoom = LLXP_LEVEL_60_XP - GetXP(oPC);
    if (nRoom < 0) nRoom = 0;

    int nToSheet = nTotal;
    if (nToSheet > nRoom) nToSheet = nRoom;
    int nToBank = nTotal - nToSheet;

    // Boost already applied above -- Boost_GiveXPNoBoost raises the boost_no_xp
    // flag so boost_xp_evt.nss leaves this write at face value.
    if (nToSheet > 0) Boost_GiveXPNoBoost(oPC, nToSheet);

    // Overflow at the ceiling goes to the family reserve UNTAXED (admin's call
    // 2026-08-13): the 15% in bank_xp_deposit.nss is a retirement fee paid on
    // XP the player chose to give up, and overflow was never theirs to keep.
    if (nToBank > 0)
    {
        string sKey = "fam_xp_" + GetPCPublicCDKey(oPC);
        SetCampaignInt(LLXP_BANK_DB, sKey,
            GetCampaignInt(LLXP_BANK_DB, sKey) + nToBank);

        SendMessageToPC(oPC, "[XP Bank] You are at the level 60 ceiling -- "
            + IntToString(nToBank) + " XP was deposited into your family reserve.");
    }
}
