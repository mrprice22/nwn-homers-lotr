// wos_inc.nss -- "The Well of Souls" quest state (Gondor Scribe / Azagoth)
// (roadmap: gondor-scribe)
//
// WHY THIS EXISTS
// ---------------
// NWScript has no getter for journal state -- nwscript.nss exposes only
// AddJournalQuestEntry and RemoveJournalQuestEntry -- so the journal cannot be
// the gate. Everything this quest used to call "quest state" was a session
// local int (azagothdead, azgiven, hanee_head_reward), cleared on relog, which
// is why the whole briefing chain replayed forever and the Annuminas Key could
// be re-earned.
//
// So: the campaign DB is the gate, the journal is the display. Every stage
// helper below stamps the DB and mirrors the matching journal entry in one
// call, so the two can never drift apart.
//
// STORAGE
// -------
// The existing questcddb / quest_cd table via quest_cd_inc -- no new schema and
// no new init (QCD_InitDb already runs from onmoduleload.nss). "Once ever" is
// QCD_LastStamp(...) == 0, the same idiom q_ent_drink.nss and q_sow_pay.nss use.
//
//   wos_accept  briefing heard, quest taken   -> journal "The Well of Souls" 1
//   wos_done    Azagoth's head turned in      -> journal "The Well of Souls" 2
//   annu_key    Annuminas Key granted         -> (no journal entry)
//
// The annu_key row PREDATES this include (commit aaf3e1c6f0b) -- the name is
// kept so characters who already drew a key are still recognised and cannot
// draw a second one.
//
// THE KEY IS A COMPLETION REWARD. It used to be handed out at accept, before
// the player had done anything, which is what made it worth farming. It is now
// granted by the head turn-in, once per character ever. One key opens exactly
// one of the two warded Annuminas coffers (KeyRequired + AutoRemoveKey), so
// the choice between the sorcerer and the wizard hoard stays permanent.
//
// Both Gondor Scribes -- gondorscribe in the Ruins of Annuminas and
// gondorscribetwr in the Tower of the High Wizard -- share this state, so the
// quest can be accepted at either and turned in at either.

#include "quest_cd_inc"

const string WOS_JOURNAL   = "The Well of Souls";  // journal category Tag
const string WOS_K_ACCEPT  = "wos_accept";
const string WOS_K_DONE    = "wos_done";
const string WOS_K_KEY     = "annu_key";           // pre-existing key, do not rename

const string WOS_KEY_RES   = "annuminaskey";       // blueprint resref
const string WOS_KEY_TAG   = "AnnuminasKey";       // item Tag (case differs from resref)

// ------------------------------------------------------------
// Stage reads

// TRUE once oPC has taken the quest from either scribe.
int WOS_Accepted(object oPC)
{
    return QCD_LastStamp(oPC, WOS_K_ACCEPT) != 0;
}

// TRUE once oPC has handed Azagoth's head to either scribe.
int WOS_Done(object oPC)
{
    return QCD_LastStamp(oPC, WOS_K_DONE) != 0;
}

// TRUE once oPC has ever been given the Annuminas Key.
int WOS_KeyGiven(object oPC)
{
    return QCD_LastStamp(oPC, WOS_K_KEY) != 0;
}

// ------------------------------------------------------------
// Stage writes. Both stamp only once, so re-running a dialogue node cannot
// bump times_done or rewind the journal.
//
// AddJournalQuestEntry is deliberately called with bAllPartyMembers = FALSE
// and bAllPlayers = FALSE (matching acquireditem_tag.nss) so a party member
// standing nearby is not dragged into a stage they have not reached.

void WOS_Accept(object oPC)
{
    if (WOS_Accepted(oPC) || WOS_Done(oPC)) return;
    QCD_Stamp(oPC, WOS_K_ACCEPT);
    AddJournalQuestEntry(WOS_JOURNAL, 1, oPC, FALSE, FALSE);
}

void WOS_Complete(object oPC)
{
    if (WOS_Done(oPC)) return;
    // A player who walked in cold and killed Azagoth before ever taking the
    // quest still needs the accept stamp, or the briefing would offer itself
    // again after completion.
    if (!WOS_Accepted(oPC)) QCD_Stamp(oPC, WOS_K_ACCEPT);
    QCD_Stamp(oPC, WOS_K_DONE);
    AddJournalQuestEntry(WOS_JOURNAL, 2, oPC, FALSE, FALSE);
}

// ------------------------------------------------------------
// The reward key. Returns TRUE only when a key was actually created.

int WOS_GiveKey(object oPC)
{
    if (WOS_KeyGiven(oPC)) return FALSE;
    // Belt and braces: never hand out a second key while one is still carried.
    if (GetIsObjectValid(GetItemPossessedBy(oPC, WOS_KEY_TAG))) return FALSE;

    CreateItemOnObject(WOS_KEY_RES, oPC, 1);
    QCD_Stamp(oPC, WOS_K_KEY);
    return TRUE;
}

// TRUE when oPC finished the quest but has never drawn the key -- the claim
// path for characters who completed it before the key moved to the turn-in.
int WOS_CanClaimKey(object oPC)
{
    return WOS_Done(oPC) && !WOS_KeyGiven(oPC);
}
