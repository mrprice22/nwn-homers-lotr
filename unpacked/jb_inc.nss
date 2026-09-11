// jb_inc.nss -- the jukebox: per-area custom background music.
//
// The jukebox item (tag jb_jukebox, handed out only by the Castle Homeless
// cheat chest) opens jb_conv, which lists the custom tracks in
// ambientmusic.2da rows 138+ and overrides the CURRENT AREA's music with the
// chosen one. It loops until the player picks another track or stops it, at
// which point the area's own music comes back.
//
// SCOPE, deliberately:
//   * AREA-WIDE, not per-player. Everyone standing in the area hears it. The
//     NWNX_Player_MusicBackground* family would give a per-listener override,
//     but "the song stays in the room I started it in" is the point.
//   * NOT PERSISTENT. State is area local variables, so a reboot restores every
//     area's default music. There is no campaign DB behind this.
//
// THE TRACK NUMBERING -- two functions, TWO DIFFERENT CONVENTIONS:
//
//   MusicBackgroundChangeDay(oArea, n)   plays ambientmusic.2da ROW n  (raw row)
//   MusicBackgroundGetDayTrack(oArea)    returns that row MINUS ONE
//
// So a track is played with its raw row, but a snapshot taken with Get() must be
// +1'd before it can be handed back to Change(). Both halves are needed and they
// are NOT the same adjustment -- getting this wrong in either direction is silent.
//
// dmfi_execute.nss:549-553 does the +1 on its restore path, and reading that as
// "Change() is 1-based" is exactly the mistake that shipped here first: every
// pick played the NEXT song in the list. Verified in game 2026-09-11 -- passing
// 139 played row 139, not row 138.
//
// Custom token range: 7010-7018 (7010-7017 slot labels, 7018 status line).
// Adjacent claims: mw_quiz_inc.nss 7000-7005, merit 5001-5078, tele 5089-5096.
// SetCustomToken is MODULE-GLOBAL, so the tokens are (re)built immediately
// before the node that reads them -- never earlier.

#include "jb_tracks"

// ---------------------------------------------------------------- area state
const string JB_ON       = "JB_ON";        // TRUE while this area is overridden
const string JB_TRACK    = "JB_TRACK";     // index into the jb_tracks table
const string JB_ORIG_DAY = "JB_ORIG_DAY";  // all three stored ALREADY +1'd
const string JB_ORIG_NGT = "JB_ORIG_NGT";
const string JB_ORIG_BAT = "JB_ORIG_BAT";

// ------------------------------------------------------------- menu plumbing
const int    JB_TOKEN_BASE = 7010;         // 7010..7017 slots, 7018 status
const int    JB_SLOTS      = 8;            // track options per page
const string JB_PAGE       = "jb_page";    // on the PC, not the area

int  JB_IsOn(object oArea);
int  JB_GetCurrent(object oArea);
void JB_Start(object oArea, int nIndex);
void JB_Stop(object oArea);
void JB_BuildMenu(object oPC);
int  JB_SlotIndex(object oPC, int nSlot);
void JB_TurnPage(object oPC, int nDelta);


int JB_IsOn(object oArea)
{
    return GetLocalInt(oArea, JB_ON);
}

int JB_GetCurrent(object oArea)
{
    return GetLocalInt(oArea, JB_TRACK);
}

void JB_Start(object oArea, int nIndex)
{
    if (!GetIsObjectValid(oArea)) return;

    int nRow = JB_GetTrackRow(nIndex);
    if (nRow < 0) return;              // index outside the generated table

    // Snapshot the area's own music the FIRST time only. Switching tracks while
    // the jukebox is already running must NOT re-snapshot -- otherwise "stop"
    // would restore the previous jukebox pick instead of the area's default.
    // The +1 here is the Get()-side adjustment described at the top of this file,
    // and it is correct: these values go back to Change() untouched in JB_Stop().
    if (!GetLocalInt(oArea, JB_ON))
    {
        SetLocalInt(oArea, JB_ORIG_DAY, MusicBackgroundGetDayTrack(oArea)    + 1);
        SetLocalInt(oArea, JB_ORIG_NGT, MusicBackgroundGetNightTrack(oArea)  + 1);
        SetLocalInt(oArea, JB_ORIG_BAT, MusicBackgroundGetBattleTrack(oArea) + 1);
        SetLocalInt(oArea, JB_ON, TRUE);
    }
    SetLocalInt(oArea, JB_TRACK, nIndex);

    // Raw row -- Change() is NOT 1-based. See the header note.
    MusicBackgroundStop(oArea);
    MusicBackgroundChangeDay(oArea, nRow);
    MusicBackgroundChangeNight(oArea, nRow);

    // Silence battle music for the duration, so a fight does not cut the track
    // off. Row 0 of ambientmusic.2da is the blank reserved row (Resource ****),
    // so this is silence either way -- as "no track", or as a track with no
    // audio behind it.
    MusicBattleStop(oArea);
    MusicBattleChange(oArea, 0);

    MusicBackgroundPlay(oArea);
}

