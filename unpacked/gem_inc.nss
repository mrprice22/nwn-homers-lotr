// gem_inc.nss - Loot Overhaul Phase 5: gem sockets (roadmap Socket-system-for-weapons).
//
// Design: docs.manual/Draft/Loot-Overhaul.html#p5 (adopting Draft/Gem-Socketing.html
// minus its retired jail parts).  Data: loot/gems.json + loot/sockets.json, compiled
// into socket_data_inc.nss by bin/gen-loot-tables.py.  bin/loot_model.py gem_merge /
// item_sockets / gem_drop are the Python mirrors loot-sim and the build gate run -
// change one, change the other.
//
// Item locals (they live in the .bic and survive the party roll's CopyItem):
//   SOCKET_MAX       sockets the item has (never lowered)
//   SOCKET_FILLED    how many are filled
//   SOCKET_<n>_GEM   resref of the gem in socket n
//   SOCKET_VER       socket-schema version last reconciled (LOOTD_SOCK_VER)
//   SOCKET_ROLLED    a rolled item's own count (loot_inc Loot_Roll)
//   SOCKET_BASEDESC / SOCKET_DESC_SET   the description before the socket line
//   GEM_P_N, GEM_P_<i>, GEM_P_<i>_OWN   ForgePropSig of every property a gem has
//                    touched, and whether a gem CREATED it.  forge_inc reads them:
//                    a gem-created property fills no forge slot, and no forge may
//                    strike or rework a gem-touched one (socketing is permanent).
//
// A gem RAISES a property of its family by its tier's steps on the family ladder
// (cost rows weakest first; the last rung is the cap: 2d10 damage, +16 attack), or
// adds it when the item has none.  It never overwrites: an existing value is the
// starting rung (one off the ladder is placed by power, i.e. average damage), and
// a gem that would not make the item stronger is refused and NOT consumed.
//
// Includes loot_inc (-> forge_inc, color).  Do not include "itemprocs" next to it.

#include "loot_inc"
#include "socket_data_inc"

// ---------------------------------------------------------------------------
// Gem identity: blueprint resref sgem_<family>_<tier>
// ---------------------------------------------------------------------------

int Gem_FamilyOfResRef(string sRes)
{
    int nP = GetStringLength(LOOTD_GEM_PREFIX);
    if (GetStringLeft(sRes, nP) != LOOTD_GEM_PREFIX) return -1;
    int n = GetStringLength(sRes);
    if (n < nP + 3 || GetSubString(sRes, n - 2, 1) != "_") return -1;
    return LootD_GemFamIndex(GetSubString(sRes, nP, n - nP - 2));
}

int Gem_TierOfResRef(string sRes)
{
    return Loot_Clamp(StringToInt(GetStringRight(sRes, 1)), 0, LOOTD_GEMTIER_COUNT - 1);
}

string Gem_ResRef(int nFam, int nTier)
{
    return LOOTD_GEM_PREFIX + LootD_GemFamId(nFam) + "_" + IntToString(nTier);
}

// "Flawed Emberstone", in its tier's rarity colour.
string Gem_Name(int nFam, int nTier)
{
    return ColorString(LootD_GemTierWord(nTier) + " " + LootD_GemFamStone(nFam),
                       Loot_RarityColor(nTier));
}

int Gem_IsGem(object oItem)
{
    return Gem_FamilyOfResRef(GetResRef(oItem)) >= 0;
}

// ---------------------------------------------------------------------------
// Socket count
// ---------------------------------------------------------------------------

// Category index (LootD_CatName) of a socketable item, -1 = never socketed.
int Gem_ItemCat(object oItem)
{
    return LootD_SockBaseCat(GetBaseItemType(oItem));
}

// The loot/sockets.json count listed for a module resref, or -1 when unlisted.
int Gem_ListedCount(string sRes)
{
    string sKey = "|" + sRes + ":";
    string sFirst = GetStringLeft(sRes, 1);
    int k;
    for (k = 0; k < 64; k++)
    {
        string s = LootD_SockList(sFirst, k);
        if (s == "") return -1;
        int i = FindSubString(s, sKey);
        if (i >= 0) return StringToInt(GetSubString(s, i + GetStringLength(sKey), 1));
    }
    return -1;
}

