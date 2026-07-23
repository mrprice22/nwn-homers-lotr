// setti_loot_inc.nss -- shared logic for the three Setti coffers in
// Numenor: Noirinan (falseheaven): SettiBeltChest / SettiRingChest /
// SettiShieldChest.
//
// These chests are a near-end-game gear source. Each mints one random
// end-game belt / ring / shield on open (see my_createbelt/ring/shield), gated
// so a single opener cannot farm them: a chest gives loot at most once per real
// hour, and while it is spent-and-empty it is left UNLOCKED so nobody wastes a
// lockpick or a consumed key on an empty box. When the hour has passed the
// chest is re-LOCKED (re-armed) again -- but nothing runs during the idle hour,
// so the re-arm is driven from the area OnEnter (q_frk_enter -> SettiRearm),
// which fires exactly as a returning player walks in. See the numenor-chests
// roadmap item.
//
// "Now" is wall-clock unix epoch from SQLite (same idiom as horn_summon /
// boost_db). The per-chest timestamp lives in the local int "CS_Opened" on the
// chest; it resets on reboot, which simply re-arms the chest -- harmless.
//
// All calls are base NWScript builtins.

const int    SETTI_COOLDOWN = 3600;         // seconds between draws (1 real hour)
const string SETTI_LAST     = "CS_Opened";  // local int: epoch of last draw

const string SETTI_TAG_BELT   = "SettiBeltChest";
const string SETTI_TAG_RING   = "SettiRingChest";
const string SETTI_TAG_SHIELD = "SettiShieldChest";

// Current wall-clock epoch seconds (server real time).
int SettiNow()
{
    sqlquery q = SqlPrepareQueryObject(GetModule(), "SELECT strftime('%s','now');");
    return SqlStep(q) ? SqlGetInt(q, 0) : 0;
}

// TRUE if oChest may mint loot right now (never opened, or its cooldown has
// elapsed). Callers record the draw with SettiMarkDrawn().
int SettiReady(object oChest)
{
    int nLast = GetLocalInt(oChest, SETTI_LAST);
    if (nLast == 0) return TRUE;                    // never opened
    return (SettiNow() >= nLast + SETTI_COOLDOWN);  // cooled down
}

// Record that oChest just minted loot (starts its cooldown).
void SettiMarkDrawn(object oChest)
{
    SetLocalInt(oChest, SETTI_LAST, SettiNow());
}

// Re-arm one chest by tag: lock it again once it is ready (never opened, or
// cooled down) and empty. While it is spent-and-cooling, or still holds loot a
// player has not taken, leave it as-is. Called on area entry.
void SettiRearmOne(string sTag)
{
    object oChest = GetObjectByTag(sTag);
    if (!GetIsObjectValid(oChest)) return;

    // Loot still sitting inside -- don't touch it (player may still be looting).
    if (GetIsObjectValid(GetFirstItemInInventory(oChest))) return;

    // Empty and still cooling down -> leave unlocked so no key/pick is wasted.
    if (!SettiReady(oChest)) return;

    // Empty and ready -> re-arm the lock for the next draw.
    SetLocked(oChest, TRUE);
}

// Re-arm all three Setti coffers. Safe to call from any area's OnEnter (it only
// touches the three tagged chests); wired from q_frk_enter (Noirinan only).
void SettiRearm()
{
    SettiRearmOne(SETTI_TAG_BELT);
    SettiRearmOne(SETTI_TAG_RING);
    SettiRearmOne(SETTI_TAG_SHIELD);
}
