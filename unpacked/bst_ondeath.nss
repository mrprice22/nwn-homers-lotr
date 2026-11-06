// bst_ondeath - wrapped creature OnDeath: record the kill, then chain original.
//
// Installed by bst_install. Credits every PC that dealt damage to the creature
// (gathered by bst_ondamage). Solo = exactly one PC contributor; Party = more
// than one. Sends each contributor a combat-log confirmation, and for hard
// creatures (CR >= BST_SF_CR) broadcasts a server-first kill. Recording happens
// BEFORE chaining the original handler so respawn/cleanup can't drop the count.

#include "bst_db"
#include "brd_db"
#include "ll_xp_inc"

// Walk the master chain to the owning PC; returns OBJECT_INVALID if none is a PC.
object Bst_OwningPC(object o)
{
    while (GetIsObjectValid(GetMaster(o))) o = GetMaster(o);
    if (GetIsPC(o) && !GetIsDM(o)) return o;
    return OBJECT_INVALID;
}

void main()
{
    object oCre     = OBJECT_SELF;
    string sCan     = Bst_Canonical(GetResRef(oCre));
    float  fCR      = GetChallengeRating(oCre);
    string sCreName = GetName(oCre);
    // A Loot Overhaul champion (loot_champion.nss) is the same creature on a good
    // day: it is counted - and named, and server-firsted - as its base creature,
    // and tallied in champ_kills too.  Its raised CR still pays the kill XP.
    int    bChamp   = GetLocalInt(oCre, "LOOT_CHAMP");
    float  fBaseCR  = fCR;
    if (bChamp)
    {
        sCreName = GetLocalString(oCre, "LOOT_CHAMP_NAME");
        fBaseCR  = GetLocalFloat(oCre, "LOOT_CHAMP_BASECR");
    }

    // A creature that is itself a PC's summon/associate (summoned monster from
    // any spell or feat, familiar, animal companion, henchman) is not a bestiary
    // target - its death is not a kill. Skip recording AND the uncatalogued log;
    // just chain the original handler. Enemy-summoned creatures have a non-PC
    // master, so Bst_OwningPC returns OBJECT_INVALID and they still count.
    if (GetIsObjectValid(Bst_OwningPC(oCre)))
    {
        string sOrigSummon = GetLocalString(oCre, "bst_orig_death");
        if (sOrigSummon != "") ExecuteScript(sOrigSummon, oCre);
        return;
    }

    // Roll of the Fallen (Well of Eru board): record a tracked boss's death
    // regardless of who lands the blow - the boss is gone either way. Reads the
    // bst_ctrb_N contributor locals for the "slain by" line; no-op otherwise.
    BRD_RecordDeath(oCre);

    int nN = GetLocalInt(oCre, "bst_ctrb_n");
    int i;

    // Always credit the killing blow's owning PC. bst_ondamage only records
    // contributors from OnDamaged, which can miss the killer (one-shot kills
    // where no non-lethal hit landed, or death via certain effects). Fold the
    // killer into the contributor list so the kill is still counted. Bst_OwningPC
    // walks the summon/henchman master chain and returns OBJECT_INVALID for
    // DMs/non-PCs, so the DM exclusion is preserved.
    object oKiller = Bst_OwningPC(GetLastKiller());
    if (GetIsObjectValid(oKiller))
    {
        int bSeen = FALSE;
        for (i = 0; i < nN; i++)
            if (GetLocalObject(oCre, "bst_ctrb_" + IntToString(i)) == oKiller)
            {
                bSeen = TRUE;
                break;
            }
        if (!bSeen)
        {
            SetLocalObject(oCre, "bst_ctrb_" + IntToString(nN), oKiller);
            nN++;
            SetLocalInt(oCre, "bst_ctrb_n", nN);
        }
    }

    // Count valid PC contributors (bst_ondamage list + the folded-in killer).
    int nValid = 0;
    for (i = 0; i < nN; i++)
    {
        object m = GetLocalObject(oCre, "bst_ctrb_" + IntToString(i));
        if (GetIsObjectValid(m) && GetIsPC(m) && !GetIsDM(m)) nValid++;
    }

    // No PC dealt the killing blow or any damage (trap, DM, environmental) ->
    // don't count; chain & exit.
    if (nValid == 0)
    {
        string sOrigNone = GetLocalString(oCre, "bst_orig_death");
        if (sOrigNone != "") ExecuteScript(sOrigNone, oCre);
        return;
    }

    int bParty = (nValid > 1);

    // Harvest of Shadows: a PC-credited kill may leave a pumpkin (no-op
    // outside the event window; never from a skeleton).
    ExecuteScript("hw_ondeath", oCre);

    // Slayer for the server-first record: the killing blow's owning PC, else the
    // first valid contributor (resolved in the loop below).
    object oSlayer = oKiller;

    for (i = 0; i < nN; i++)
    {
        object m = GetLocalObject(oCre, "bst_ctrb_" + IntToString(i));
        if (!GetIsObjectValid(m) || !GetIsPC(m) || GetIsDM(m)) continue;
        if (!GetIsObjectValid(oSlayer)) oSlayer = m;

        string sUuid = GetObjectUUID(m);
        Bst_RecordKill(sUuid, GetPCPublicCDKey(m), GetName(m), sCan, bParty, bChamp);

        // Legendary-tier kill XP (roadmap: ll-xp-award-balance). The engine pays
        // nothing above level 40 because xptable.2da was never extended, so 41+
        // characters are paid here instead. No-op at level 40 and below, where
        // the engine is still paying.
        //
        // This loop decides WHO is paid -- the damage contributors, with summons,
        // henchmen, DMs and environmental deaths already excluded above, so an
        // out-of-area party member neither collects nor dilutes. HOW MUCH is
        // LlXp_PartyMod's job: it reapplies the engine's own 1/N party split and
        // per-associate penalty, which used to stop at level 40 and made crossing
        // it pay MORE rather than less (roadmap: gwathdor-snakes, 2026-09-14).
        // That replaces the undivided per-contributor award of 2026-08-13.
        LlXp_GiveKillXP(m, fCR, oCre);

        int nTotal = Bst_GetTotal(sUuid, sCan);
        SendMessageToPC(m, "[Bestiary] You have slain " + IntToString(nTotal) + " "
            + sCreName + (bParty ? " (Party)" : " (Solo)")
            + (bChamp ? " - a champion!" : "."));
    }

    // Loot Overhaul Phase 4: rolled drops on the corpse. The beneficiary (Phase
    // 6's wishlist reads it) is a random valid contributor. ExecuteScript keeps
    // loot_inc and the generated loot tables out of this script's include tree.
    {
        int nPick = Random(nValid);
        int nSeen = 0;
        for (i = 0; i < nN; i++)
        {
            object m = GetLocalObject(oCre, "bst_ctrb_" + IntToString(i));
            if (!GetIsObjectValid(m) || !GetIsPC(m) || GetIsDM(m)) continue;
            if (nSeen++ == nPick)
            {
                SetLocalObject(oCre, "LOOT_BENEF", m);
                break;
            }
        }
        ExecuteScript("loot_ondeath", oCre);
    }

    // Uncatalogued kill: the creature was slain (and recorded above) but isn't in
    // the seeded catalogue, so it won't show in the in-game book / wiki "present"
    // list. Flag it for a DM to add it to the module or refresh the wiki. Logged
    // once per resref per server session to avoid spam.
    if (!Bst_InCatalogue(sCan))
    {
        object oMod = GetModule();
        string sGuard = "bst_uncat_" + sCan;
        if (!GetLocalInt(oMod, sGuard))
        {
            SetLocalInt(oMod, sGuard, 1);
            string sLog = "[Bestiary] Uncatalogued creature slain: '" + sCreName
                + "' (resref " + sCan + ", CR " + IntToString(FloatToInt(fBaseCR))
                + ") by " + GetName(oSlayer)
                + ". Add it to the module or refresh the wiki catalogue.";
            WriteTimestampedLogEntry(sLog);
            SendMessageToAllDMs(sLog);
        }
    }

    // Server-first broadcast for hard creatures.
    if (fBaseCR >= BST_SF_CR && GetIsObjectValid(oSlayer)
        && Bst_RegisterServerFirst(sCan, fBaseCR, GetObjectUUID(oSlayer),
                                   GetName(oSlayer), GetPCPublicCDKey(oSlayer),
                                   GetPCPlayerName(oSlayer)))
    {
        string sMsg = "[SERVER FIRST] " + GetName(oSlayer)
            + (bParty ? "'s party" : "") + " has slain " + sCreName
            + " (CR " + IntToString(FloatToInt(fBaseCR))
            + ") for the first time on the server!";
        object oP = GetFirstPC();
        while (GetIsObjectValid(oP))
        {
            SendMessageToPC(oP, sMsg);
            oP = GetNextPC();
        }
    }

    // Chain the creature's original OnDeath handler, if any.
    string sOrig = GetLocalString(oCre, "bst_orig_death");
    if (sOrig != "") ExecuteScript(sOrig, oCre);
}
