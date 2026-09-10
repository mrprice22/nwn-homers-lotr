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
// ## One party crasher per ACCOUNT, and it is opt-in
//
// Grants are per character, but the ENTITLEMENT to them is per account: each CD
// key nominates exactly one character as its "party crasher", by talking to a
// penguin. Without that, an account could roll alt after alt and claim the whole
// set on each -- the items are undroppable so they could not be pooled, but the
// souvenir is meant to mean something and alt-farming it cheapens it.
//
// Opting out is offered by the same penguin, releases the slot, RECLAIMS every
// party item the character is holding (CP_ReclaimItems) and clears their grant
// flags -- so opting back in, on that character or a different one, issues a
// fresh set. Losing an item to its last charge and then re-opting is therefore a
// legitimate way to get another, and that is deliberate: the items are toys, and
// the rule being enforced is "one character at a time per account", not scarcity.
//
// This is only possible because every party item is Plot + Cursed and so cannot
// be dropped, traded, sold or banked. Reclaim can be complete precisely because
// there is nowhere for an item to have gone.
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

// Barrels get their own tag so the penguins' rummage can search for a BARREL
// rather than for "anything the dials made" -- GetNearestObjectByTag on the
// shared tag returns another penguin nearly every time in a crowd. Cleanup and
// counting match the cp_load PREFIX so both tags are still covered by one
// filter; see CP_IsLoadTag.
const string CP_KEG_TAG  = "cp_load_keg";

const int CP_ITEM_COUNT = 10;
const int CP_WAVE_MAX   = 3;

// ------------------------------------------------------------ borrowed faces
//
// The Mask and the Cloak both write Appearance_Type, so they must agree on what
// the player's real face is -- but "one stash, whoever finishes first puts it
// back" strands the other item: use the Mask while the Cloak is on and the
// Mask's 90s revert DELETES the stash, after which taking the Cloak off has
// nothing to restore from and the player is left as a badger with no item and
// no timer that will ever fix it. That is what these three functions exist to
// prevent.
//
// One stash, a bitmask of who is currently borrowing a face, and the real face
// goes back only when the LAST holder lets go. The variable names are the
// mask-era ones on purpose: they are already serialised into live .bic files,
// and renaming them would strand exactly the players this is meant to rescue.
const string CP_FACE_TRUE  = "CP_MASK_TRUEFORM";
const string CP_FACE_SET   = "CP_MASK_TRUEFORM_SET";
const string CP_FACE_HOLD  = "CP_FACE_HOLD";
const int    CP_FACE_MASK  = 1;
const int    CP_FACE_CLOAK = 2;

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
int    CP_ReclaimItems(object oPC);
void   CP_VenueOpen(int bOpen);
void   CP_PenguinCheer();
void   CP_AnnounceFire();
void   CP_AnnounceSchedule();
object CP_FindItem(object oPC, string sResRef);
object CP_Target(object oPC);
int    CP_OnlineCount();
int    CP_IsLoadTag(object oObj);
string CP_BelchSound(int nTipsy);
void   CP_FaceClaim(object oPC, int nWho);
int    CP_FaceRelease(object oPC, int nWho);
int    CP_FaceRestoreAll(object oPC);

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
    CP_VenueOpen(bOn);
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
    CP_PenguinCheer();
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
        case 6: return "cp_drum";
        case 7: return "cp_crown";
        case 8: return "cp_cloak";
        case 9: return "cp_gloves";
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
        case 6: return 1;   // Drum of the Marching Band
        case 7: return 2;   // Crown of Cacophony      (worn)
        case 8: return 2;   // Cloak of a Thousand Faces (worn)
        case 9: return 3;   // Gloves of a Great Many Punches (on-hit)
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
        case 6: return 300;
        // The two WORN items spend a charge per time they are PUT ON, not per
        // pulse. A charge per pulse would burn a generous-looking number down to
        // a quarter of an hour, and since players are never told the count the
        // item would just seem to break at random.
        case 7: return 150;
        case 8: return 150;
        // On-hit, so a charge is spent per PROC (20% of hits), not per swing.
        case 9: return 400;
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

    // The account has to have nominated THIS character. Everything else about
    // the hand-out is per character; this one check is per account.
    if (!CP_IsCrasher(oPC)) return 0;

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