// How many sockets oItem should have.  Mirrors loot_model.item_sockets.
int Gem_SocketMax(object oItem)
{
    if (!GetIsObjectValid(oItem) || GetObjectType(oItem) != OBJECT_TYPE_ITEM) return 0;
    int n;
    if (Loot_IsRolled(oItem) && !GetLocalInt(oItem, "LOOT_NAMED"))
        n = GetLocalInt(oItem, "SOCKET_ROLLED");
    else
    {
        if (Gem_ItemCat(oItem) < 0 || GetPlotFlag(oItem) || GetItemCursedFlag(oItem)
            || GetItemStackSize(oItem) > 1)
            return 0;
        n = Gem_ListedCount(GetResRef(oItem));
        if (n < 0) n = LOOTD_SOCK_DEFAULT;
    }
    return Loot_Clamp(n, 0, LOOTD_SOCK_MAX);
}

// The socket line, rebuilt from the item's socket locals.
void Gem_Describe(object oItem)
{
    int nFilled = GetLocalInt(oItem, "SOCKET_FILLED");
    string s = "";
    int i;
    for (i = 0; i < nFilled; i++)
    {
        string sRes = GetLocalString(oItem, "SOCKET_" + IntToString(i) + "_GEM");
        int nFam = Gem_FamilyOfResRef(sRes);
        if (i > 0) s += ", ";
        s += nFam >= 0 ? Gem_Name(nFam, Gem_TierOfResRef(sRes)) : sRes;
    }
    Loot_SetSocketDesc(oItem, s, nFilled);
}

// Bring oItem up to its socket count - it only ever ADDS sockets - and stamp the
// schema version so the login pass skips it until LOOTD_SOCK_VER is bumped.
// Items that can never hold a socket are left untouched (no locals on them).
// Returns the item's socket count.
int Gem_Reconcile(object oItem)
{
    if (!GetIsObjectValid(oItem)) return 0;
    int nCur = GetLocalInt(oItem, "SOCKET_MAX");
    if (GetLocalInt(oItem, "SOCKET_VER") == LOOTD_SOCK_VER) return nCur;
    if (Gem_ItemCat(oItem) < 0 || GetItemStackSize(oItem) > 1) return nCur;
    SetLocalInt(oItem, "SOCKET_VER", LOOTD_SOCK_VER);
    int nWant = Gem_SocketMax(oItem);
    if (nWant > nCur)
    {
        SetLocalInt(oItem, "SOCKET_MAX", nWant);
        Gem_Describe(oItem);
        return nWant;
    }
    return nCur;
}

// ---------------------------------------------------------------------------
// The merge (mirrors loot_model.gem_merge)
// ---------------------------------------------------------------------------

// Strength of cost row nRow of property type nType.
int Gem_Power(int nType, int nRow)
{
    return nType == ITEM_PROPERTY_DAMAGE_BONUS ? LootD_DmgPower(nRow) : nRow;
}

// TRUE when gem family nFam may go into an item of category nCat.
int Gem_Fits(int nFam, int nCat)
{
    if (nCat < 0) return FALSE;
    string sCat = "|" + LootD_CatName(nCat) + "|";
    int k;
    for (k = 0; k < LootD_GemFamAffixCount(nFam); k++)
        if (FindSubString(LootD_AffixCats(LootD_GemFamAffix(nFam, k)), sCat) >= 0)
            return TRUE;
    return FALSE;
}

// Index of a GEM_P_ / LOOT_AFX_ style signature in a counted list, or -1.
int Gem_SigIndex(object oItem, string sCountVar, string sPrefix, string sSig)
{
    int n = GetLocalInt(oItem, sCountVar);
    int i;
    for (i = 0; i < n; i++)
        if (GetLocalString(oItem, sPrefix + IntToString(i)) == sSig)
            return i;
    return -1;
}

