// loot_inc.nss - Season 3 rolled loot: Loot_Roll() and its helpers.
//
// Roadmap: loot-overhaul epic, lo-loot-core (Phase 2).  Design:
// docs.manual/Draft/Loot-Overhaul.html.  Data: loot/*.json at the repo root,
// compiled into loot_data_inc.nss by bin/gen-loot-tables.py (never hand-edit
// that file).  bin/loot_model.py roll() is the Python mirror of Loot_Roll()
// that bin/loot-sim.py and the build gate run - change one, change the other.
//
// What a roll does, in order:
//   1. rarity  - weighted pick, raised to the caller's floor, then a chance of
//                a one- or two-tier upgrade;
//   2. named   - a top-tier roll may award a curated existing item instead
//                (loot/named.json, inside its loot-level window);
//   3. base    - category from the profile's weights, then a base item; the
//                item is created from that base's forge blank (forge_inc
//                ForgeBlankResRef) and given a random appearance taken from
//                one of the module's own items of that base;
//   4. affixes - an optional downside (which buys one extra upside and a
//                bigger budget), then the upsides; never two of one group;
//   5. budget  - the whole set is priced on a scratch forge blank with the
//                engine's own GetGoldPieceValue, exactly as the forge prices
//                an item, and stepped down until it fits the rarity's budget
//                for this loot level.  Properties reach the real item only
//                once the set fits - nothing is ever read back after a
//                removal (the forge_inc ForgeRebuildValue rule);
//   6. name    - "<Prefix> <Base> of <Suffix>" in the rarity's colour;
//   7. stamps  - LOOT_VER / LOOT_LVL / LOOT_RARITY / LOOT_PROFILE, plus
//                LOOT_AFX_N and LOOT_AFX_<i> = ForgePropSig of each random
//                property.  They live in the .bic and survive the party
//                roll's CopyItem(..., TRUE); they are what lets a Fate token
//                (Phase 7) re-roll exactly the random affixes and never a
//                forged enchantment or a socketed gem.
//
// No contraband by construction: a rolled item is bounded by its rarity's
// value budget and by the gate-checked affix ladders - nothing judges gear
// after the fact (the jail is retired).
//
// Includes forge_inc (which pulls in color).  Do not include "color" or
// "itemprocs" next to this file.

#include "forge_inc"
#include "loot_data_inc"
#include "loot_db"

const int LOOT_VER = 1;

// Rarity indices (loot/rarity.json order).
const int LOOT_RARITY_COMMON    = 0;
const int LOOT_RARITY_UNCOMMON  = 1;
const int LOOT_RARITY_RARE      = 2;
const int LOOT_RARITY_EPIC      = 3;
const int LOOT_RARITY_LEGENDARY = 4;

// ---------------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------------

int Loot_Clamp(int n, int nLo, int nHi)
{
    if (n < nLo) return nLo;
    if (n > nHi) return nHi;
    return n;
}

// The color.nss constant a rarity is drawn in.
string Loot_RarityColor(int nRarity)
{
    string s = LootD_RarityColorName(nRarity);
    if (s == "COLOR_WHITE")        return COLOR_WHITE;
    if (s == "COLOR_GREEN")        return COLOR_GREEN;
    if (s == "COLOR_BLUE")         return COLOR_BLUE;
    if (s == "COLOR_PURPLE")       return COLOR_PURPLE;
    if (s == "COLOR_ORANGE")       return COLOR_ORANGE;
    if (s == "COLOR_LIGHT_BLUE")   return COLOR_LIGHT_BLUE;
    if (s == "COLOR_LIGHT_ORANGE") return COLOR_LIGHT_ORANGE;
    if (s == "COLOR_LIGHT_PURPLE") return COLOR_LIGHT_PURPLE;
    if (s == "COLOR_YELLOW")       return COLOR_YELLOW;
    if (s == "COLOR_RED")          return COLOR_RED;
    if (s == "COLOR_GRAY")         return COLOR_GRAY;
    return COLOR_WHITE;
}

// Rarity name in its own colour, e.g. for messages.
string Loot_RarityLabel(int nRarity)
{
    return ColorString(LootD_RarityName(nRarity), Loot_RarityColor(nRarity));
}

// Budget for a rarity at a loot level, with the downside bonus when bDown.
int Loot_Budget(int nRarity, int nLvl, int bDown)
{
    int nB = LootD_RarityBudget(nRarity, nLvl);
    if (bDown)
        nB = nB * (100 + LootD_RarityDownPct(nRarity)) / 100;
    return nB;
}

void Loot_Warn(string sMsg)
{
    WriteTimestampedLogEntry("LOOT: " + sMsg);
}

