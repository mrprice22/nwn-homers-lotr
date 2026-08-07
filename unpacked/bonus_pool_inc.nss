// bonus_pool_inc.nss - one attack-bonus and one damage-bonus ledger per creature.
//
// THE PROBLEM THIS EXISTS TO SOLVE
//
// Same-type attack-bonus EFFECTS do not stack in NWN: the engine applies the
// HIGHEST and discards the rest. Every attack bonus this module hands out went
// through EffectAttackIncrease with the default ATTACK_BONUS_MISC, so they all
// fought each other and only the biggest was ever felt:
//
//   * Legendary Prowess (+5, permanent) swallowed Bard Song entirely - at the
//     song's top tier singing moved attack by +1, and at every tier below +5 by
//     NOTHING. That is the bug Szescian82 reported (roadmap:
//     bard-legendary-prowess-conflict).
//   * Legendary Grip's +4 was worth exactly ZERO to any character who also took
//     Prowess - a whole half of a legendary feat, silently dead.
//   * Legendary Reaping's first two kill stacks did nothing for the same reason.
//
// Damage bonuses have the identical rule, where Bard Song and Reaping collided.
//
// THE FIX: A LEDGER, NOT AN EFFECT PER SOURCE
//
// Each source registers an AMOUNT under its own key. The ledger sums the live
// entries and applies ONE effect built from the total, so the sources stack in
// practice without arguing with the engine rule. This is the pattern
// legfeat_atk_inc.nss already ran for a single feat (a running total in a local
// int, a tagged effect stripped and rebuilt from it, generation counters for
// expiry), generalized to every source in the module.
//
// AN EFFECT'S MAGNITUDE CANNOT BE READ BACK, which is the whole reason the
// total lives in a local int: the effect is a render of the ledger, never the
// record itself. Strip and rebuild, every time.
//
// WHAT IS AND IS NOT POOLED
//
// Only sources the module itself owns. Stock spells (Bless, Aid, Prayer, Divine
// Favor) and item attack bonus stay engine-typed and still take max-of-two
// against the pooled total - this makes OUR sources stack with each other,
// which is what was asked for, and it does not rewrite the game's rule.
// tests/check_bonus_pool.py is the build gate: a new EffectAttackIncrease or
// EffectDamageIncrease in a module-owned script must come through here or be
// listed as a deliberate exemption. An unpooled bonus is invisible - it
// compiles, it runs, and it silently suppresses every pooled bonus smaller than
// itself.
//
// STORAGE IS LOCAL INTS, DELIBERATELY. Nothing needs to persist: effects do not
// survive a logout (see mod_cliententer.nss) and a PC's locals die with the
// object, so the ledger and the effects reset together - there is no stale
// ledger case. At login LegFeat_ApplyAll re-registers the permanent sources
// exactly as it rebuilds their effects today. Locals also work on NPCs,
// henchmen and summons, which a PC-keyed campaign DB would not, and Bard Song
// buffs allies of every kind.

const int BPOOL_CH_ATTACK = 0;
const int BPOOL_CH_DAMAGE = 1;

// One tag per channel. The pooled effect is the only effect wearing it, so
// stripping by tag can never catch someone else's work.
const string BPOOL_TAG_ATTACK = "BPOOL_AB";
const string BPOOL_TAG_DAMAGE = "BPOOL_DMG";