// Drop entry nAt from LOOT_AFX_*: a gemmed property is no longer a random affix,
// so the Phase 7 reforge (which strips exactly LOOT_AFX_*) can never take a gem.
void Gem_DropLootAffix(object oItem, int nAt)
{
    int n = GetLocalInt(oItem, "LOOT_AFX_N");
    int i;
    for (i = nAt; i < n - 1; i++)
        SetLocalString(oItem, "LOOT_AFX_" + IntToString(i),
                       GetLocalString(oItem, "LOOT_AFX_" + IntToString(i + 1)));
    DeleteLocalString(oItem, "LOOT_AFX_" + IntToString(n - 1));
    SetLocalInt(oItem, "LOOT_AFX_N", n - 1);
}

// Record that a gem made sNew (replacing sOld, "" when it created the property).
void Gem_TrackProp(object oItem, string sOld, string sNew)
{
    int i = sOld == "" ? -1 : Gem_SigIndex(oItem, "GEM_P_N", "GEM_P_", sOld);
    if (i < 0)
    {
        i = GetLocalInt(oItem, "GEM_P_N");
        SetLocalInt(oItem, "GEM_P_N", i + 1);
        SetLocalInt(oItem, "GEM_P_" + IntToString(i) + "_OWN", sOld == "");
    }
    SetLocalString(oItem, "GEM_P_" + IntToString(i), sNew);
    if (sOld != "")
    {
        int j = Gem_SigIndex(oItem, "LOOT_AFX_N", "LOOT_AFX_", sOld);
        if (j >= 0) Gem_DropLootAffix(oItem, j);
    }
}