// Take back every party item this character is holding, and return how many.
//
// Used by the opt-out path only. It is thorough on purpose: the whole promise of
// "one crasher per account" rests on opting out actually emptying your hands,
// and a leftover tankard would let somebody cycle the slot to accumulate a set
// per alt after all.
//
// The souvenir goes too. It is the one item with no charges and no expiry, which
// makes it exactly the thing worth alt-farming, so it cannot be the exception.
//
// SetPlotFlag(FALSE) before DestroyObject -- plot items resist destroy, and
// every cp_* item is plot (kalrist_gems.nss:72 is the precedent).
int CP_ReclaimItems(object oPC)
{
    int nTaken = 0;

    // ONE pass over the inventory, stepping to the next item BEFORE destroying
    // the current one. Do not be tempted to re-fetch by tag in a loop instead:
    // DestroyObject is deferred to the end of the script, so the item stays
    // valid and a re-fetch would hand back the same object forever.
    //
    // Matching on the resref prefix rather than the item table also catches the
    // souvenir and anything a future wave adds, without a second list to keep in
    // step. Every cp_* item is non-equippable (base item 29), so inventory is
    // the only place one can be.
    object oItem = GetFirstItemInInventory(oPC);
    while (GetIsObjectValid(oItem))
    {
        object oNext = GetNextItemInInventory(oPC);

        if (GetStringLeft(GetResRef(oItem), 3) == "cp_")
        {
            SetPlotFlag(oItem, FALSE);   // plot resists destroy
            DestroyObject(oItem);
            nTaken++;
        }

        oItem = oNext;
    }

    return nTaken;
}

// Every penguin in the venue cheers when a wave drops.
//
// Three cheers rather than one, chosen per penguin, so a crowd produces a MIX
// rather than a chorus -- twenty five voices saying the identical thing in the
// same instant reads as a bug, not a party.
//
// Each is delayed by a random fraction of a second for the same reason it is
// staggered elsewhere: firing twenty five SpeakStrings inside one frame is a
// spike on the exact object whose purpose is to make load measurable.
void CP_PenguinCheer()
{
    object oArea = GetObjectByTag("TheWellofEru");
    if (!GetIsObjectValid(oArea)) return;

    object oObj = GetFirstObjectInArea(oArea);
    while (GetIsObjectValid(oObj))
    {
        if (GetObjectType(oObj) == OBJECT_TYPE_CREATURE
            && !GetIsPC(oObj)
            && (GetTag(oObj) == CP_LOAD_TAG || GetTag(oObj) == "cp_penguin"))
        {
            string sCheer;
            switch (Random(4))
            {
                case 0:  sCheer = "PaRtY TiMe!!";              break;
                case 1:  sCheer = "WAAAAUGH! MORE GROG!";      break;
                case 2:  sCheer = "HOORAY FOR THE PENGUINS!";  break;
                default: sCheer = "*honks ecstatically*";      break;
            }
            float fWhen = IntToFloat(Random(25)) / 10.0;
            AssignCommand(oObj, DelayCommand(fWhen, SpeakString(sCheer)));
            AssignCommand(oObj, DelayCommand(fWhen,
                PlayAnimation(ANIMATION_FIREFORGET_VICTORY3, 1.0)));
        }
        oObj = GetNextObjectInArea(oArea);
    }
}

// ------------------------------------------------------------ the countdown
//
// The countdown runs itself once started, and can still be pushed by hand.
//
// Deliberately NOT gated on CP_IsOn: the whole countdown happens BEFORE the
// party is switched on ("starts in one hour"), so a mode check here would stop
// it firing at all.
//
// Superseding: every schedule bumps CP_ANN_GEN and every tick bumps
// CP_ANN_SEEN, so a tick that is not the newest returns without firing. That is
// what makes a manual press safe -- pressing the placard early fires the line
// AND re-schedules, and the older pending tick quietly retires instead of
// double-announcing. Same generation guard as the Mask's revert.

const string CP_ANN_STEP = "CP_ANN_STEP";
const string CP_ANN_GEN  = "CP_ANN_GEN";
const string CP_ANN_SEEN = "CP_ANN_SEEN";

// Minutes from each line to the next. The last entry ends the chain: past the
// doors opening there is nothing to count down to, and a party that nags every
// half hour is worse than one that does not.
int CP_AnnounceGap(int nStep)
{
    switch (nStep)
    {
        case 0: return 30;   // "one hour"     -> "thirty minutes"
        case 1: return 20;   // "thirty"       -> "ten minutes"
        case 2: return 10;   // "ten minutes"  -> doors open
    }
    return 0;                // doors open: chain ends, manual only from here
}

void CP_AnnounceFire()
{
    int nStep = GetLocalInt(GetModule(), CP_ANN_STEP);
    string sMsg;
    switch (nStep)
    {
        case 0:
            sMsg = "The Crash Party starts in ONE HOUR. Come to the Well of Eru -- " +
                   "we are trying to break the server's all-time record for players online.";
            break;
        case 1:
            sMsg = "THIRTY MINUTES to the Crash Party. Drag a friend along; every " +
                   "single body counts toward the record.";
            break;
        case 2:
            sMsg = "TEN MINUTES. Head to the Well of Eru now.";
            break;
        case 3:
            sMsg = "The Crash Party begins NOW! Free party favours at the Well of Eru, " +
                   "and they are yours to keep afterwards.";
            break;
        default:
            sMsg = "The Crash Party is still going at the Well of Eru. Everyone welcome.";
            break;
    }
    CP_Broadcast("*** " + sMsg + " ***", COLOR_YELLOW);
    SetLocalInt(GetModule(), CP_ANN_STEP, nStep + 1);
}

