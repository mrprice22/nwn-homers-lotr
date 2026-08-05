// pw_inc.nss - Concerning Pipeweed: the rest-persistent pipe-weed high.
// (roadmap: concerning-pipeweed)
//
// Five strains of Shire leaf, smoked at the water pipes of the Smoking
// Chamber (area024). Each strain is a trade: a real gift and a real penalty,
// for one FULL HOUR OF REAL TIME. The whole point of the item is that the
// penalty is not free -- so the high must survive a rest.
//
// Why this is not just ApplyEffectToObject:
//   Plain DURATION_TYPE_TEMPORARY effects are scrubbed by the engine's rest
//   pass. A player could smoke Old Toby (WIS +4 / CHA -4), rest, and keep
//   nothing at all -- or, worse, arrange to keep only the half they liked.
//   So the authoritative state is a stored (strain, expiry) pair and the
//   effects are merely a *projection* of it, re-derived on every boundary
//   where the engine might have wiped them (rest finish, client enter).
//
// Storage - campaign DB "pipeweeddb", NOT PC locals:
//   Locals die with the server process. A pipe costs up to 1200 gp and lasts
//   a real hour, so a reboot 10 minutes in would silently refund the penalty
//   and burn the purchase -- exactly the "penalty is half free" bug this
//   exists to kill. A campaign row keyed on GetObjectUUID (the same identity
//   key quest_cd_inc and the bestiary use) survives reboots, relogs and
//   character transfers between them. Locals PW_STRAIN / PW_EXPIRY are still
//   mirrored on the PC as a cheap read for other systems (e.g. NPCs noticing
//   the state you are in) -- the DB is the source of truth.
//
//   Schema: pipeweed(uuid PK, strain, expires_at, cdkey, char_name)
//   Time is real-world unix epoch from SQLite, never the game clock: an
//   in-game hour is about two real minutes at the default clock.
//
// One strain at a time. Lighting a second pipe strips the first strain's
// effects before applying the new ones -- no stacking, no mixing.
//
// Consumers: wg_bong.nss (the water pipes), on_mod_rest.nss (REST_FINISHED
// reapply), mod_cliententer.nss (login reapply), onmoduleload.nss (schema).

#include "color"

const string PW_DB         = "pipeweeddb";
const string PW_EFFECT_TAG = "PW_STRAIN_EFF";  // marks every effect we own
const int    PW_DURATION   = 3600;             // one real hour, in seconds

// Strain ids. These are the values stored in the DB and in PW_STRAIN; they
// are deliberately not the item tags, so a retag never orphans live state.
const string PW_LONGBOTTOM = "longbottom";
const string PW_OLDTOBY    = "oldtoby";
const string PW_SOUTHLINCH = "southlinch";
const string PW_HORNBLOWER = "hornblower";
const string PW_WITCHWEED  = "witchweed";

// ------------------------------------------------------------
// Schema + clock

void PW_InitDb()
{
    sqlquery q = SqlPrepareQueryCampaign(PW_DB,
        "CREATE TABLE IF NOT EXISTS pipeweed (" +
        "uuid TEXT NOT NULL PRIMARY KEY," +
        "strain TEXT NOT NULL," +
        "expires_at INTEGER NOT NULL," +
        "cdkey TEXT," +
        "char_name TEXT)");
    SqlStep(q);
}

// Real-world "now" as unix-epoch seconds (from SQLite, not the game clock).
int PW_Now()
{
    sqlquery q = SqlPrepareQueryCampaign(PW_DB,
        "SELECT CAST(strftime('%s','now') AS INTEGER)");
    return SqlStep(q) ? SqlGetInt(q, 0) : 0;
}

// ------------------------------------------------------------
// Strain metadata

// Item tag -> strain id. "witchbud" is the legacy tag handed out by
// QHOB_PayOut (Concerning Hobbits) and carried by the old witchbud.uti
// blueprint; it lights as Longbottom Leaf so no old pouch is ever stranded.
string PW_StrainForItemTag(string sTag)
{
    if (sTag == "pw_longbottom" || sTag == "witchbud") return PW_LONGBOTTOM;
    if (sTag == "pw_oldtoby")    return PW_OLDTOBY;
    if (sTag == "pw_southlinch") return PW_SOUTHLINCH;
    if (sTag == "pw_hornblower") return PW_HORNBLOWER;
    if (sTag == "pw_witchweed")  return PW_WITCHWEED;
    return "";
}

