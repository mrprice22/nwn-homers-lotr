// q_post_inc.nss — Hobbit Post shared helpers (roadmap: hobbit-post)
//
// T1 daily delivery quest, journal tag "hobbit_post". Posco Whitfoot, the
// Hobbiton post-master, hands out one sealed parcel per real day; the
// addressee rotates with the game calendar (GetCalendarDay() % 5 + 1):
//
//   1  Daddy Twofoot                 Hobbiton (same area as Posco)
//   2  Old Noakes                    Bywater
//   3  the Keeper of the Green Dragon  Green Dragon Inn (door off Hobbiton)
//   4  Salvia Brockhouse             Whitfurrow Inn
//   5  Milo Burrows                  Whitfurrow Inn
//
// State lives entirely on the parcel item (tag QP_TAG, blueprint
// q_post_parcel — plot + cursed, so it can't be sold, dropped or traded):
//   POST_DAY  int 1..5 — the addressee on the label (baked at accept time,
//                        so a calendar flip mid-delivery can't strand it)
//   POST_MIS  int 0/1  — misdelivery: the label is wrong; the labelled
//                        recipient refuses and points at the true one,
//                        QP_TrueRec(label) = (label % 5) + 1, who pays extra
//   POST_T0   int      — real-world accept epoch (QCD_Now); the speed bonus
//                        pays if delivery lands within QP_FAST_SECS of it
//
// Daily gating is quest_cd_inc's calendar reset: QCD_IsDoneToday gates the
// offer, QCD_Stamp fires in QP_Pay on delivery. Custom tokens 6340 (name),
// 6341 (place), 6342 (time to reset) are set by the StartingConditionals.
//
// Rewards (QP_Pay): 60 gp base, +40 gp if fast, +60 gp and a small random
// parcel-loot item if misdelivered, +50 XP always.

#include "quest_cd_inc"

const string QP_TAG       = "q_post_parcel";   // item tag AND blueprint resref
const string QP_QUEST     = "hobbit_post";     // questcddb key + journal tag
const int    QP_FAST_SECS = 300;               // speed-bonus window (5 real min)
const int    QP_MIS_PCT   = 8;                 // % chance the label is wrong
const int    QP_GOLD_BASE = 60;
const int    QP_GOLD_FAST = 40;
const int    QP_GOLD_MIS  = 60;
const int    QP_XP        = 50;

// Today's addressee index, 1..5.
int QP_TodayIdx()
{
    return (GetCalendarDay() % 5) + 1;
}

// Who a mislabelled parcel really belongs to.
int QP_TrueRec(int nLabel)
{
    return (nLabel % 5) + 1;
}

string QP_Name(int n)
{
    switch (n)
    {
        case 1: return "Daddy Twofoot";
        case 2: return "Old Noakes";
        case 3: return "the Keeper of the Green Dragon";
        case 4: return "Salvia Brockhouse";
        case 5: return "Milo Burrows";
    }
    return "somebody in the Shire";
}

string QP_Place(int n)
{
    switch (n)
    {
        case 1: return "here in Hobbiton, under the Hill";
        case 2: return "out along the Bywater road";
        case 3: return "behind the bar of the Green Dragon Inn";
        case 4: return "in the common room of the Whitfurrow Inn";
        case 5: return "in the common room of the Whitfurrow Inn";
    }
    return "somewhere in the Shire";
}

// The parcel the PC is carrying, or OBJECT_INVALID.
object QP_Parcel(object oPC)
{
    return GetItemPossessedBy(oPC, QP_TAG);
}

// Label on the carried parcel (1..5), or 0 when no parcel.
int QP_Label(object oPC)
{
    object oParcel = QP_Parcel(oPC);
    if (!GetIsObjectValid(oParcel)) return 0;
    return GetLocalInt(oParcel, "POST_DAY");
}

// TRUE when the carried parcel is mislabelled.
int QP_Mis(object oPC)
{
    object oParcel = QP_Parcel(oPC);
    return GetIsObjectValid(oParcel) && GetLocalInt(oParcel, "POST_MIS");
}

// --- Recipient StartingConditional cores (r = recipient index 1..5) ---

// Normal delivery: parcel labelled for r and the label is honest.
int QP_CanAccept(object oPC, int r)
{
    return QP_Label(oPC) == r && !QP_Mis(oPC);
}

// Mislabelled: parcel says r, but it isn't theirs. Sets tokens 6340/6341 to
// the TRUE recipient so the refusal line can point the player onward.
int QP_IsMislabel(object oPC, int r)
{
    if (QP_Label(oPC) != r || !QP_Mis(oPC)) return FALSE;
    int nTrue = QP_TrueRec(r);
    SetCustomToken(6340, QP_Name(nTrue));
    SetCustomToken(6341, QP_Place(nTrue));
    return TRUE;
}

// True recipient of a mislabelled parcel.
int QP_IsTrue(object oPC, int r)
{
    int nLabel = QP_Label(oPC);
    return nLabel > 0 && QP_Mis(oPC) && QP_TrueRec(nLabel) == r;
}

// --- Payout — ActionTaken on every accepting entry (normal + true-recipient).
// Guarded so it can never pay twice in a day or without a parcel in hand.
void QP_Pay(object oPC)
{
    object oParcel = QP_Parcel(oPC);
    if (!GetIsObjectValid(oParcel)) return;

    int bMis = GetLocalInt(oParcel, "POST_MIS");
    int nT0  = GetLocalInt(oParcel, "POST_T0");
    DestroyObject(oParcel);

    if (QCD_IsDoneToday(oPC, QP_QUEST)) return;
    QCD_Stamp(oPC, QP_QUEST);

    int nElapsed = QCD_Now() - nT0;
    int bFast = (nT0 > 0 && nElapsed >= 0 && nElapsed <= QP_FAST_SECS);

    int nGold = QP_GOLD_BASE;
    if (bFast) nGold += QP_GOLD_FAST;
    if (bMis)  nGold += QP_GOLD_MIS;

    GiveGoldToCreature(oPC, nGold);
    GiveXPToCreature(oPC, QP_XP);
    AddJournalQuestEntry(QP_QUEST, 2, oPC, FALSE, FALSE, TRUE);

    if (bFast)
        FloatingTextStringOnCreature(
            "Swift delivery! The seal was still warm -- bonus pay.", oPC, FALSE);

    // Misdelivered parcels turn up with a little something extra inside.
    if (bMis)
    {
        switch (d3())
        {
            case 1: CreateItemOnObject("frogpint", oPC, 1);         break;
            case 2: CreateItemOnObject("nw_it_mpotion003", oPC, 1); break;
            case 3: CreateItemOnObject("nw_it_mpotion021", oPC, 1); break;
        }
        FloatingTextStringOnCreature(
            "The rightful owner tips you for untangling the post.", oPC, FALSE);
    }
}
