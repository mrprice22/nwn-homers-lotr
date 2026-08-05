// csp_inc.nss - the caster spell picker: entitlement, legality, granting.
// Roadmap: legendary-caster-spells-on-level-up.
//
// WHY THIS EXISTS. Past CLASS level 40 the game client's own level-up spell
// page is broken: it asks a wizard for its usual 2 picks, populates only the
// cantrip tab, and then spends the picks anyway when the player continues. The
// tabs render enabled for about one frame and are then disabled by a later pass
// in CLIENT code, so no 2DA, hak, plugin option or server script can reach it -
// tests A-D on the roadmap item ruled out every data lever there is. The
// diagnosis is closed; this is the replacement.
//
// So the module hands out the picks itself, server-side, and opens its own
// window right after the level-up finishes (csp_lvl.nss). Being server-side it
// is also immune to whatever the client does next.
//
// SCOPE AS SHIPPED - READ THIS BEFORE EXTENDING.
//
//   WIZARD ONLY. A wizard past class level 40 banks 2 picks per level and
//   spends them on new spellbook spells. That is the case where the client
//   destroys a stock entitlement, and it is the whole of what is wired today.
//
//   SORCERER AND BARD are deliberately INERT: CSP_PicksPerLevel returns 0 for
//   them, so they bank nothing, the window never opens, and nothing is spent or
//   lost. Their case is a SWAP (trade a known spell for a better one), not a
//   grant, which needs a second UI mode this build does not have. Half-wiring
//   it would be worse than the bug it fixes - a window that eats a pick and
//   gives nothing back. When it is built, give them a CSP_PicksPerLevel and a
//   swap path; the DB, the entitlement and the legality checks below are
//   already class-parameterised for it.
//
// STAGE THEN COMMIT. The pick is charged to the ledger and the spell added in
// one place (CSP_Learn) and nowhere else. Nothing else in the module may call
// NWNX_Creature_AddKnownSpell for a PC - a grant that does not go through here
// is a grant with no charge, which is the farm.

#include "csp_db"
#include "nwnx_creature"

// Class levels above this lose their spell picks to the client bug. Below it
// the stock level-up page works and must be left alone.
const int CSP_CAP_LEVEL = 40;

// Stock wizard entitlement: 2 new spells per level. Unchanged - this feature
// restores what the client eats, it does not hand out more.
const int CSP_WIZ_PER_LEVEL = 2;

// Bound on the spells.2da scan. Get2DARowCount is authoritative; this only
// stops a bad answer turning into an unbounded loop.
const int CSP_MAX_SPELL_ROWS = 3000;

// CSP_Learn result codes.
const int CSP_OK       = 0;
const int CSP_NOPICKS  = 1;   // nothing banked
const int CSP_KNOWN    = 2;   // already in the spellbook
const int CSP_ILLEGAL  = 3;   // not learnable by this character at all
const int CSP_FAILED   = 4;   // engine refused the write (charged, and loud)

int    CSP_PicksPerLevel(int nClass);
int    CSP_ClassLevel(object oPC, int nClass);
int    CSP_Remaining(object oPC);
int    CSP_EnsureAllotment(object oPC);
int    CSP_SpellLevelOf(int nSpellId);
int    CSP_CanUseSpellLevel(object oPC, int nSpellLevel);
int    CSP_MaxSpellLevel(object oPC);
string CSP_OpposedLetter(object oPC);
int    CSP_IsOpposed(object oPC, int nSpellId);
int    CSP_IsOffered(object oPC, int nSpellId);
string CSP_SpellName(int nSpellId);
string CSP_SpellDesc(int nSpellId);
string CSP_SchoolName(int nSpellId);
int    CSP_Learn(object oPC, int nSpellId);

// How many picks one level in this class is worth. ZERO IS THE SAFE DEFAULT and
// is what keeps every class except wizard completely inert - no entitlement, no
// window, no spend. See the scope note at the top before adding a class here.
int CSP_PicksPerLevel(int nClass)
{
    if (nClass == CLASS_TYPE_WIZARD) return CSP_WIZ_PER_LEVEL;
    return 0;
}

// The picker class this character is eligible under, or CLASS_TYPE_INVALID.
// Only one today; written as a lookup so adding sorcerer/bard later is a change
// here rather than in every caller.
int CSP_PickerClass(object oPC)
{
    if (GetLevelByClass(CLASS_TYPE_WIZARD, oPC) > CSP_CAP_LEVEL)
        return CLASS_TYPE_WIZARD;
    return CLASS_TYPE_INVALID;
}

