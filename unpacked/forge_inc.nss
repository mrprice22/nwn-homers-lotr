// forge_inc.nss — shared helpers for the Forge of Wonders system.
//
// Pricing, per-forge caps, legality checks and the disenchant service all go
// through here. Do NOT #include "itemprocs" from this file (NWScript has no
// include guards; consumer scripts include both side by side).
//
// Reserved custom tokens: 6110-6117 disenchant slot names, 6118 picked name
// (forge already uses 100-103).

// Generated whitelist of legally-placed item variants (ForgeIsKnownLegalVariant,
// ForgeLegalFingerprint) — regenerate with bin/gen-forge-legal.py.
#include "forge_legal_inc"
// Appraise scaling (AppraiseBonusScaled) for the per-player value ceiling.
#include "appraise_inc"
// Colour-token strings (COLOR_RED / COLOR_END / ColorString) for the staged
// disenchant menu's "[planned]" marker. No forge consumer also includes "color",
// so this is conflict-free (NWScript has no include guards).
#include "color"

const int FORGE_LEGAL_MAX_PROPS = 6;
const int FORGE_LEGAL_MAX_VALUE = 750000;

// Extra item value (gp) a maxed-Appraise player may lawfully forge above the
// default ceilings: +0 at no Appraise investment, +500,000 at an Appraise check
// of 65. Applied to each forge's per-tier cap, the global enchant backstop, and
// the contraband/jail ceiling alike. See appraise_inc.nss.
const int FORGE_APPRAISE_MAX_BONUS = 500000;

// Item-local int stamped by modifyitem when a forge lawfully enchants an item
// above the default global ceiling because the player's Appraise allowed it.
// Its value is the lawful per-item value ceiling that justified the work, so the
// contraband scan / Forge Warden honor it regardless of who later holds the item
// (legality stays intrinsic to the item — see FORGE_CLEAN note below).
const string FORGE_CEIL = "FORGE_CEIL";

// Appraise-extended value bonus for oPC (0..FORGE_APPRAISE_MAX_BONUS).
int ForgeAppraiseBonus(object oPC)
{
    return AppraiseBonusScaled(oPC, FORGE_APPRAISE_MAX_BONUS);
}

// ---------------------------------------------------------------------------
// Boss-kill progressive forge bonuses (roadmap: forge-limits-progressive).
//
// A character earns a personal bonus to the forge caps by slaying DISTINCT
// bosses from the Roll of the Fallen registry (respawndb boss_registry, the
// CR>60 single-instance bosses — see CLAUDE-boss-tracker.md). Kills are read
// from the bestiary (bestiarydb kills, per-character GetObjectUUID, solo OR
// party credit both count). Distinct bosses — not raw kills — so the reward
// tracks progression, not farming one boss.
//
// TIER TABLE (tune here; every threshold/percent lives in these constants):
//   >= FORGE_BOSS_TIER1_KILLS (10) distinct bosses  ->  +5% forge value cap
//   >= FORGE_BOSS_TIER2_KILLS (25)                  -> +10%
//   >= FORGE_BOSS_TIER3_KILLS (50)                  -> +15%
//   ALL tracked bosses (registry count, 78 today)   -> +20% and +1 property
//                       slot at the TOP-tier forges only (Moria / Kallrist,
//                       i.e. forges whose prop cap is FORGE_LEGAL_MAX_PROPS).
//
// The percent applies to the forge's own FORGE_MAX_VALUE area cap (before the
// Appraise bonus is added), so lower-tier forges give proportionally smaller
// rewards. Personal bonuses apply ONLY AT FORGE TIME (what YOU may build).
//
// TRANSFERABILITY: the contraband/legality ceiling everywhere (login scan,
// Well of Eru, Forge Warden, staged disenchant lawfulness) is the MAXIMUM
// ACHIEVABLE cap — ForgeLegalMaxValue()/ForgeLegalMaxProps() below, i.e.
// base + the top-tier bonus, uniformly for every character. So an item forged
// by a decorated boss-slayer can be traded to a fresh character without the
// recipient ever being jailed for holding it. Raising the ceiling only ever
// LOOSENS the law, so existing FORGE_CLEAN stamps stay valid (no
// FORGE_CLEAN_VER bump needed).
const int FORGE_BOSS_TIER1_KILLS = 10;
const int FORGE_BOSS_TIER1_PCT   = 5;
const int FORGE_BOSS_TIER2_KILLS = 25;
const int FORGE_BOSS_TIER2_PCT   = 10;
const int FORGE_BOSS_TIER3_KILLS = 50;
const int FORGE_BOSS_TIER3_PCT   = 15;
// Top tier: ALL currently-tracked bosses (dynamic registry count).
const int FORGE_BOSS_TOP_PCT     = 20;

// Global legal value ceiling INCLUDING the top boss-tier bonus. Any character
// could lawfully hold an item forged at the top personal cap, so every
// contraband/legality check must judge against this, never a holder's
// personal cap. 750,000 + 20% = 900,000 gp today.
int ForgeLegalMaxValue()
{
    return FORGE_LEGAL_MAX_VALUE
        + FORGE_LEGAL_MAX_VALUE / 100 * FORGE_BOSS_TOP_PCT;
}

// Global legal property-count ceiling INCLUDING the top boss-tier +1 slot
// (earned at the top forges by slaying every tracked boss). 7 today.
int ForgeLegalMaxProps()
{
    return FORGE_LEGAL_MAX_PROPS + 1;
}

// Quoted, comma-separated list of every tracked boss resref (registry +
// aliases) for SQL IN(...) clauses, e.g. "'gollum','witchking',...". Resrefs
// are filenames (alphanumeric), so inlining them into SQL text is safe.
// Cached on the module: brd_db reseeds the registry only on module load.
// Returns "" when the respawndb registry is unavailable (feature no-ops).
string ForgeBossRegistryList()
{
    object oMod = GetModule();
    string sList = GetLocalString(oMod, "FORGE_BOSS_LIST");
    if (sList != "")
        return sList;
    sqlquery q = SqlPrepareQueryCampaign("respawndb",
        "SELECT group_concat('''' || resref || '''') FROM"
        + " (SELECT resref FROM boss_registry"
        + "  UNION SELECT resref FROM boss_alias)");
    if (SqlStep(q))
    {
        sList = SqlGetString(q, 0);
        SetLocalString(oMod, "FORGE_BOSS_LIST", sList);
    }
    return sList;
}

// How many bosses the registry tracks (the top-tier threshold). Cached on the
// module for the same reason as the list above. 0 when unavailable.
int ForgeBossTotalTracked()
{
    object oMod = GetModule();
    int nTotal = GetLocalInt(oMod, "FORGE_BOSS_TOTAL");
    if (nTotal > 0)
        return nTotal;
    sqlquery q = SqlPrepareQueryCampaign("respawndb",
        "SELECT COUNT(*) FROM boss_registry");
    if (SqlStep(q))
    {
        nTotal = SqlGetInt(q, 0);
        SetLocalInt(oMod, "FORGE_BOSS_TOTAL", nTotal);
    }
    return nTotal;
}

// Distinct tracked bosses this character has slain (solo or party credit),
// per the bestiarydb kill records. Bestiary kills are stored by CANONICAL
// resref, so match both the raw registry resrefs and their bestiary-canonical
// translations. 0 on any missing DB/table (graceful no-op).
int ForgeBossDistinctKills(object oPC)
{
    string sList = ForgeBossRegistryList();
    if (sList == "")
        return 0;
    sqlquery q = SqlPrepareQueryCampaign("bestiarydb",
        "SELECT COUNT(DISTINCT resref) FROM kills WHERE uuid=@u"
        + " AND (resref IN (" + sList + ")"
        + " OR resref IN (SELECT canonical FROM resref_alias"
        + "               WHERE resref IN (" + sList + ")))");
    SqlBindString(q, "@u", GetObjectUUID(oPC));
    if (SqlStep(q))
        return SqlGetInt(q, 0);
    return 0;
}