string PW_StrainName(string sStrain)
{
    if (sStrain == PW_LONGBOTTOM) return "Longbottom Leaf";
    if (sStrain == PW_OLDTOBY)    return "Old Toby";
    if (sStrain == PW_SOUTHLINCH) return "Southlinch";
    if (sStrain == PW_HORNBLOWER) return "Hornblower's Garden";
    if (sStrain == PW_WITCHWEED)  return "Witch Weed";
    return "pipe-weed";
}

// One-line summary of the trade, for the message the smoker gets.
string PW_StrainBlurb(string sStrain)
{
    if (sStrain == PW_LONGBOTTOM)
        return "Wisdom +4, Intelligence -2, Spot and Listen +5";
    if (sStrain == PW_OLDTOBY)
        return "Wisdom +4, Charisma -4, Lore +10";
    if (sStrain == PW_SOUTHLINCH)
        return "Charisma +4, Wisdom -4, Persuade +10";
    if (sStrain == PW_HORNBLOWER)
        return "Constitution +4, Dexterity -2, +2 on saves against fear";
    if (sStrain == PW_WITCHWEED)
        return "Intelligence +4, Wisdom -4";
    return "";
}

// ------------------------------------------------------------
// Effects. Every effect we apply is tagged PW_EFFECT_TAG so PW_StripEffects
// can take back exactly ours and nothing else.

void PW_ApplyOne(object oPC, effect e, float fDur)
{
    ApplyEffectToObject(DURATION_TYPE_TEMPORARY,
        TagEffect(e, PW_EFFECT_TAG), oPC, fDur);
}

void PW_ApplyEffects(object oPC, string sStrain, float fDur)
{
    if (fDur <= 0.0) return;

    if (sStrain == PW_LONGBOTTOM)
    {
        PW_ApplyOne(oPC, EffectAbilityIncrease(ABILITY_WISDOM, 4), fDur);
        PW_ApplyOne(oPC, EffectAbilityDecrease(ABILITY_INTELLIGENCE, 2), fDur);
        PW_ApplyOne(oPC, EffectSkillIncrease(SKILL_SPOT, 5), fDur);
        PW_ApplyOne(oPC, EffectSkillIncrease(SKILL_LISTEN, 5), fDur);
    }
    else if (sStrain == PW_OLDTOBY)
    {
        PW_ApplyOne(oPC, EffectAbilityIncrease(ABILITY_WISDOM, 4), fDur);
        PW_ApplyOne(oPC, EffectAbilityDecrease(ABILITY_CHARISMA, 4), fDur);
        PW_ApplyOne(oPC, EffectSkillIncrease(SKILL_LORE, 10), fDur);
    }
    else if (sStrain == PW_SOUTHLINCH)
    {
        PW_ApplyOne(oPC, EffectAbilityIncrease(ABILITY_CHARISMA, 4), fDur);
        PW_ApplyOne(oPC, EffectAbilityDecrease(ABILITY_WISDOM, 4), fDur);
        PW_ApplyOne(oPC, EffectSkillIncrease(SKILL_PERSUADE, 10), fDur);
    }
    else if (sStrain == PW_HORNBLOWER)
    {
        PW_ApplyOne(oPC, EffectAbilityIncrease(ABILITY_CONSTITUTION, 4), fDur);
        PW_ApplyOne(oPC, EffectAbilityDecrease(ABILITY_DEXTERITY, 2), fDur);
        PW_ApplyOne(oPC, EffectSavingThrowIncrease(SAVING_THROW_ALL, 2,
                        SAVING_THROW_TYPE_FEAR), fDur);
    }
    else if (sStrain == PW_WITCHWEED)
    {
        PW_ApplyOne(oPC, EffectAbilityIncrease(ABILITY_INTELLIGENCE, 4), fDur);
        PW_ApplyOne(oPC, EffectAbilityDecrease(ABILITY_WISDOM, 4), fDur);
    }
}

// Take back every effect we own, and only those.
void PW_StripEffects(object oPC)
{
    effect e = GetFirstEffect(oPC);
    while (GetIsEffectValid(e))
    {
        if (GetEffectTag(e) == PW_EFFECT_TAG) RemoveEffect(oPC, e);
        e = GetNextEffect(oPC);
    }
}

// ------------------------------------------------------------
// Persistent state

