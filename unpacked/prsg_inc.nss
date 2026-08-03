// prsg_inc.nss - Prestige-order hub shared helpers (roadmap: prestige-trainer-hub)
//
// The hub: Halmir the Grey, Keeper of the Old Orders (prsg_trainer, tag
// PrestigeTrainer), stands in the Well of Eru and brokers introductions to
// the twelve "old orders" - the prestige classes, framed in-fiction as
// orders/disciplines. He is script-spawned at the admin-placed waypoint
// AP_prestigehub_1 by prsg_spawn (fired from the thewelloferu OnEnter
// wrapper prsg_enter, which chains the area's previous OnEnter
// welloferuenter); everything no-ops gracefully until the waypoint exists
// and never double-spawns.
//
// The gating framework the twelve future prestige quests reuse:
//   * PRSG_MeetsLevel(oPC, nMin)  - total character level gate (hub lines).
//   * PRSG_HasClass(oPC, nClass) - 1+ level in the prestige class (quest
//     givers: pass a CLASS_TYPE_* constant).
//   * PRSG_LVL_* constants        - the per-order minimum-level table.
//   * The hub dialogue (prsg_conv) shows one line per order, each behind a
//     per-order StartingConditional (prsg_c_harper .. prsg_c_shift) that
//     checks that order's minimum level - plus dwarf race for the Dwarven
//     Defenders. Non-qualifying orders are hidden entirely.
//
// Campaign-DB idiom for the future prestige quests (mirrors the fret /
// mos2 / maz20 pattern - per-character, persistent, relog- and
// restart-safe, no farmable local state):
//   * One shared DB PRSG_DB ("prestigedb"), keyed per character via the
//     oPC parameter of Get/SetCampaignInt.
//   * Per-order stage int under "<order>_stage" (use the short order keys:
//     harper, pdk, pale, shadow, archer, rdd, assn, wm, bg, divch, dwdef,
//     shift) - 0 none / 1 accepted / ... / N done; one-offs never reset
//     their final stage. Read/write via PRSG_GetStage / PRSG_SetStage.
//   * Extra per-order keys (kill counts, trial flags) go in the same DB as
//     "<order>_<what>" so a whole order can be audited in one place.
//
// Custom token 6381 (PRSG_TOKEN_LIST) carries the "orders that would hear
// your name" summary line; set by prsg_c_sum just before the line shows.

const string PRSG_DB          = "prestigedb";      // shared campaign DB
const string PRSG_TRAINER_RES = "prsg_trainer";    // hub NPC blueprint
const string PRSG_TRAINER_TAG = "PrestigeTrainer";
const string PRSG_WP_TAG      = "AP_prestigehub_1"; // admin-placed waypoint
const int    PRSG_TOKEN_LIST  = 6381;              // qualifying-orders token

// Minimum total character level per order (the hub's gating table).
const int PRSG_LVL_HARPER  = 6;   // Harper Scout
const int PRSG_LVL_PDK     = 6;   // Knight of Westernesse (Purple Dragon Knight)
const int PRSG_LVL_PALE    = 11;  // Pale Master
const int PRSG_LVL_SHADOW  = 11;  // Shadowdancer
const int PRSG_LVL_ARCHER  = 12;  // Arcane Archer
const int PRSG_LVL_RDD     = 12;  // Red Dragon Disciple
const int PRSG_LVL_ASSN    = 13;  // Assassin
const int PRSG_LVL_WM      = 13;  // Weapon Master
const int PRSG_LVL_BG      = 14;  // Blackguard
const int PRSG_LVL_DIVCH   = 14;  // Divine Champion
const int PRSG_LVL_DWDEF   = 14;  // Dwarven Defender (Dwarf only)
const int PRSG_LVL_SHIFT   = 16;  // Shifter

// TRUE if oPC's total character level is at least nMin.
int PRSG_MeetsLevel(object oPC, int nMin)
{
    return GetHitDice(oPC) >= nMin;
}

