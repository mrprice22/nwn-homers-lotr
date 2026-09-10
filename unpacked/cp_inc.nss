// cp_inc -- Crash Party: shared logic for the event's items, DM console and signs.
//
// Read this header before touching any cp_* script; several of the rules below
// are the opposite of what you would guess.
//
// ## The two switches
//
//   CP_MODE   is the party on?   Gates the DISPENSER ONLY.
//   CP_WAVE   0-3, the DM's escalating release. GLOBAL, never per-PC.
//
// Both are LocalInts on the module and are deliberately NOT persistent: a reboot
// turns the party off, which is the right failsafe (dbg_combat.nss is the
// precedent). Per-PC grant flags are the opposite -- they live in the campaign DB
// (cp_db.nss) so a relog cannot re-trigger a grant.
//
// ## Waves are global, and late joiners are caught up
//
// Raising CP_WAVE unlocks that wave for EVERYONE at once. A player who logs in
// during wave 3 receives waves 0, 1, 2 and 3 in one go -- there is no per-PC
// progress gate, no grind, and nobody is ever behind. That is the whole point of
// CP_GrantUpToWave().
//
// ## Charges: generous, invisible, and the player's to keep
//
// Items expire on a USE COUNT ONLY. There is no real-time cap and NOTHING expires
// when the party ends. Leftover charges survive logout and reboot (the counter is
// a LocalInt on the item, which serialises into the .bic) and the item keeps
// working forever. So:
//
//   * item scripts must NOT check CP_IsOn() -- only the dispenser does;
//   * NEVER tell the player the count. No "N uses remaining", nothing in the
//     description, and never SetItemCharges (client-visible, and it resets when a
//     blueprint respawns -- see the ammorep_inc.nss rationale). The break message
//     is the only signal a player ever gets;
//   * counts are set high enough that nobody rations during the event.
//
// ## Cleanup never touches player inventories
//
// The DM's CLEAR ALL and the module-load sweep destroy objects tagged CP_LOAD_TAG
// -- DM-spawned creatures and placeables -- and nothing else. There is no code
// path anywhere that removes a player-held cp_* item. The only thing that ever
// does is that item spending its last charge, in the player's own hands.

#include "cp_db"
#include "color"

const string CP_MODE_VAR = "CP_MODE";
const string CP_WAVE_VAR = "CP_WAVE";
const string CP_USES_VAR = "CP_USES";
const string CP_INIT_VAR = "CP_USES_INIT";

// Every DM-spawned load object carries this tag, and cleanup keys on it alone.
const string CP_LOAD_TAG = "cp_load";

const int CP_ITEM_COUNT = 6;
const int CP_WAVE_MAX   = 3;

int    CP_IsOn();
int    CP_Wave();
void   CP_Broadcast(string sMsg, string sColor = "");
void   CP_SetMode(int bOn);
void   CP_SetWave(int nWave);
int    CP_Spam(object oPC, string sKey, float fSeconds);
int    CP_ConsumeUse(object oItem, int nMaxUses, string sBreakMsg);
string CP_ItemResRef(int nIndex);
int    CP_ItemWave(int nIndex);
int    CP_ItemCharges(int nIndex);
int    CP_GrantUpToWave(object oPC);
object CP_FindItem(object oPC, string sResRef);
object CP_Target(object oPC);
int    CP_OnlineCount();
string CP_BelchSound(int nTipsy);

// ------------------------------------------------------------ state

int CP_IsOn()  { return GetLocalInt(GetModule(), CP_MODE_VAR); }
int CP_Wave()  { return GetLocalInt(GetModule(), CP_WAVE_VAR); }

// The module has no SendMessageToAllPCs wrapper; this is it. Same loop shape as
// bst_ondeath.nss's server-first announcement.
void CP_Broadcast(string sMsg, string sColor = "")
{
    string sOut = (sColor == "") ? sMsg : sColor + sMsg + COLOR_END;
    object oP = GetFirstPC();
    while (GetIsObjectValid(oP))
    {
        SendMessageToPC(oP, sOut);
        oP = GetNextPC();
    }
}

void CP_SetMode(int bOn)
{
    SetLocalInt(GetModule(), CP_MODE_VAR, bOn);
    if (bOn)
    {
        CP_Broadcast("*** THE CRASH PARTY HAS BEGUN! Head to the Well of Eru. ***",
                     COLOR_YELLOW);
    }
    else
    {
        SetLocalInt(GetModule(), CP_WAVE_VAR, 0);
        // Deliberately reassuring: people will ask.
        CP_Broadcast("*** The Crash Party is over. Thank you for coming! "
                     + "Anything you were given is yours to keep. ***", COLOR_YELLOW);
    }
}

void CP_SetWave(int nWave)
{
    if (nWave < 0) nWave = 0;
    if (nWave > CP_WAVE_MAX) nWave = CP_WAVE_MAX;
    SetLocalInt(GetModule(), CP_WAVE_VAR, nWave);
    CP_Broadcast("*** CRASH PARTY -- WAVE " + IntToString(nWave)
                 + " RELEASED! New party favours at the Well of Eru. ***",
                 COLOR_YELLOW);
}

// ------------------------------------------------------------ guards

// TRUE means "still cooling down, bail". The convention every emote script in the
// module already uses (SetLocalInt + DelayCommand to clear).
int CP_Spam(object oPC, string sKey, float fSeconds)
{
    if (GetLocalInt(oPC, sKey)) return TRUE;
    SetLocalInt(oPC, sKey, TRUE);
    DelayCommand(fSeconds, DeleteLocalInt(oPC, sKey));
    return FALSE;
}