// SOURCE KEYS ARE A FIXED COMPILE-TIME LIST. NWScript cannot enumerate the
// local variables on an object, so the rebuild walks this list instead. Adding
// a source means adding a constant here AND a case to BPool_SourceAt - the
// build gate checks the count matches, because a source missing from the walk
// is a bonus that is stored and never applied.
const string BPOOL_SRC_PROWESS = "prow";   // Legendary Prowess,  permanent
const string BPOOL_SRC_GRIP    = "grip";   // Legendary Grip,     permanent, dual-wield
const string BPOOL_SRC_REAPING = "reap";   // Legendary Reaping,  12s, refreshing
const string BPOOL_SRC_SONG    = "song";   // Bard Song,          song duration
const string BPOOL_SRC_SUMMON  = "summ";   // summon/companion boost, permanent
// Buff SPELLS, all in the one 'spell' group below (attack channel only - see
// the group note). Added for the follow-up report spell-ab-prowess-stack:
// pooling the module's own sources still left every buff spell in the game
// reading as +0 to anyone carrying Legendary Prowess's permanent +5.
const string BPOOL_SRC_BLESS   = "bles";   // Bless,              spell duration
const string BPOOL_SRC_AID     = "aid_";   // Aid,                spell duration
const string BPOOL_SRC_PRAYER  = "pray";   // Prayer,             spell duration
const string BPOOL_SRC_WARCRY  = "wcry";   // War Cry,            spell duration
const string BPOOL_SRC_DIVFAV  = "dfav";   // Divine Favor,       spell duration
const string BPOOL_SRC_DIVPOW  = "dpow";   // Divine Power,       spell duration
const string BPOOL_SRC_DIVWRA  = "dwra";   // Divine Wrath,       ability duration
const int    BPOOL_SRC_COUNT   = 12;

// GROUPS: SOURCES IN THE SAME GROUP TAKE THE MAX, GROUPS SUM.
//
// The first build summed every entry, which is right for the module's own
// sources - a feat, a song and a kill streak are meant to add up. It is NOT
// right for the buff spells: Bless, Aid, Prayer and Divine Favor never stacked
// with each other in the engine and pooling them naively would have handed out
// a stacking rule D&D never had (a cleric self-buffing to +9 before any feat).
//
// So each spell keeps its own key - it has its own duration, its own witness
// and its own caster - but they all share ONE group, and the group contributes
// only its largest live entry. Between groups the totals add, which is what
// makes a spell felt on top of Legendary Prowess at last.
//
// Adding a source means adding a case to BPool_GroupAt as well as
// BPool_SourceAt; the build gate checks both walks.
const int BPOOL_GRP_PROWESS = 0;
const int BPOOL_GRP_GRIP    = 1;
const int BPOOL_GRP_REAPING = 2;
const int BPOOL_GRP_SONG    = 3;
const int BPOOL_GRP_SUMMON  = 4;
const int BPOOL_GRP_SPELL   = 5;   // every pooled buff spell shares this one
const int BPOOL_GRP_COUNT   = 6;

// Flat damage bonus the engine can express. IPGetDamageBonusConstantFromNumber
// clamps here too; above it the number simply cannot be represented.
const int BPOOL_DAMAGE_MAX = 20;

// THE LEDGER MUST RECALCULATE WHEN EFFECTS END, NOT ONLY WHEN THEY START.
//
// The first build only ever rebuilt on registration and at login, and UAT found
// both halves of what that misses:
//
//   * A bard song that ended early (death) left its share in the ledger, so the
//     attack bonus survived after the song icon was gone.
//   * A respawn (mod_respawn.nss calls RemoveEffects) stripped the pooled
//     effect, and nothing re-rendered it - so the PERMANENT feat bonuses
//     vanished too, until the next login.
//
// Both are answered by revalidation: a WITNESS decides whether a transient
// entry is still real, and the render is redrawn from whatever survives.
// bpool_eff.nss calls this on every effect removal (guarded); mod_respawn calls
// it after its wholesale strip.
const string BPOOL_LIVE    = "bpool_live";     // has >=1 entry: the hot-path guard
const string BPOOL_PENDING = "bpool_pending";  // a revalidate is already queued
const string BPOOL_BUSY    = "bpool_busy";     // we are mid-rebuild; ignore our own churn

// WITNESS SPELL IDS (spells.2da row numbers, verified against the game's own
// spells.2da rather than from memory). A transient entry is only as real as the
// spell effect that justifies it: if the creature no longer carries an effect
// from that spell - it ended, it was dispelled, the character died and
// everything was stripped - the entry goes with it. Sources with a witness of 0
// are permanent (the legendary feats, the summon boost) and are always
// re-rendered.
//
// Each pooled spell script keeps a non-attack effect in its link (the saving
// throw bonus, the duration VFX), so removing the attack effect from the link
// never leaves the witness with nothing to be.
const int BPOOL_SPELL_BARDSONG = 411;  // Bards_Song
const int BPOOL_SPELL_BLESS    = 6;    // Bless
const int BPOOL_SPELL_AID      = 1;    // Aid
const int BPOOL_SPELL_PRAYER   = 133;  // Prayer
const int BPOOL_SPELL_WARCRY   = 373;  // War_Cry
const int BPOOL_SPELL_DIVFAV   = 414;  // Divine_Favor
const int BPOOL_SPELL_DIVPOW   = 42;   // Divine_Power
const int BPOOL_SPELL_DIVWRA   = 622;  // DC_Divine_Wrath

