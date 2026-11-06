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
//   3. base    - with the wishlist chance, a base item from the beneficiary's
//                wishlist or Auto list (Phase 6, Loot_WishPick), inside the
//                profile's categories and base filter; otherwise
//                category from the profile's weights, then a base item; the
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
//   8. sockets - 0..n gem sockets by rarity (Phase 5; SOCKET_ROLLED /
//                SOCKET_MAX, filled by gem_inc).
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

// ---------------------------------------------------------------------------
// Phase 6: the loot wishlist (lo-wishlist).  Mirrors loot_model.wish_candidates
// and wish_pick.  Candidate lists are "row:weight|row:weight|" strings.
// ---------------------------------------------------------------------------

const string LOOT_AUTO      = "LOOT_AUTO";       // PC local: cached Auto list
const string LOOT_AUTO_KEY  = "LOOT_AUTO_KEY";   // PC local: hit dice it was built at
const string LOOT_AUTO_TIER = "LOOT_AUTO_TIER";  // PC local: 1 focus, 2 proficiency, 0 none

// How many of the feats in sList ("|feat|feat|") oPC holds.
int Loot_FeatsHeld(object oPC, string sList)
{
    int n = 0;
    int nPos = 1;
    int nLen = GetStringLength(sList);
    while (nPos < nLen)
    {
        int nEnd = FindSubString(sList, "|", nPos);
        if (nEnd < 0) break;
        if (GetHasFeat(StringToInt(GetSubString(sList, nPos, nEnd - nPos)), oPC)) n++;
        nPos = nEnd + 1;
    }
    return n;
}

// TRUE when spellcasting classes (classes.2da SpellCaster) hold at least half
// of oPC's levels - the wishlist's proficiency tier offers a magic staff only then.
int Loot_IsCaster(object oPC)
{
    int nCast = 0;
    int i;
    for (i = 1; i <= 8; i++)
    {
        int nClass = GetClassByPosition(i, oPC);
        if (nClass == CLASS_TYPE_INVALID) break;
        if (LootD_ClassCaster(nClass)) nCast += GetLevelByPosition(i, oPC);
    }
    return nCast > 0 && nCast * 2 >= GetHitDice(oPC);
}

// The Auto candidate list, cached on the PC per hit-dice total (a level-up,
// legendary levels included, rebuilds it).  Tier 1: melee/ranged bases whose
// weapon-focus family feats oPC holds, LOOTD_WISH_FOCUS_W per feat.  Tier 2 when
// tier 1 is empty: melee/ranged/caster bases oPC is proficient with, at their
// base weight; a caster-category base (the magic staff) only for a caster.
string Loot_AutoList(object oPC)
{
    int nKey = GetHitDice(oPC);
    if (GetLocalInt(oPC, LOOT_AUTO_KEY) == nKey)
        return GetLocalString(oPC, LOOT_AUTO);

    string sOut = "";
    int nTier = 0;
    int c, k;
    for (c = 0; c < LOOTD_CAT_COUNT; c++)
    {
        string sCat = LootD_CatName(c);
        if (sCat != "melee" && sCat != "ranged") continue;
        int n = LootD_BaseCount(c);
        for (k = 0; k < n; k++)
        {
            int nBase = LootD_BaseRow(c, k);
            int nHeld = Loot_FeatsHeld(oPC, LootD_BaseFocusFeats(nBase));
            if (nHeld > 0)
                sOut += IntToString(nBase) + ":" + IntToString(nHeld * LOOTD_WISH_FOCUS_W) + "|";
        }
    }
    if (sOut != "")
        nTier = 1;
    else
    {
        int bCaster = Loot_IsCaster(oPC);
        for (c = 0; c < LOOTD_CAT_COUNT; c++)
        {
            string sCat = LootD_CatName(c);
            if (sCat != "melee" && sCat != "ranged" && sCat != "caster") continue;
            if (sCat == "caster" && !bCaster) continue;
            int n = LootD_BaseCount(c);
            for (k = 0; k < n; k++)
            {
                int nBase = LootD_BaseRow(c, k);
                string sReq = LootD_BaseReqFeats(nBase);
                if (sReq == "|" || Loot_FeatsHeld(oPC, sReq) > 0)
                    sOut += IntToString(nBase) + ":" + IntToString(LootD_BaseWeight(c, k)) + "|";
            }
        }
        if (sOut != "") nTier = 2;
    }
    SetLocalString(oPC, LOOT_AUTO, sOut);
    SetLocalInt(oPC, LOOT_AUTO_KEY, nKey);
    SetLocalInt(oPC, LOOT_AUTO_TIER, nTier);
    return sOut;
}