void PW_Store(object oPC, string sStrain, int nExpiry)
{
    sqlquery q = SqlPrepareQueryCampaign(PW_DB,
        "INSERT INTO pipeweed(uuid,strain,expires_at,cdkey,char_name)" +
        " VALUES(@u,@s,@e,@k,@n)" +
        " ON CONFLICT(uuid) DO UPDATE SET" +
        " strain=excluded.strain," +
        " expires_at=excluded.expires_at," +
        " cdkey=excluded.cdkey," +
        " char_name=excluded.char_name");
    SqlBindString(q, "@u", GetObjectUUID(oPC));
    SqlBindString(q, "@s", sStrain);
    SqlBindInt(q,    "@e", nExpiry);
    SqlBindString(q, "@k", GetPCPublicCDKey(oPC));
    SqlBindString(q, "@n", GetName(oPC));
    SqlStep(q);

    SetLocalString(oPC, "PW_STRAIN", sStrain);
    SetLocalInt(oPC, "PW_EXPIRY", nExpiry);
}

void PW_Forget(object oPC)
{
    sqlquery q = SqlPrepareQueryCampaign(PW_DB,
        "DELETE FROM pipeweed WHERE uuid=@u");
    SqlBindString(q, "@u", GetObjectUUID(oPC));
    SqlStep(q);

    DeleteLocalString(oPC, "PW_STRAIN");
    DeleteLocalInt(oPC, "PW_EXPIRY");
}

// Stored expiry (unix epoch), 0 if this character has no row.
int PW_Expiry(object oPC)
{
    sqlquery q = SqlPrepareQueryCampaign(PW_DB,
        "SELECT expires_at FROM pipeweed WHERE uuid=@u");
    SqlBindString(q, "@u", GetObjectUUID(oPC));
    return SqlStep(q) ? SqlGetInt(q, 0) : 0;
}

// Stored strain id, "" if this character has no row.
string PW_StoredStrain(object oPC)
{
    sqlquery q = SqlPrepareQueryCampaign(PW_DB,
        "SELECT strain FROM pipeweed WHERE uuid=@u");
    SqlBindString(q, "@u", GetObjectUUID(oPC));
    return SqlStep(q) ? SqlGetString(q, 0) : "";
}

// The strain oPC is currently under, or "" if none / expired. Side-effect
// free apart from clearing a row that has run out.
string PW_ActiveStrain(object oPC)
{
    if (!GetIsPC(oPC)) return "";
    string sStrain = PW_StoredStrain(oPC);
    if (sStrain == "") return "";
    if (PW_Expiry(oPC) <= PW_Now())
    {
        PW_Forget(oPC);
        return "";
    }
    return sStrain;
}

// ------------------------------------------------------------
// The two operations the rest of the module calls.

// Light a pipe: clear whatever was riding, store the new strain for a real
// hour, apply its effects, and tell the smoker what the trade is.
void PW_Light(object oPC, string sStrain)
{
    if (!GetIsPC(oPC) || sStrain == "") return;

    PW_StripEffects(oPC);

    int nExpiry = PW_Now() + PW_DURATION;
    PW_Store(oPC, sStrain, nExpiry);
    PW_ApplyEffects(oPC, sStrain, IntToFloat(PW_DURATION));

    SendMessageToPC(oPC, ColorString(
        "The smoke of " + PW_StrainName(sStrain)
        + " settles on you for one hour, and resting will not shake it: "
        + PW_StrainBlurb(sStrain) + ".", COLOR_GREEN));
}

// Re-derive the effects from the stored state. Call at every boundary where
// the engine may have wiped them: rest finish and client enter. Cheap and
// idempotent -- a character with no row does one SELECT and returns.
void PW_Refresh(object oPC)
{
    if (!GetIsPC(oPC)) return;

    string sStrain = PW_StoredStrain(oPC);
    if (sStrain == "")
    {
        DeleteLocalString(oPC, "PW_STRAIN");
        DeleteLocalInt(oPC, "PW_EXPIRY");
        return;
    }

    int nExpiry = PW_Expiry(oPC);
    int nLeft   = nExpiry - PW_Now();
    if (nLeft <= 0)
    {
        PW_StripEffects(oPC);
        PW_Forget(oPC);
        return;
    }

    SetLocalString(oPC, "PW_STRAIN", sStrain);
    SetLocalInt(oPC, "PW_EXPIRY", nExpiry);

    PW_StripEffects(oPC);
    PW_ApplyEffects(oPC, sStrain, IntToFloat(nLeft));
}