// Percent bonus to the forge value cap for nKills distinct boss kills out of
// nTotal tracked. The single tunable mapping from progress to reward.
int ForgeBossBonusPct(int nKills, int nTotal)
{
    if (nTotal > 0 && nKills >= nTotal)
        return FORGE_BOSS_TOP_PCT;
    if (nKills >= FORGE_BOSS_TIER3_KILLS) return FORGE_BOSS_TIER3_PCT;
    if (nKills >= FORGE_BOSS_TIER2_KILLS) return FORGE_BOSS_TIER2_PCT;
    if (nKills >= FORGE_BOSS_TIER1_KILLS) return FORGE_BOSS_TIER1_PCT;
    return 0;
}
const string FORGE_VAULT_TAG = "FORGE_VAULT";
const int FORGE_DIS_SLOTS = 8;

// Staged-disenchant plan bitmask: one bit per ORIGINAL permanent-property index,
// spread across FORGE_STG_WORDS local ints (FORGE_STG_M0..) of FORGE_STG_BITS
// bits each, so the menu can paginate past the 8 visible slots and plan removals
// on items with far more than 8 enchantments. 30 bits/word stays clear of the
// sign bit; 6 words covers 180 properties (no real item approaches that). A
// page of FORGE_DIS_SLOTS slots maps slot n -> absolute index page*8 + n.
const int FORGE_STG_BITS  = 30;
const int FORGE_STG_WORDS = 6;

// Contraband-scan "clean" stamp. An item verified legal by the login scan gets
// item-local int "FORGE_CLEAN" set to FORGE_CLEAN_VER; future logins skip it,
// so a repeat login does almost no work. The stamp persists with the item in
// the player's .bic. BUMP FORGE_CLEAN_VER whenever the legality rules or the
// forge_legal_inc whitelist change, so every item is re-scanned exactly once
// after a rules update. Forge masters clear the stamp when they modify an item
// (see modifyitem.nss / forge_dis_go.nss). Legality is intrinsic to the item,
// so a clean stamp is valid across owners — trading can't launder gear.
const int FORGE_CLEAN_VER = 3;

// Tri-state result of ForgeItemLegality.
const int FORGE_LEG_LEGAL         = 0;  // confirmed within the law
const int FORGE_LEG_ILLEGAL       = 1;  // tampered + over the ceiling
const int FORGE_LEG_INDETERMINATE = 2;  // valuation infra unavailable — don't judge

void ForgeLog(string sMsg)
{
    if (!GetLocalInt(GetModule(), "FORGE_DEBUG")) return;
    string sLine = "[FORGE] " + sMsg;
    WriteTimestampedLogEntry(sLine);
    SendMessageToAllDMs(sLine);
}

// Cosmetic properties are not enchantments: never counted, compared, listed
// or fingerprinted by the forge system. Covers weapon visual effects (Bree
// appearance station, see inc_emotewand AddItemPropertyVisualEffect) and
// Light of any color/brightness (Continual Flame, gems of power, the forge's
// own Light enchant — illumination only, no combat bonus). forge_legal_inc's
// ForgeLegalFingerprint mirrors this rule.
int ForgeIsCosmeticProp(itemproperty ip)
{
    int nType = GetItemPropertyType(ip);
    return nType == ITEM_PROPERTY_VISUALEFFECT
        || nType == ITEM_PROPERTY_LIGHT;
}

// Creature items (natural weapons / hide) are equipped by the engine into the
// creature slots during polymorph — druid Dragon Shape, wild shape, shifter
// forms, etc. They carry the form's built-in enchantments, have no stock
// blueprint, and cannot be forged or disenchanted by a player, so they must
// never count as contraband. Base item types 69-73 (CSLASHWEAPON, CPIERCWEAPON,
// CBLUDGWEAPON, CSLSHPRCWEAP, CREATUREITEM).
int ForgeIsCreatureItem(object oItem)
{
    int nBase = GetBaseItemType(oItem);
    return nBase == BASE_ITEM_CSLASHWEAPON
        || nBase == BASE_ITEM_CPIERCWEAPON
        || nBase == BASE_ITEM_CBLUDGWEAPON
        || nBase == BASE_ITEM_CSLSHPRCWEAP
        || nBase == BASE_ITEM_CREATUREITEM;
}

// Hidden inventory placeable (in the prison) used to host temporary item
// copies so valuations never transit a player-visible inventory or fire
// OnAcquireItem hooks. Falls back to OBJECT_SELF when it has an inventory.
object ForgeHolder()
{
    object oVault = GetObjectByTag(FORGE_VAULT_TAG);
    if (GetIsObjectValid(oVault))
        return oVault;
    if (GetHasInventory(OBJECT_SELF))
        return OBJECT_SELF;
    ForgeLog("ForgeHolder: FORGE_VAULT missing and OBJECT_SELF has no inventory");
    return OBJECT_INVALID;
}

// Resref of the clean, Cost=0, property-free blank blueprint for a base item
// type (generated by bin/gen-forge-blanks.py). The forge values items by their
// enchantments by rebuilding them on one of these blanks — see ForgeRebuildValue.
string ForgeBlankResRef(int nBaseItem)
{
    return "forge_blank_" + IntToString(nBaseItem);
}

// Enchantment-derived worth of a single unit of oItem: build a clean blank of the
// SAME base item type (which carries NO Cost override) and copy oItem's permanent,
// non-cosmetic properties onto it, then read GetGoldPieceValue. The engine then
// prices the item from its actual properties + base item cost.
//
// This exists because NWN's GetGoldPieceValue returns an item's fixed blueprint
// Cost override (when one is set, e.g. The High Staff's 2,426,048) and IGNORES its
// properties — so a copy/remove never lowers the worth and players can't strip an
// over-cap item lawful. Rebuilding on an override-free blank is the only thing that
// makes the worth track the actual enchantments. (Base armor AC from appearance is
// not reproduced on the blank — a negligible few-hundred-gp difference well under
// any cap.) Returns -1 only when no valuation is possible; if the base type somehow
// has no blank it falls back to a plain identified/non-plot copy so it is never -1
// for a real item.
int ForgeRebuildValue(object oItem)
{
    if (!GetIsObjectValid(oItem))
        return -1;
    object oHolder = ForgeHolder();
    if (!GetIsObjectValid(oHolder))
        return -1;
    object oBlank = CreateItemOnObject(ForgeBlankResRef(GetBaseItemType(oItem)),
                                       oHolder);
    if (!GetIsObjectValid(oBlank))
    {
        // No blank for this base type — fall back to a plain copy (subject to any
        // Cost override, but never -1 for a valid item).
        object oCopy = CopyItem(oItem, oHolder, TRUE);
        if (!GetIsObjectValid(oCopy))
            return -1;
        SetItemStackSize(oCopy, 1);
        SetIdentified(oCopy, TRUE);
        SetPlotFlag(oCopy, FALSE);
        int v = GetGoldPieceValue(oCopy);
        DestroyObject(oCopy);
        return v;
    }
    itemproperty ip = GetFirstItemProperty(oItem);
    while (GetIsItemPropertyValid(ip))
    {
        if (GetItemPropertyDurationType(ip) == DURATION_TYPE_PERMANENT
            && !ForgeIsCosmeticProp(ip))
            AddItemProperty(DURATION_TYPE_PERMANENT, ip, oBlank);
        ip = GetNextItemProperty(oItem);
    }
    int nValue = GetGoldPieceValue(oBlank);
    DestroyObject(oBlank);
    return nValue;
}

// True assessed value of an item, priced by its enchantments (override-immune via
// ForgeRebuildValue). Returns -1 when no valuation is possible (callers must
// refuse, not treat as free).
// bPerUnit: value a single unit, not the whole stack. The rebuild values one unit,
// so the contraband ceiling (a per-item cap) passes TRUE; the forge pricing callers
// leave it FALSE (enchanting a stack enchants every unit), so the worth is scaled
// by stack size to match the old whole-stack GetGoldPieceValue contract.
int ForgeItemValue(object oItem, int bPerUnit = FALSE)
{
    int nUnit = ForgeRebuildValue(oItem);
    if (nUnit < 0)
        return -1;
    if (bPerUnit)
        return nUnit;
    int nStack = GetItemStackSize(oItem);
    if (nStack < 1)
        nStack = 1;
    return nUnit * nStack;
}