string BPool_SourceAt(int nIndex);
int    BPool_GroupAt(int nIndex);
int    BPool_WitnessAt(int nIndex);
string BPool_Tag(int nChannel);
string BPool_Var(int nChannel, string sSource);
string BPool_GenVar(int nChannel, string sSource);
int    BPool_DamageConst(int nAmount);
int    BPool_Get(object oCreature, int nChannel, string sSource);
int    BPool_Total(object oCreature, int nChannel);
void   BPool_StripTag(object oCreature, string sTag);
void   BPool_Rebuild(object oCreature, int nChannel);
void   BPool_Set(object oCreature, int nChannel, string sSource, int nAmount,
                 float fDuration = 0.0);
void   BPool_Clear(object oCreature, int nChannel, string sSource);
void   BPool_Expire(object oCreature, int nChannel, string sSource, int nGen);
void   BPool_Resync(object oCreature);
void   BPool_UpdateLive(object oCreature);
void   BPool_Revalidate(object oCreature);
void   BPool_ClearTransient(object oCreature);
void   BPool_SpellAttack(object oCreature, string sSource, int nAmount,
                         float fDuration);

// The walk order of the ledger. Order is irrelevant to the sum; what matters is
// that every key in the constant list above appears exactly once.
string BPool_SourceAt(int nIndex)
{
    switch (nIndex)
    {
        case 0: return BPOOL_SRC_PROWESS;
        case 1: return BPOOL_SRC_GRIP;
        case 2: return BPOOL_SRC_REAPING;
        case 3: return BPOOL_SRC_SONG;
        case 4: return BPOOL_SRC_SUMMON;
        case 5: return BPOOL_SRC_BLESS;
        case 6: return BPOOL_SRC_AID;
        case 7: return BPOOL_SRC_PRAYER;
        case 8: return BPOOL_SRC_WARCRY;
        case 9: return BPOOL_SRC_DIVFAV;
        case 10: return BPOOL_SRC_DIVPOW;
        case 11: return BPOOL_SRC_DIVWRA;
    }
    return "";
}

// Which group each source contributes to. Same index space as BPool_SourceAt.
// Everything the module owns has a group to itself (they add up, as before);
// every buff spell shares BPOOL_GRP_SPELL, so they take the max among
// themselves and that best spell adds to the module's sources.
int BPool_GroupAt(int nIndex)
{
    switch (nIndex)
    {
        case 0: return BPOOL_GRP_PROWESS;
        case 1: return BPOOL_GRP_GRIP;
        case 2: return BPOOL_GRP_REAPING;
        case 3: return BPOOL_GRP_SONG;
        case 4: return BPOOL_GRP_SUMMON;
        case 5:
        case 6:
        case 7:
        case 8:
        case 9:
        case 10:
        case 11: return BPOOL_GRP_SPELL;
    }
    return BPOOL_GRP_SPELL;
}

// The spell whose presence keeps a transient entry alive, or 0 for a permanent
// source. Same index space again.
int BPool_WitnessAt(int nIndex)
{
    switch (nIndex)
    {
        case 3:  return BPOOL_SPELL_BARDSONG;
        case 5:  return BPOOL_SPELL_BLESS;
        case 6:  return BPOOL_SPELL_AID;
        case 7:  return BPOOL_SPELL_PRAYER;
        case 8:  return BPOOL_SPELL_WARCRY;
        case 9:  return BPOOL_SPELL_DIVFAV;
        case 10: return BPOOL_SPELL_DIVPOW;
        case 11: return BPOOL_SPELL_DIVWRA;
    }
    return 0;   // permanent: Prowess, Grip, the summon boost - and Reaping,
                // whose clock is its own 12s refresh, not an effect.
}

