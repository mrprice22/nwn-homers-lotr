// q_kwn_inc.nss — Knight of Westernesse initiation "The Banner of the West"
// (roadmap: knight-westernesse-quest)
//
// The second of the twelve prestige-order quests hung on Halmir the Grey
// (the prestige hub, prsg_inc.nss). T1 one-off, journal tag "pc_pdk".
//
// Flow: Halmir's Knights-of-Westernesse branch (prsg_conv) offers the
// proving to a PC with 1+ Knight of Westernesse level (Purple Dragon
// Knight, CLASS_TYPE_PURPLE_DRAGON_KNIGHT — the roadmap/design gate; the
// hub line itself is visible from total level 6). The PC reports to Wart,
// the Gondorian Gate Captain at the Gates of Minas Tirith (an EXISTING
// placed NPC, reused — no new placement), who sets the command exercise:
// muster three of his gate-watch guardsmen to the banner-detail. Each
// existing placed Gondorian Guardsman at the Gates carries a post index
// (instance local int q_kwn_post, 1..7) and rallying him stamps the
// per-character survival/command counter "pdk_command" from the design
// card (SetCampaignInt idiom). With three spears mustered the captain
// releases the standard; the knight plants it with their own hand at the
// old banner-stone on the Pelennor Fields — a placeable script-spawned at
// the admin-placed waypoint AP_knightwest_1 — then carries word back to
// Halmir for the knighthood: the Banner of the West tower shield plus XP.
// The card's "each guardsman who survives adds +1 command" escort is
// compacted to the muster count (no henchman AI) to keep the quest T1.
//
// Quest state is per-character and persistent via the prestige hub's
// campaign-DB stage idiom (prestigedb, order key "pdk" — see
// prsg_inc.nss): 0 none / 1 accepted / 2 mustering / 3 mustered /
// 4 standard released / 5 banner planted / 6 done. One-off: stage 6
// never resets. Rallied posts persist per character (pdk_post_<n>).
//
// The banner-stone is script-spawned at the admin-placed waypoint
// AP_knightwest_1 (thepelennorfield) by q_kwn_spawn, fired from the
// Pelennor OnEnter wrapper q_kwn_ent1 (which chains the previous OnEnter,
// d_cleartrash). Graceful no-op until the waypoint exists; never
// double-spawns.

#include "prsg_inc"

const string QKWN_ORDER     = "pdk";              // prestigedb stage key
const string QKWN_QUEST     = "pc_pdk";           // journal category tag
const string QKWN_COUNT_KEY = "pdk_command";      // design-card command counter
const string QKWN_POST_KEY  = "pdk_post_";        // + post index 1..7, per PC
const string QKWN_POST_VAR  = "q_kwn_post";       // local int on guard instances
const string QKWN_STONE_RES = "q_kwn_stone";
const string QKWN_STONE_TAG = "kwn_bannerstone";
const string QKWN_WP_TAG    = "AP_knightwest_1";  // admin-placed waypoint
const string QKWN_SHIELD_RES = "q_kwn_shield";
const string QKWN_SHIELD_TAG = "BannerOfTheWest";

const int QKWN_XP     = 750;  // knighthood XP (L6-tier, matches the Harper quest)
const int QKWN_MUSTER = 3;    // guardsmen to rally (the card's three)

// Stages (see header).
const int QKWN_STAGE_NONE     = 0;
const int QKWN_STAGE_ACCEPTED = 1;
const int QKWN_STAGE_MUSTER   = 2;
const int QKWN_STAGE_MUSTERED = 3;
const int QKWN_STAGE_STANDARD = 4;
const int QKWN_STAGE_PLANTED  = 5;
const int QKWN_STAGE_DONE     = 6;

int QKWN_GetStage(object oPC)
{
    return PRSG_GetStage(oPC, QKWN_ORDER);
}

void QKWN_SetStage(object oPC, int nStage)
{
    PRSG_SetStage(oPC, QKWN_ORDER, nStage);
}

// TRUE if oPC already rides in the order's line (1+ Knight of Westernesse
// / Purple Dragon Knight level) — the design gate for the proving.
int QKWN_IsKnight(object oPC)
{
    return PRSG_HasClass(oPC, CLASS_TYPE_PURPLE_DRAGON_KNIGHT);
}

// The design card's per-character command counter.
int QKWN_GetCommand(object oPC)
{
    return GetCampaignInt(PRSG_DB, QKWN_COUNT_KEY, oPC);
}

void QKWN_SetCommand(object oPC, int n)
{
    SetCampaignInt(PRSG_DB, QKWN_COUNT_KEY, n, oPC);
}

// Per-character, persistent "this gate post already stands mustered".
int QKWN_HasPost(object oPC, int nPost)
{
    return GetCampaignInt(PRSG_DB, QKWN_POST_KEY + IntToString(nPost), oPC);
}

void QKWN_SetPost(object oPC, int nPost)
{
    SetCampaignInt(PRSG_DB, QKWN_POST_KEY + IntToString(nPost), 1, oPC);
}

// Spawn the banner-stone at the admin-placed waypoint on the Pelennor.
// Graceful no-op until the waypoint exists; never double-spawns
// (module-wide tag guard).
void QKWN_SpawnStone()
{
    if (GetIsObjectValid(GetObjectByTag(QKWN_STONE_TAG))) return;

    object oWP = GetWaypointByTag(QKWN_WP_TAG);
    if (!GetIsObjectValid(oWP)) return;

    CreateObject(OBJECT_TYPE_PLACEABLE, QKWN_STONE_RES, GetLocation(oWP));
}
