// warmeter_inc.nss - The Isengard war-machine meter (Fangorn tug-of-war)
//
// Roadmap: lumber-ent-tugofwar. This is the METER LAYER ONLY - the shared,
// server-wide contest value that the future Lumber Runners (evil) and Ent-Watch
// (good) Fangorn dailies will push, and that the Helm's Deep event will read.
// It deliberately contains NO quest content: no giver NPCs, no objectives, and
// no per-band Helm's Deep effects. Those are queued design questions.
//
// It is a thin, opinionated wrapper over worldstate_inc.nss - do NOT build a
// second world-state layer. Everything here ends up in the worldstatedb
// campaign DB under the single key WM_KEY.
//
// ------------------------------------------------------------
// APPROVED MECHANIC (admin, roadmap design question, 2026-08):
//
//   back-end range  0 .. 200   (clamped)
//   neutral / start 100
//   step            +/- 5 per qualifying action
//   decay           1 point per real hour, toward 100
//   bands           <=25 / 26-74 / 75-125 / 126-174 / >=175
//
//   "any in-game mentions of this progress should be normalized to %, as 0 to
//    100% for one side or the other ... 100% for one faction means either
//    back end value of 0 or 200"
//
// ARITHMETIC CHECK (the display rate the admin asked for falls out exactly):
//   neutral 100 -> either extreme is exactly 100 back-end points, and each side
//   spans exactly 100% of its own half. So 1 back-end point == 1 display point,
//   and the decay of 1 back-end point per real hour IS a display decay of
//   1% per hour. No scaling factor is needed anywhere.
//     back-end   0 = 100% to Fangorn
//     back-end 100 =   0% - neutral
//     back-end 200 = 100% to Isengard
//   Higher = Isengard winning (the key is named for Isengard's war machine).
//
// DISPLAY RULE: never show a player the raw 0..200 number. Use
// WM_GetPercent() / WM_GetLeader() / WM_GetStatusText(). The one deliberate
// exception is the admin readout (wm_report.nss), which is gated on
// Admin_CanAdmin() and prints the raw value on purpose for tuning/UAT.
//
// WIRING: WM_Init() is called once from onmoduleload.nss (idempotent - it
// registers the decay rule and seeds the neutral value only on a virgin DB).
// The decay itself is applied by worldstate_inc's WS_Tick(), already running
// off the module heartbeat (bleeding.nss) - nothing else to hook up.

#include "worldstate_inc"

// ------------------------------------------------------------
// Tuning constants - the single place any of these numbers live.

// World-state key. Shared with every future consumer (dailies, Helm's Deep).
const string WM_KEY = "isengard_warmachine";

const int WM_MIN     = 0;      // 100% to Fangorn
const int WM_NEUTRAL = 100;    // start / decay target
const int WM_MAX     = 200;    // 100% to Isengard

// One qualifying action moves the meter this far.
const int WM_STEP = 5;

// Decay: WM_DECAY_RATE points toward WM_NEUTRAL every WM_DECAY_PERIOD real
// seconds. 1 point / 3600s == 1% of a side's progress per real hour.
const int WM_DECAY_RATE   = 1;
const int WM_DECAY_PERIOD = 3600;

// Side names - used in every player-visible string, so they read the same way
// everywhere. "Fangorn" covers the Ents / Ent-Watch side.
const string WM_SIDE_ISENGARD = "Isengard";
const string WM_SIDE_FANGORN  = "Fangorn";

// ------------------------------------------------------------
// Difficulty bands (the five the admin approved), ascending with the meter:
// band 0 is Fangorn utterly ascendant, band 4 is Isengard utterly ascendant.

const int WM_BAND_FANGORN_ASCENDANT  = 0;   // meter <=  25
const int WM_BAND_FANGORN_RISING     = 1;   // meter  26 -  74
const int WM_BAND_BALANCED           = 2;   // meter  75 - 125
const int WM_BAND_ISENGARD_RISING    = 3;   // meter 126 - 174
const int WM_BAND_ISENGARD_ASCENDANT = 4;   // meter >= 175

// ------------------------------------------------------------
// Prototypes

void   WM_Init();
int    WM_Get();
int    WM_Adjust(int nSteps);
int    WM_PushIsengard(int nActions = 1);
int    WM_PushFangorn(int nActions = 1);
int    WM_GetBandOf(int nValue);
int    WM_GetBand();
string WM_GetBandName(int nBand);
int    WM_GetPercentOf(int nValue);
int    WM_GetPercent();
string WM_GetLeaderOf(int nValue);
string WM_GetLeader();
string WM_GetStatusText();
void   WM_Reset();