string BPool_Tag(int nChannel)
{
    return (nChannel == BPOOL_CH_DAMAGE) ? BPOOL_TAG_DAMAGE : BPOOL_TAG_ATTACK;
}

string BPool_Var(int nChannel, string sSource)
{
    return "bpool_" + IntToString(nChannel) + "_" + sSource;
}

string BPool_GenVar(int nChannel, string sSource)
{
    return "bpoolg_" + IntToString(nChannel) + "_" + sSource;
}

// Flat amount -> DAMAGE_BONUS_* constant.
//
// EffectDamageIncrease TAKES A CONSTANT, NOT A FLAT INT, and the two only agree
// up to 6: raw 7 is 1d6 and raw 10 is 2d6, so a naive int turns a promised flat
// bonus into dice. nw_s2_bardsong documented this trap and converted;
// legfeat_atk_inc did not, which is why Legendary Reaping's 4th and 5th kill
// stacks (+8, +10) were landing as dice. Routing every damage bonus through the
// ledger fixes that by construction - the conversion happens once, here, on the
// total.
//
// This mirrors IPGetDamageBonusConstantFromNumber (x2_inc_itemprop) rather than
// calling it: legfeat_atk_inc is included by devcrit_atk.nss, the server-wide
// attack handler, and that hot path should not drag a 1300-line include behind
// it.
int BPool_DamageConst(int nAmount)
{
    if (nAmount > BPOOL_DAMAGE_MAX) nAmount = BPOOL_DAMAGE_MAX;
    switch (nAmount)
    {
        case 1:  return DAMAGE_BONUS_1;
        case 2:  return DAMAGE_BONUS_2;
        case 3:  return DAMAGE_BONUS_3;
        case 4:  return DAMAGE_BONUS_4;
        case 5:  return DAMAGE_BONUS_5;
        case 6:  return DAMAGE_BONUS_6;
        case 7:  return DAMAGE_BONUS_7;
        case 8:  return DAMAGE_BONUS_8;
        case 9:  return DAMAGE_BONUS_9;
        case 10: return DAMAGE_BONUS_10;
        case 11: return DAMAGE_BONUS_11;
        case 12: return DAMAGE_BONUS_12;
        case 13: return DAMAGE_BONUS_13;
        case 14: return DAMAGE_BONUS_14;
        case 15: return DAMAGE_BONUS_15;
        case 16: return DAMAGE_BONUS_16;
        case 17: return DAMAGE_BONUS_17;
        case 18: return DAMAGE_BONUS_18;
        case 19: return DAMAGE_BONUS_19;
        case 20: return DAMAGE_BONUS_20;
    }
    return 0;
}

int BPool_Get(object oCreature, int nChannel, string sSource)
{
    return GetLocalInt(oCreature, BPool_Var(nChannel, sSource));
}

// GROUPS SUM; WITHIN A GROUP THE LARGEST ENTRY WINS.
//
// The inner walk is what preserves the engine's own rule between buff spells
// (Bless and Prayer give the better of the two, not both) while the outer sum
// is what makes that best spell add to Legendary Prowess instead of vanishing
// behind it.
int BPool_Total(object oCreature, int nChannel)
{
    int nTotal = 0;
    int nGroup;
    for (nGroup = 0; nGroup < BPOOL_GRP_COUNT; nGroup++)
    {
        int nBest = 0;
        int i;
        for (i = 0; i < BPOOL_SRC_COUNT; i++)
        {
            if (BPool_GroupAt(i) != nGroup) continue;
            int n = GetLocalInt(oCreature, BPool_Var(nChannel, BPool_SourceAt(i)));
            if (n > nBest) nBest = n;
        }
        nTotal += nBest;
    }
    return nTotal;
}

void BPool_StripTag(object oCreature, string sTag)
{
    effect e = GetFirstEffect(oCreature);
    while (GetIsEffectValid(e))
    {
        if (GetEffectTag(e) == sTag) RemoveEffect(oCreature, e);
        e = GetNextEffect(oCreature);
    }
}