// oPC's candidates: the wishlist picks (weight 1 each), else the Auto list
// when Auto is on, else "" (plain random loot).
string Loot_WishCands(object oPC)
{
    string sList = Loot_WishGet(oPC);
    string sOut = "";
    int nPos = 1;
    int nLen = GetStringLength(sList);
    while (nPos < nLen)
    {
        int nEnd = FindSubString(sList, "|", nPos);
        if (nEnd < 0) break;
        int nBase = StringToInt(GetSubString(sList, nPos, nEnd - nPos));
        if (nBase >= 0) sOut += IntToString(nBase) + ":1|";
        nPos = nEnd + 1;
    }
    if (sOut != "") return sOut;
    if (!Loot_WishAutoOn(oPC)) return "";
    return Loot_AutoList(oPC);
}

// Weight of candidate base nBase for profile nProfile: nW when the profile
// rolls the base's category and its base filter allows it, else 0.
int Loot_WishFit(int nProfile, int nBase, int nW)
{
    int nCat = LootD_BaseCat(nBase);
    if (nCat < 0 || nW <= 0) return 0;
    if (LootD_ProfileCatWeight(nProfile, nCat) <= 0) return 0;
    if (!LootD_ProfileBaseOk(nProfile, nBase)) return 0;
    return nW;
}

// A base item row drawn from oBenef's wishlist / Auto list for this profile,
// or -1 (no PC, the LOOTD_WISH_CHANCE roll missed, or nothing fits).
int Loot_WishPick(object oBenef, int nProfile)
{
    if (!GetIsObjectValid(oBenef) || !GetIsPC(oBenef) || GetIsDM(oBenef)) return -1;
    if (Random(1000) >= LOOTD_WISH_CHANCE) return -1;
    string s = Loot_WishCands(oBenef);
    int nLen = GetStringLength(s);
    if (nLen == 0) return -1;
    int nPass;
    int nTotal = 0;
    int r = 0;
    for (nPass = 0; nPass < 2; nPass++)
    {
        if (nPass == 1)
        {
            if (nTotal <= 0) return -1;
            r = Random(nTotal);
        }
        int nPos = 0;
        while (nPos < nLen)
        {
            int nColon = FindSubString(s, ":", nPos);
            int nEnd = FindSubString(s, "|", nPos);
            if (nColon < 0 || nEnd < 0) break;
            int nBase = StringToInt(GetSubString(s, nPos, nColon - nPos));
            int nW = Loot_WishFit(nProfile, nBase,
                         StringToInt(GetSubString(s, nColon + 1, nEnd - nColon - 1)));
            if (nPass == 0) nTotal += nW;
            else
            {
                r -= nW;
                if (r < 0) return nBase;
            }
            nPos = nEnd + 1;
        }
    }
    return -1;
}

// "|type:sub|" - the key a reforge (Phase 7) blocks an affix by when the item
// already carries a kept property of that type and subtype.
// A property with no subtype reads back as 0 or 65535 (the "blank Subtype"
// encodings), so both are keyed as 0, which is what LootD_AffixSub uses.
string Loot_TypeSubKey(int nType, int nSub)
{
    if (nSub < 0 || nSub == 65535) nSub = 0;
    return "|" + IntToString(nType) + ":" + IntToString(nSub) + "|";
}

// sBlock: Loot_TypeSubKey()s already on the item ("" for a fresh roll).
int Loot_AffixEligible(int nAffix, string sCat, int nLvl, int bDown, string sUsed,
                       string sBlock = "")
{
    if (LootD_AffixIsDown(nAffix) != bDown) return FALSE;
    if (LootD_AffixWeight(nAffix) <= 0) return FALSE;
    if (nLvl < LootD_AffixMinLevel(nAffix)) return FALSE;
    if (FindSubString(LootD_AffixCats(nAffix), "|" + sCat + "|") < 0) return FALSE;
    if (FindSubString(sUsed, "|" + LootD_AffixGroup(nAffix) + "|") >= 0) return FALSE;
    if (sBlock != ""
        && FindSubString(sBlock, Loot_TypeSubKey(LootD_AffixType(nAffix), LootD_AffixSub(nAffix))) >= 0)
        return FALSE;
    return TRUE;
}