void JB_Stop(object oArea)
{
    if (!GetIsObjectValid(oArea)) return;
    if (!GetLocalInt(oArea, JB_ON)) return;

    MusicBackgroundStop(oArea);
    MusicBackgroundChangeDay(oArea,   GetLocalInt(oArea, JB_ORIG_DAY));
    MusicBackgroundChangeNight(oArea, GetLocalInt(oArea, JB_ORIG_NGT));
    MusicBattleChange(oArea,          GetLocalInt(oArea, JB_ORIG_BAT));

    DeleteLocalInt(oArea, JB_ON);
    DeleteLocalInt(oArea, JB_TRACK);
    DeleteLocalInt(oArea, JB_ORIG_DAY);
    DeleteLocalInt(oArea, JB_ORIG_NGT);
    DeleteLocalInt(oArea, JB_ORIG_BAT);

    MusicBackgroundPlay(oArea);
}

// Populate the tokens and per-PC slot flags for the page the PC is on.
// Idempotent -- it runs from the entry node's StartingConditional, which the
// engine may evaluate more than once before the node renders.
void JB_BuildMenu(object oPC)
{
    object oArea = GetArea(oPC);
    int nTotal = JB_GetTrackCount();
    int nPages = (nTotal + JB_SLOTS - 1) / JB_SLOTS;
    if (nPages < 1) nPages = 1;

    int nPage = GetLocalInt(oPC, JB_PAGE);
    if (nPage < 0 || nPage >= nPages)
    {
        nPage = 0;
        SetLocalInt(oPC, JB_PAGE, 0);
    }

    int nOff = nPage * JB_SLOTS;
    int nOn  = GetLocalInt(oArea, JB_ON);
    int nNow = GetLocalInt(oArea, JB_TRACK);

    int i;
    for (i = 0; i < JB_SLOTS; i++)
    {
        int nIndex = nOff + i;
        string sVar = "jb_slot_" + IntToString(i);
        if (nIndex < nTotal)
        {
            // Stored +1 so that 0 unambiguously means "this slot is empty".
            SetLocalInt(oPC, sVar, nIndex + 1);
            string sLabel = JB_GetTrackName(nIndex);
            if (nOn && nNow == nIndex) sLabel += "   [playing]";
            SetCustomToken(JB_TOKEN_BASE + i, sLabel);
        }
        else
        {
            DeleteLocalInt(oPC, sVar);
            SetCustomToken(JB_TOKEN_BASE + i, "");
        }
    }

    SetLocalInt(oPC, "jb_hasprev", nPage > 0);
    SetLocalInt(oPC, "jb_hasnext", nPage < nPages - 1);
    SetLocalInt(oPC, "jb_ison", nOn);

    string sStatus;
    if (nOn)
        sStatus = "Now playing: " + JB_GetTrackName(nNow);
    else
        sStatus = "Idle. This area is playing its own music.";
    if (nPages > 1)
        sStatus += "  (page " + IntToString(nPage + 1) + " of " + IntToString(nPages) + ")";
    SetCustomToken(JB_TOKEN_BASE + JB_SLOTS, sStatus);
}

// The absolute track index behind a visible slot, or -1 if the slot is empty.
int JB_SlotIndex(object oPC, int nSlot)
{
    return GetLocalInt(oPC, "jb_slot_" + IntToString(nSlot)) - 1;
}

void JB_TurnPage(object oPC, int nDelta)
{
    int nPage = GetLocalInt(oPC, JB_PAGE) + nDelta;
    if (nPage < 0) nPage = 0;
    SetLocalInt(oPC, JB_PAGE, nPage);
}
