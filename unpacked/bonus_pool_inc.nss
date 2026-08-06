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
const int    BPOOL_SRC_COUNT   = 5;

// Flat damage bonus the engine can express. IPGetDamageBonusConstantFromNumber
// clamps here too; above it the number simply cannot be represented.
const int BPOOL_DAMAGE_MAX = 20;

string BPool_SourceAt(int nIndex);
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
    }
    return "";
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

int BPool_Total(object oCreature, int nChannel)
{
    int nTotal = 0;
    int i;
    for (i = 0; i < BPOOL_SRC_COUNT; i++)
    {
        int n = GetLocalInt(oCreature, BPool_Var(nChannel, BPool_SourceAt(i)));
        if (n > 0) nTotal += n;
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
}

// Scheduled by BPool_Set. A refresh in the meantime bumped the generation, so
// this call is stale and must do nothing.
void BPool_Expire(object oCreature, int nChannel, string sSource, int nGen)
{
    if (GetLocalInt(oCreature, BPool_GenVar(nChannel, sSource)) != nGen) return;
    BPool_Clear(oCreature, nChannel, sSource);
}

// Rebuild both channels from the ledger. For anything that wipes effects out
// from under us without touching the ledger - a login, a polymorph - the pooled
// effect is a render and can always be redrawn.
void BPool_Resync(object oCreature)
{
    BPool_Rebuild(oCreature, BPOOL_CH_ATTACK);
    BPool_Rebuild(oCreature, BPOOL_CH_DAMAGE);
}