// Render the ledger: one effect carrying the sum of every live entry.
//
// PERMANENT and SUPERNATURAL on purpose. One effect has to stand in for sources
// with different remaining durations, so it cannot carry a duration of its own -
// expiry is the ledger's job (BPool_Expire), not the engine's. Supernatural so
// it is not stripped by rest or dispel while entries are still live; the cost
// is that dispelling a bard song no longer removes its share, which the ledger's
// timer does instead.
void BPool_Rebuild(object oCreature, int nChannel)
{
    string sTag = BPool_Tag(nChannel);

    // Stripping our own effect fires NWNX_ON_EFFECT_REMOVED_AFTER, which is
    // wired to bpool_eff -> BPool_Revalidate -> back in here. Without this flag
    // that is an endless loop, every rebuild scheduling the next one. The flag
    // is cleared on the next frame, which is also after the ApplyEffect below.
    SetLocalInt(oCreature, BPOOL_BUSY, TRUE);
    DelayCommand(0.0, DeleteLocalInt(oCreature, BPOOL_BUSY));

    BPool_StripTag(oCreature, sTag);

    int nTotal = BPool_Total(oCreature, nChannel);
    if (nTotal <= 0) return;

    effect e;
    if (nChannel == BPOOL_CH_DAMAGE)
    {
        // Bludgeoning is what both damage sources already used. A pooled total
        // has to pick ONE type, and picking the one already in play changes no
        // damage-reduction interaction that was not already there.
        int nConst = BPool_DamageConst(nTotal);
        if (nConst == 0) return;
        e = EffectDamageIncrease(nConst, DAMAGE_TYPE_BLUDGEONING);
    }
    else
    {
        e = EffectAttackIncrease(nTotal);
    }

    e = SupernaturalEffect(TagEffect(e, sTag));
    ApplyEffectToObject(DURATION_TYPE_PERMANENT, e, oCreature);
}

// Register (or refresh) one source's contribution.
//
// fDuration 0.0 means "until cleared" - the permanent sources (legendary feats,
// the summon boost), which are cleared by a respec or rebuilt at login.
//
// GENERATION COUNTERS are what make a refreshing source safe: each call bumps
// the counter and schedules its expiry with the generation it saw, so an older
// scheduled expiry becomes a no-op. Without that, a second kill's 12 seconds
// would be cut short by the first kill's expiry - the exact bug
// LegFeatAtk_ExpireStack was written to avoid.
void BPool_Set(object oCreature, int nChannel, string sSource, int nAmount,
               float fDuration = 0.0)
{
    if (!GetIsObjectValid(oCreature)) return;

    if (nAmount <= 0)
    {
        BPool_Clear(oCreature, nChannel, sSource);
        return;
    }

    SetLocalInt(oCreature, BPool_Var(nChannel, sSource), nAmount);
    SetLocalInt(oCreature, BPOOL_LIVE, TRUE);

    int nGen = GetLocalInt(oCreature, BPool_GenVar(nChannel, sSource)) + 1;
    SetLocalInt(oCreature, BPool_GenVar(nChannel, sSource), nGen);

    BPool_Rebuild(oCreature, nChannel);

    if (fDuration > 0.0)
        DelayCommand(fDuration,
                     BPool_Expire(oCreature, nChannel, sSource, nGen));
}

void BPool_Clear(object oCreature, int nChannel, string sSource)
{
    if (!GetIsObjectValid(oCreature)) return;
    DeleteLocalInt(oCreature, BPool_Var(nChannel, sSource));
    BPool_Rebuild(oCreature, nChannel);
    BPool_UpdateLive(oCreature);
}

// The hot-path guard bpool_eff reads on every effect removal on the server.
// Set while this creature carries any entry at all, deleted the moment it does
// not, so a creature that has never been buffed costs one GetLocalInt.
void BPool_UpdateLive(object oCreature)
{
    if (BPool_Total(oCreature, BPOOL_CH_ATTACK) > 0
        || BPool_Total(oCreature, BPOOL_CH_DAMAGE) > 0)
        SetLocalInt(oCreature, BPOOL_LIVE, TRUE);
    else
        DeleteLocalInt(oCreature, BPOOL_LIVE);
}