// Format a non-negative gold amount with thousands separators for player-facing
// text: 1234567 -> "1,234,567". Negative inputs (sentinel/"unavailable" values)
// pass through unformatted. Used everywhere a gold value is shown in the forge
// dialogs; property counts and page numbers stay plain IntToString.
string ForgeGold(int n)
{
    if (n < 0)
        return IntToString(n);
    string sIn = IntToString(n);
    int nLen = GetStringLength(sIn);
    string sOut = "";
    int i;
    for (i = 0; i < nLen; i++)
    {
        if (i > 0 && (nLen - i) % 3 == 0)
            sOut += ",";
        sOut += GetSubString(sIn, i, 1);
    }
    return sOut;
}

// Display word for token 102 ("Sword", "Armor", "Ring", ...) from the base item
// type. Used by the anvil context refresh below.
string ForgeBaseWord(int iBase)
{
    switch (iBase)
    {
        case BASE_ITEM_AMULET:        return "Amulet";
        case BASE_ITEM_ARMOR:         return "Armor";
        case BASE_ITEM_ARROW:         return "Arrow";
        case BASE_ITEM_BASTARDSWORD:  return "Sword";
        case BASE_ITEM_BATTLEAXE:     return "Axe";
        case BASE_ITEM_BELT:          return "Belt";
        case BASE_ITEM_BOLT:          return "Bolt";
        case BASE_ITEM_BOOTS:         return "Boots";
        case BASE_ITEM_BRACER:        return "Bracers";
        case BASE_ITEM_BULLET:        return "Bullet";
        case BASE_ITEM_CLOAK:         return "Cloak";
        case BASE_ITEM_CLUB:          return "Club";
        case BASE_ITEM_DAGGER:        return "Dagger";
        case BASE_ITEM_DART:          return "Dart";
        case BASE_ITEM_DIREMACE:      return "Dire Mace";
        case BASE_ITEM_DOUBLEAXE:     return "Double Axe";
        case BASE_ITEM_DWARVENWARAXE: return "War Axe";
        case BASE_ITEM_GLOVES:        return "Gloves";
        case BASE_ITEM_GREATAXE:      return "Axe";
        case BASE_ITEM_GREATSWORD:    return "Sword";
        case BASE_ITEM_HALBERD:       return "Halberd";
        case BASE_ITEM_HANDAXE:       return "Axe";
        case BASE_ITEM_HEAVYCROSSBOW: return "Crossbow";
        case BASE_ITEM_HEAVYFLAIL:    return "Flail";
        case BASE_ITEM_HELMET:        return "Helm";
        case BASE_ITEM_KAMA:          return "Kama";
        case BASE_ITEM_KATANA:        return "Katana";
        case BASE_ITEM_KUKRI:         return "Kukri";
        case BASE_ITEM_LARGESHIELD:   return "Shield";
        case BASE_ITEM_LIGHTCROSSBOW: return "Crossbow";
        case BASE_ITEM_LIGHTFLAIL:    return "Flail";
        case BASE_ITEM_LIGHTHAMMER:   return "Hammer";
        case BASE_ITEM_LIGHTMACE:     return "Mace";
        case BASE_ITEM_LONGBOW:       return "Bow";
        case BASE_ITEM_LONGSWORD:     return "Sword";
        case BASE_ITEM_MAGICSTAFF:    return "Staff";
        case BASE_ITEM_MORNINGSTAR:   return "Morningstar";
        case BASE_ITEM_QUARTERSTAFF:  return "Staff";
        case BASE_ITEM_RAPIER:        return "Rapier";
        case BASE_ITEM_RING:          return "Ring";
        case BASE_ITEM_SCIMITAR:      return "Scimitar";
        case BASE_ITEM_SCYTHE:        return "Scythe";
        case BASE_ITEM_SHORTBOW:      return "Bow";
        case BASE_ITEM_SHORTSPEAR:    return "Spear";
        case BASE_ITEM_SHORTSWORD:    return "Sword";
        case BASE_ITEM_SHURIKEN:      return "Shuriken";
        case BASE_ITEM_SICKLE:        return "Sickle";
        case BASE_ITEM_SLING:         return "Sling";
        case BASE_ITEM_SMALLSHIELD:   return "Shield";
        case BASE_ITEM_THROWINGAXE:   return "Axe";
        case BASE_ITEM_TOWERSHIELD:   return "Shield";
        case BASE_ITEM_TWOBLADEDSWORD:return "Sword";
        case BASE_ITEM_WARHAMMER:     return "Hammer";
        case BASE_ITEM_WHIP:          return "Whip";
    }
    return "Item";
}

// Find the single item on the nearest pAnvilOfWonder, cache it on oPC as
// MODIFY_ITEM, and prime EVERY display token the forge dialogs use: name (100),
// base word (102), PC name (103), current worth (104), this forge's cap (105)
// and the remaining headroom (106) — plus the PC value/property caps MODIFY_MAX
// / MODIFY_MAX_PROPS. Returns TRUE only when exactly one item sits on the anvil.
//
// This is the SINGLE source of truth for "the item on the anvil". NWN custom
// tokens are server-global, so a node that shows <CUSTOM100>/<CUSTOM105> renders
// whatever item was last refreshed by ANY player; the dialog therefore calls
// this both as the isitemonanvil reply-gate AND as the modify/strip reply script
// (forge_anvil_ctx), so the tokens are always re-primed immediately before the
// node that shows them — never the previously-worked item, never a stale cap.
int ForgeRefreshAnvilContext(object oPC)
{
    object oAnvil = GetNearestObjectByTag("pAnvilOfWonder");
    if (oAnvil == OBJECT_INVALID)
    {
        ForgeLog("anvil-ctx: PC=" + GetName(oPC) + " anvil NOT FOUND");
        return FALSE;
    }
    object oItem = GetFirstItemInInventory(oAnvil);
    if (oItem == OBJECT_INVALID)
    {
        ForgeLog("anvil-ctx: PC=" + GetName(oPC) + " no item on anvil");
        return FALSE;
    }
    if (GetNextItemInInventory(oAnvil) != OBJECT_INVALID)
    {
        ForgeLog("anvil-ctx: PC=" + GetName(oPC) + " MULTIPLE items on anvil");
        return FALSE;
    }
    SetIdentified(oItem, TRUE);
    if (!GetLocalInt(oItem, "FORGE_BASE_SET"))
    {
        SetLocalInt(oItem, "FORGE_BASE_VALUE", ForgeItemValue(oItem));
        SetLocalInt(oItem, "FORGE_BASE_SET", TRUE);
    }
    SetLocalObject(oPC, "MODIFY_ITEM", oItem);

    // Per-forge ceilings read from the anvil's area. Uncapped forges were removed
    // June 2026, so a missing/zero cap falls back to the global legal ceiling
    // rather than the old "no" placeholder. Boss-kill progress raises the
    // area's base cap by a percent (see the tier table above), then a high
    // Appraise raises the ceiling further (take-20, up to +500k at an
    // Appraise check of 65).
    int nBossKills = ForgeBossDistinctKills(oPC);
    int nBossTotal = ForgeBossTotalTracked();
    int nBossPct   = ForgeBossBonusPct(nBossKills, nBossTotal);
    int iMaxValue = GetLocalInt(GetArea(oAnvil), "FORGE_MAX_VALUE");
    if (iMaxValue <= 0)
        iMaxValue = FORGE_LEGAL_MAX_VALUE;
    iMaxValue += iMaxValue / 100 * nBossPct;
    iMaxValue += ForgeAppraiseBonus(oPC);
    SetLocalInt(oPC, "MODIFY_MAX", iMaxValue);
    int iMaxProps = GetLocalInt(GetArea(oAnvil), "FORGE_MAX_PROPS");
    if (iMaxProps <= 0)
        iMaxProps = FORGE_LEGAL_MAX_PROPS;
    // Top boss tier (every tracked boss slain) earns one extra property slot,
    // but only at the top-tier forges (prop cap already at the legal max).
    int bBossPropSlot = (nBossPct >= FORGE_BOSS_TOP_PCT
                         && iMaxProps >= FORGE_LEGAL_MAX_PROPS);
    if (bBossPropSlot)
        iMaxProps++;
    SetLocalInt(oPC, "MODIFY_MAX_PROPS", iMaxProps);

    // Tell the player their boss-progress bonus once per session (re-told when
    // the distinct-kill count changes, e.g. after slaying a new boss).
    if (GetLocalInt(oPC, "FORGE_BOSS_TOLD") != nBossKills + 1)
    {
        SetLocalInt(oPC, "FORGE_BOSS_TOLD", nBossKills + 1);
        string sBoss;
        if (nBossPct > 0)
        {
            sBoss = "Boss-slayer's edge: " + IntToString(nBossKills) + " of "
                + IntToString(nBossTotal) + " bosses of the Roll of the Fallen "
                + "slain — +" + IntToString(nBossPct)
                + "% to this forge's value cap";
            if (bBossPropSlot)
                sBoss += " and one extra enchantment slot";
            sBoss += ".";
        }
        else if (nBossTotal > 0)
            sBoss = "Forge lore: slay " + IntToString(FORGE_BOSS_TIER1_KILLS)
                + " different bosses of the Roll of the Fallen to earn a forge "
                + "cap bonus (" + IntToString(nBossKills) + " of "
                + IntToString(nBossTotal) + " so far).";
        if (sBoss != "")
            FloatingTextStringOnCreature(sBoss, oPC, FALSE);
    }

    SetCustomToken(100, GetName(oItem));
    SetCustomToken(102, ForgeBaseWord(GetBaseItemType(oItem)));
    SetCustomToken(103, GetName(oPC));
    int iWorth = ForgeItemValue(oItem);
    SetCustomToken(104, ForgeGold(iWorth));
    SetCustomToken(105, ForgeGold(iMaxValue));
    int iHeadroom = iMaxValue - iWorth;
    if (iHeadroom < 0) iHeadroom = 0;
    SetCustomToken(106, ForgeGold(iHeadroom));
    ForgeLog("anvil-ctx: PC=" + GetName(oPC) + " item='" + GetName(oItem)
        + "' worth=" + IntToString(iWorth) + " cap=" + IntToString(iMaxValue));
    return TRUE;
}