// Apply gem (nFam, nTier) to oItem.  "" on success (the change is described in
// the GEM_LAST_MSG local on the item), else the reason it was refused - in which
// case NOTHING on the item changed.
string Gem_Apply(object oItem, int nFam, int nTier)
{
    int nCat = Gem_ItemCat(oItem);
    if (!Gem_Fits(nFam, nCat))
        return "A " + LootD_GemFamStone(nFam) + " cannot be set in this kind of item.";
    int nLen = LootD_GemFamLadderLen(nFam);
    int nSteps = LootD_GemFamSteps(nFam, nTier);
    string sCat = "|" + LootD_CatName(nCat) + "|";

    // 1. the item's own property of the family, in the family's preference order
    int nType = -1;
    int nSub = -1;
    int nOld = -1;
    itemproperty ipOld;
    int k;
    for (k = 0; k < LootD_GemFamAffixCount(nFam) && nOld < 0; k++)
    {
        int t = LootD_GemFamType(nFam, k);
        int s = LootD_GemFamSub(nFam, k);
        itemproperty ip = GetFirstItemProperty(oItem);
        while (GetIsItemPropertyValid(ip))
        {
            if (GetItemPropertyDurationType(ip) == DURATION_TYPE_PERMANENT
                && GetItemPropertyType(ip) == t
                && (s < 0 || GetItemPropertySubType(ip) == s))
            {
                nType = t;
                nSub = s;
                nOld = GetItemPropertyCostTableValue(ip);
                ipOld = ip;
                break;
            }
            ip = GetNextItemProperty(oItem);
        }
    }

    // 2. the new rung
    int nNew;
    if (nOld >= 0)
    {
        int nPos = -1;
        int bOn = FALSE;
        for (k = 0; k < nLen; k++)
            if (LootD_GemFamLadder(nFam, k) == nOld) { nPos = k; bOn = TRUE; break; }
        if (!bOn)
        {
            int nPw = Gem_Power(nType, nOld);
            for (k = 0; k < nLen; k++)
                if (Gem_Power(nType, LootD_GemFamLadder(nFam, k)) <= nPw) nPos = k;
        }
        int nIdx = nPos + nSteps;
        if (nIdx > nLen - 1) nIdx = nLen - 1;
        if (nIdx <= nPos)
            return "Its " + LootD_GemFamEffect(nFam) + " is already at the socket cap.";
        nNew = LootD_GemFamLadder(nFam, nIdx);
        if (!bOn && Gem_Power(nType, nNew) <= Gem_Power(nType, nOld))
            return "That gem would not make its " + LootD_GemFamEffect(nFam) + " any stronger.";
    }
    else
    {
        // created: the first of the family's affixes this category allows
        for (k = 0; k < LootD_GemFamAffixCount(nFam); k++)
            if (FindSubString(LootD_AffixCats(LootD_GemFamAffix(nFam, k)), sCat) >= 0)
            {
                nType = LootD_GemFamType(nFam, k);
                nSub = LootD_GemFamSub(nFam, k);
                break;
            }
        if (nType < 0)
            return "A " + LootD_GemFamStone(nFam) + " cannot be set in this kind of item.";
        int nI = nSteps > nLen ? nLen - 1 : nSteps - 1;
        nNew = LootD_GemFamLadder(nFam, nI);
    }

    // 3. build and self-check before touching the item
    itemproperty ipNew = Loot_MakeIP(nType, nSub < 0 ? 0 : nSub, nNew);
    if (!GetIsItemPropertyValid(ipNew) || GetItemPropertyType(ipNew) != nType
        || GetItemPropertyCostTableValue(ipNew) != nNew)
    {
        Loot_Warn("gem family '" + LootD_GemFamId(nFam) + "' built the wrong property (type "
                  + IntToString(GetItemPropertyType(ipNew)) + " cost "
                  + IntToString(GetItemPropertyCostTableValue(ipNew)) + ")");
        return "The gem will not take - tell the admin (LOOT: in the server log).";
    }
    string sOldName = nOld >= 0 ? ForgePropName(ipOld) : "";
    string sOldSig = nOld >= 0 ? ForgePropSig(ipOld) : "";
    if (nOld >= 0)
        RemoveItemProperty(oItem, ipOld);
    AddItemProperty(DURATION_TYPE_PERMANENT, ipNew, oItem);

    // 4. the new property's signature, read off the item (its cost row tells it
    // apart from the old one, which may still be listed until the script ends)
    string sNewSig = "";
    itemproperty ipS = GetFirstItemProperty(oItem);
    while (GetIsItemPropertyValid(ipS))
    {
        if (GetItemPropertyDurationType(ipS) == DURATION_TYPE_PERMANENT
            && GetItemPropertyType(ipS) == nType
            && GetItemPropertyCostTableValue(ipS) == nNew
            && (nSub < 0 || GetItemPropertySubType(ipS) == nSub))
        {
            sNewSig = ForgePropSig(ipS);
            break;
        }
        ipS = GetNextItemProperty(oItem);
    }
    if (sNewSig == "") sNewSig = ForgePropSig(ipNew);
    Gem_TrackProp(oItem, sOldSig, sNewSig);
    SetLocalString(oItem, "GEM_LAST_MSG", nOld >= 0
        ? sOldName + " -> " + ForgePropName(ipNew)
        : ForgePropName(ipNew) + " (new)");
    return "";
}

// Set gem oGem into oItem (both already validated as items the socketing PC
// holds).  "" on success, else the refusal - the gem is consumed only on success.
string Gem_Socket(object oItem, object oGem)
{
    string sRes = GetResRef(oGem);
    int nFam = Gem_FamilyOfResRef(sRes);
    if (nFam < 0) return "That is not a socket gem.";
    if (Gem_IsGem(oItem)) return "A gem cannot be set in another gem.";
    if (!GetIdentified(oItem)) return "Identify the item first - you cannot see where a gem would sit.";
    int nMax = Gem_Reconcile(oItem);
    if (nMax <= 0) return "That item has no sockets.";
    int nFilled = GetLocalInt(oItem, "SOCKET_FILLED");
    if (nFilled >= nMax) return "Every socket in that item is already filled.";
    int nTier = Gem_TierOfResRef(sRes);
    string sWhy = Gem_Apply(oItem, nFam, nTier);
    if (sWhy != "") return sWhy;
    SetLocalString(oItem, "SOCKET_" + IntToString(nFilled) + "_GEM", sRes);
    SetLocalInt(oItem, "SOCKET_FILLED", nFilled + 1);
    Gem_Describe(oItem);
    DestroyObject(oGem);
    return "";
}

