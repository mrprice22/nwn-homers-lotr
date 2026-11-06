// lootlab_inc.nss - Loot Lab, the admin test surface for Season 3 rolled loot.
//
// Roadmap: loot-overhaul epic, lo-loot-core (Phase 2).
//
// TRIGGER: rest menu / emote wand -> Admin Options -> "[Admin] Loot Lab"
// (emotewand.dlg Entry 19).  The parent Admin Options link is gated by the
// _cdkey admindb check; every action script re-checks Admin_CanAdmin as
// defence in depth.  NOT a DM console command - the admin has no DM client
// (CLAUDE.md, "The admin has no DM console").
//
// State lives on the admin's PC as locals: LOOTLAB_LVL (loot level 1..60,
// defaults to the PC's hit dice) and LOOTLAB_FLOOR (rarity floor index).
// Custom tokens: 6450 = loot level, 6451 = rarity floor label.
// Phase 5 added "grant a socket gem" (lootlab_gem1 / lootlab_gemall, which
// include gem_inc themselves); Phase 7 added "grant a Shard of Fate" and "clear
// my Shard of Fate lockouts" (lootlab_fate / lootlab_fateclr).

#include "admin_db"
#include "loot_inc"

const int LOOTLAB_TOK_LEVEL = 6450;
const int LOOTLAB_TOK_FLOOR = 6451;
const int LOOTLAB_TOK_FORCE = 6452;   // "ON" / "OFF": force creature drops on my kills

// The admin running the menu: the dialog speaker, or OBJECT_SELF so that
// ExecuteScript("lootlab_...", oPC) works too.
object LL_Speaker()
{
    object oPC = GetPCSpeaker();
    if (!GetIsObjectValid(oPC)) oPC = OBJECT_SELF;
    return oPC;
}

int LL_Authorised(object oPC)
{
    if (GetIsPC(oPC) && !GetIsDM(oPC) && !Admin_CanAdmin(oPC))
    {
        SendMessageToPC(oPC, "You are not authorised to use that.");
        return FALSE;
    }
    return TRUE;
}

int LL_Level(object oPC)
{
    int n = GetLocalInt(oPC, "LOOTLAB_LVL");
    if (n <= 0) n = GetHitDice(oPC);
    return Loot_Clamp(n, 1, LOOTD_MAX_LEVEL);
}

int LL_Floor(object oPC)
{
    return Loot_Clamp(GetLocalInt(oPC, "LOOTLAB_FLOOR"), 0, LOOTD_RARITY_COUNT - 1);
}

void LL_SetTokens(object oPC)
{
    SetCustomToken(LOOTLAB_TOK_LEVEL, IntToString(LL_Level(oPC)));
    SetCustomToken(LOOTLAB_TOK_FLOOR, Loot_RarityLabel(LL_Floor(oPC)));
    SetCustomToken(LOOTLAB_TOK_FORCE, GetLocalInt(oPC, "LOOT_FORCE_DROPS") ? "ON" : "OFF");
}

void LL_AdjustLevel(int nDelta)
{
    object oPC = LL_Speaker();
    if (!LL_Authorised(oPC)) return;
    SetLocalInt(oPC, "LOOTLAB_LVL", Loot_Clamp(LL_Level(oPC) + nDelta, 1, LOOTD_MAX_LEVEL));
    LL_SetTokens(oPC);
}

// Roll nCount items into the admin's pack and report each one.
void LL_Roll(int nCount)
{
    object oPC = LL_Speaker();
    if (!LL_Authorised(oPC)) return;
    int nLvl = LL_Level(oPC);
    int nFloor = LL_Floor(oPC);
    int i;
    for (i = 0; i < nCount; i++)
    {
        object oItem = Loot_Roll(nLvl, nFloor, "lab", oPC, oPC);
        if (GetIsObjectValid(oItem))
            SendMessageToPC(oPC, "Loot Lab: " + Loot_Describe(oItem));
        else
            SendMessageToPC(oPC, "Loot Lab: the roll failed - see the server log (LOOT:).");
    }
}
