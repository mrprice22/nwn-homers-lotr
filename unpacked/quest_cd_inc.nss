// quest_cd_inc.nss - Quest cooldown helpers (daily/weekly gating)
//
// Campaign DB: "questcddb" (SQLite, file database/questcddb.sqlite3 on the
// server - never part of the .mod). One row per (character, quest): when the
// quest was last completed, in real-world unix-epoch seconds.
//
// Schema:  quest_cd(uuid, quest, cdkey, char_name, stamped_at, times_done,
//                   PRIMARY KEY (uuid, quest))
//          Character identity is QCD_Ident: GetObjectUUID (persists in the
//          .bic, same key the bestiary uses), falling back to CD key + name
//          for an unsaved character whose UUID is still empty. cdkey/char_name
//          are stored for out-of-band inspection with sqlite3 only - lookups
//          never use those columns.
//
// This is the shared gate for every Daily/Weekly repeatable quest. Time is
// real-world wall-clock (SQLite strftime('%s','now')), NOT the game calendar,
// so cooldowns survive reboots, relogs and module time changes.
//
// Two gating styles:
//   * Rolling window  - "once per 24 real hours from completion":
//         QCD_IsOnCooldown(oPC, "ferny_return", QCD_DAY)
//   * Calendar reset  - "resets at UTC midnight / start of ISO week":
//         QCD_IsDoneToday(oPC, "hobbit_post")
//         QCD_IsDoneThisWeek(oPC, "riddle_gollum")
//
// ------------------------------------------------------------
// Usage - typical daily quest dialogue:
//
//   // StartingConditional on the "I have another job for you" NPC line:
//   #include "quest_cd_inc"
//   int StartingConditional()
//   {
//       return !QCD_IsOnCooldown(GetPCSpeaker(), "ferny_return", QCD_DAY);
//   }
//
//   // StartingConditional on the "come back later" line (tell them when):
//   #include "quest_cd_inc"
//   int StartingConditional()
//   {
//       object oPC = GetPCSpeaker();
//       if (!QCD_IsOnCooldown(oPC, "ferny_return", QCD_DAY)) return FALSE;
//       SetCustomToken(6320, QCD_FmtSpan(QCD_SecondsRemaining(oPC, "ferny_return", QCD_DAY)));
//       return TRUE;   // dialogue text: "Come back in <CUSTOM6320>."
//   }
//
//   // Reward action script, after handing out the loot:
//   QCD_Stamp(oPC, "ferny_return");
//
// Weekly quest: same calls with QCD_WEEK (rolling) or QCD_IsDoneThisWeek
// (calendar). QCD_InitDb() is called from onmoduleload.nss - new consumers
// need no setup beyond the #include.

const string QCD_DB   = "questcddb";
const int    QCD_HOUR = 3600;
const int    QCD_DAY  = 86400;      // rolling daily window
const int    QCD_WEEK = 604800;     // rolling weekly window

// ------------------------------------------------------------
// Schema - idempotent; called once from onmoduleload.nss.

void QCD_InitDb()
{
    sqlquery q = SqlPrepareQueryCampaign(QCD_DB,
        "CREATE TABLE IF NOT EXISTS quest_cd (" +
        "uuid TEXT NOT NULL," +
        "quest TEXT NOT NULL," +
        "cdkey TEXT," +
        "char_name TEXT," +
        "stamped_at INTEGER NOT NULL," +      // unix epoch of last completion
        "times_done INTEGER NOT NULL DEFAULT 1," +
        "PRIMARY KEY (uuid, quest))");
    SqlStep(q);
}

// ------------------------------------------------------------
// Small helpers

// ------------------------------------------------------------
// Character identity for the quest_cd primary key.
//
// Normally GetObjectUUID: it is minted once and persists in the .bic, so it
// survives relogs and reboots. But an UNSAVED character (offline toolset
// testing, or a PC the server has not exported yet) can hand back an empty
// string, and an empty uuid means every lookup misses -- which reads in game
// as "the once-ever gate does not work" while the live server is fine.
// Fall back to CD key + character name in that case: still per-character,
// still stable within a session, and it keeps a test build honest.
//
// Backward compatible: a saved character always has a UUID, so existing rows
// keep matching.
string QCD_Ident(object oPC)
{
    string sUuid = GetObjectUUID(oPC);
    if (sUuid != "") return sUuid;
    return "k:" + GetPCPublicCDKey(oPC) + "|" + GetName(oPC);
}

// Real-world "now" as unix-epoch seconds (from SQLite, not the game clock).
int QCD_Now()
{
    sqlquery q = SqlPrepareQueryCampaign(QCD_DB,
        "SELECT CAST(strftime('%s','now') AS INTEGER)");
    return SqlStep(q) ? SqlGetInt(q, 0) : 0;
}

// Friendly span for dialogue tokens, e.g. "1d 3h", "5h 12m", "9m".
string QCD_FmtSpan(int nSec)
{
    if (nSec < 0) nSec = 0;
    int nDays  = nSec / 86400;
    int nHours = (nSec % 86400) / 3600;
    int nMins  = (nSec % 3600) / 60;
    if (nDays > 0)  return IntToString(nDays)  + "d " + IntToString(nHours) + "h";
    if (nHours > 0) return IntToString(nHours) + "h " + IntToString(nMins)  + "m";
    return IntToString(nMins) + "m";
}

