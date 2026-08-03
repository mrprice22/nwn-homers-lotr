// bst_ondeath - wrapped creature OnDeath: record the kill, then chain original.
//
// Installed by bst_install. Credits every PC that dealt damage to the creature
// (gathered by bst_ondamage). Solo = exactly one PC contributor; Party = more
// than one. Sends each contributor a combat-log confirmation, and for hard
// creatures (CR >= BST_SF_CR) broadcasts a server-first kill. Recording happens
// BEFORE chaining the original handler so respawn/cleanup can't drop the count.

#include "bst_db"
#include "brd_db"

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

    // Slayer for the server-first record: the killing blow's owning PC, else the
    // first valid contributor (resolved in the loop below).
    object oSlayer = oKiller;

    for (i = 0; i < nN; i++)
    {
        object m = GetLocalObject(oCre, "bst_ctrb_" + IntToString(i));
        if (!GetIsObjectValid(m) || !GetIsPC(m) || GetIsDM(m)) continue;
        if (!GetIsObjectValid(oSlayer)) oSlayer = m;

        string sUuid = GetObjectUUID(m);
        Bst_RecordKill(sUuid, GetPCPublicCDKey(m), GetName(m), sCan, bParty);

        int nTotal = Bst_GetTotal(sUuid, sCan);
        SendMessageToPC(m, "[Bestiary] You have slain " + IntToString(nTotal) + " "
            + sCreName + (bParty ? " (Party)." : " (Solo)."));
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
                + "' (resref " + sCan + ", CR " + IntToString(FloatToInt(fCR))
                + ") by " + GetName(oSlayer)
                + ". Add it to the module or refresh the wiki catalogue.";
            WriteTimestampedLogEntry(sLog);
            SendMessageToAllDMs(sLog);
        }
    }

    // Server-first broadcast for hard creatures.
    if (fCR >= BST_SF_CR && GetIsObjectValid(oSlayer)
        && Bst_RegisterServerFirst(sCan, fCR, GetObjectUUID(oSlayer),
                                   GetName(oSlayer), GetPCPublicCDKey(oSlayer),
                                   GetPCPlayerName(oSlayer)))
    {
        string sMsg = "[SERVER FIRST] " + GetName(oSlayer)
            + (bParty ? "'s party" : "") + " has slain " + sCreName
            + " (CR " + IntToString(FloatToInt(fCR))
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