int ForgeCountProps(object oItem)
{
    int nCount = 0;
    itemproperty ip = GetFirstItemProperty(oItem);
    while (GetIsItemPropertyValid(ip))
    {
        if (GetItemPropertyDurationType(ip) == DURATION_TYPE_PERMANENT
            && !ForgeIsCosmeticProp(ip))
            nCount++;
        ip = GetNextItemProperty(oItem);
    }
    return nCount;
}

// Same matcher CustomAddProperty (itemprocs) uses to replace-instead-of-add:
// a property "matches" when types are equal and the new property's subtype is
// -1 (wildcard) or equal. A matching enchant replaces and does not grow the
// property count.
int ForgePropMatchesExisting(object oItem, itemproperty ip)
{
    int iTyp = GetItemPropertyType(ip);
    int iSubTyp = GetItemPropertySubType(ip);
    itemproperty ipLoop = GetFirstItemProperty(oItem);
    while (GetIsItemPropertyValid(ipLoop))
    {
        if (GetItemPropertyType(ipLoop) == iTyp
            && (iSubTyp == -1 || GetItemPropertySubType(ipLoop) == iSubTyp))
            return TRUE;
        ipLoop = GetNextItemProperty(oItem);
    }
    return FALSE;
}

// Nth (0-based) permanent property, in GetFirstItemProperty order.
itemproperty ForgeGetPermPropByIndex(object oItem, int nIndex)
{
    int nCount = 0;
    itemproperty ip = GetFirstItemProperty(oItem);
    while (GetIsItemPropertyValid(ip))
    {
        if (GetItemPropertyDurationType(ip) == DURATION_TYPE_PERMANENT
            && !ForgeIsCosmeticProp(ip))
        {
            if (nCount == nIndex)
                return ip;
            nCount++;
        }
        ip = GetNextItemProperty(oItem);
    }
    itemproperty ipInvalid;
    return ipInvalid;
}

// Human-readable property label from the 2das, e.g.
// "Enhancement Bonus: +3" or "Damage Bonus: Fire / 2d6".
// Falls back to raw numbers when a 2da lookup comes back empty.
string ForgePropName(itemproperty ip)
{
    int iTyp = GetItemPropertyType(ip);
    string sName;
    string sRef = Get2DAString("itempropdef", "GameStrRef", iTyp);
    if (sRef != "")
        sName = GetStringByStrRef(StringToInt(sRef));
    if (sName == "")
        sName = "Property #" + IntToString(iTyp);

    int iSubTyp = GetItemPropertySubType(ip);
    if (iSubTyp >= 0)
    {
        string sSubRes = Get2DAString("itempropdef", "SubTypeResRef", iTyp);
        if (sSubRes != "")
        {
            string sSubRef = Get2DAString(sSubRes, "Name", iSubTyp);
            string sSub = "";
            if (sSubRef != "")
                sSub = GetStringByStrRef(StringToInt(sSubRef));
            if (sSub == "")
                sSub = IntToString(iSubTyp);
            sName += ": " + sSub;
        }
    }

    int iCostTab = GetItemPropertyCostTable(ip);
    if (iCostTab >= 0)
    {
        string sCostRes = Get2DAString("iprp_costtable", "Name", iCostTab);
        if (sCostRes != "")
        {
            string sCostRef = Get2DAString(sCostRes, "Name",
                GetItemPropertyCostTableValue(ip));
            string sCost = "";
            if (sCostRef != "")
                sCost = GetStringByStrRef(StringToInt(sCostRef));
            if (sCost != "")
                sName += " " + sCost;
        }
    }
    return sName;
}

// Compare oItem's permanent properties against its pristine blueprint
// (instantiated by resref). Order-insensitive multiset compare keyed on
// (type, subtype, costtablevalue, param1value). Unknown resref counts as
// deviating — conservative by design.
int ForgeItemDeviatesFromBlueprint(object oItem)
{
    object oHolder = ForgeHolder();
    if (!GetIsObjectValid(oHolder))
        return FALSE; // can't judge — never jail on infrastructure failure

    string sResRef = GetResRef(oItem);
    object oStock = CreateItemOnObject(sResRef, oHolder);
    if (!GetIsObjectValid(oStock))
    {
        ForgeLog("DeviatesFromBlueprint: no blueprint for resref '" + sResRef
            + "' (item '" + GetName(oItem) + "') — treating as deviant");
        return TRUE;
    }

    int bDeviates = FALSE;
    if (ForgeCountProps(oItem) != ForgeCountProps(oStock))
        bDeviates = TRUE;
    else
    {
        // Every property on oItem must consume a distinct match on oStock.
        // Track consumed stock properties by index in a flag string.
        int nStock = ForgeCountProps(oStock);
        string sUsed; // one char per stock prop: "0" free, "1" consumed
        int i;
        for (i = 0; i < nStock; i++)
            sUsed += "0";

        itemproperty ip = GetFirstItemProperty(oItem);
        while (!bDeviates && GetIsItemPropertyValid(ip))
        {
            if (GetItemPropertyDurationType(ip) == DURATION_TYPE_PERMANENT
                && !ForgeIsCosmeticProp(ip))
            {
                int bMatched = FALSE;
                for (i = 0; i < nStock && !bMatched; i++)
                {
                    if (GetSubString(sUsed, i, 1) == "0")
                    {
                        itemproperty ipS = ForgeGetPermPropByIndex(oStock, i);
                        if (GetItemPropertyType(ipS) == GetItemPropertyType(ip)
                            && GetItemPropertySubType(ipS) == GetItemPropertySubType(ip)
                            && GetItemPropertyCostTableValue(ipS) == GetItemPropertyCostTableValue(ip)
                            && GetItemPropertyParam1Value(ipS) == GetItemPropertyParam1Value(ip))
                        {
                            sUsed = GetStringLeft(sUsed, i) + "1"
                                + GetSubString(sUsed, i + 1, nStock - i - 1);
                            bMatched = TRUE;
                        }
                    }
                }
                if (!bMatched)
                    bDeviates = TRUE;
            }
            ip = GetNextItemProperty(oItem);
        }
    }
    DestroyObject(oStock);
    return bDeviates;
}