// ---------------------------------------------------------------------------
// Picks (each mirrors the matching step of loot_model.roll)
// ---------------------------------------------------------------------------

int Loot_PickRarity(int nFloor)
{
    int nTotal = 0;
    int i;
    for (i = 0; i < LOOTD_RARITY_COUNT; i++)
        nTotal += LootD_RarityWeight(i);
    int nIdx = 0;
    if (nTotal > 0)
    {
        int r = Random(nTotal);
        for (i = 0; i < LOOTD_RARITY_COUNT; i++)
        {
            r -= LootD_RarityWeight(i);
            if (r < 0) { nIdx = i; break; }
        }
    }
    if (nIdx < nFloor) nIdx = nFloor;
    int nRoll = Random(1000);
    int nTwo = LootD_RarityUpTwo(nIdx);
    if (nRoll < nTwo)
        nIdx += 2;
    else if (nRoll < nTwo + LootD_RarityUpOne(nIdx))
        nIdx += 1;
    return Loot_Clamp(nIdx, 0, LOOTD_RARITY_COUNT - 1);
}

// Index into the named pool for this loot level, or -1.
// A named-pool item inside its level window (and, for a profile with a
// "bases" filter, of an allowed base item), or -1.
int Loot_PickNamed(int nLvl, int nProfile)
{
    int nTotal = 0;
    int i;
    for (i = 0; i < LOOTD_NAMED_COUNT; i++)
        if (nLvl >= LootD_NamedMin(i) && nLvl <= LootD_NamedMax(i)
            && LootD_ProfileBaseOk(nProfile, LootD_NamedBase(i)))
            nTotal += LootD_NamedWeight(i);
    if (nTotal <= 0) return -1;
    int r = Random(nTotal);
    for (i = 0; i < LOOTD_NAMED_COUNT; i++)
    {
        if (nLvl < LootD_NamedMin(i) || nLvl > LootD_NamedMax(i)) continue;
        if (!LootD_ProfileBaseOk(nProfile, LootD_NamedBase(i))) continue;
        r -= LootD_NamedWeight(i);
        if (r < 0) return i;
    }
    return -1;
}

int Loot_PickCategory(int nProfile)
{
    int nTotal = 0;
    int c;
    for (c = 0; c < LOOTD_CAT_COUNT; c++)
        nTotal += LootD_ProfileCatWeight(nProfile, c);
    if (nTotal <= 0) return -1;
    int r = Random(nTotal);
    for (c = 0; c < LOOTD_CAT_COUNT; c++)
    {
        r -= LootD_ProfileCatWeight(nProfile, c);
        if (r < 0) return c;
    }
    return -1;
}

// Weight of base nK of category nCat for profile nProfile (0 when the
// profile's "bases" filter excludes it).
int Loot_BaseWeightFor(int nCat, int nK, int nProfile)
{
    if (!LootD_ProfileBaseOk(nProfile, LootD_BaseRow(nCat, nK))) return 0;
    return LootD_BaseWeight(nCat, nK);
}

// Base item row for a category (inside the profile's base filter), or -1.
int Loot_PickBase(int nCat, int nProfile)
{
    int n = LootD_BaseCount(nCat);
    int nTotal = 0;
    int k;
    for (k = 0; k < n; k++)
        nTotal += Loot_BaseWeightFor(nCat, k, nProfile);
    if (nTotal <= 0) return -1;
    int r = Random(nTotal);
    for (k = 0; k < n; k++)
    {
        r -= Loot_BaseWeightFor(nCat, k, nProfile);
        if (r < 0) return LootD_BaseRow(nCat, k);
    }
    return -1;
}

int Loot_AffixEligible(int nAffix, string sCat, int nLvl, int bDown, string sUsed)
{
    if (LootD_AffixIsDown(nAffix) != bDown) return FALSE;
    if (LootD_AffixWeight(nAffix) <= 0) return FALSE;
    if (nLvl < LootD_AffixMinLevel(nAffix)) return FALSE;
    if (FindSubString(LootD_AffixCats(nAffix), "|" + sCat + "|") < 0) return FALSE;
    if (FindSubString(sUsed, "|" + LootD_AffixGroup(nAffix) + "|") >= 0) return FALSE;
    return TRUE;
}

// Weighted pick among eligible affixes, or -1.
int Loot_PickAffix(string sCat, int nLvl, int bDown, string sUsed)
{
    int nTotal = 0;
    int i;
    for (i = 0; i < LOOTD_AFFIX_COUNT; i++)
        if (Loot_AffixEligible(i, sCat, nLvl, bDown, sUsed))
            nTotal += LootD_AffixWeight(i);
    if (nTotal <= 0) return -1;
    int r = Random(nTotal);
    for (i = 0; i < LOOTD_AFFIX_COUNT; i++)
    {
        if (!Loot_AffixEligible(i, sCat, nLvl, bDown, sUsed)) continue;
        r -= LootD_AffixWeight(i);
        if (r < 0) return i;
    }
    return -1;
}