// ------------------------------------------------------------
// Init - idempotent. Safe to call on every module load.

void WM_Init()
{
    // Seed the neutral value only when the key has never been written. -1 is
    // outside the clamped range, so it can only mean "no row yet".
    if (WS_GetInt(WM_KEY, -1) == -1)
        WS_SetInt(WM_KEY, WM_NEUTRAL);

    // Re-registering the same decay rule is an UPSERT; it only re-phases the
    // rule's last_tick, which costs at most one hour of drift per reboot.
    WS_RegisterDecay(WM_KEY, WM_DECAY_RATE, WM_NEUTRAL, WM_DECAY_PERIOD);
}

// ------------------------------------------------------------
// Read / write

// Raw back-end value, 0..200. Callers that show anything to a player must go
// through WM_GetPercent / WM_GetLeader / WM_GetStatusText instead.
int WM_Get()
{
    return WS_GetInt(WM_KEY, WM_NEUTRAL);
}

// Move the meter by nSteps qualifying actions (positive = toward Isengard,
// negative = toward Fangorn). Clamped. Returns the new raw value. This is the
// ONLY place WM_STEP is applied, so the step size lives in exactly one spot.
int WM_Adjust(int nSteps)
{
    if (nSteps == 0) return WM_Get();
    return WS_AdjustInt(WM_KEY, nSteps * WM_STEP, WM_MIN, WM_MAX);
}

// One (or nActions) qualifying action for the Lumber Runners / Isengard side.
int WM_PushIsengard(int nActions = 1)
{
    if (nActions < 0) nActions = 0;
    return WM_Adjust(nActions);
}

// One (or nActions) qualifying action for the Ent-Watch / Fangorn side.
int WM_PushFangorn(int nActions = 1)
{
    if (nActions < 0) nActions = 0;
    return WM_Adjust(-nActions);
}

// ------------------------------------------------------------
// Bands

int WM_GetBandOf(int nValue)
{
    if (nValue <=  25) return WM_BAND_FANGORN_ASCENDANT;
    if (nValue <=  74) return WM_BAND_FANGORN_RISING;
    if (nValue <= 125) return WM_BAND_BALANCED;
    if (nValue <= 174) return WM_BAND_ISENGARD_RISING;
    return WM_BAND_ISENGARD_ASCENDANT;
}

int WM_GetBand()
{
    return WM_GetBandOf(WM_Get());
}

// Player-safe label for a band (carries no raw numbers).
string WM_GetBandName(int nBand)
{
    switch (nBand)
    {
        case WM_BAND_FANGORN_ASCENDANT:  return "Fangorn Ascendant";
        case WM_BAND_FANGORN_RISING:     return "Fangorn Rising";
        case WM_BAND_BALANCED:           return "Balanced";
        case WM_BAND_ISENGARD_RISING:    return "Isengard Rising";
        case WM_BAND_ISENGARD_ASCENDANT: return "Isengard Ascendant";
    }
    return "Balanced";
}

// ------------------------------------------------------------
// Normalization for display - 0..100% toward whichever side is ahead.

// How far the leading side has pushed, as a percentage of its own half.
// 0 at neutral, 100 at either extreme.
int WM_GetPercentOf(int nValue)
{
    int nDelta = nValue - WM_NEUTRAL;
    if (nDelta < 0) nDelta = -nDelta;
    if (nDelta > 100) nDelta = 100;
    return nDelta;
}

int WM_GetPercent()
{
    return WM_GetPercentOf(WM_Get());
}

// Name of the side currently ahead, or "" when the meter sits exactly neutral.
string WM_GetLeaderOf(int nValue)
{
    if (nValue > WM_NEUTRAL) return WM_SIDE_ISENGARD;
    if (nValue < WM_NEUTRAL) return WM_SIDE_FANGORN;
    return "";
}

string WM_GetLeader()
{
    return WM_GetLeaderOf(WM_Get());
}

// The canonical player-facing sentence. Percent only - never the raw value.
string WM_GetStatusText()
{
    int    nVal    = WM_Get();
    string sLeader = WM_GetLeaderOf(nVal);
    if (sLeader == "")
        return "The struggle for Fangorn stands even -- neither side holds ground.";
    return "The struggle for Fangorn stands at " + IntToString(WM_GetPercentOf(nVal)) +
           "% to " + sLeader + ".";
}

// ------------------------------------------------------------
// Admin / UAT

// Put the meter back to dead neutral (leaves the decay rule registered).
void WM_Reset()
{
    WS_SetInt(WM_KEY, WM_NEUTRAL);
}