// Tri-state legality verdict. Illegal = exceeds the global legal ceiling
// (ForgeLegalMaxProps() properties / ForgeLegalMaxValue() gp — the MAXIMUM
// ACHIEVABLE forge caps including the top boss-kill bonus, so items forged by
// a decorated boss-slayer stay legal in ANY character's hands) AND was
// tampered with (deviates from its stock blueprint). Stock drops above the
// ceiling stay legal. Returns INDETERMINATE when no valuation is possible —
// callers must neither jail nor mark such items clean. The single source of
// truth for legality (ForgeIsItemIllegal and the login scan both go through
// here).
int ForgeItemLegality(object oItem)
{
    if (!GetIsObjectValid(oItem))
        return FORGE_LEG_LEGAL;
    if (ForgeIsCreatureItem(oItem))
        return FORGE_LEG_LEGAL; // polymorph natural weapon/hide — engine-managed, never forged
    int nValue = ForgeItemValue(oItem, TRUE); // per-unit: the cap is per item, not per stack
    if (nValue < 0)
        return FORGE_LEG_INDETERMINATE; // no valuation infrastructure — never judge blind
    // A forge stamps FORGE_CEIL on an item it lawfully enchanted above the
    // default ceiling because the forger's Appraise allowed it; honor that
    // higher per-item ceiling for everyone (legality is intrinsic to the item).
    int nValueCeil = ForgeLegalMaxValue();
    int nStamp = GetLocalInt(oItem, FORGE_CEIL);
    if (nStamp > nValueCeil)
        nValueCeil = nStamp;
    if (ForgeCountProps(oItem) <= ForgeLegalMaxProps()
        && nValue <= nValueCeil)
        return FORGE_LEG_LEGAL;
    if (!ForgeItemDeviatesFromBlueprint(oItem))
        return FORGE_LEG_LEGAL;
    // Deviating from blueprint is fine when the deviation matches an item the
    // module itself places (embedded store stock, creature loot, container
    // contents) — those are legally obtainable, not player-forged.
    if (ForgeIsKnownLegalVariant(oItem))
    {
        ForgeLog("ItemLegality: '" + GetName(oItem) + "' (" + GetResRef(oItem)
            + ") deviates but matches a known legal variant — allowed.");
        return FORGE_LEG_LEGAL;
    }
    return FORGE_LEG_ILLEGAL;
}

int ForgeIsItemIllegal(object oItem)
{
    return ForgeItemLegality(oItem) == FORGE_LEG_ILLEGAL;
}

// TRUE when oItem exists and sits in oPC's inventory or equipment (one
// container level deep — bags can't nest). Guards warden scripts against
// stale cached handles whose object id the engine may have recycled.
int ForgePCHolds(object oPC, object oItem)
{
    if (!GetIsObjectValid(oItem))
        return FALSE;
    object oPoss = GetItemPossessor(oItem);
    if (oPoss == oPC)
        return TRUE;
    return GetIsObjectValid(oPoss) && GetItemPossessor(oPoss) == oPC;
}

// TRUE when oItem was already handled by the current revert-all pass on oPC
// (item-local FORGE_RVT_SKIP carries the pass's run stamp). Stale stamps from
// earlier passes don't match, so nothing is skipped forever.
int ForgeRevertSeen(object oItem, object oPC)
{
    return GetLocalInt(oItem, "FORGE_RVT_SKIP")
        == GetLocalInt(oPC, "FORGE_RVT_RUN");
}

// An item the login/Warden scan already verified legal carries the current
// FORGE_CLEAN stamp. Legality is intrinsic to the item and a forge clears the
// stamp on any change (see modifyitem / forge_dis_go), so a stamped item can be
// skipped without re-running the expensive valuation — this is what keeps the
// synchronous scanners (revert-all loop, release guard) under the instruction
// cap once an inventory has been scanned.
int ForgeIsKnownClean(object oItem)
{
    return GetLocalInt(oItem, "FORGE_CLEAN") == FORGE_CLEAN_VER;
}

// First illegal item on the PC: equipped slots, then inventory, descending
// one level into containers (bags can't nest in NWN). bSkipMarked skips items
// already handled by the current revert-all pass (see ForgeRevertSeen) — they
// still count as illegal everywhere else. Clean-stamped items are skipped before
// the costly legality check (short-circuit), so a fully-scanned inventory costs
// little here.
object ForgeFindIllegalItem(object oPC, int bSkipMarked = FALSE)
{
    int nSlot;
    for (nSlot = 0; nSlot < NUM_INVENTORY_SLOTS; nSlot++)
    {
        object oItem = GetItemInSlot(nSlot, oPC);
        if (GetIsObjectValid(oItem) && !ForgeIsKnownClean(oItem)
            && ForgeIsItemIllegal(oItem)
            && !(bSkipMarked && ForgeRevertSeen(oItem, oPC)))
            return oItem;
    }
    object oItem = GetFirstItemInInventory(oPC);
    while (GetIsObjectValid(oItem))
    {
        if (!ForgeIsKnownClean(oItem) && ForgeIsItemIllegal(oItem)
            && !(bSkipMarked && ForgeRevertSeen(oItem, oPC)))
            return oItem;
        if (GetHasInventory(oItem))
        {
            object oInBag = GetFirstItemInInventory(oItem);
            while (GetIsObjectValid(oInBag))
            {
                if (!ForgeIsKnownClean(oInBag) && ForgeIsItemIllegal(oInBag)
                    && !(bSkipMarked && ForgeRevertSeen(oInBag, oPC)))
                    return oInBag;
                oInBag = GetNextItemInInventory(oItem);
            }
        }
        oItem = GetNextItemInInventory(oPC);
    }
    return OBJECT_INVALID;
}

// Replace oItem with a pristine copy of its stock blueprint, created on oPC.
// New item is created first so a missing blueprint never costs the player
// the original. Returns the new item, or OBJECT_INVALID when the blueprint
// is unknown (item left untouched). Equipped originals land the replacement
// in the backpack.
object ForgeRevertToBlueprint(object oItem, object oPC)
{
    if (!GetIsObjectValid(oItem))
        return OBJECT_INVALID;
    string sResRef = GetResRef(oItem);
    object oNew = CreateItemOnObject(sResRef, oPC);
    if (!GetIsObjectValid(oNew))
    {
        ForgeLog("RevertToBlueprint: no blueprint for resref '" + sResRef
            + "' (item '" + GetName(oItem) + "')");
        return OBJECT_INVALID;
    }
    SetIdentified(oNew, TRUE);
    ForgeLog("RevertToBlueprint: '" + GetName(oItem) + "' -> stock '"
        + GetName(oNew) + "' (resref " + sResRef + ") for " + GetName(oPC));
    DestroyObject(oItem);
    return oNew;
}

// Revert every illegal item on the PC to its stock blueprint. Returns how
// many could NOT be reverted (no known blueprint); those stay illegal.
// Every visited item is stamped with this pass's run id BEFORE the revert,
// so the loop terminates even if DestroyObject is deferred past the rescan.
int ForgeRevertAllIllegal(object oPC)
{
    int nRun = GetLocalInt(oPC, "FORGE_RVT_RUN") + 1;
    SetLocalInt(oPC, "FORGE_RVT_RUN", nRun);
    int nFail = 0;
    int nGuard = 0;
    object oBad = ForgeFindIllegalItem(oPC, TRUE);
    while (GetIsObjectValid(oBad) && nGuard < 100)
    {
        nGuard++;
        SetLocalInt(oBad, "FORGE_RVT_SKIP", nRun);
        if (!GetIsObjectValid(ForgeRevertToBlueprint(oBad, oPC)))
            nFail++;
        oBad = ForgeFindIllegalItem(oPC, TRUE);
    }
    return nFail;
}

