// q_silk_inc.nss - Spider Silk Harvest shared helpers (roadmap: spider-silk-harvest)
//
// T2 daily kill-collect quest, journal tag "mirkwood_silk". Thranduil, King
// of Eryn Lasgalen (Thranduil's Hall, through the Wood of Legolas off
// Mirkwood: North), pays a daily bounty for QS_NEED bolts of spider silk cut
// from the great spiders of Mirkwood. Level QS_MIN_LVL+.
//
// Active-state is persistent and item-free: accepting stamps the questcddb
// key QS_ACC (quest_cd_inc calendar-daily), so "active today" =
// accepted-today && !paid-today. That survives relogs and server restarts,
// and resets at UTC midnight together with the completion gate - no local
// variables to lose, no state item to exploit.
//
// Silk drops: the six module spider blueprints that fill every Mirkwood
// encounter (spidgiant001 Giant Spider, spiderboss001 Spider-Queen,
// spidwra001 Lava Climber, spidphase001 Death Weeper, spidswrd001 Black
// Spear Spider, spiddire001 Sword Spider) carry q_silk_d1/d2/d3 as their
// blueprint OnDeath. Bestiary-safe by construction: bst_install stores the
// blueprint OnDeath as bst_orig_death at spawn and bst_ondeath chains it
// AFTER recording the kill, and each q_silk_d* wrapper in turn chains the
// spider family's original reward script (gpondeath / 350ondeathtopart /
// sb_creaturekill), so bestiary counts, gold and XP all still fire.
// The base-game nw_spid* / nw_ettercap encounter fillers are untouched and
// simply never drop silk.
//
// v1 pays a flat bounty. The Quest Ideas dynamic-pricing variant (a
// silk_supply campaign var moving the price) is deferred to a future v2 per
// the roadmap note.

#include "quest_cd_inc"

const string QS_QUEST    = "mirkwood_silk";     // questcddb key + journal tag
const string QS_ACC      = "mirkwood_silk_acc"; // questcddb accepted-today key
const string QS_TAG      = "silkbolt";          // item tag AND blueprint resref
const int    QS_NEED     = 6;                   // bolts per turn-in
const int    QS_DROP_PCT = 75;                  // silk chance per qualifying kill
const int    QS_MIN_LVL  = 12;
const int    QS_GOLD     = 300;
const int    QS_XP       = 600;

// TRUE while the harvest is active for oPC: accepted today, not yet paid.
int QS_IsActive(object oPC)
{
    return QCD_IsDoneToday(oPC, QS_ACC) && !QCD_IsDoneToday(oPC, QS_QUEST);
}

// Total silk bolts in oPC's pack (bolts stack).
int QS_CountBolts(object oPC)
{
    int n = 0;
    object oItem = GetFirstItemInInventory(oPC);
    while (GetIsObjectValid(oItem))
    {
        if (GetTag(oItem) == QS_TAG)
            n += GetItemStackSize(oItem);
        oItem = GetNextItemInInventory(oPC);
    }
    return n;
}

// Remove nCount bolts from oPC's pack, stack-aware.
void QS_TakeBolts(object oPC, int nCount)
{
    object oItem = GetFirstItemInInventory(oPC);
    while (GetIsObjectValid(oItem) && nCount > 0)
    {
        if (GetTag(oItem) == QS_TAG)
        {
            int nStack = GetItemStackSize(oItem);
            if (nStack > nCount)
            {
                SetItemStackSize(oItem, nStack - nCount);
                nCount = 0;
            }
            else
            {
                nCount -= nStack;
                DestroyObject(oItem);
            }
        }
        oItem = GetNextItemInInventory(oPC);
    }
}

// Walk the master chain to the owning PC (summons/companions/henchmen credit
// their master, same rule as the bestiary); OBJECT_INVALID for non-PC kills.
object QS_OwningPC(object o)
{
    while (GetIsObjectValid(GetMaster(o))) o = GetMaster(o);
    if (GetIsPC(o) && !GetIsDM(o)) return o;
    return OBJECT_INVALID;
}

// Shared core of the q_silk_d* death wrappers. OBJECT_SELF = the dying
// spider. Cheap checks first; the SQL-backed QS_IsActive runs last.
// Drops are capped at QS_NEED carried bolts, so silk can never be hoarded
// past a single day's turn-in.
void QS_OnSpiderDeath()
{
    object oSpider = OBJECT_SELF;

    // Only the wild spiders of Mirkwood proper yield harvestable silk
    // (mirkwoodwest / central / centrale / centrals / east / north).
    if (GetStringLeft(GetResRef(GetArea(oSpider)), 8) != "mirkwood") return;

    object oPC = QS_OwningPC(GetLastKiller());
    if (!GetIsObjectValid(oPC)) return;
    if (QS_CountBolts(oPC) >= QS_NEED) return;   // day's need already met
    if (!QS_IsActive(oPC)) return;
    if (d100() > QS_DROP_PCT) return;

    CreateItemOnObject(QS_TAG, oPC, 1);
    FloatingTextStringOnCreature("You cut a bolt of spider silk from the carcass ("
        + IntToString(QS_CountBolts(oPC)) + " of " + IntToString(QS_NEED) + ").",
        oPC, FALSE);
}
