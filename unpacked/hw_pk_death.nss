// hw_pk_death - a pumpkin is smashed.
//
// Every pumpkin leaves Pumpkin Guts (the leaderboard currency). A town pumpkin
// is just a pumpkin. A cursed or boss-ring one bursts with a Power Word: Kill
// flash and lets out skeletons scaled to the area and to whoever broke it.
// A cursed pumpkin's DB row is deleted (it is gone for good); a boss-ring
// pumpkin records when it fell and grows back 30 minutes later.

#include "hw_inc"
#include "season_prof_inc"

object HW_OwnerPC(object o)
{
    while (GetIsObjectValid(GetMaster(o))) o = GetMaster(o);
    return GetIsPC(o) ? o : OBJECT_INVALID;
}

void main()
{
    object oPk   = OBJECT_SELF;
    // A placeable's OnDeath can fire more than once for one death (a single
    // blow carrying several damage types): a Bree town pumpkin paid 4 guts.
    // Everything below happens once.
    if (GetLocalInt(oPk, "hw_dead")) return;
    SetLocalInt(oPk, "hw_dead", 1);
    object oArea = GetArea(oPk);
    location l   = GetLocation(oPk);
    string sKind = GetLocalString(oPk, "hw_kind");
    if (sKind == "door") return;   // plot decoration; unreachable, but never pays
    int nTier    = GetLocalInt(oPk, "hw_tier");

    object oKiller = HW_OwnerPC(GetLastDamager(oPk));
    if (!GetIsObjectValid(oKiller)) oKiller = HW_OwnerPC(GetLastKiller());

    // Guts go straight into the party's packs - no clicking - and only while
    // the event runs (a stray pumpkin outside the window is worth nothing).
    int nGuts = 1;
    if (sKind == "boss")        nGuts = 3;
    else if (sKind == "cursed") nGuts = 1 + nTier / 2;
    if (HW_Phase() == HW_PHASE_ACTIVE)
        HW_GiveGuts(oKiller, l, nGuts);
    if (SP_DEV_TOOLS && GetIsObjectValid(oKiller))
        SendMessageToPC(oKiller, "[HW dev] " + sKind + " pumpkin (tier "
            + IntToString(nTier) + ") smashed: " + IntToString(nGuts) + " guts each");
    // The remains: a splatter of pulp, not a pickup.
    ApplyEffectAtLocation(DURATION_TYPE_INSTANT,
        EffectVisualEffect(VFX_COM_CHUNK_YELLOW_MEDIUM), l);

    if (sKind == "town")
    {
        HW_TownGone(oArea);
        return;
    }

    ApplyEffectAtLocation(DURATION_TYPE_INSTANT, EffectVisualEffect(VFX_FNF_PWKILL), l);
    HW_SpawnSkeletons(l, nTier, oKiller, sKind == "boss" ? 3 : 1 + Random(3));

    if (sKind == "cursed")
    {
        sqlquery q = SqlPrepareQueryCampaign(HW_DB, "DELETE FROM hw_pumpkin WHERE pkey=@k");
        SqlBindString(q, "@k", GetLocalString(oPk, "hw_key"));
        SqlStep(q);
    }
    else if (sKind == "boss")
    {
        int nSlot = GetLocalInt(oPk, "hw_slot");
        sqlquery q = SqlPrepareQueryCampaign(HW_DB,
            "INSERT INTO hw_bossring (slot, cleared_at) VALUES (@s, @t) " +
            "ON CONFLICT(slot) DO UPDATE SET cleared_at = @t");
        SqlBindInt(q, "@s", nSlot);
        SqlBindInt(q, "@t", HW_Now());
        SqlStep(q);
        AssignCommand(GetModule(),
            DelayCommand(IntToFloat(HW_BOSS_RESPAWN), HW_RespawnBossSlot(nSlot)));
    }
}