// TRUE if oPC already has 1+ level in nClass (a CLASS_TYPE_* constant).
// The twelve prestige quests gate their giver lines on this.
int PRSG_HasClass(object oPC, int nClass)
{
    return GetLevelByClass(nClass, oPC) > 0;
}

// The Dwarven Defenders take only dwarves of proven years.
int PRSG_QualifiesDwarvenDef(object oPC)
{
    return PRSG_MeetsLevel(oPC, PRSG_LVL_DWDEF)
        && GetRacialType(oPC) == RACIAL_TYPE_DWARF;
}

// Persistent per-order quest stage for oPC (see the header idiom).
int PRSG_GetStage(object oPC, string sOrder)
{
    return GetCampaignInt(PRSG_DB, sOrder + "_stage", oPC);
}

void PRSG_SetStage(object oPC, string sOrder, int nStage)
{
    SetCampaignInt(PRSG_DB, sOrder + "_stage", nStage, oPC);
}

// Comma-list helper for PRSG_QualifyList.
string PRSG_AppendOrder(string sList, string sOrder)
{
    if (sList == "") return sOrder;
    return sList + ", " + sOrder;
}

// Human-readable list of every order that would hear oPC's name as they
// stand today (the hub's summary line, token PRSG_TOKEN_LIST).
string PRSG_QualifyList(object oPC)
{
    string s = "";
    if (PRSG_MeetsLevel(oPC, PRSG_LVL_HARPER)) s = PRSG_AppendOrder(s, "the Harper Scouts");
    if (PRSG_MeetsLevel(oPC, PRSG_LVL_PDK))    s = PRSG_AppendOrder(s, "the Knights of Westernesse");
    if (PRSG_MeetsLevel(oPC, PRSG_LVL_PALE))   s = PRSG_AppendOrder(s, "the Pale Masters");
    if (PRSG_MeetsLevel(oPC, PRSG_LVL_SHADOW)) s = PRSG_AppendOrder(s, "the Shadowdancers");
    if (PRSG_MeetsLevel(oPC, PRSG_LVL_ARCHER)) s = PRSG_AppendOrder(s, "the Arcane Archers");
    if (PRSG_MeetsLevel(oPC, PRSG_LVL_RDD))    s = PRSG_AppendOrder(s, "the Red Dragon Disciples");
    if (PRSG_MeetsLevel(oPC, PRSG_LVL_ASSN))   s = PRSG_AppendOrder(s, "the Assassins");
    if (PRSG_MeetsLevel(oPC, PRSG_LVL_WM))     s = PRSG_AppendOrder(s, "the Weapon Masters");
    if (PRSG_MeetsLevel(oPC, PRSG_LVL_BG))     s = PRSG_AppendOrder(s, "the Blackguards");
    if (PRSG_MeetsLevel(oPC, PRSG_LVL_DIVCH))  s = PRSG_AppendOrder(s, "the Divine Champions");
    if (PRSG_QualifiesDwarvenDef(oPC))         s = PRSG_AppendOrder(s, "the Dwarven Defenders");
    if (PRSG_MeetsLevel(oPC, PRSG_LVL_SHIFT))  s = PRSG_AppendOrder(s, "the Shifters");

    if (s == "")
        s = "none yet - the orders look for proven hands; the first would "
            + "hear your name at your sixth level";
    return s;
}

// Spawn Halmir at the admin-placed waypoint. Graceful no-op until the
// waypoint exists; never double-spawns (module-wide tag guard).
void PRSG_SpawnTrainer()
{
    if (GetIsObjectValid(GetObjectByTag(PRSG_TRAINER_TAG))) return;

    object oWP = GetWaypointByTag(PRSG_WP_TAG);
    if (!GetIsObjectValid(oWP)) return;

    CreateObject(OBJECT_TYPE_CREATURE, PRSG_TRAINER_RES, GetLocation(oWP));
}