// The entire expiry model. Returns TRUE if this use is allowed to happen --
// including the very last one, which fires AND breaks the item.
//
// The plot flag is cleared before DestroyObject because plot items resist destroy
// (kalrist_gems.nss:72 is the precedent, and every cp_* item is plot).
int CP_ConsumeUse(object oItem, int nMaxUses, string sBreakMsg)
{
    if (!GetIsObjectValid(oItem)) return FALSE;

    int nLeft;
    if (!GetLocalInt(oItem, CP_INIT_VAR))
    {
        nLeft = nMaxUses;                       // first ever use of this copy
        SetLocalInt(oItem, CP_INIT_VAR, TRUE);
    }
    else
    {
        nLeft = GetLocalInt(oItem, CP_USES_VAR);
        if (nLeft <= 0) return FALSE;           // defensive; normally destroyed
    }

    nLeft--;

    if (nLeft <= 0)
    {
        object oOwner = GetItemPossessor(oItem);
        if (sBreakMsg != "" && GetIsObjectValid(oOwner) && GetIsPC(oOwner))
            SendMessageToPC(oOwner, sBreakMsg);
        SetPlotFlag(oItem, FALSE);
        DestroyObject(oItem);
        return TRUE;                            // the last charge still works
    }

    SetLocalInt(oItem, CP_USES_VAR, nLeft);
    return TRUE;
}

// ------------------------------------------------------------ the item table
//
// One place that the dispenser, the DM console and the items themselves all agree
// on. NWScript has no arrays, hence the switch.

string CP_ItemResRef(int nIndex)
{
    switch (nIndex)
    {
        case 0: return "cp_tankard";
        case 1: return "cp_popper";
        case 2: return "cp_strings";
        case 3: return "cp_mask";
        case 4: return "cp_coin";
        case 5: return "cp_fireworks";
    }
    return "";
}

int CP_ItemWave(int nIndex)
{
    switch (nIndex)
    {
        case 0: return 0;   // Magical Tankard
        case 1: return 0;   // Party Popper
        case 2: return 1;   // Puppet Strings of Bard's Folly
        case 3: return 1;   // Mask of a Thousand Faces
        case 4: return 2;   // Wishing Coin
        case 5: return 3;   // Fireworks Finale Staff
    }
    return 99;
}

int CP_ItemCharges(int nIndex)
{
    switch (nIndex)
    {
        case 0: return 500;
        case 1: return 400;
        case 2: return 400;
        case 3: return 300;
        case 4: return 240;
        case 5: return 120;
    }
    return 0;
}

// ------------------------------------------------------------ the dispenser

// Hand over everything released so far that this character has not already had.
// Returns how many were granted, so the caller can stay quiet when it is zero.
//
// This is the late-joiner guarantee: arrive at wave 3 and you get waves 0-3 at
// once. It is also the mid-party top-up: called again after a wave drops, it
// hands over only what is new.
int CP_GrantUpToWave(object oPC)
{
    if (!CP_IsOn()) return 0;
    if (!GetIsPC(oPC)) return 0;

    int nWave = CP_Wave();
    int nGranted = 0;
    int i;

    for (i = 0; i < CP_ITEM_COUNT; i++)
    {
        if (CP_ItemWave(i) > nWave) continue;

        string sRes = CP_ItemResRef(i);
        if (CP_HasGrant(oPC, sRes)) continue;

        // One at a time. CreateItemOnObject's stack argument is clamped to the
        // base item's Stacking value, so a count is meaningless here anyway
        // (CLAUDE-gotchas.md).
        object oItem = CreateItemOnObject(sRes, oPC);
        if (!GetIsObjectValid(oItem)) continue;

        SetIdentified(oItem, TRUE);
        CP_MarkGrant(oPC, sRes);
        nGranted++;
    }

    if (nGranted > 0)
    {
        SendMessageToPC(oPC, COLOR_YELLOW
            + "Party favours have been tucked into your pack. They are yours to keep."
            + COLOR_END);
    }
    return nGranted;
}

// Resolve the activated item. dmfi_activate stashes it on the activator right
// before dispatching us, because the OnActivateItem getters are not something an
// ExecuteScript-dispatched script should lean on (the module's existing item
// scripts, ammorep_open.nss and dye_nui_open.nss, re-find their item too).
//
// The possession lookup is the fallback, and is safe here because every cp_*
// item's Tag is identical to its ResRef by design and GetItemPossessedBy matches
// on TAG. These are non-stacking base-29 items, so the "reports a stack of six as
// one" caveat in CLAUDE-gotchas.md does not bite.
object CP_FindItem(object oPC, string sResRef)
{
    object oItem = GetLocalObject(oPC, "cp_item");
    if (GetIsObjectValid(oItem) && GetResRef(oItem) == sResRef) return oItem;
    return GetItemPossessedBy(oPC, sResRef);
}

// Whatever the player pointed the item at, or OBJECT_INVALID for a self-use.
object CP_Target(object oPC)
{
    return GetLocalObject(oPC, "cp_target");
}

// ------------------------------------------------------------ tankard shared

// Real belches exist in the base game data (as_pl_belchingm1/2); the tavern
// drunk set is the flavour once somebody is properly far gone.
string CP_BelchSound(int nTipsy)
{
    if (nTipsy >= 6 && Random(2) == 0)
        return "as_pl_tavdrunkm" + IntToString(Random(4) + 1);
    return "as_pl_belchingm" + IntToString(Random(2) + 1);
}

// ------------------------------------------------------------ misc

int CP_OnlineCount()
{
    int n = 0;
    object oP = GetFirstPC();
    while (GetIsObjectValid(oP))
    {
        if (!GetIsDM(oP)) n++;
        oP = GetNextPC();
    }
    return n;
}
