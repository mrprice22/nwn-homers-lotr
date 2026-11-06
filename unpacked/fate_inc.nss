// fate_inc.nss - the Shard of Fate boss bonus-roll prompt (Loot Overhaul
// Phase 7, roadmap lo-fate-token).
//
// When a boss dies, loot_ondeath picks every PC contributor in the corpse's
// area who carries a Shard of Fate and is not locked out on that boss, stores
// the offer on the PC (FATE_P_*) and runs fate_open on them.  This window asks
// "spend it?" for LOOTD_FATE_TIMEOUT seconds; fate_evt handles the buttons.
//
//   Spend  - re-checks everything (the offer is still the live one, the lockout,
//            a Shard is still carried), rolls ONE item from the LOOTD_FATE_PROFILE
//            profile at the boss's loot level straight into the pack, and only
//            then consumes the Shard and records the lockout (lootdb
//            loot_fate_lockout, one per character per boss per rolling
//            LOOTD_FATE_LOCKOUT seconds).  A roll that fails keeps the Shard.
//   Keep / timeout - nothing happens; the Shard stays in the pack.
//
// A second boss offer while one is open replaces it (the first counts as kept).
// Every offer carries a nonce; a stale tick or click sees a different nonce and
// does nothing.  NUI traps respected: resrefs <= 16 characters, explicit widths,
// long text in a `text` widget (a label clips, a tooltip never wraps).

#include "nw_inc_nui"
#include "loot_inc"

const string FATE_WIN   = "lofate";       // NuiCreate window id
const string FATE_NONCE = "FATE_NONCE";   // PC local: live offer's nonce, 0 = none
const string FATE_SEQ   = "FATE_SEQ";     // PC local: nonce counter
const string FATE_LEFT  = "FATE_LEFT";    // PC local: seconds left on the live offer
const string FATE_BOSS  = "FATE_BOSS";    // PC local: boss resref (the lockout key)
const string FATE_BNAME = "FATE_BNAME";   // PC local: boss display name
const string FATE_LVL   = "FATE_LVL";     // PC local: loot level of the bonus roll

// The pending offer loot_ondeath writes before it runs fate_open on the PC.
const string FATE_P_BOSS  = "FATE_P_BOSS";
const string FATE_P_BNAME = "FATE_P_BNAME";
const string FATE_P_LVL   = "FATE_P_LVL";

const float FATE_WIN_W = 420.0;
const float FATE_WIN_H = 300.0;
const float FATE_COL_W = 390.0;

void Fate_Close(object oPC)
{
    int nTok = NuiFindWindow(oPC, FATE_WIN);
    if (nTok) NuiDestroy(oPC, nTok);
    DeleteLocalInt(oPC, FATE_NONCE);
    DeleteLocalInt(oPC, FATE_LEFT);
}

string Fate_TimerText(int nLeft)
{
    return "The Shard falls quiet in " + IntToString(nLeft) + "s.";
}

json Fate_Window(string sBossName)
{
    json jCol = JsonArray();
    jCol = JsonArrayInsert(jCol, NuiHeight(NuiWidth(NuiLabel(JsonString(sBossName + " has fallen"),
        JsonInt(NUI_HALIGN_CENTER), JsonInt(NUI_VALIGN_MIDDLE)), FATE_COL_W), 26.0));
    string sBody = "The Shard of Fate in your pack stirs. Spend it for a personal roll on "
        + sBossName + "'s hoard? The item goes straight into your pack, and the Shard is "
        + "spent.\n\nYou can take one bonus roll per boss per day. If you keep the Shard, "
        + "you can still use it later, or at a Forge of Wonders to reforge an item.";
    jCol = JsonArrayInsert(jCol, NuiHeight(NuiWidth(NuiText(JsonString(sBody), TRUE,
        NUI_SCROLLBARS_AUTO), FATE_COL_W), 150.0));
    jCol = JsonArrayInsert(jCol, NuiHeight(NuiWidth(NuiLabel(NuiBind("fate_timer"),
        JsonInt(NUI_HALIGN_CENTER), JsonInt(NUI_VALIGN_MIDDLE)), FATE_COL_W), 24.0));
    json jRow = JsonArray();
    jRow = JsonArrayInsert(jRow, NuiWidth(NuiId(NuiButton(JsonString("Spend the Shard")),
        "fspend"), 190.0));
    jRow = JsonArrayInsert(jRow, NuiWidth(NuiId(NuiButton(JsonString("Keep it")),
        "fkeep"), 190.0));
    jCol = JsonArrayInsert(jCol, NuiHeight(NuiRow(jRow), 36.0));
    return NuiWindow(NuiCol(jCol), JsonString("Shard of Fate"),
        NuiRect(-1.0, -1.0, FATE_WIN_W, FATE_WIN_H),
        JsonBool(FALSE),   // resizable
        JsonBool(FALSE),   // collapsed
        JsonBool(FALSE),   // closable: answer with a button
        JsonBool(FALSE),   // transparent
        JsonBool(TRUE));   // border
}

