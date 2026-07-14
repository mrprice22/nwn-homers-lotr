// Hobbit Post (roadmap: hobbit-post)
// ActionTaken when Posco Whitfoot hands over (or re-addresses) today's
// parcel. Destroys any parcel already carried first, so parcels can never
// stack up, then issues a fresh one labelled for today's addressee with the
// accept timestamp for the speed bonus and the misdelivery roll baked in.
#include "q_post_inc"

void main()
{
    object oPC = GetPCSpeaker();
    if (QCD_IsDoneToday(oPC, QP_QUEST))
        return;

    // Sweep out stale/duplicate parcels (DestroyObject is deferred, so walk
    // the inventory rather than re-querying GetItemPossessedBy).
    object oItem = GetFirstItemInInventory(oPC);
    while (GetIsObjectValid(oItem))
    {
        if (GetTag(oItem) == QP_TAG)
            DestroyObject(oItem);
        oItem = GetNextItemInInventory(oPC);
    }

    object oParcel = CreateItemOnObject(QP_TAG, oPC, 1);
    SetLocalInt(oParcel, "POST_DAY", QP_TodayIdx());
    SetLocalInt(oParcel, "POST_T0", QCD_Now());
    if (d100() <= QP_MIS_PCT)
        SetLocalInt(oParcel, "POST_MIS", 1);

    AddJournalQuestEntry(QP_QUEST, 1, oPC, FALSE, FALSE, TRUE);
}