// Weighted pick among eligible affixes, or -1.
int Loot_PickAffix(string sCat, int nLvl, int bDown, string sUsed, string sBlock = "")
{
    int nTotal = 0;
    int i;
    for (i = 0; i < LOOTD_AFFIX_COUNT; i++)
        if (Loot_AffixEligible(i, sCat, nLvl, bDown, sUsed, sBlock))
            nTotal += LootD_AffixWeight(i);
    if (nTotal <= 0) return -1;
    int r = Random(nTotal);
    for (i = 0; i < LOOTD_AFFIX_COUNT; i++)
    {
        if (!Loot_AffixEligible(i, sCat, nLvl, bDown, sUsed, sBlock)) continue;
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
// Affixes: pick + budget + apply.  Shared by Loot_Roll and the Phase 7 reforge
// (Loot_Reforge); bin/loot_model.py roll_affixes() is the mirror.
// ---------------------------------------------------------------------------

// Engine value of oTemplate (a forge blank already carrying the properties a
// reforge keeps) plus the work list: priced on a scratch copy in the forge
// vault.  -1 = no valuation possible.
int Loot_PriceWorkOn(object oTemplate, object oWork)
{
    object oHolder = ForgeHolder();
    if (!GetIsObjectValid(oHolder)) return -1;
    object oCopy = CopyItem(oTemplate, oHolder, FALSE);
    if (!GetIsObjectValid(oCopy)) return -1;
    int n = GetLocalInt(oWork, "LW_N");
    int k;
    for (k = 0; k < n; k++)
    {
        itemproperty ip = Loot_WorkIP(oWork, k);
        if (GetIsItemPropertyValid(ip))
            AddItemProperty(DURATION_TYPE_PERMANENT, ip, oCopy);
    }
    int nValue = GetGoldPieceValue(oCopy);
    DestroyObject(oCopy);
    return nValue;
}

// Steps 4-5 of a roll: choose the affixes into oWork's LW_* work list, then
// step them down until they fit the rarity's budget for nLvl.
//   sBlock     Loot_TypeSubKey()s of properties the item keeps ("" = fresh roll)
//   nMaxNew    most affixes to add, downside included (a downside needs room
//              for the extra upside it buys, so it is only rolled when >= 2)
//   oTemplate  valid: also step down while oTemplate + the affixes is worth
//              more than nTotalCap (the reforge's whole-item bound)
// Returns the affix-only engine value, or -1 when nothing could be priced.
// LW_DOWN on oWork = a downside was rolled.
int Loot_RollAffixes(object oWork, int nBase, string sCat, int nLvl, int nRarity,
                     string sBlock = "", int nMaxNew = 99,
                     object oTemplate = OBJECT_INVALID, int nTotalCap = 0)
{
    int nUp = LootD_RarityAffMin(nRarity)
            + Random(LootD_RarityAffMax(nRarity) - LootD_RarityAffMin(nRarity) + 1);
    string sUsed = "|";
    int bDown = FALSE;
    int a;
    if (Random(1000) < LootD_RarityDownside(nRarity) && nMaxNew >= 2)
    {
        a = Loot_PickAffix(sCat, nLvl, TRUE, sUsed, sBlock);
        if (a >= 0)
        {
            Loot_WorkAdd(oWork, a, Loot_PickStep(a, nLvl, 0));
            sUsed += LootD_AffixGroup(a) + "|";
            bDown = TRUE;
            nUp++;
        }
    }
    int nBias = LootD_RarityRollBias(nRarity);
    int u;
    for (u = 0; u < nUp; u++)
    {
        if (GetLocalInt(oWork, "LW_N") >= nMaxNew) break;
        a = Loot_PickAffix(sCat, nLvl, FALSE, sUsed, sBlock);
        if (a < 0) break;
        Loot_WorkAdd(oWork, a, Loot_PickStep(a, nLvl, nBias));
        sUsed += LootD_AffixGroup(a) + "|";
    }
    SetLocalInt(oWork, "LW_DOWN", bDown);

    // Budget: step the last upside that can still step down; once none can,
    // drop the last upside.  The first-rolled affix gives ground last.
    int bTotal = GetIsObjectValid(oTemplate);
    int nBudget = Loot_Budget(nRarity, nLvl, bDown);
    int nValue = Loot_PriceWork(nBase, oWork);
    int bOver = nValue > nBudget;
    if (!bOver && bTotal && nValue >= 0)
        bOver = Loot_PriceWorkOn(oTemplate, oWork) > nTotalCap;
    int nSteps = 0;
    int n;
    int j;
    int k;
    while (bOver && nValue >= 0 && nSteps < 64)
    {
        nSteps++;
        n = GetLocalInt(oWork, "LW_N");
        j = -1;
        for (k = n - 1; k >= 0; k--)
        {
            if (!LootD_AffixIsDown(GetLocalInt(oWork, "LW_A" + IntToString(k)))
                && GetLocalInt(oWork, "LW_S" + IntToString(k)) > 0)
            {
                j = k;
                break;
            }
        }
        if (j >= 0)
            SetLocalInt(oWork, "LW_S" + IntToString(j), GetLocalInt(oWork, "LW_S" + IntToString(j)) - 1);
        else
        {
            int nLastUp = -1;
            for (k = n - 1; k >= 0; k--)
                if (!LootD_AffixIsDown(GetLocalInt(oWork, "LW_A" + IntToString(k))))
                {
                    nLastUp = k;
                    break;
                }
            if (nLastUp < 0) break;
            Loot_WorkRemove(oWork, nLastUp);
        }
        nValue = Loot_PriceWork(nBase, oWork);
        bOver = nValue > nBudget;
        if (!bOver && bTotal && nValue >= 0)
            bOver = Loot_PriceWorkOn(oTemplate, oWork) > nTotalCap;
    }
    return nValue;
}

// Number of upside affixes in oWork's work list.
int Loot_WorkUps(object oWork)
{
    int n = GetLocalInt(oWork, "LW_N");
    int nUps = 0;
    int k;
    for (k = 0; k < n; k++)
        if (!LootD_AffixIsDown(GetLocalInt(oWork, "LW_A" + IntToString(k))))
            nUps++;
    return nUps;
}

// Step 6: add oWork's work list to oItem as permanent properties and name it
// "<Prefix> <Base> of <Suffix>" in the rarity's colour; clears the work list
// and returns the plain name.  Self-check: each constructor must yield the
// property type (and cost row) that was asked for - a wrong argument order
// would otherwise ship silently.
// bStamp: rewrite LOOT_AFX_N / LOOT_AFX_<i> from the properties added here (the
// reforge, whose item also carries kept properties).  Loot_Roll passes FALSE
// and stamps by reading its all-random item back.
string Loot_ApplyWork(object oItem, object oWork, int nRarity, int nBase, int bStamp)
{
    string sPrefix = "";
    string sSuffix = "";
    int nUps = 0;
    int nAfx = 0;
    int n = GetLocalInt(oWork, "LW_N");
    int k;
    if (bStamp)
    {
        int nOld = GetLocalInt(oItem, "LOOT_AFX_N");
        for (k = 0; k < nOld; k++)
            DeleteLocalString(oItem, "LOOT_AFX_" + IntToString(k));
    }
    for (k = 0; k < n; k++)
    {
        int a = GetLocalInt(oWork, "LW_A" + IntToString(k));
        int nType = LootD_AffixType(a);
        int nCost = LootD_AffixLadder(a, GetLocalInt(oWork, "LW_S" + IntToString(k)));
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
        if (bStamp)
        {
            SetLocalString(oItem, "LOOT_AFX_" + IntToString(nAfx), ForgePropSig(ip));
            nAfx++;
        }
        if (!LootD_AffixIsDown(a))
        {
            if (nUps == 0) sPrefix = LootD_AffixPrefix(a);
            else if (nUps == 1) sSuffix = LootD_AffixSuffix(a);
            nUps++;
        }
    }
    if (bStamp)
        SetLocalInt(oItem, "LOOT_AFX_N", nAfx);
    Loot_WorkClear(oWork);
    DeleteLocalInt(oWork, "LW_DOWN");

    string sName = LootD_BaseName(nBase);
    if (sPrefix != "") sName = sPrefix + " " + sName;
    if (sSuffix != "") sName = sName + " of " + sSuffix;
    SetName(oItem, ColorString(sName, Loot_RarityColor(nRarity)));
    return sName;
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

// ---------------------------------------------------------------------------
// Sockets (Phase 5).  The socket rules and gems live in gem_inc / the generated
// socket_data_inc; loot_inc only rolls a new item's socket count and writes the
// socket line, so the chest wrappers never carry the socket tables.
// ---------------------------------------------------------------------------

// Rebuild oItem's description as its original text + "Sockets (f/m): ...".
// sFilled = the comma-joined names of its nFilled filled sockets.  The original
// text is kept once in SOCKET_BASEDESC, so the line is replaced, never stacked.
void Loot_SetSocketDesc(object oItem, string sFilled, int nFilled)
{
    int nMax = GetLocalInt(oItem, "SOCKET_MAX");
    if (nMax <= 0) return;
    if (!GetLocalInt(oItem, "SOCKET_DESC_SET"))
    {
        SetLocalString(oItem, "SOCKET_BASEDESC", GetDescription(oItem));
        SetLocalInt(oItem, "SOCKET_DESC_SET", TRUE);
    }
    string s = sFilled;
    int i;
    for (i = nFilled; i < nMax; i++)
        s += (s == "" ? "" : ", ") + "[empty]";
    string sBase = GetLocalString(oItem, "SOCKET_BASEDESC");
    SetDescription(oItem, (sBase == "" ? "" : sBase + "\n\n") + "Sockets ("
                   + IntToString(nFilled) + "/" + IntToString(nMax) + "): " + s);
}

// One socket gem (loot/gems.json) onto oDest at loot level nLvl, tier floor
// nFloor: gem_drop.nss does it, so the gem tables stay out of this include.
void Loot_DropSocketGem(int nLvl, int nFloor, object oDest)
{
    SetLocalInt(oDest, "GEM_DROP_LVL", nLvl);
    SetLocalInt(oDest, "GEM_DROP_FLOOR", nFloor);
    ExecuteScript("gem_drop", oDest);
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
//   oBeneficiary who it is for: steers the base item through their wishlist
//                (Phase 6, Loot_WishPick) and is logged; may be invalid
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

    // 3. base: the beneficiary's wishlist / Auto list first (Phase 6)
    int nCat = -1;
    int nBase = Loot_WishPick(oBeneficiary, nProfile);
    if (nBase >= 0)
        nCat = LootD_BaseCat(nBase);
    else
    {
        nCat = Loot_PickCategory(nProfile);
        nBase = nCat < 0 ? -1 : Loot_PickBase(nCat, nProfile);
    }
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

    // 4.-6. affixes, budget, apply + name (shared with the Phase 7 reforge)
    int nValue = Loot_RollAffixes(oItem, nBase, sCat, nLvl, nRarity);
    if (nValue < 0)
    {
        Loot_Warn("could not price base item " + IntToString(nBase) + " (forge vault missing?)");
        Loot_WorkClear(oItem);
        DestroyObject(oItem);
        return OBJECT_INVALID;
    }
    string sName = Loot_ApplyWork(oItem, oItem, nRarity, nBase, FALSE);
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

    // Phase 5: gem sockets by rarity (SOCKET_ROLLED is what gem_inc reconciles to).
    int nSock = LootD_RaritySockMin(nRarity)
              + Random(LootD_RaritySockMax(nRarity) - LootD_RaritySockMin(nRarity) + 1);
    if (nSock > 0)
    {
        SetLocalInt(oItem, "SOCKET_ROLLED", nSock);
        SetLocalInt(oItem, "SOCKET_MAX", nSock);
        Loot_SetSocketDesc(oItem, "", 0);
    }

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

    // Phase 5: one socket gem, last (loot_model.chest_contents order).
    if (Random(1000) < LootD_ProfileSockGemChance(nProfile))
        Loot_DropSocketGem(nLvl, 0, oBox);
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
    if (GetLocalInt(oItem, "SOCKET_MAX") > 0)
        s += "\n   sockets " + IntToString(GetLocalInt(oItem, "SOCKET_FILLED")) + "/"
           + IntToString(GetLocalInt(oItem, "SOCKET_MAX"));
    if (GetLocalInt(oItem, "LOOT_FATE_N") > 0)
        s += "\n   reforged with a Shard of Fate " + IntToString(GetLocalInt(oItem, "LOOT_FATE_N"))
           + " time(s)";
    if (!GetIdentified(oItem)) s += "\n   (unidentified)";
    return s;
}

// ---------------------------------------------------------------------------
// The Shard of Fate (Phase 7, lo-fate-token).  Tokens: loot/tokens.json
// "fate" -> LOOTD_FATE_*.  Mirror: loot_model.reforge / creature_drop.
// ---------------------------------------------------------------------------

const int LOOT_FATE_OK         = 1;
const int LOOT_FATE_NOT_ROLLED = -1;   // not made by Loot_Roll
const int LOOT_FATE_NAMED      = -2;   // a named-pool item: nothing random on it
const int LOOT_FATE_NO_BASE    = -3;   // its base item is not a loot base any more
const int LOOT_FATE_NO_ROOM    = -4;   // no upside fits the item's bounds
const int LOOT_FATE_NO_VAULT   = -5;   // the forge vault / blank is missing

// The first Shard of Fate oPC carries, or OBJECT_INVALID.
object Loot_FindShard(object oPC)
{
    return GetItemPossessedBy(oPC, LOOTD_FATE_RESREF);
}

// Consume one Shard from oPC.  The Shard is Plot (never sold), so the flag is
// cleared before it is destroyed.  FALSE when oPC carries none.
int Loot_SpendShard(object oPC)
{
    object oShard = Loot_FindShard(oPC);
    if (!GetIsObjectValid(oShard)) return FALSE;
    SetPlotFlag(oShard, FALSE);
    DestroyObject(oShard);
    return TRUE;
}

// Create a Shard on oDest (a corpse, a PC).  PL_ALWAYS sends it through the
// party Need/Greed roll below the gp threshold (admin 2026-11-06).
object Loot_DropShard(object oDest)
{
    object oShard = CreateItemOnObject(LOOTD_FATE_RESREF, oDest);
    if (!GetIsObjectValid(oShard))
    {
        Loot_Warn("Shard of Fate blueprint '" + LOOTD_FATE_RESREF + "' could not be created");
        return OBJECT_INVALID;
    }
    SetLocalInt(oShard, "PL_ALWAYS", 1);
    Loot_MarkCorpseLoot(oShard, oDest);
    return oShard;
}

// "|sig|sig|" of oItem's random affixes (LOOT_AFX_*).
string Loot_AfxSigList(object oItem)
{
    string s = "|";
    int n = GetLocalInt(oItem, "LOOT_AFX_N");
    int i;
    for (i = 0; i < n; i++)
        s += GetLocalString(oItem, "LOOT_AFX_" + IntToString(i)) + "|";
    return s;
}

// sList with its first "|sSig|" taken out, or "" when sSig is not in it.
// (A non-empty result always keeps the leading "|".)
string Loot_TakeSig(string sList, string sSig)
{
    string sKey = "|" + sSig + "|";
    int nAt = FindSubString(sList, sKey);
    if (nAt < 0) return "";
    return GetStringLeft(sList, nAt)
         + GetStringRight(sList, GetStringLength(sList) - nAt - GetStringLength(sKey) + 1);
}

// Remove every property of oItem whose ForgePropSig is a random affix, each
// signature once.  Nothing is read back after a removal: a second pass only
// catches a property the iterator skipped, and a consumed signature never
// matches again.
void Loot_StripAfx(object oItem)
{
    string sLeft = Loot_AfxSigList(oItem);
    int nPass;
    for (nPass = 0; nPass < 4 && sLeft != "|"; nPass++)
    {
        int bRemoved = FALSE;
        itemproperty ip = GetFirstItemProperty(oItem);
        while (GetIsItemPropertyValid(ip))
        {
            if (GetItemPropertyDurationType(ip) == DURATION_TYPE_PERMANENT)
            {
                string sNext = Loot_TakeSig(sLeft, ForgePropSig(ip));
                if (sNext != "")
                {
                    sLeft = sNext;
                    RemoveItemProperty(oItem, ip);
                    bRemoved = TRUE;
                }
            }
            ip = GetNextItemProperty(oItem);
        }
        if (!bRemoved) break;
    }
}

// Re-roll oItem's random affixes in place (the anvil's "Reforge its fate").
// Transactional: the new set is chosen and priced on a scratch blank carrying
// only the properties the item keeps (forged enchantments, gem properties,
// anything not in LOOT_AFX_*), and oItem is touched only once a set with at
// least one upside fits.  Bounds - an item-mutating path bounds itself:
//   * the affix-only value fits the rarity's budget at LOOT_LVL (the budget the
//     original roll had), so a reforge can never beat what a roll could make;
//   * the whole item stays at or under max(its value now, nValueCap) - a forge
//     passes its MODIFY_MAX, so a lawful piece never leaves its forge's cap;
//   * counted enchantments stay at or under max(its count now, nPropCap).
// Level, rarity, base, look, sockets, gems and description are unchanged; the
// name is rebuilt from the new prefix/suffix.  Returns LOOT_FATE_*.
int Loot_Reforge(object oItem, int nValueCap, int nPropCap, object oPC)
{
    if (!Loot_IsRolled(oItem)) return LOOT_FATE_NOT_ROLLED;
    if (GetLocalInt(oItem, "LOOT_NAMED")) return LOOT_FATE_NAMED;
    int nBase = GetBaseItemType(oItem);
    int nCat = LootD_BaseCat(nBase);
    if (nCat < 0) return LOOT_FATE_NO_BASE;
    int nLvl = Loot_Clamp(GetLocalInt(oItem, "LOOT_LVL"), 1, LOOTD_MAX_LEVEL);
    int nRarity = Loot_Clamp(GetLocalInt(oItem, "LOOT_RARITY"), 0, LOOTD_RARITY_COUNT - 1);
    object oHolder = ForgeHolder();
    if (!GetIsObjectValid(oHolder)) return LOOT_FATE_NO_VAULT;
    object oTpl = CreateItemOnObject(ForgeBlankResRef(nBase), oHolder);
    if (!GetIsObjectValid(oTpl)) return LOOT_FATE_NO_VAULT;

    // The kept properties: onto the template (priced), into the block list
    // (no affix may duplicate one), and counted against the slot bound.
    string sLeft = Loot_AfxSigList(oItem);
    string sBlock = "";
    int nKeptCounted = 0;
    itemproperty ip = GetFirstItemProperty(oItem);
    while (GetIsItemPropertyValid(ip))
    {
        if (GetItemPropertyDurationType(ip) == DURATION_TYPE_PERMANENT)
        {
            string sNext = Loot_TakeSig(sLeft, ForgePropSig(ip));
            if (sNext != "")
                sLeft = sNext;                       // a random affix: re-rolled
            else
            {
                sBlock += Loot_TypeSubKey(GetItemPropertyType(ip), GetItemPropertySubType(ip));
                if (ForgePropInSet(ip, FORGE_SEL_COUNTED, oItem)) nKeptCounted++;
                if (ForgePropInSet(ip, FORGE_SEL_PRICED))
                    AddItemProperty(DURATION_TYPE_PERMANENT, ip, oTpl);
            }
        }
        ip = GetNextItemProperty(oItem);
    }

    int nBefore = ForgeItemValue(oItem, TRUE);
    int nTotalCap = nBefore > nValueCap ? nBefore : nValueCap;
    int nCountBefore = ForgeCountProps(oItem);
    int nPropMax = nCountBefore > nPropCap ? nCountBefore : nPropCap;
    int nMaxNew = nPropMax - nKeptCounted;
    if (nMaxNew < 0) nMaxNew = 0;

    int nValue = Loot_RollAffixes(oTpl, nBase, LootD_CatName(nCat), nLvl, nRarity,
                                  sBlock, nMaxNew, oTpl, nTotalCap);
    if (nValue < 0 || Loot_WorkUps(oTpl) <= 0)
    {
        Loot_WorkClear(oTpl);
        DestroyObject(oTpl);
        return nValue < 0 ? LOOT_FATE_NO_VAULT : LOOT_FATE_NO_ROOM;
    }

    // Commit: strip the old random affixes, apply the new set, re-stamp.
    Loot_StripAfx(oItem);
    string sName = Loot_ApplyWork(oItem, oTpl, nRarity, nBase, TRUE);
    DestroyObject(oTpl);
    SetLocalInt(oItem, "LOOT_FATE_N", GetLocalInt(oItem, "LOOT_FATE_N") + 1);
    Loot_LogRoll("fate", GetLocalString(oItem, "LOOT_PROFILE"), nLvl, nRarity, nBase,
                 sName, nValue, oPC);
    return LOOT_FATE_OK;
}