// Recalculate after something ended - the answer to "the song is over but I
// still have its attack bonus" AND to "I respawned and lost my feat bonus".
//
// A transient source is only as real as its WITNESS. Bard Song's witness is the
// song's own effect: if that is gone (it ended, it was dispelled, the character
// died and everything was stripped), the entry goes with it. Sources with no
// witness are permanent and simply get re-rendered, which is what puts the
// legendary feats back after a wholesale RemoveEffects.
void BPool_Revalidate(object oCreature)
{
    DeleteLocalInt(oCreature, BPOOL_PENDING);
    if (!GetIsObjectValid(oCreature)) return;

    int i;
    for (i = 0; i < BPOOL_SRC_COUNT; i++)
    {
        int nSpell = BPool_WitnessAt(i);
        if (nSpell == 0) continue;                            // permanent
        if (GetHasSpellEffect(nSpell, oCreature)) continue;   // still real
        string sSource = BPool_SourceAt(i);
        DeleteLocalInt(oCreature, BPool_Var(BPOOL_CH_ATTACK, sSource));
        DeleteLocalInt(oCreature, BPool_Var(BPOOL_CH_DAMAGE, sSource));
    }

    BPool_Resync(oCreature);
    BPool_UpdateLive(oCreature);
}

// Drop every non-permanent entry outright. Death is the one event where a
// transient bonus should not come back on its own merits: a kill streak
// (Legendary Reaping) has to end when the killer dies, witness or no witness.
void BPool_ClearTransient(object oCreature)
{
    // Everything with a witness (the song, every buff spell) plus Reaping,
    // whose kill streak has to end with the killer and has no witness effect
    // to lose. The permanent sources are left alone: BPool_Resync below is
    // exactly what puts the legendary feats back after the wholesale strip.
    int i;
    for (i = 0; i < BPOOL_SRC_COUNT; i++)
    {
        string sSource = BPool_SourceAt(i);
        if (BPool_WitnessAt(i) == 0 && sSource != BPOOL_SRC_REAPING) continue;
        DeleteLocalInt(oCreature, BPool_Var(BPOOL_CH_ATTACK, sSource));
        DeleteLocalInt(oCreature, BPool_Var(BPOOL_CH_DAMAGE, sSource));
    }
    BPool_Resync(oCreature);
    BPool_UpdateLive(oCreature);
}

// Scheduled by BPool_Set. A refresh in the meantime bumped the generation, so
// this call is stale and must do nothing.
void BPool_Expire(object oCreature, int nChannel, string sSource, int nGen)
{
    if (GetLocalInt(oCreature, BPool_GenVar(nChannel, sSource)) != nGen) return;
    BPool_Clear(oCreature, nChannel, sSource);
}

// The one call every pooled buff spell makes, so the seven overridden spell
// scripts cannot drift apart on the details.
//
// THE TIMER IS A BACKSTOP, NOT THE CLOCK - the same rule Bard Song follows.
// eff_dur_x2 doubles the duration of every temporary effect a player applies,
// so the spell on the character really lasts longer than the duration its own
// script asks for, and a 1x timer would drop the attack bonus halfway through a
// buff that is visibly still running. The entry really ends when the spell's
// own effect does, which BPool_Revalidate sees through the witness; 3x exists
// only so a missed removal event cannot strand a bonus forever.
//
// ATTACK CHANNEL ONLY, deliberately. These spells' DAMAGE bonuses carry real
// damage types (slashing, magical, divine) and effects of different damage
// types already stack in the engine, so there is nothing to fix there - and
// pooling them would flatten those types into the pool's bludgeoning and change
// what damage reduction eats.
void BPool_SpellAttack(object oCreature, string sSource, int nAmount,
                       float fDuration)
{
    if (nAmount <= 0) return;
    BPool_Set(oCreature, BPOOL_CH_ATTACK, sSource, nAmount, fDuration * 3.0);
}

// Rebuild both channels from the ledger. For anything that wipes effects out
// from under us without touching the ledger - a login, a polymorph - the pooled
// effect is a render and can always be redrawn.
void BPool_Resync(object oCreature)
{
    BPool_Rebuild(oCreature, BPOOL_CH_ATTACK);
    BPool_Rebuild(oCreature, BPOOL_CH_DAMAGE);
}