int CSP_ClassLevel(object oPC, int nClass)
{
    if (nClass == CLASS_TYPE_INVALID) return 0;
    return GetLevelByClass(nClass, oPC);
}

// Picks banked but not yet spent. Reads the ledger only - CSP_EnsureAllotment
// is what puts new picks in it.
int CSP_Remaining(object oPC)
{
    int nClass = CSP_PickerClass(oPC);
    if (nClass == CLASS_TYPE_INVALID) return 0;

    CSP_InitDb();
    int n = CSP_GetGranted(oPC, nClass) - CSP_GetSpent(oPC, nClass);
    return (n > 0) ? n : 0;
}

// Pay this character for every class level past the cap it has not been paid
// for yet, and return what it now has to spend.
//
// This IS the retroactive make-good. A character first seen at wizard 53 has no
// row, so paid_to seeds at 40 and it is paid for levels 41-53 in one go: 26
// picks. The very same call then stores paid_to = 53, so it is paid once and
// never again, and because paid_to only ever rises (CSP_SetAlloc takes MAX), no
// amount of de-levelling and re-levelling can be paid for a second time.
//
// Safe to call as often as you like - every caller does, on login, on rest and
// on every level event.
int CSP_EnsureAllotment(object oPC)
{
    if (!GetIsPC(oPC) || GetIsDM(oPC)) return 0;

    int nClass = CSP_PickerClass(oPC);
    if (nClass == CLASS_TYPE_INVALID) return 0;

    int nPer = CSP_PicksPerLevel(nClass);
    if (nPer <= 0) return 0;

    CSP_InitDb();

    int nLevel  = CSP_ClassLevel(oPC, nClass);
    int nPaidTo = CSP_GetPaidTo(oPC, nClass, CSP_CAP_LEVEL);
    if (nPaidTo < CSP_CAP_LEVEL) nPaidTo = CSP_CAP_LEVEL;

    if (nLevel > nPaidTo)
    {
        int nOwed = (nLevel - nPaidTo) * nPer;
        CSP_SetAlloc(oPC, nClass, nLevel, CSP_GetGranted(oPC, nClass) + nOwed);
    }

    return CSP_Remaining(oPC);
}

// The spell level this spell is learnable at for a wizard, or -1 if a wizard
// cannot learn it at all.
//
// Two filters, and both matter:
//   Master  - a subradial variant (the individual Bigby's, the domain copies).
//             It is not a separate spell to learn and offering it would put a
//             duplicate in the book.
//   Wiz_Sorc - blank on everything outside the arcane list, including every
//             monster, epic and item-only spell in the table.
// Together they select exactly the 179 wizard-learnable rows in stock
// spells.2da (L0:7 L1:22 L2:28 L3:23 L4:21 L5:18 L6:20 L7:13 L8:13 L9:14).
int CSP_SpellLevelOf(int nSpellId)
{
    if (nSpellId < 0) return -1;
    if (Get2DAString("spells", "Master", nSpellId) != "") return -1;

    string sLvl = Get2DAString("spells", "Wiz_Sorc", nSpellId);
    if (sLvl == "") return -1;

    int nLvl = StringToInt(sLvl);
    if (nLvl < 0 || nLvl > 9) return -1;
    return nLvl;
}

// Can this character use spells of this level at all?
//
// Deliberately arithmetic rather than a 2DA read: a wizard gains spell level L
// at class level 2L-1, and needs Intelligence 10+L to cast it. Both are stock
// rules that do not change with the level cap, and neither depends on a table
// the client bug has already proved unreliable to reason about.
int CSP_CanUseSpellLevel(object oPC, int nSpellLevel)
{
    if (nSpellLevel < 0 || nSpellLevel > 9) return FALSE;

    int nClass = CSP_PickerClass(oPC);
    if (nClass == CLASS_TYPE_INVALID) return FALSE;

    int nNeed = (nSpellLevel <= 0) ? 1 : (nSpellLevel * 2 - 1);
    if (CSP_ClassLevel(oPC, nClass) < nNeed) return FALSE;

    return GetAbilityScore(oPC, ABILITY_INTELLIGENCE) >= 10 + nSpellLevel;
}

// Highest spell level this character may pick, or -1 if none.
int CSP_MaxSpellLevel(object oPC)
{
    int i;
    for (i = 9; i >= 0; i--)
        if (CSP_CanUseSpellLevel(oPC, i)) return i;
    return -1;
}