// A ladder step inside the affix's window: the best of (1 + nBias) rolls.
int Loot_PickStep(int nAffix, int nLvl, int nBias)
{
    int nLo = LootD_AffixLo(nAffix, nLvl);
    int nHi = LootD_AffixHi(nAffix, nLvl);
    if (nHi < nLo) nHi = nLo;
    int nStep = nLo + Random(nHi - nLo + 1);
    int b;
    for (b = 0; b < nBias; b++)
    {
        int nAlt = nLo + Random(nHi - nLo + 1);
        if (nAlt > nStep) nStep = nAlt;
    }
    return nStep;
}

// ---------------------------------------------------------------------------
// The chosen-affix work list, kept as locals on the item being built
// ---------------------------------------------------------------------------

void Loot_WorkAdd(object oWork, int nAffix, int nStep)
{
    int n = GetLocalInt(oWork, "LW_N");
    SetLocalInt(oWork, "LW_A" + IntToString(n), nAffix);
    SetLocalInt(oWork, "LW_S" + IntToString(n), nStep);
    SetLocalInt(oWork, "LW_N", n + 1);
}

void Loot_WorkRemove(object oWork, int nAt)
{
    int n = GetLocalInt(oWork, "LW_N");
    int k;
    for (k = nAt; k < n - 1; k++)
    {
        SetLocalInt(oWork, "LW_A" + IntToString(k), GetLocalInt(oWork, "LW_A" + IntToString(k + 1)));
        SetLocalInt(oWork, "LW_S" + IntToString(k), GetLocalInt(oWork, "LW_S" + IntToString(k + 1)));
    }
    DeleteLocalInt(oWork, "LW_A" + IntToString(n - 1));
    DeleteLocalInt(oWork, "LW_S" + IntToString(n - 1));
    SetLocalInt(oWork, "LW_N", n - 1);
}

void Loot_WorkClear(object oWork)
{
    int n = GetLocalInt(oWork, "LW_N");
    int k;
    for (k = 0; k < n; k++)
    {
        DeleteLocalInt(oWork, "LW_A" + IntToString(k));
        DeleteLocalInt(oWork, "LW_S" + IntToString(k));
    }
    DeleteLocalInt(oWork, "LW_N");
}

itemproperty Loot_WorkIP(object oWork, int k)
{
    int a = GetLocalInt(oWork, "LW_A" + IntToString(k));
    int s = GetLocalInt(oWork, "LW_S" + IntToString(k));
    return Loot_MakeIP(LootD_AffixType(a), LootD_AffixSub(a), LootD_AffixLadder(a, s));
}

// Engine value of base nBase carrying the work list: priced on a fresh forge
// blank in the forge vault, as ForgeRebuildValue prices any item.  -1 = no
// valuation possible (no vault or no blank).
int Loot_PriceWork(int nBase, object oWork)
{
    object oHolder = ForgeHolder();
    if (!GetIsObjectValid(oHolder)) return -1;
    object oBlank = CreateItemOnObject(ForgeBlankResRef(nBase), oHolder);
    if (!GetIsObjectValid(oBlank)) return -1;
    int n = GetLocalInt(oWork, "LW_N");
    int k;
    for (k = 0; k < n; k++)
    {
        itemproperty ip = Loot_WorkIP(oWork, k);
        if (GetIsItemPropertyValid(ip))
            AddItemProperty(DURATION_TYPE_PERMANENT, ip, oBlank);
    }
    int nValue = GetGoldPieceValue(oBlank);
    DestroyObject(oBlank);
    return nValue;
}

// ---------------------------------------------------------------------------
// Appearance
// ---------------------------------------------------------------------------

// The nIdx-th comma-separated int of sList.
int Loot_CsvInt(string sList, int nIdx)
{
    int i;
    int nComma;
    for (i = 0; i < nIdx; i++)
    {
        nComma = FindSubString(sList, ",");
        if (nComma < 0) return -1;
        sList = GetSubString(sList, nComma + 1, GetStringLength(sList));
    }
    nComma = FindSubString(sList, ",");
    if (nComma >= 0) sList = GetStringLeft(sList, nComma);
    return StringToInt(sList);
}

object Loot_Reshape(object oItem, int nType, int nIndex, int nValue)
{
    if (nValue < 0) return oItem;
    object oNew = CopyItemAndModify(oItem, nType, nIndex, nValue, TRUE);
    if (!GetIsObjectValid(oNew)) return oItem;
    DestroyObject(oItem);
    return oNew;
}

