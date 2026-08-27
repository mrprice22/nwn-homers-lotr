// kalrist_riddle - Kallrist Crypt elemental-pillar riddle, altar (brazier) OnUsed.
//
// The riddle: "Red earth crumbles, Blue flames glow, Green water splashes,
// Golden airs blow."  RedGem->ECHO_EARTH, BlueGem->ECHO_FIRE,
// GreenGem->ECHO_WATER, YellowGem->ECHO_AIR.  Solving it mints kalcryptkey001,
// the key to kallupper2riddledoor and so to the central chamber, the lower
// crypt loot and the Kallrist forge.
//
// REPEATABLE BY DESIGN - roadmap kallrist-crypt-quest-only-doable-once-per-
// server-reset.  The old version did DestroyObject(OBJECT_SELF, 1.8) on a
// solve, deleting the only OnUsed handler in the area, so the puzzle was dead
// for the rest of the reset and every later party found a sealed door and an
// empty gem chest.  Now:
//
//   * the altar survives - it stays Plot=1 and is never destroyed.  The old
//     permanent "silenced" local is gone; all that is left is an 8s busy flag
//     that clears itself, so a double-click cannot pay out twice;
//   * the four gems are CONSUMED on a solve, so the pillars empty themselves.
//     Without that, the next click would re-read the same filled pillars and
//     hand out a free second key;
//   * the gem chest's restock timer is cleared here, so the next party gets a
//     fresh set on their very next open instead of waiting out the 25 minute
//     cooldown (see kalrist_gems.nss);
//   * the key goes to the PCs, not into the altar.  The old code created it on
//     OBJECT_SELF and then destroyed OBJECT_SELF 1.8s later, giving the player
//     under two seconds to loot it;
//   * XP diminishes per CHARACTER, persistently, via questcddb: 6000 for a
//     character's first ever solve, 3000 for their second, 1000 thereafter.
//     A repeatable puzzle must not be an XP farm.
//
// Matching is BY TAG inside each pillar.  The old code compared object identity
// against GetObjectByTag("RedGem"), which returns the module-wide first match -
// a gem sitting in some other player's pack in another area could silently
// break the check.  Tag matching also means junk stuffed into a pillar by a
// griefer is simply ignored.
//
// The door itself needs nothing: kallupper2riddledoor is OnOpen doorlock ->
// DoorAutoClose(8.0, TRUE), so it re-locks 8s after each use, and
// AutoRemoveKey=0 means a solver keeps their key for good.
#include "quest_cd_inc"

const string KAL_KEY_RES  = "kalcryptkey001";  // blueprint resref
const string KAL_KEY_TAG  = "kalcryptkey001";  // == the door's KeyName
const string KAL_GEMCHEST = "KAL_GEM_CHEST";   // the retagged gem chest
const string KAL_QUEST    = "kalcrypt_riddle"; // questcddb key

// Diminishing returns, per character, forever.
const int KAL_XP_FIRST  = 6000;
const int KAL_XP_SECOND = 3000;
const int KAL_XP_AFTER  = 1000;

// Double-click debounce. Not a puzzle cooldown - the gems are already gone by
// the time this expires, so it only guards the same click arriving twice.
const string KAL_BUSY     = "KAL_RIDDLE_BUSY";
const float  KAL_BUSY_SEC = 8.0;

const string KAL_HINT =
    "I is not import', 'ere is the thing, follow the rhymes, come back for the blings, Red earth crumblesss, Blue flames glooow, Green water splashesss, Golden 'airs blooow.";

// TRUE when oChest holds at least one item tagged sTag.
int KalChestHas(object oChest, string sTag)
{
    if (!GetIsObjectValid(oChest)) return FALSE;
    object oItem = GetFirstItemInInventory(oChest);
    while (GetIsObjectValid(oItem))
    {
        if (GetTag(oItem) == sTag) return TRUE;
        oItem = GetNextItemInInventory(oChest);
    }
    return FALSE;
}