// Player-facing summary of what still makes oItem unlawful (for the Forge
// Warden's dialog), or a confirmation that it is now within the law.
string ForgeLegalStatus(object oItem)
{
    if (!GetIsObjectValid(oItem))
        return "";
    int nProps = ForgeCountProps(oItem);
    int nValue = ForgeItemValue(oItem, TRUE); // per-unit: matches the ForgeIsItemIllegal gate
    // Honor any Appraise-extended ceiling stamped on the item (see FORGE_CEIL),
    // so a lawfully high-value piece reads as within the law, not contraband.
    int nValueCeil = ForgeLegalMaxValue();
    int nStamp = GetLocalInt(oItem, FORGE_CEIL);
    if (nStamp > nValueCeil)
        nValueCeil = nStamp;
    int bProps = nProps > ForgeLegalMaxProps();
    int bValue = nValue > nValueCeil;
    if (!bProps && !bValue)
        return "It is within the law now: " + IntToString(nProps)
            + " enchantments of the " + IntToString(ForgeLegalMaxProps())
            + " allowed, and a worth of " + ForgeGold(nValue)
            + " gold under the lawful " + ForgeGold(nValueCeil) + ".";
    string s = "";
    if (bProps)
        s += "It still bears " + IntToString(nProps) + " enchantments where the "
            + "law allows but " + IntToString(ForgeLegalMaxProps()) + ".";
    if (bValue)
    {
        if (s != "") s += " And i";
        else s += "I";
        s += "ts worth, " + ForgeGold(nValue) + " gold, still exceeds the lawful "
            + ForgeGold(nValueCeil) + ".";
    }
    return s;
}

// Prime the disenchant sub-conversation: target item on the PC, property
// count, and one custom token per listed property slot.
void ForgeDisenchantSetup(object oPC, object oTarget)
{
    SetLocalObject(oPC, "FORGE_DIS_ITEM", oTarget);
    int nCount = 0;
    if (GetIsObjectValid(oTarget))
    {
        nCount = ForgeCountProps(oTarget);
        SetCustomToken(100, GetName(oTarget));
    }
    SetLocalInt(oPC, "FORGE_DIS_COUNT", nCount);
    int n;
    for (n = 0; n < FORGE_DIS_SLOTS; n++)
    {
        string sLabel = "";
        if (n < nCount)
            sLabel = ForgePropName(ForgeGetPermPropByIndex(oTarget, n));
        SetCustomToken(6110 + n, sLabel);
    }
}

// ---------------------------------------------------------------------------
// Staged (transactional) anvil disenchant. The forge masters let a player PLAN
// which properties to strike from an over-quality item and only commit the
// removals once the planned result would be lawful — so the real item never
// passes through an illegal state (and the player is never jailed mid-effort).
// A per-PC bitmask FORGE_STG_MASK records which ORIGINAL permanent-property
// indices are planned for removal; because nothing is mutated until commit, the
// indices stay stable for the whole conversation. These are ANVIL-ONLY — the
// Forge Warden's jail dialog keeps using the immediate-removal forge_dis_*
// scripts above.

// Effective per-item legality ceiling for oPC working oItem: the global cap
// (max-achievable, incl. the top boss-tier bonus — see ForgeLegalMaxValue)
// raised by the player's live Appraise headroom, never below a FORGE_CEIL the
// item already carries. Mirrors the max() ForgeItemLegality uses, plus the live
// Appraise bonus (what this smith may allow this player).
int ForgeEffectiveCeil(object oPC, object oItem)
{
    int nCeil = ForgeLegalMaxValue() + ForgeAppraiseBonus(oPC);
    int nStamp = GetLocalInt(oItem, FORGE_CEIL);
    if (nStamp > nCeil)
        nCeil = nStamp;
    return nCeil;
}

// --- Staged plan bitmask (per-PC, indexed by absolute permanent-property index).
// Spread across FORGE_STG_WORDS local ints so the menu can plan removals on more
// than 8 (or 30) properties. Bit `idx` lives in word idx/FORGE_STG_BITS.
int ForgeStageGetBit(object oPC, int idx)
{
    int w = idx / FORGE_STG_BITS;
    int b = idx % FORGE_STG_BITS;
    return (GetLocalInt(oPC, "FORGE_STG_M" + IntToString(w)) & (1 << b)) != 0;
}

void ForgeStageToggleBit(object oPC, int idx)
{
    int w = idx / FORGE_STG_BITS;
    int b = idx % FORGE_STG_BITS;
    string sVar = "FORGE_STG_M" + IntToString(w);
    SetLocalInt(oPC, sVar, GetLocalInt(oPC, sVar) ^ (1 << b));
}

void ForgeStageClear(object oPC)
{
    int w;
    for (w = 0; w < FORGE_STG_WORDS; w++)
        DeleteLocalInt(oPC, "FORGE_STG_M" + IntToString(w));
    DeleteLocalInt(oPC, "FORGE_STG_MASK"); // legacy single-int mask, if present
}

int ForgeStageAnyBit(object oPC)
{
    int w;
    for (w = 0; w < FORGE_STG_WORDS; w++)
        if (GetLocalInt(oPC, "FORGE_STG_M" + IntToString(w)) != 0)
            return TRUE;
    return FALSE;
}

// Projected per-unit value of oItem with the planned removals (oPC's plan
// bitmask) applied, optionally flipping one index (nToggleIdx) to preview what
// CLICKING that slot would do without mutating the live plan. Works on a
// throwaway copy in FORGE_VAULT: copy, remove every selected property index in
// DESCENDING order (so lower indices stay valid as we go), then price it
// identified/non-plot/per-unit exactly like ForgeItemValue. Returns -1 when
// valuation infrastructure is unavailable.
int ForgeProjectedValue(object oPC, object oItem, int nToggleIdx = -1)
{
    if (!GetIsObjectValid(oItem))
        return -1;
    object oHolder = ForgeHolder();
    if (!GetIsObjectValid(oHolder))
        return -1;
    // Rebuild on a clean Cost=0 blank of the same base type, copying only the
    // KEPT (not planned-for-removal) permanent, non-cosmetic properties, then let
    // the engine price it. This is override-immune, so the worth actually drops as
    // properties are planned for removal (plain GetGoldPieceValue would not — see
    // ForgeRebuildValue). nToggleIdx flips one index to preview a click.
    object oBlank = CreateItemOnObject(ForgeBlankResRef(GetBaseItemType(oItem)),
                                       oHolder);
    if (!GetIsObjectValid(oBlank))
        return -1;
    int n = 0;
    itemproperty ip = GetFirstItemProperty(oItem);
    while (GetIsItemPropertyValid(ip))
    {
        if (GetItemPropertyDurationType(ip) == DURATION_TYPE_PERMANENT
            && !ForgeIsCosmeticProp(ip))
        {
            int bDrop = ForgeStageGetBit(oPC, n);
            if (n == nToggleIdx)
                bDrop = !bDrop;
            if (!bDrop)
                AddItemProperty(DURATION_TYPE_PERMANENT, ip, oBlank);
            n++;
        }
        ip = GetNextItemProperty(oItem);
    }
    int nValue = GetGoldPieceValue(oBlank);
    DestroyObject(oBlank);
    return nValue;
}

// Permanent-property count remaining after the planned removals.
int ForgeProjectedPropCount(object oPC, object oItem)
{
    int nCount = ForgeCountProps(oItem);
    int nRemoved = 0;
    int n;
    for (n = 0; n < nCount; n++)
        if (ForgeStageGetBit(oPC, n))
            nRemoved++;
    return nCount - nRemoved;
}