// Give oItem the look of a random donor (one of the module's own items of
// that base - loot/bases.json).  Returns the (possibly new) item.
object Loot_ApplyDonor(object oItem, int nBase)
{
    int nDonors = LootD_DonorCount(nBase);
    if (nDonors <= 0) return oItem;
    string sDonor = LootD_Donor(nBase, Random(nDonors));
    int nModel = LootD_BaseModelType(nBase);
    int k;
    if (nModel == 0 || nModel == 1)
        oItem = Loot_Reshape(oItem, ITEM_APPR_TYPE_SIMPLE_MODEL, 0, Loot_CsvInt(sDonor, 0));
    else if (nModel == 2)
    {
        for (k = 0; k < 3; k++)
            oItem = Loot_Reshape(oItem, ITEM_APPR_TYPE_WEAPON_MODEL, k, Loot_CsvInt(sDonor, k));
    }
    else if (nModel == 3)
    {
        for (k = 0; k < 19; k++)
            oItem = Loot_Reshape(oItem, ITEM_APPR_TYPE_ARMOR_MODEL, k, Loot_CsvInt(sDonor, k));
    }
    return oItem;
}

// ---------------------------------------------------------------------------
// Stamps
// ---------------------------------------------------------------------------

void Loot_StampCommon(object oItem, int nLvl, int nRarity, string sProfile)
{
    SetLocalInt(oItem, "LOOT_VER", LOOT_VER);
    SetLocalInt(oItem, "LOOT_LVL", nLvl);
    SetLocalInt(oItem, "LOOT_RARITY", nRarity);
    SetLocalString(oItem, "LOOT_PROFILE", sProfile);
}

// True when oItem was produced by Loot_Roll.
int Loot_IsRolled(object oItem)
{
    return GetLocalInt(oItem, "LOOT_VER") > 0;
}

// A rolled item put on a non-PC creature (a corpse, Phase 4) must be droppable:
// Jasperre's DeathCheck / DeleteAllThings destroys a dead creature's
// non-droppable items, so it would never reach the party roll.
void Loot_MarkCorpseLoot(object oItem, object oDest)
{
    if (GetObjectType(oDest) == OBJECT_TYPE_CREATURE && !GetIsPC(oDest))
        SetDroppableFlag(oItem, TRUE);
}

// Move an item built in the forge vault to its destination.
object Loot_Deliver(object oItem, object oDest)
{
    if (!GetIsObjectValid(oDest) || GetItemPossessor(oItem) == oDest) return oItem;
    object oCopy = CopyItem(oItem, oDest, TRUE);
    if (!GetIsObjectValid(oCopy)) return oItem;
    DestroyObject(oItem);
    Loot_MarkCorpseLoot(oCopy, oDest);
    return oCopy;
}

// A named-pool award inside its level window, created on oDest and stamped at
// nRarity.  OBJECT_INVALID when the pool has nothing for this level/profile.
// Mirrors loot_model.give_named: Loot_Roll's named branch and a boss's separate
// named roll (loot_ondeath, Phase 4) both come through here.
object Loot_GiveNamed(int nLvl, int nRarity, string sProfile, object oBeneficiary, object oDest)
{
    int nProfile = LootD_ProfileIndex(sProfile);
    if (nProfile < 0) return OBJECT_INVALID;
    int nNamed = Loot_PickNamed(nLvl, nProfile);
    if (nNamed < 0) return OBJECT_INVALID;
    string sRes = LootD_NamedResRef(nNamed);
    object oNamed = CreateItemOnObject(sRes, oDest);
    if (!GetIsObjectValid(oNamed))
    {
        Loot_Warn("named item '" + sRes + "' could not be created");
        return OBJECT_INVALID;
    }
    Loot_StampCommon(oNamed, nLvl, nRarity, sProfile);
    SetLocalInt(oNamed, "LOOT_NAMED", 1);
    SetLocalInt(oNamed, "LOOT_AFX_N", 0);
    Loot_MarkCorpseLoot(oNamed, oDest);
    Loot_LogRoll(sProfile == "lab" ? "lab" : "roll", sProfile, nLvl, nRarity,
                 GetBaseItemType(oNamed), sRes, -1, oBeneficiary);
    return oNamed;
}

// ---------------------------------------------------------------------------
// The roll
// ---------------------------------------------------------------------------