// The school letter this character is barred from, or "" for a generalist.
//
// Specialist wizards may not learn their opposition school (dialog.tlk 64459).
// The pairing is read from spellschools.2da's Opposition column rather than
// hard-coded, so it stays correct under any hak that changes it.
string CSP_OpposedLetter(object oPC)
{
    int nSpec = GetSpecialization(oPC, CLASS_TYPE_WIZARD);
    if (nSpec <= 0) return "";      // -1 error, 0 = General = no specialisation

    string sOpp = Get2DAString("spellschools", "Opposition", nSpec);
    if (sOpp == "") return "";

    return Get2DAString("spellschools", "Letter", StringToInt(sOpp));
}

int CSP_IsOpposed(object oPC, int nSpellId)
{
    string sOpp = CSP_OpposedLetter(oPC);
    if (sOpp == "") return FALSE;
    return Get2DAString("spells", "School", nSpellId) == sOpp;
}

// Everything except "has a pick to spend": is this a spell this character could
// legally add to its book right now? The window uses it to build the list and
// CSP_Learn re-checks it, because the window is only a snapshot.
int CSP_IsOffered(object oPC, int nSpellId)
{
    int nLvl = CSP_SpellLevelOf(nSpellId);
    if (nLvl < 0) return FALSE;
    if (!CSP_CanUseSpellLevel(oPC, nLvl)) return FALSE;
    if (CSP_IsOpposed(oPC, nSpellId)) return FALSE;

    int nClass = CSP_PickerClass(oPC);
    if (nClass == CLASS_TYPE_INVALID) return FALSE;
    if (GetIsInKnownSpellList(oPC, nClass, nSpellId)) return FALSE;

    return TRUE;
}

string CSP_SpellName(int nSpellId)
{
    string sRef = Get2DAString("spells", "Name", nSpellId);
    if (sRef == "") return Get2DAString("spells", "Label", nSpellId);
    return GetStringByStrRef(StringToInt(sRef));
}

string CSP_SpellDesc(int nSpellId)
{
    string sRef = Get2DAString("spells", "SpellDesc", nSpellId);
    if (sRef == "") return "";
    return GetStringByStrRef(StringToInt(sRef));
}

// Full school name for the list column, from the letter in spells.2da. Walked
// rather than switched on a letter, so a hak that adds a school still reads
// correctly.
string CSP_SchoolName(int nSpellId)
{
    string sLetter = Get2DAString("spells", "School", nSpellId);
    if (sLetter == "") return "";

    int nRows = Get2DARowCount("spellschools");
    if (nRows <= 0 || nRows > 64) nRows = 9;

    int i;
    for (i = 0; i < nRows; i++)
        if (Get2DAString("spellschools", "Letter", i) == sLetter)
            return Get2DAString("spellschools", "Label", i);

    return "";
}

// Spend one pick on one spell. The ONLY place a pick is spent and the only
// place this feature adds a known spell.
//
// ORDER MATTERS, AND IT IS CHARGE-THEN-GRANT ON PURPOSE. The ledger row is
// written before the engine call, so the worst case if the engine ever refuses
// the write is a lost pick with a loud message - never a spell granted free of
// charge, which would be farmable by whatever made the write fail. The
// already-known check above it is what stops a double-clicked button charging
// twice: the second click sees the spell in the book and returns CSP_KNOWN
// without touching the ledger.
int CSP_Learn(object oPC, int nSpellId)
{
    if (!GetIsPC(oPC) || GetIsDM(oPC)) return CSP_ILLEGAL;

    int nClass = CSP_PickerClass(oPC);
    if (nClass == CLASS_TYPE_INVALID) return CSP_ILLEGAL;

    int nLvl = CSP_SpellLevelOf(nSpellId);
    if (nLvl < 0) return CSP_ILLEGAL;
    if (!CSP_CanUseSpellLevel(oPC, nLvl)) return CSP_ILLEGAL;
    if (CSP_IsOpposed(oPC, nSpellId)) return CSP_ILLEGAL;

    if (GetIsInKnownSpellList(oPC, nClass, nSpellId)) return CSP_KNOWN;

    // Re-derive the entitlement here rather than trusting the window: this is
    // the check that actually binds.
    if (CSP_EnsureAllotment(oPC) <= 0) return CSP_NOPICKS;

    CSP_RecordLearn(oPC, nClass, nSpellId);
    NWNX_Creature_AddKnownSpell(oPC, nClass, nLvl, nSpellId);

    // Known spells live in the .bic, so flush rather than trusting the
    // character to be exported later.
    ExportSingleCharacter(oPC);

    if (!GetIsInKnownSpellList(oPC, nClass, nSpellId)) return CSP_FAILED;
    return CSP_OK;
}