// Player-facing running status of the planned result (header token 6119): the
// projected worth and whether it is within the law or how much it is still over.
// Returns a non-empty fallback for an invalid/unvaluable item so the dialog's
// <CUSTOM6119> never renders as "<UNRECOGNIZED TOKEN>".
string ForgeProjectedStatus(object oPC, object oItem)
{
    if (!GetIsObjectValid(oItem))
        return "Place an item on the anvil for me to weigh.";
    int nVal = ForgeProjectedValue(oPC, oItem);
    if (nVal < 0)
        return "I cannot weigh that piece just now.";
    int nCeil = ForgeEffectiveCeil(oPC, oItem);
    int nProps = ForgeProjectedPropCount(oPC, oItem);
    string s;
    if (!ForgeStageAnyBit(oPC))
        s = "As it stands the " + GetName(oItem) + " is worth "
            + ForgeGold(nVal) + " gold";
    else
        s = "With your plan struck, the " + GetName(oItem) + " would be worth "
            + ForgeGold(nVal) + " gold";
    if (nVal <= nCeil && nProps <= ForgeLegalMaxProps())
        return s + " — within the lawful " + ForgeGold(nCeil) + ".";
    if (nVal > nCeil)
        s += ", still " + ForgeGold(nVal - nCeil) + " over the lawful "
            + ForgeGold(nCeil);
    if (nProps > ForgeLegalMaxProps())
        s += ", and bears " + IntToString(nProps) + " enchantments where the law "
            + "allows but " + IntToString(ForgeLegalMaxProps());
    return s + ". Strike more to bring it within the law.";
}

// TRUE when the plan is non-empty AND the projected result is lawful (worth
// within ForgeEffectiveCeil and at most ForgeLegalMaxProps() properties —
// the uniform legal ceiling, so a committed plan can never mint contraband).
// Drives the commit reply's Active gate (forge_stg_ok).
int ForgeStagePlanIsLawful(object oPC, object oItem)
{
    if (!GetIsObjectValid(oItem) || !ForgeStageAnyBit(oPC))
        return FALSE;
    int nVal = ForgeProjectedValue(oPC, oItem);
    if (nVal < 0)
        return FALSE;
    if (nVal > ForgeEffectiveCeil(oPC, oItem))
        return FALSE;
    return ForgeProjectedPropCount(oPC, oItem) <= ForgeLegalMaxProps();
}

// Prime the staged anvil disenchant menu for the CURRENT page (FORGE_STG_PAGE):
// target item, property count, the eight per-slot label+cue tokens 6110-6117
// (slot n shows absolute property index page*8 + n, marked planned/kept with the
// worth that CLICKING it would produce), and the running status token 6119 (with
// a page indicator when the item has more than one page of enchantments).
void ForgeStageSetupCued(object oPC, object oItem)
{
    SetLocalObject(oPC, "FORGE_STG_ITEM", oItem);
    int nCount = 0;
    if (GetIsObjectValid(oItem))
    {
        nCount = ForgeCountProps(oItem);
        SetCustomToken(100, GetName(oItem));
    }
    SetLocalInt(oPC, "FORGE_DIS_COUNT", nCount);

    int nPages = (nCount + FORGE_DIS_SLOTS - 1) / FORGE_DIS_SLOTS;
    if (nPages < 1) nPages = 1;
    int nPage = GetLocalInt(oPC, "FORGE_STG_PAGE");
    // Clamp the page if the list shrank (e.g. after a commit removed properties).
    if (nPage >= nPages)
    {
        nPage = nPages - 1;
        SetLocalInt(oPC, "FORGE_STG_PAGE", nPage);
    }

    int n;
    for (n = 0; n < FORGE_DIS_SLOTS; n++)
    {
        int a = nPage * FORGE_DIS_SLOTS + n;   // absolute property index
        string sLabel = "";
        if (a < nCount)
        {
            int bStaged = ForgeStageGetBit(oPC, a);
            string sName = ForgePropName(ForgeGetPermPropByIndex(oItem, a));
            // Name only, with the red [planned] marker when staged for removal.
            // The running projected worth + lawful check is the header (token
            // 6119); per-slot worth previews were dropped to keep the menu to one
            // rebuild valuation per render.
            sLabel = (bStaged ? ColorString("[planned]", COLOR_RED) + " " : "")
                + sName;
        }
        SetCustomToken(6110 + n, sLabel);
    }

    string sStatus = ForgeProjectedStatus(oPC, oItem);
    if (nPages > 1)
        sStatus += " [Page " + IntToString(nPage + 1) + " of "
            + IntToString(nPages) + "]";
    SetCustomToken(6119, sStatus);
}

// Open/refresh the staged disenchant menu for the item on the anvil: start a
// fresh plan + first page whenever the menu opens on a DIFFERENT item, then prime
// every slot/status token. Call this from the reply scripts that lead INTO the D1
// menu entry (the strip-hook + "reconsider" replies via forge_stg_open, the slot
// toggles, the page-nav replies) so the tokens are set BEFORE D1's text renders.
// An NWN entry's own "Actions Taken" runs AFTER its text, which left token 6119
// unset ("<UNRECOGNIZED TOKEN>") on first open and the slot labels one click stale.
void ForgeStageOpen(object oPC)
{
    object oItem = GetLocalObject(oPC, "MODIFY_ITEM");
    if (oItem != GetLocalObject(oPC, "FORGE_STG_ITEM"))
    {
        ForgeStageClear(oPC);
        DeleteLocalInt(oPC, "FORGE_STG_PAGE");
    }
    ForgeStageSetupCued(oPC, oItem);
}

// Stamp the lawful ceiling and clean mark on a freshly-worked item so legality
// is intrinsic and the login/Well contraband scan agrees in O(1). Per the user
// request the ceiling (with Appraise headroom) is recorded whenever the smith
// works the item, so it stays lawful even if the bearer later loses Appraise or
// trades the item away. Mirrors the FORGE_CEIL/FORGE_CLEAN contract in
// modifyitem.nss.
void ForgeStampLawful(object oPC, object oItem)
{
    if (!GetIsObjectValid(oItem))
        return;
    // Stamp the max-achievable global ceiling + this player's Appraise, so a
    // boss-tier + Appraise forger's lawful work stays legal for any holder.
    int nCeil = ForgeLegalMaxValue() + ForgeAppraiseBonus(oPC);
    if (nCeil > GetLocalInt(oItem, FORGE_CEIL))
        SetLocalInt(oItem, FORGE_CEIL, nCeil);
    if (ForgeItemLegality(oItem) == FORGE_LEG_LEGAL)
        SetLocalInt(oItem, "FORGE_CLEAN", FORGE_CLEAN_VER);
}

// Commit the plan: strike every planned property from the REAL item (highest
// index first so lower indices stay valid), then stamp it lawful and clear the
// plan. Called only from forge_stg_go, whose reply is gated by ForgeStagePlanIsLawful.
void ForgeStageCommit(object oPC, object oItem)
{
    if (!GetIsObjectValid(oItem))
        return;
    int nCount = ForgeCountProps(oItem);
    int n;
    for (n = nCount - 1; n >= 0; n--)
    {
        if (ForgeStageGetBit(oPC, n))
        {
            itemproperty ip = ForgeGetPermPropByIndex(oItem, n);
            if (GetIsItemPropertyValid(ip))
            {
                ForgeLog("stage-disenchant: PC=" + GetName(oPC) + " item='"
                    + GetName(oItem) + "' removing [" + ForgePropName(ip) + "]");
                RemoveItemProperty(oItem, ip);
            }
        }
    }
    // Footprint changed — drop the stale clean stamp, then re-stamp the lawful
    // ceiling + clean mark on the now-lawful result.
    DeleteLocalInt(oItem, "FORGE_CLEAN");
    ForgeStampLawful(oPC, oItem);
    ForgeStageClear(oPC);
    DeleteLocalInt(oPC, "FORGE_STG_PAGE");
}