// Create one rolled item on oDest (a container, creature or PC).
//   nLevel       loot level 1..60 (LootD_LevelForCR maps a CR onto it)
//   nRarityFloor lowest rarity index the roll may land on
//   sProfile     loot/sources.json profile ("lab", "chest_low", "boss", ...)
//   oBeneficiary who it is for (Phase 6 wishlist; logged), may be invalid
// Returns the item, or OBJECT_INVALID when nothing could be built.
object Loot_Roll(int nLevel, int nRarityFloor, string sProfile,
                 object oBeneficiary, object oDest)
{
    int nLvl = Loot_Clamp(nLevel, 1, LOOTD_MAX_LEVEL);
    int nProfile = LootD_ProfileIndex(sProfile);
    if (nProfile < 0)
    {
        Loot_Warn("unknown profile '" + sProfile + "'");
        return OBJECT_INVALID;
    }
    int nRarity = Loot_PickRarity(Loot_Clamp(nRarityFloor, 0, LOOTD_RARITY_COUNT - 1));

    // 2. named pool
    if (Random(1000) < LootD_RarityNamed(nRarity))
    {
        object oNamed = Loot_GiveNamed(nLvl, nRarity, sProfile, oBeneficiary, oDest);
        if (GetIsObjectValid(oNamed)) return oNamed;
    }

    // 3. base
    int nCat = Loot_PickCategory(nProfile);
    int nBase = nCat < 0 ? -1 : Loot_PickBase(nCat, nProfile);
    if (nBase < 0)
    {
        Loot_Warn("profile '" + sProfile + "' has no base items");
        return OBJECT_INVALID;
    }
    string sCat = LootD_CatName(nCat);
    object oHolder = ForgeHolder();
    object oItem = CreateItemOnObject(ForgeBlankResRef(nBase), GetIsObjectValid(oHolder) ? oHolder : oDest);
    if (!GetIsObjectValid(oItem))
    {
        Loot_Warn("no forge blank for base item " + IntToString(nBase));
        return OBJECT_INVALID;
    }
    oItem = Loot_ApplyDonor(oItem, nBase);

    // 4. affixes
    int nUp = LootD_RarityAffMin(nRarity)
            + Random(LootD_RarityAffMax(nRarity) - LootD_RarityAffMin(nRarity) + 1);
    string sUsed = "|";
    int bDown = FALSE;
    int a;
    if (Random(1000) < LootD_RarityDownside(nRarity))
    {
        a = Loot_PickAffix(sCat, nLvl, TRUE, sUsed);
        if (a >= 0)
        {
            Loot_WorkAdd(oItem, a, Loot_PickStep(a, nLvl, 0));
            sUsed += LootD_AffixGroup(a) + "|";
            bDown = TRUE;
            nUp++;
        }
    }
    int nBias = LootD_RarityRollBias(nRarity);
    int u;
    for (u = 0; u < nUp; u++)
    {
        a = Loot_PickAffix(sCat, nLvl, FALSE, sUsed);
        if (a < 0) break;
        Loot_WorkAdd(oItem, a, Loot_PickStep(a, nLvl, nBias));
        sUsed += LootD_AffixGroup(a) + "|";
    }

    // 5. budget: step the last upside that can still step down; once none
    // can, drop the last upside.  The first-rolled affix gives ground last.
    int nBudget = Loot_Budget(nRarity, nLvl, bDown);
    int nValue = Loot_PriceWork(nBase, oItem);
    int nSteps = 0;
    int n;
    int j;
    int k;
    while (nValue > nBudget && nSteps < 64)
    {
        nSteps++;
        n = GetLocalInt(oItem, "LW_N");
        j = -1;
        for (k = n - 1; k >= 0; k--)
        {
            if (!LootD_AffixIsDown(GetLocalInt(oItem, "LW_A" + IntToString(k)))
                && GetLocalInt(oItem, "LW_S" + IntToString(k)) > 0)
            {
                j = k;
                break;
            }
        }
        if (j >= 0)
            SetLocalInt(oItem, "LW_S" + IntToString(j), GetLocalInt(oItem, "LW_S" + IntToString(j)) - 1);
        else
        {
            int nLastUp = -1;
            for (k = n - 1; k >= 0; k--)
                if (!LootD_AffixIsDown(GetLocalInt(oItem, "LW_A" + IntToString(k))))
                {
                    nLastUp = k;
                    break;
                }
            if (nLastUp < 0) break;
            Loot_WorkRemove(oItem, nLastUp);
        }
        nValue = Loot_PriceWork(nBase, oItem);
    }
    if (nValue < 0)
    {
        Loot_Warn("could not price base item " + IntToString(nBase) + " (forge vault missing?)");
        Loot_WorkClear(oItem);
        DestroyObject(oItem);
        return OBJECT_INVALID;
    }