// One second of the countdown; closes the window when it runs out.
void Fate_Tick(object oPC, int nNonce)
{
    if (!GetIsObjectValid(oPC) || GetLocalInt(oPC, FATE_NONCE) != nNonce) return;
    int nLeft = GetLocalInt(oPC, FATE_LEFT) - 1;
    if (nLeft <= 0)
    {
        Fate_Close(oPC);
        SendMessageToPC(oPC, "The Shard of Fate falls quiet. It stays in your pack.");
        return;
    }
    SetLocalInt(oPC, FATE_LEFT, nLeft);
    int nTok = NuiFindWindow(oPC, FATE_WIN);
    if (nTok) NuiSetBind(oPC, nTok, "fate_timer", JsonString(Fate_TimerText(nLeft)));
    DelayCommand(1.0, Fate_Tick(oPC, nNonce));
}

// Open the offer stored in FATE_P_* on oPC (fate_open runs this).
void Fate_Offer(object oPC)
{
    string sBoss = GetLocalString(oPC, FATE_P_BOSS);
    string sName = GetLocalString(oPC, FATE_P_BNAME);
    int nLvl = GetLocalInt(oPC, FATE_P_LVL);
    DeleteLocalString(oPC, FATE_P_BOSS);
    DeleteLocalString(oPC, FATE_P_BNAME);
    DeleteLocalInt(oPC, FATE_P_LVL);
    if (sBoss == "" || nLvl <= 0) return;

    if (GetLocalInt(oPC, FATE_NONCE))
        SendMessageToPC(oPC, "A new boss has fallen; the Shard of Fate turns to it instead.");
    Fate_Close(oPC);

    int nNonce = GetLocalInt(oPC, FATE_SEQ) + 1;
    SetLocalInt(oPC, FATE_SEQ, nNonce);
    SetLocalInt(oPC, FATE_NONCE, nNonce);
    SetLocalInt(oPC, FATE_LEFT, LOOTD_FATE_TIMEOUT);
    SetLocalString(oPC, FATE_BOSS, sBoss);
    SetLocalString(oPC, FATE_BNAME, sName);
    SetLocalInt(oPC, FATE_LVL, nLvl);

    int nTok = NuiCreate(oPC, Fate_Window(sName), FATE_WIN, "fate_evt");
    NuiSetBind(oPC, nTok, "fate_timer", JsonString(Fate_TimerText(LOOTD_FATE_TIMEOUT)));
    AssignCommand(oPC, DelayCommand(1.0, Fate_Tick(oPC, nNonce)));
}

// "Spend the Shard": the bonus roll.
void Fate_Spend(object oPC)
{
    if (!GetLocalInt(oPC, FATE_NONCE))
    {
        Fate_Close(oPC);
        return;
    }
    string sBoss = GetLocalString(oPC, FATE_BOSS);
    string sName = GetLocalString(oPC, FATE_BNAME);
    int nLvl = GetLocalInt(oPC, FATE_LVL);
    Fate_Close(oPC);

    int nWait = Loot_FateLockedFor(oPC, sBoss, LOOTD_FATE_LOCKOUT);
    if (nWait > 0)
    {
        SendMessageToPC(oPC, "You have already taken a bonus roll on " + sName
            + " today. You can take another in " + IntToString((nWait + 3599) / 3600)
            + " hour(s). Your Shard is kept.");
        return;
    }
    if (!GetIsObjectValid(Loot_FindShard(oPC)))
    {
        SendMessageToPC(oPC, "You no longer carry a Shard of Fate.");
        return;
    }
    int nProfile = LootD_ProfileIndex(LOOTD_FATE_PROFILE);
    int nFloor = nProfile < 0 ? 0 : LootD_ProfileFloor(nProfile);
    object oItem = Loot_Roll(nLvl, nFloor, LOOTD_FATE_PROFILE, oPC, oPC);
    if (!GetIsObjectValid(oItem))
    {
        SendMessageToPC(oPC, "The Shard flickers, but nothing comes of it. Your Shard is kept.");
        return;
    }
    Loot_SpendShard(oPC);
    Loot_FateLock(oPC, sBoss);
    string sItem = GetIdentified(oItem) ? GetName(oItem) : "an unidentified item";
    SendMessageToPC(oPC, "The Shard of Fate shatters. From " + sName + "'s hoard: "
        + sItem + ".");
    FloatingTextStringOnCreature("The Shard of Fate shatters!", oPC, FALSE);
    ApplyEffectToObject(DURATION_TYPE_INSTANT, EffectVisualEffect(VFX_IMP_MAGBLUE), oPC);
}
