// ammorep_inc.nss - Quiver of Endless Flight: inventory scan, menu cues, grant.
//
// Activating the quiver opens ammorep_conv, a flat menu listing the ammunition
// stacks the player is carrying, richest first. Picking one grants AMMOREP_GRANT
// more units of that exact ammo. Two uses per quiver, tracked in ammorep_db.nss.
//
// Menu plumbing follows the staged-forge pattern (forge_stg_*): the per-slot cues
// are primed BEFORE the entry renders (here, in ammorep_open.nss, ahead of
// ActionStartConversation), each slot has a StartingConditional (ammorep_c<i>)
// and an Actions Taken (ammorep_p<i>).
//
// Custom tokens:
//   6440-6447   slot labels (ammo name / stack / per-unit worth)
//   6448        menu header (uses remaining, overflow note)

#include "ammorep_db"

const string AMMOREP_TAG   = "ammoreplicator";
const int    AMMOREP_SLOTS = 8;
const int    AMMOREP_TOK   = 6440;  // .. 6447
const int    AMMOREP_TOKHD = 6448;

// Engine cap for a single ammo stack. Only used to bound the copy loop; the grant
// itself reads the stack size back, so it is correct whether the cap is 99 or 999.
const int    AMMOREP_MAXCOPIES = 24;

string AmmoRep_SlotVar(int i) { return "AMMOREP_SLOT_" + IntToString(i); }
string AmmoRep_ValVar(int i)  { return "AMMOREP_VAL_"  + IntToString(i); }

int AmmoRep_IsAmmo(object oItem)
{
    int nBase = GetBaseItemType(oItem);
    return (nBase == BASE_ITEM_ARROW
         || nBase == BASE_ITEM_BOLT
         || nBase == BASE_ITEM_BULLET);
}

// 1234567 -> "1,234,567" (player-facing gold, same convention as ForgeGold).
string AmmoRep_Gold(int n)
{
    if (n < 0) return IntToString(n);
    string sOut = "";
    string sIn  = IntToString(n);
    int nLen = GetStringLength(sIn);
    int i;
    for (i = 0; i < nLen; i++)
    {
        if (i > 0 && ((nLen - i) % 3) == 0) sOut += ",";
        sOut += GetSubString(sIn, i, 1);
    }
    return sOut;
}

// The quiver this player is carrying (OBJECT_INVALID if it is gone).
object AmmoRep_GetQuiver(object oPC)
{
    return GetItemPossessedBy(oPC, AMMOREP_TAG);
}

void AmmoRep_ClearSlots(object oPC)
{
    int i;
    for (i = 0; i < AMMOREP_SLOTS; i++)
    {
        DeleteLocalObject(oPC, AmmoRep_SlotVar(i));
        DeleteLocalInt(oPC, AmmoRep_ValVar(i));
    }
    DeleteLocalInt(oPC, "AMMOREP_COUNT");
}

// Fill the slot locals + cue tokens with the player's ammo stacks, sorted by
// per-unit worth descending. GetGoldPieceValue is a WHOLE-STACK figure (see the
// note on ForgeItemValue in forge_inc.nss), so it is divided by the stack size to
// normalise. Only the richest AMMOREP_SLOTS stacks are shown.
void AmmoRep_Scan(object oPC)
{
    AmmoRep_ClearSlots(oPC);

    int nCount = 0;
    int nSeen  = 0;

    object oItem = GetFirstItemInInventory(oPC);
    while (GetIsObjectValid(oItem))
    {
        if (AmmoRep_IsAmmo(oItem))
        {
            nSeen++;

            int nStack = GetItemStackSize(oItem);
            if (nStack < 1) nStack = 1;
            int nUnit = GetGoldPieceValue(oItem) / nStack;

            // Insertion sort, descending. Starting at AMMOREP_SLOTS lets a rich
            // stack push the current last entry off the end.
            int i = nCount;
            if (i > AMMOREP_SLOTS) i = AMMOREP_SLOTS;
            while (i > 0 && GetLocalInt(oPC, AmmoRep_ValVar(i - 1)) < nUnit)
            {
                if (i < AMMOREP_SLOTS)
                {
                    SetLocalObject(oPC, AmmoRep_SlotVar(i),
                                   GetLocalObject(oPC, AmmoRep_SlotVar(i - 1)));
                    SetLocalInt(oPC, AmmoRep_ValVar(i),
                                GetLocalInt(oPC, AmmoRep_ValVar(i - 1)));
                }
                i--;
            }
            if (i < AMMOREP_SLOTS)
            {
                SetLocalObject(oPC, AmmoRep_SlotVar(i), oItem);
                SetLocalInt(oPC, AmmoRep_ValVar(i), nUnit);
                if (nCount < AMMOREP_SLOTS) nCount++;
            }
        }
        oItem = GetNextItemInInventory(oPC);
    }

    SetLocalInt(oPC, "AMMOREP_COUNT", nCount);

    int s;
    for (s = 0; s < AMMOREP_SLOTS; s++)
    {
        if (s < nCount)
        {
            object oAmmo = GetLocalObject(oPC, AmmoRep_SlotVar(s));
            int nShow = GetItemStackSize(oAmmo);
            if (nShow < 1) nShow = 1;
            SetCustomToken(AMMOREP_TOK + s,
                GetName(oAmmo) + "  (x" + IntToString(nShow) + ", "
                + AmmoRep_Gold(GetLocalInt(oPC, AmmoRep_ValVar(s))) + " gp each)");
        }
        else
        {
            SetCustomToken(AMMOREP_TOK + s, "");
        }
    }

    string sHdr = "Uses remaining: "
                + IntToString(AmmoRep_UsesLeft(AmmoRep_GetQuiver(oPC)));
    if (nSeen > nCount)
        sHdr += "   (showing the " + IntToString(nCount) + " most valuable of "
              + IntToString(nSeen) + " kinds you carry)";
    SetCustomToken(AMMOREP_TOKHD, sHdr);
}