    // Apply the set that fits.  Self-check: each constructor must yield the
    // property type (and cost row) that was asked for - a wrong argument
    // order would otherwise ship silently.
    string sPrefix = "";
    string sSuffix = "";
    int nUps = 0;
    n = GetLocalInt(oItem, "LW_N");
    for (k = 0; k < n; k++)
    {
        a = GetLocalInt(oItem, "LW_A" + IntToString(k));
        int nType = LootD_AffixType(a);
        int nCost = LootD_AffixLadder(a, GetLocalInt(oItem, "LW_S" + IntToString(k)));
        itemproperty ip = Loot_MakeIP(nType, LootD_AffixSub(a), nCost);
        if (!GetIsItemPropertyValid(ip) || GetItemPropertyType(ip) != nType
            || (nCost != 0 && GetItemPropertyCostTableValue(ip) != nCost))
        {
            Loot_Warn("affix '" + LootD_AffixId(a) + "' built the wrong property (type "
                      + IntToString(GetItemPropertyType(ip)) + " cost "
                      + IntToString(GetItemPropertyCostTableValue(ip)) + ", wanted type "
                      + IntToString(nType) + " cost " + IntToString(nCost) + ") - skipped");
            continue;
        }
        AddItemProperty(DURATION_TYPE_PERMANENT, ip, oItem);
        if (!LootD_AffixIsDown(a))
        {
            if (nUps == 0) sPrefix = LootD_AffixPrefix(a);
            else if (nUps == 1) sSuffix = LootD_AffixSuffix(a);
            nUps++;
        }
    }
    Loot_WorkClear(oItem);

    // 6. name + description
    string sName = LootD_BaseName(nBase);
    if (sPrefix != "") sName = sPrefix + " " + sName;
    if (sSuffix != "") sName = sName + " of " + sSuffix;
    SetName(oItem, ColorString(sName, Loot_RarityColor(nRarity)));
    SetDescription(oItem, LootD_RarityName(nRarity) + " " + LootD_BaseName(nBase)
                   + ", loot level " + IntToString(nLvl) + ".");
    SetTag(oItem, "loot_" + IntToString(nBase));

    // 7. stamps: one ForgePropSig per random property, read off the item
    Loot_StampCommon(oItem, nLvl, nRarity, sProfile);
    int nAfx = 0;
    itemproperty ipS = GetFirstItemProperty(oItem);
    while (GetIsItemPropertyValid(ipS))
    {
        if (GetItemPropertyDurationType(ipS) == DURATION_TYPE_PERMANENT)
        {
            SetLocalString(oItem, "LOOT_AFX_" + IntToString(nAfx), ForgePropSig(ipS));
            nAfx++;
        }
        ipS = GetNextItemProperty(oItem);
    }
    SetLocalInt(oItem, "LOOT_AFX_N", nAfx);

    if (Random(1000) < LootD_RarityUnid(nRarity))
        SetIdentified(oItem, FALSE);

    Loot_LogRoll(sProfile == "lab" ? "lab" : "roll", sProfile, nLvl, nRarity, nBase,
                 sName, nValue, oBeneficiary);
    return Loot_Deliver(oItem, oDest);
}

// A profile's full drop: its roll count, at its rarity floor (or the caller's,
// whichever is higher).  Returns how many items were created.
int Loot_RollProfile(int nLevel, string sProfile, object oBeneficiary, object oDest,
                     int nFloor = 0)
{
    int nProfile = LootD_ProfileIndex(sProfile);
    if (nProfile < 0) return 0;
    int nRolls = LootD_ProfileRolls(nProfile);
    int nF = LootD_ProfileFloor(nProfile);
    if (nFloor > nF) nF = nFloor;
    int nMade = 0;
    int i;
    for (i = 0; i < nRolls; i++)
        if (GetIsObjectValid(Loot_Roll(nLevel, nF, sProfile, oBeneficiary, oDest)))
            nMade++;
    return nMade;
}

// ---------------------------------------------------------------------------
// Containers (Phase 3) - each step mirrors loot_model.chest_contents
// ---------------------------------------------------------------------------

// Loot level of an area (loot/area_levels.json: median hostile CR, or an
// override), cached on the area as LOOT_AREA_LVL.  0 = the area has none.
int Loot_AreaLevel(object oArea)
{
    if (!GetIsObjectValid(oArea)) return 0;
    int n = GetLocalInt(oArea, "LOOT_AREA_LVL");
    if (n > 0) return n;
    n = LootD_AreaLevel(GetResRef(oArea));
    if (n > 0) SetLocalInt(oArea, "LOOT_AREA_LVL", n);
    return n;
}

// ---------------------------------------------------------------------------
// Creatures (Phase 4) - mirrors loot_model.creature_class / champion rules
// ---------------------------------------------------------------------------