// ---------------------------------------------------------------------------
// Drops (mirrors loot_model.gem_tier / gem_drop)
// ---------------------------------------------------------------------------

int Gem_RollTier(int nLvl, int nFloor)
{
    int nF = LootD_GemBandFloor(nLvl);
    if (nFloor > nF) nF = nFloor;
    int nT = Loot_PickRarity(Loot_Clamp(nF, 0, LOOTD_RARITY_COUNT - 1));
    int nC = LootD_GemBandCeil(nLvl);
    return nT > nC ? nC : nT;
}

int Gem_PickFamily()
{
    int nTotal = 0;
    int i;
    for (i = 0; i < LOOTD_GEMFAM_COUNT; i++) nTotal += LootD_GemFamWeight(i);
    if (nTotal <= 0) return -1;
    int r = Random(nTotal);
    for (i = 0; i < LOOTD_GEMFAM_COUNT; i++)
    {
        r -= LootD_GemFamWeight(i);
        if (r < 0) return i;
    }
    return -1;
}

// Create gem (nFam, nTier) on oDest, named in its rarity colour.
object Gem_Create(int nFam, int nTier, object oDest)
{
    object oGem = CreateItemOnObject(Gem_ResRef(nFam, nTier), oDest);
    if (!GetIsObjectValid(oGem))
    {
        Loot_Warn("gem '" + Gem_ResRef(nFam, nTier) + "' could not be created");
        return OBJECT_INVALID;
    }
    SetName(oGem, Gem_Name(nFam, nTier));
    Loot_MarkCorpseLoot(oGem, oDest);
    return oGem;
}

// One random gem at loot level nLvl, tier floor nFloor, onto oDest.
object Gem_Drop(int nLvl, int nFloor, object oDest)
{
    int nFam = Gem_PickFamily();
    if (nFam < 0) return OBJECT_INVALID;
    return Gem_Create(nFam, Gem_RollTier(Loot_Clamp(nLvl, 1, LOOTD_MAX_LEVEL), nFloor), oDest);
}

// ---------------------------------------------------------------------------
// Login pass: give existing gear its sockets (gem_scan_step does the work)
// ---------------------------------------------------------------------------

// Queue every item oPC carries or wears; gem_scan_step reconciles a few per step.
void Gem_BeginScan(object oPC)
{
    if (!GetIsObjectValid(oPC) || !GetIsPC(oPC) || GetIsDM(oPC)) return;
    int n = 0;
    int i;
    for (i = 0; i < INVENTORY_SLOT_CWEAPON_L; i++)
    {
        object oE = GetItemInSlot(i, oPC);
        if (GetIsObjectValid(oE) && GetLocalInt(oE, "SOCKET_VER") != LOOTD_SOCK_VER
            && Gem_ItemCat(oE) >= 0)
        {
            SetLocalObject(oPC, "GEM_SCAN_" + IntToString(n), oE);
            n++;
        }
    }
    object oItem = GetFirstItemInInventory(oPC);
    while (GetIsObjectValid(oItem))
    {
        if (GetLocalInt(oItem, "SOCKET_VER") != LOOTD_SOCK_VER && Gem_ItemCat(oItem) >= 0)
        {
            SetLocalObject(oPC, "GEM_SCAN_" + IntToString(n), oItem);
            n++;
        }
        oItem = GetNextItemInInventory(oPC);
    }
    SetLocalInt(oPC, "GEM_SCAN_N", n);
    SetLocalInt(oPC, "GEM_SCAN_I", 0);
    if (n > 0)
        DelayCommand(0.1, ExecuteScript("gem_scan_step", oPC));
}