// Add nTotal units of oProto's ammo to oPC. The source stack is grown first, so
// any overflow copies are always made from a FULL stack and can never merge back
// into a partial one and corrupt the tally. Returns the units actually delivered.
int AmmoRep_Grant(object oPC, object oProto, int nTotal)
{
    int nStart = GetItemStackSize(oProto);
    if (nStart < 1) nStart = 1;

    SetItemStackSize(oProto, nStart + nTotal);
    int nDelivered = GetItemStackSize(oProto) - nStart;
    int nRemaining = nTotal - nDelivered;

    int nGuard = 0;
    while (nRemaining > 0 && nGuard < AMMOREP_MAXCOPIES)
    {
        nGuard++;
        object oCopy = CopyItem(oProto, oPC, TRUE);
        if (!GetIsObjectValid(oCopy)) break;

        SetItemStackSize(oCopy, nRemaining);
        int nGot = GetItemStackSize(oCopy);
        if (nGot < 1) { DestroyObject(oCopy); break; }

        nDelivered += nGot;
        nRemaining -= nGot;
    }

    return nDelivered;
}

// Menu slot nSlot was picked: replicate that ammo and burn one use of the quiver.
void AmmoRep_Pick(object oPC, int nSlot)
{
    object oQuiver = AmmoRep_GetQuiver(oPC);
    if (!GetIsObjectValid(oQuiver))
    {
        FloatingTextStringOnCreature(
            "The quiver must be in your possession to use it.", oPC, FALSE);
        return;
    }
    if (AmmoRep_UsesLeft(oQuiver) < 1)
    {
        DestroyObject(oQuiver);
        FloatingTextStringOnCreature("The quiver is spent.", oPC, FALSE);
        return;
    }

    // Re-check the chosen stack: it could have been dropped or sold between the
    // menu opening and the click.
    object oAmmo = GetLocalObject(oPC, AmmoRep_SlotVar(nSlot));
    if (!GetIsObjectValid(oAmmo) || GetItemPossessor(oAmmo) != oPC
        || !AmmoRep_IsAmmo(oAmmo))
    {
        FloatingTextStringOnCreature(
            "That ammunition is no longer in your pack.", oPC, FALSE);
        AmmoRep_ClearSlots(oPC);
        return;
    }

    string sName = GetName(oAmmo);
    int nGiven = AmmoRep_Grant(oPC, oAmmo, AMMOREP_GRANT);
    int nLeft  = AmmoRep_Consume(oQuiver);

    ApplyEffectToObject(DURATION_TYPE_INSTANT,
        EffectVisualEffect(VFX_IMP_MAGBLUE), oPC);
    FloatingTextStringOnCreature(
        "The quiver overflows: " + IntToString(nGiven) + " x " + sName + ".",
        oPC, FALSE);

    if (nLeft < 1)
    {
        DestroyObject(oQuiver);
        ApplyEffectToObject(DURATION_TYPE_INSTANT,
            EffectVisualEffect(VFX_FNF_SUMMON_MONSTER_3), oPC);
        FloatingTextStringOnCreature(
            "Its purpose spent, the quiver crumbles to dust.", oPC, FALSE);
    }
    else
    {
        FloatingTextStringOnCreature(
            "The quiver has " + IntToString(nLeft) + " use remaining.", oPC, FALSE);
    }

    AmmoRep_ClearSlots(oPC);
}