// ------------------------------------------------------------
// Core API

// Unix epoch of oPC's last completion of sQuest, or 0 if never done.
int QCD_LastStamp(object oPC, string sQuest)
{
    sqlquery q = SqlPrepareQueryCampaign(QCD_DB,
        "SELECT stamped_at FROM quest_cd WHERE uuid=@u AND quest=@q");
    SqlBindString(q, "@u", QCD_Ident(oPC));
    SqlBindString(q, "@q", sQuest);
    if (!SqlStep(q)) return 0;
    return SqlGetInt(q, 0);
}

// How many times oPC has completed sQuest, 0 if never done. Reads the
// times_done column QCD_Stamp already maintains. Use it for diminishing
// returns on a REPEATABLE quest: read it BEFORE calling QCD_Stamp, so 0 means
// "this is their first completion". The Kallrist Crypt riddle
// (kalrist_riddle.nss) pays 6000/3000/1000 XP off this.
int QCD_TimesDone(object oPC, string sQuest)
{
    sqlquery q = SqlPrepareQueryCampaign(QCD_DB,
        "SELECT times_done FROM quest_cd WHERE uuid=@u AND quest=@q");
    SqlBindString(q, "@u", QCD_Ident(oPC));
    SqlBindString(q, "@q", sQuest);
    if (!SqlStep(q)) return 0;
    return SqlGetInt(q, 0);
}

// Record that oPC completed sQuest just now (upsert; bumps times_done).
// Call from the quest's reward/turn-in script.
void QCD_Stamp(object oPC, string sQuest)
{
    sqlquery q = SqlPrepareQueryCampaign(QCD_DB,
        "INSERT INTO quest_cd(uuid,quest,cdkey,char_name,stamped_at,times_done)" +
        " VALUES(@u,@q,@k,@n,CAST(strftime('%s','now') AS INTEGER),1)" +
        " ON CONFLICT(uuid,quest) DO UPDATE SET" +
        " stamped_at=excluded.stamped_at," +
        " times_done=times_done+1," +
        " cdkey=excluded.cdkey," +
        " char_name=excluded.char_name");
    SqlBindString(q, "@u", QCD_Ident(oPC));
    SqlBindString(q, "@q", sQuest);
    SqlBindString(q, "@k", GetPCPublicCDKey(oPC));
    SqlBindString(q, "@n", GetName(oPC));
    SqlStep(q);
}

// Seconds until the rolling nCooldownSec window elapses, or 0 when the quest
// is available (never done, or window expired). Feed through QCD_FmtSpan for
// "come back in ..." dialogue text.
int QCD_SecondsRemaining(object oPC, string sQuest, int nCooldownSec)
{
    int nLast = QCD_LastStamp(oPC, sQuest);
    if (nLast == 0) return 0;
    int nLeft = (nLast + nCooldownSec) - QCD_Now();
    return (nLeft > 0) ? nLeft : 0;
}

// TRUE while oPC is still inside the rolling cooldown window for sQuest.
// Use QCD_DAY / QCD_WEEK for the standard daily/weekly windows.
int QCD_IsOnCooldown(object oPC, string sQuest, int nCooldownSec)
{
    return QCD_SecondsRemaining(oPC, sQuest, nCooldownSec) > 0;
}

// ------------------------------------------------------------
// Calendar-style resets (all UTC, computed in SQLite so there is no
// game-clock drift). "Done today" flips back to available at UTC midnight;
// "done this week" at the start of the next ISO-style week (%Y-%W).

// TRUE if oPC already completed sQuest today (UTC calendar day).
int QCD_IsDoneToday(object oPC, string sQuest)
{
    sqlquery q = SqlPrepareQueryCampaign(QCD_DB,
        "SELECT 1 FROM quest_cd WHERE uuid=@u AND quest=@q" +
        " AND date(stamped_at,'unixepoch') = date('now')");
    SqlBindString(q, "@u", QCD_Ident(oPC));
    SqlBindString(q, "@q", sQuest);
    return SqlStep(q);
}

// TRUE if oPC already completed sQuest this calendar week (UTC, %Y-%W).
int QCD_IsDoneThisWeek(object oPC, string sQuest)
{
    sqlquery q = SqlPrepareQueryCampaign(QCD_DB,
        "SELECT 1 FROM quest_cd WHERE uuid=@u AND quest=@q" +
        " AND strftime('%Y-%W', stamped_at,'unixepoch') = strftime('%Y-%W','now')");
    SqlBindString(q, "@u", QCD_Ident(oPC));
    SqlBindString(q, "@q", sQuest);
    return SqlStep(q);
}

// ------------------------------------------------------------
// Admin / testing

// Forget oPC's cooldown for sQuest (DM reset; also handy in UAT).
void QCD_Clear(object oPC, string sQuest)
{
    sqlquery q = SqlPrepareQueryCampaign(QCD_DB,
        "DELETE FROM quest_cd WHERE uuid=@u AND quest=@q");
    SqlBindString(q, "@u", QCD_Ident(oPC));
    SqlBindString(q, "@q", sQuest);
    SqlStep(q);
}