// Sequester a contested item for DM review: stored in the craftdb quarantine
// queue (same keys welloferuenter.nss uses), so it lands in the DM-review
// chest (ZEP_CR_QUARANTINE, House of Homer) on next open. No refund — a DM
// returns the item if the player's claim holds.
void ForgeQuarantineDisputedItem(object oItem, object oPC)
{
    if (!GetIsObjectValid(oItem) || !GetIsObjectValid(oPC))
        return;
    string sName = GetName(oItem);
    // Value the item BEFORE StoreCampaignObject/DestroyObject invalidate it.
    string sLog = "[FORGE DISPUTE] Item '" + sName + "' (resref: "
        + GetResRef(oItem) + ", props " + IntToString(ForgeCountProps(oItem))
        + ", value " + IntToString(ForgeItemValue(oItem))
        + ") sequestered from " + GetName(oPC) + " (account: "
        + GetPCPlayerName(oPC) + ") pending DM review.";

    // Stamp provenance onto the item itself so it travels with the object into
    // the quarantine chest snapshot and survives until a DM physically removes
    // it from the chest. The parallel quarantine_*_info campaign string below
    // is cleared the moment the chest is first opened (zep_cr_qrestore.nss), so
    // this local var is the durable record of who submitted the item.
    SetLocalString(oItem, "QUARANTINE_INFO", sLog);

    int nQ = GetCampaignInt("craftdb", "quarantine_count");
    StoreCampaignObject("craftdb", "quarantine_" + IntToString(nQ), oItem);
    SetCampaignString("craftdb", "quarantine_" + IntToString(nQ) + "_info", sLog);
    SetCampaignInt("craftdb", "quarantine_count", nQ + 1);
    DestroyObject(oItem);

    WriteTimestampedLogEntry(sLog);
    SendMessageToAllDMs(sLog);
    SendMessageToPC(oPC, "[Forge Warden] Your '" + sName + "' has been "
        + "sequestered under seal in the House of Homer pending DM review. "
        + "If your claim of lawful provenance holds, it will be returned to "
        + "you; if not, it is forfeit. No compensation is owed while the "
        + "matter is under judgment.");
}

// Jail oPC in the Pit Prison for carrying the illegal item oBad. Shared by the
// synchronous ForgeJailIfIllegal and the chunked login scan (forge_scan_step).
void ForgeJailForItem(object oPC, object oBad)
{
    if (!GetIsObjectValid(oBad))
        return;
    SetLocalObject(oPC, "FORGE_ILLEGAL_ITEM", oBad);
    // Seed the Warden's O(1) gate verdict: the scan just proved this item
    // illegal, so the gates can trust "dirty" the moment the PC arrives, with
    // no need to re-scan a (possibly huge) inventory inside a StartingConditional.
    SetLocalInt(oPC, "FORGE_WARDEN_DIRTY", TRUE);
    SetLocalInt(oPC, "FORGE_WARDEN_READY", TRUE);
    ForgeLog("Jailing " + GetName(oPC) + " for item '" + GetName(oBad)
        + "' (resref " + GetResRef(oBad) + ", props "
        + IntToString(ForgeCountProps(oBad)) + ", value "
        + IntToString(ForgeItemValue(oBad)) + ", fp="
        + ForgeLegalFingerprint(oBad) + ")");
    object oWP = GetWaypointByTag("jailed");
    if (!GetIsObjectValid(oWP))
    {
        ForgeLog("ForgeJailForItem: waypoint 'jailed' missing!");
        return;
    }
    FloatingTextStringOnCreature("The " + GetName(oBad) + " you carry bears "
        + "unlawful enchantment. The Valar take notice...", oPC, FALSE);
    location lJail = GetLocation(oWP);
    DelayCommand(1.0, AssignCommand(oPC, JumpToLocation(lJail)));
    // Spoken hint after arrival so the player knows which jailer applies.
    DelayCommand(3.0, AssignCommand(oPC, SpeakString("The forged enchantments "
        + "on my " + GetName(oBad) + " are beyond the law. I should speak with "
        + "a FORGE WARDEN to make my gear lawful again.")));
}

// Jail the PC in the Pit Prison if they carry illegally forged gear. Synchronous
// full scan — kept for callers that need an immediate verdict; the login path
// uses ForgeBeginScan instead to stay under the instruction cap.
void ForgeJailIfIllegal(object oPC)
{
    if (!GetIsPC(oPC) || GetIsDM(oPC))
        return;
    ForgeJailForItem(oPC, ForgeFindIllegalItem(oPC));
}

// Enumerate oPC's equipment, then inventory and one level of bag contents into
// ordered item-handle locals (FORGE_SCAN_0..N-1, count FORGE_SCAN_N, cursor
// FORGE_SCAN_I reset to 0). Returns the item count. This pass does no
// valuation/blueprint work, so it is cheap even for a large inventory; the
// per-item cost is paid one item at a time by forge_scan_step. Shared by the
// login (jail) scan and the Warden (verdict) scan.
int ForgeEnqueueScan(object oPC)
{
    int n = 0;
    int nSlot;
    for (nSlot = 0; nSlot < NUM_INVENTORY_SLOTS; nSlot++)
    {
        object oItem = GetItemInSlot(nSlot, oPC);
        if (GetIsObjectValid(oItem))
            SetLocalObject(oPC, "FORGE_SCAN_" + IntToString(n++), oItem);
    }
    object oItem = GetFirstItemInInventory(oPC);
    while (GetIsObjectValid(oItem))
    {
        SetLocalObject(oPC, "FORGE_SCAN_" + IntToString(n++), oItem);
        if (GetHasInventory(oItem))
        {
            object oInBag = GetFirstItemInInventory(oItem);
            while (GetIsObjectValid(oInBag))
            {
                SetLocalObject(oPC, "FORGE_SCAN_" + IntToString(n++), oInBag);
                oInBag = GetNextItemInInventory(oItem);
            }
        }
        oItem = GetNextItemInInventory(oPC);
    }
    SetLocalInt(oPC, "FORGE_SCAN_N", n);
    SetLocalInt(oPC, "FORGE_SCAN_I", 0);
    return n;
}

// Begin a chunked contraband scan of oPC in LOGIN mode: forge_scan_step
// evaluates ONE item per delayed step — each step gets a fresh NWScript
// instruction budget, so a full inventory can't overflow — and jails the bearer
// on the first illegal item.
void ForgeBeginScan(object oPC)
{
    if (!GetIsPC(oPC) || GetIsDM(oPC))
        return;
    SetLocalInt(oPC, "FORGE_SCAN_MODE", 0); // login/jail mode
    int n = ForgeEnqueueScan(oPC);
    if (n > 0)
        DelayCommand(0.1, ExecuteScript("forge_scan_step", oPC));
}

// Begin a chunked scan of oPC in WARDEN VERDICT mode: forge_scan_step records
// the contraband verdict into FORGE_WARDEN_DIRTY / FORGE_WARDEN_READY (and
// FORGE_ILLEGAL_ITEM) WITHOUT jailing, so the Forge Warden's dialog gates
// (forge_ward_c_il / forge_ward_c_ok) can read an O(1) cached result instead of
// scanning a whole inventory inside a StartingConditional (the cause of the
// TOO MANY INSTRUCTIONS prison trap). Refreshed on each mutating Warden action.
void ForgeBeginWardenScan(object oPC)
{
    if (!GetIsPC(oPC) || GetIsDM(oPC))
        return;
    SetLocalInt(oPC, "FORGE_SCAN_MODE", 1); // warden verdict mode
    SetLocalInt(oPC, "FORGE_WARDEN_READY", FALSE); // verdict pending until scan ends
    int n = ForgeEnqueueScan(oPC);
    if (n > 0)
    {
        DelayCommand(0.1, ExecuteScript("forge_scan_step", oPC));
        return;
    }
    // Empty inventory: trivially clean, verdict known immediately.
    SetLocalInt(oPC, "FORGE_WARDEN_DIRTY", FALSE);
    DeleteLocalObject(oPC, "FORGE_ILLEGAL_ITEM");
    SetLocalInt(oPC, "FORGE_WARDEN_READY", TRUE);
}