// Queue the next line, if there is one. Safe to call after every fire.
void CP_AnnounceSchedule()
{
    int nGap = CP_AnnounceGap(GetLocalInt(GetModule(), CP_ANN_STEP) - 1);
    if (nGap <= 0) return;

    int nGen = GetLocalInt(GetModule(), CP_ANN_GEN) + 1;
    SetLocalInt(GetModule(), CP_ANN_GEN, nGen);
    DelayCommand(IntToFloat(nGap) * 60.0, ExecuteScript("cp_anntick", GetModule()));
}

// ------------------------------------------------------------ the venue
//
// Bartholomew and the scoreboard are CREATED when the party starts and destroyed
// when it stops. They are deliberately NOT permanent placements: the Well of Eru
// is the module's hub and every player passes through it constantly, so a
// penguin and a chalkboard standing there year-round advertising an event that
// is not running is just clutter -- and worse, a reboot re-created them whether
// or not anybody had scheduled anything.
//
// Their positions live on waypoints (cp_penguin_wp, cp_board_wp) so the admin
// can still move them in the toolset, which is the whole reason this is not
// hardcoded coordinates.
//
// Idempotent in both directions: spawning checks for an existing one by tag
// first (the MWSpawnAtWaypoint pattern), so a double-press cannot produce two
// penguins, and closing is a no-op when nothing is there.
void CP_VenueOpen(int bOpen)
{
    object oPeng  = GetObjectByTag("cp_penguin");
    object oBoard = GetObjectByTag("cp_board");

    if (!bOpen)
    {
        if (GetIsObjectValid(oPeng))  { SetPlotFlag(oPeng, FALSE);  DestroyObject(oPeng); }
        if (GetIsObjectValid(oBoard)) { SetPlotFlag(oBoard, FALSE); DestroyObject(oBoard); }
        return;
    }

    if (!GetIsObjectValid(oPeng))
    {
        object oWP = GetWaypointByTag("cp_penguin_wp");
        if (GetIsObjectValid(oWP))
            CreateObject(OBJECT_TYPE_CREATURE, "cp_penguin", GetLocation(oWP), FALSE);
    }
    if (!GetIsObjectValid(oBoard))
    {
        object oWP = GetWaypointByTag("cp_board_wp");
        if (GetIsObjectValid(oWP))
            CreateObject(OBJECT_TYPE_PLACEABLE, "cp_board", GetLocation(oWP), FALSE);
    }
}

// One filter for everything the stress dials create, whatever its specific tag.
// Keep this a PREFIX test: a new kind of load object should be collected by
// CLEAR ALL the moment it is added, without anyone having to remember to update
// a list of exact tags.
int CP_IsLoadTag(object oObj)
{
    return GetStringLeft(GetTag(oObj), GetStringLength(CP_LOAD_TAG)) == CP_LOAD_TAG;
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

// ------------------------------------------------------------ borrowed faces

// Take a face. Stashes the real one the FIRST time only, so stacking a Mask on
// top of a Cloak can never record an already-borrowed face as the real one.
void CP_FaceClaim(object oPC, int nWho)
{
    if (!GetLocalInt(oPC, CP_FACE_SET))
    {
        SetLocalInt(oPC, CP_FACE_TRUE, GetAppearanceType(oPC));
        SetLocalInt(oPC, CP_FACE_SET, TRUE);
    }
    SetLocalInt(oPC, CP_FACE_HOLD, GetLocalInt(oPC, CP_FACE_HOLD) | nWho);
}

// Give a face back. Returns TRUE only if this was the last holder and the real
// face actually went back on -- callers use that to decide whether to say so,
// since "your own face returns" is a lie while the Cloak is still rerolling.
//
// A character carrying pre-fix state (stash set, no holder bits) releases to
// zero on the first call and self-heals.
int CP_FaceRelease(object oPC, int nWho)
{
    int nHold = GetLocalInt(oPC, CP_FACE_HOLD) & ~nWho;
    SetLocalInt(oPC, CP_FACE_HOLD, nHold);
    if (nHold != 0) return FALSE;

    DeleteLocalInt(oPC, CP_FACE_HOLD);
    return CP_FaceRestoreAll(oPC);
}

// Unconditional: put the real face back and drop every holder. This is the
// login path (every timer that would have released died at logout) and the
// get-me-out-of-here path.
int CP_FaceRestoreAll(object oPC)
{
    DeleteLocalInt(oPC, CP_FACE_HOLD);
    if (!GetLocalInt(oPC, CP_FACE_SET)) return FALSE;

    int nTrue = GetLocalInt(oPC, CP_FACE_TRUE);

    // Clear the bookkeeping FIRST, so a restore that somehow fails cannot leave
    // a stale stash to overwrite a legitimate appearance later.
    DeleteLocalInt(oPC, CP_FACE_TRUE);
    DeleteLocalInt(oPC, CP_FACE_SET);

    if (GetAppearanceType(oPC) == nTrue) return TRUE;

    ApplyEffectToObject(DURATION_TYPE_INSTANT,
        EffectVisualEffect(VFX_IMP_POLYMORPH), oPC);
    SetCreatureAppearanceType(oPC, nTrue);
    return TRUE;
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