// A creature is a NATURAL elite (never a champion: it already is one) when it
// is hand-listed elite_include, or when its CR's loot level is at least its
// area's loot level + LOOTD_ELITE_MARGIN and it is not listed elite_exclude.
// Reads the BASE CR, so a champion's raised CR never feeds back into this.
int Loot_IsNaturalElite(object oCre)
{
    int nList = LootD_CreatureListed(GetResRef(oCre));
    if (nList == LOOTD_LIST_ELITE) return TRUE;
    if (nList == LOOTD_LIST_NOT_ELITE) return FALSE;
    int nArea = Loot_AreaLevel(GetArea(oCre));
    if (nArea <= 0) return FALSE;
    float fCR = GetLocalInt(oCre, "LOOT_CHAMP") ? GetLocalFloat(oCre, "LOOT_CHAMP_BASECR")
                                               : GetChallengeRating(oCre);
    return LootD_LevelForCR(fCR) >= nArea + LOOTD_ELITE_MARGIN;
}

// Per-mille chance a normal creature spawning in oArea becomes a champion,
// cached on the area as LOOT_AREA_CHAMP (stored +1 so a real 0 still caches).
int Loot_AreaChampion(object oArea)
{
    if (!GetIsObjectValid(oArea)) return 0;
    int n = GetLocalInt(oArea, "LOOT_AREA_CHAMP");
    if (n > 0) return n - 1;
    n = LootD_AreaChampion(GetResRef(oArea));
    SetLocalInt(oArea, "LOOT_AREA_CHAMP", n + 1);
    return n;
}

// The level a container rolls at: its own LOOT_LEVEL local (set in the
// toolset to pin one chest), else its area's level, else 1 with a warning -
// the build gate makes every placed container's area have a level, so the
// warning means a container was created somewhere new.
int Loot_ContainerLevel(object oBox)
{
    int n = GetLocalInt(oBox, "LOOT_LEVEL");
    if (n > 0) return Loot_Clamp(n, 1, LOOTD_MAX_LEVEL);
    n = Loot_AreaLevel(GetArea(oBox));
    if (n > 0) return n;
    Loot_Warn("no loot level for area '" + GetResRef(GetArea(oBox)) + "' (container '"
              + GetTag(oBox) + "') - rolling at level 1");
    return 1;
}

// Pay nValue gp into oDest: up to 3 treasure gems (each picked evenly among the
// gems worth between a quarter of what is left and all of it, else the
// dearest gem that still fits), and whatever is left as gold.
void Loot_PayGems(int nValue, object oDest)
{
    int nLeft = nValue;
    int g;
    int i;
    int nV;
    for (g = 0; g < 3; g++)
    {
        int nPick = -1;
        int nN = 0;
        for (i = 0; i < LOOTD_GEM_COUNT; i++)
        {
            nV = LootD_GemValue(i);
            if (nV <= nLeft && nV * 4 >= nLeft) nN++;
        }
        if (nN > 0)
        {
            int r = Random(nN);
            for (i = 0; i < LOOTD_GEM_COUNT; i++)
            {
                nV = LootD_GemValue(i);
                if (nV <= nLeft && nV * 4 >= nLeft)
                {
                    if (r == 0) { nPick = i; break; }
                    r--;
                }
            }
        }
        else
        {
            int nBest = 0;
            for (i = 0; i < LOOTD_GEM_COUNT; i++)
            {
                nV = LootD_GemValue(i);
                if (nV <= nLeft && nV > nBest) { nBest = nV; nPick = i; }
            }
        }
        if (nPick < 0) break;
        if (!GetIsObjectValid(CreateItemOnObject(LootD_GemResRef(nPick), oDest)))
        {
            Loot_Warn("treasure gem '" + LootD_GemResRef(nPick) + "' could not be created");
            break;
        }
        nLeft -= LootD_GemValue(nPick);
    }
    if (nLeft > 0)
        CreateItemOnObject("nw_it_gold001", oDest, nLeft);
}