// Consume every item tagged sTag in oChest. DestroyObject is deferred to the
// end of the script, so destroying inside the GetFirst/GetNext walk is safe.
void KalConsume(object oChest, string sTag)
{
    if (!GetIsObjectValid(oChest)) return;
    object oItem = GetFirstItemInInventory(oChest);
    while (GetIsObjectValid(oItem))
    {
        if (GetTag(oItem) == sTag)
        {
            SetPlotFlag(oItem, FALSE);   // defensive: plot items resist destroy
            DestroyObject(oItem, 0.0);
        }
        oItem = GetNextItemInInventory(oChest);
    }
}

// XP for this character's next completion, read BEFORE stamping.
int KalXpFor(object oPC)
{
    int nDone = QCD_TimesDone(oPC, KAL_QUEST);
    if (nDone <= 0) return KAL_XP_FIRST;
    if (nDone == 1) return KAL_XP_SECOND;
    return KAL_XP_AFTER;
}

void main()
{
    object oSelf = OBJECT_SELF;

    // Debounce first: two clicks in the same instant must not pay out twice.
    if (GetLocalInt(oSelf, KAL_BUSY)) return;

    // OnUsed is the live path (the altar instance is deliberately
    // HasInventory=0, because a container placeable's click is an OPEN, not a
    // USE). GetLastOpenedBy is the fallback in case this is ever re-hooked
    // from OnOpen instead.
    object oPC = GetLastUsedBy();
    if (!GetIsObjectValid(oPC)) oPC = GetLastOpenedBy(oSelf);

    object oAir   = GetObjectByTag("ECHO_AIR");
    object oFire  = GetObjectByTag("ECHO_FIRE");
    object oWater = GetObjectByTag("ECHO_WATER");
    object oEarth = GetObjectByTag("ECHO_EARTH");

    int bSolved = KalChestHas(oAir,   "YellowGem")
               && KalChestHas(oFire,  "BlueGem")
               && KalChestHas(oWater, "GreenGem")
               && KalChestHas(oEarth, "RedGem");

    if (!bSolved)
    {
        if (GetIsObjectValid(oPC))
            SendMessageToPC(oPC, "A disembodied voice, coming from the altar, whispers...");
        SpeakString(KAL_HINT);
        return;
    }

    SetLocalInt(oSelf, KAL_BUSY, 1);
    DelayCommand(KAL_BUSY_SEC, DeleteLocalInt(oSelf, KAL_BUSY));

    // The offering is taken - the pillars are empty again for the next party.
    KalConsume(oAir,   "YellowGem");
    KalConsume(oFire,  "BlueGem");
    KalConsume(oWater, "GreenGem");
    KalConsume(oEarth, "RedGem");

    DelayCommand(1.5, SpeakString("Phew...music to my ears..."));
    DelayCommand(1.6, ApplyEffectToObject(DURATION_TYPE_INSTANT,
                        EffectVisualEffect(VFX_FNF_MYSTICAL_EXPLOSION), oSelf));

    // The whole party is paid, wherever they are standing - this is a
    // four-corner puzzle a party physically splits up to run, and making one
    // member re-solve it once per companion is the annoyance that would
    // otherwise remain. Both grants are individually guarded, so paying the
    // party costs nothing: the key is skipped for anyone already holding one,
    // and the XP is on each character's own persistent counter.
    if (GetIsObjectValid(oPC))
    {
        object oMember = GetFirstFactionMember(oPC, TRUE);
        while (GetIsObjectValid(oMember))
        {
            if (!GetIsDM(oMember))
            {
                if (!GetIsObjectValid(GetItemPossessedBy(oMember, KAL_KEY_TAG)))
                    CreateItemOnObject(KAL_KEY_RES, oMember, 1);

                int nXp = KalXpFor(oMember);
                GiveXPToCreature(oMember, nXp);
                QCD_Stamp(oMember, KAL_QUEST);

                SendMessageToPC(oMember,
                    "The noises in the chamber become quieter, less chaotic, and you hear a sigh of relief.");
            }
            oMember = GetNextFactionMember(oPC, TRUE);
        }
    }

    // Let the gem chest restock on its very next open, cooldown or not.
    object oChest = GetObjectByTag(KAL_GEMCHEST);
    if (GetIsObjectValid(oChest)) DeleteLocalInt(oChest, "CS_Opened");
}