// One consumable (weighted among those whose level window holds nLvl) onto oDest.
object Loot_RollConsumable(int nLvl, object oDest)
{
    int nTotal = 0;
    int i;
    int nChunk = -1;
    string sChunk;
    string sRow;
    for (i = 0; i < LOOTD_CONS_COUNT; i++)
    {
        if (i / LOOTD_CONS_CHUNK != nChunk)
        {
            nChunk = i / LOOTD_CONS_CHUNK;
            sChunk = LootD_ConsChunk(nChunk);
        }
        sRow = GetSubString(sChunk, (i % LOOTD_CONS_CHUNK) * LOOTD_CONS_ROW, LOOTD_CONS_ROW);
        if (StringToInt(GetStringLeft(sRow, 2)) <= nLvl && nLvl <= StringToInt(GetSubString(sRow, 2, 2)))
            nTotal += StringToInt(GetSubString(sRow, 4, 4));
    }
    if (nTotal <= 0) return OBJECT_INVALID;
    int r = Random(nTotal);
    nChunk = -1;
    for (i = 0; i < LOOTD_CONS_COUNT; i++)
    {
        if (i / LOOTD_CONS_CHUNK != nChunk)
        {
            nChunk = i / LOOTD_CONS_CHUNK;
            sChunk = LootD_ConsChunk(nChunk);
        }
        sRow = GetSubString(sChunk, (i % LOOTD_CONS_CHUNK) * LOOTD_CONS_ROW, LOOTD_CONS_ROW);
        if (StringToInt(GetStringLeft(sRow, 2)) > nLvl || nLvl > StringToInt(GetSubString(sRow, 2, 2)))
            continue;
        r -= StringToInt(GetSubString(sRow, 4, 4));
        if (r < 0)
        {
            int nLo = StringToInt(GetSubString(sRow, 8, 2));
            int nHi = StringToInt(GetSubString(sRow, 10, 2));
            string sRes = GetSubString(sRow, 12, 16);
            int nBar = FindSubString(sRes, "|");
            if (nBar >= 0) sRes = GetStringLeft(sRes, nBar);
            object oItem = CreateItemOnObject(sRes, oDest, nLo + Random(nHi - nLo + 1));
            if (!GetIsObjectValid(oItem))
                Loot_Warn("consumable '" + sRes + "' could not be created");
            return oItem;
        }
    }
    return OBJECT_INVALID;
}

// Fill a container with one draw of profile sProfile at loot level nLvl:
// its gear rolls (each with the profile's gear chance), then its gold - paid
// as treasure gems at the profile's gem chance - then its consumables.
// Returns the number of rolled gear items made.
int Loot_FillContainer(object oBox, string sProfile, int nLvl, object oBeneficiary)
{
    int nProfile = LootD_ProfileIndex(sProfile);
    if (nProfile < 0)
    {
        Loot_Warn("unknown container profile '" + sProfile + "'");
        return 0;
    }
    nLvl = Loot_Clamp(nLvl, 1, LOOTD_MAX_LEVEL);
    int nMade = 0;
    int nRolls = LootD_ProfileRolls(nProfile);
    int nFloor = LootD_ProfileFloor(nProfile);
    int nGear = LootD_ProfileGearChance(nProfile);
    int i;
    for (i = 0; i < nRolls; i++)
        if (Random(1000) < nGear)
            if (GetIsObjectValid(Loot_Roll(nLvl, nFloor, sProfile, oBeneficiary, oBox)))
                nMade++;

    int nMean = LootD_RarityBudget(LOOT_RARITY_COMMON, nLvl) * LootD_ProfileGoldPct(nProfile) / 100;
    if (nMean > 0)
    {
        int nGold = nMean / 2 + Random(nMean + 1);
        if (Random(1000) < LootD_ProfileGemChance(nProfile))
            Loot_PayGems(nGold, oBox);
        else
            CreateItemOnObject("nw_it_gold001", oBox, nGold);
    }

    int nLo = LootD_ProfileConsMin(nProfile);
    int nHi = LootD_ProfileConsMax(nProfile);
    int nCons = nHi >= nLo ? nLo + Random(nHi - nLo + 1) : 0;
    for (i = 0; i < nCons; i++)
        Loot_RollConsumable(nLvl, oBox);
    return nMade;
}

// One-line description of a rolled item's stamps, for Loot Lab.
string Loot_Describe(object oItem)
{
    if (!Loot_IsRolled(oItem))
        return GetName(oItem) + ": not a rolled item.";
    int nRarity = GetLocalInt(oItem, "LOOT_RARITY");
    int nLvl = GetLocalInt(oItem, "LOOT_LVL");
    string s = GetName(oItem) + " [" + LootD_RarityName(nRarity) + ", level "
             + IntToString(nLvl) + ", profile " + GetLocalString(oItem, "LOOT_PROFILE") + "]";
    if (GetLocalInt(oItem, "LOOT_NAMED"))
        return s + " named-pool item.";
    int nVal = ForgeItemValue(oItem, TRUE);
    s += " value " + IntToString(nVal) + " / budget " + IntToString(Loot_Budget(nRarity, nLvl, FALSE));
    int n = GetLocalInt(oItem, "LOOT_AFX_N");
    int i;
    for (i = 0; i < n; i++)
        s += "\n   " + GetLocalString(oItem, "LOOT_AFX_" + IntToString(i));
    if (!GetIdentified(oItem)) s += "\n   (unidentified)";
    return s;
}
