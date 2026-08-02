// mod_cliententer — the module's Mod_OnClientEntr handler.
//
// Split out of hgll_cliententer.nss (roadmap: ll-hgll-split-cliententer). That
// script carried the whole login flow under the retired legendary leveler's
// name; everything here is ordinary module login wiring — merit, bestiary,
// teleports, faction allegiance, XP boosts, server-info journals, the death
// amulet / bleeding-out resolution, the build stamp and the contraband sweep.
//
// The leveler itself was deleted in full (roadmap: ll-hgll-remove-scripts), so
// nothing here calls into it any more. Levels 41-60 are ordinary levels on
// hak_2da/exptable.2da.

#include "pers_state_inc"
#include "merit_db"
#include "bst_db"
#include "forge_inc"
#include "tele_db"
#include "boost_db"
#include "q_frk_inc"
#include "faction_db"
#include "nextlvl_inc"
#include "legfeat_inc"
#include "color"

// Legendary feats: re-derive the allotment (which revokes picks a relevel or a
// lost level has invalidated) and nudge if any are left to spend.
void LegFeatLoginCheck(object oPC)
{
    int nRemaining = LegFeat_EnsureAllotment(oPC);
    if (nRemaining <= 0) return;
    SendMessageToPC(oPC, ColorString("You have " + IntToString(nRemaining)
        + " legendary feat pick" + ((nRemaining == 1) ? "" : "s")
        + " to spend. Force Rest to choose.", COLOR_GREEN));
}

// Death amulet check + persistent state restore. Delayed so the engine's
// own post-login passes (inventory hydration, spellbook sync, "fresh PC"
// HP/spell resets) have settled before we read or override state.
void ModPostEnter(object oPC)
{
    object oItem = GetFirstItemInInventory(oPC);
    while (GetIsObjectValid(oItem))
    {
        if (GetTag(oItem) == "deathamulet")
        {
            ApplyEffectToObject(DURATION_TYPE_INSTANT, EffectDeath(FALSE, FALSE), oPC);
            return;
        }
        oItem = GetNextItemInInventory(oPC);
    }

    // Bleeding-out login resolution: HP was saved as 0 to -9 (dying state).
    // Roll Con save DC 12 — pass returns player at 2 HP, fail kills them.
    if (NWNX_Object_GetInt(oPC, PERS_HP_VALID) == 1)
    {
        int nSaved = NWNX_Object_GetInt(oPC, PERS_HP);
        if (nSaved >= -9 && nSaved <= 0)
        {
            int nConMod = GetAbilityModifier(ABILITY_CONSTITUTION, oPC);
            int nRoll   = d20(1);
            int nTotal  = nRoll + nConMod;
            string sMsg = "You logged out while bleeding out (HP: "
                + IntToString(nSaved) + "). Constitution survival check DC 12 — "
                + "rolled " + IntToString(nRoll)
                + " + CON " + IntToString(nConMod)
                + " = " + IntToString(nTotal) + ". ";
            if (nTotal >= 12)
            {
                SendMessageToPC(oPC, sMsg + "You cling to life! (2 HP)");
                PersState_Restore(oPC);
                NWNX_Object_SetCurrentHitPoints(oPC, 2);
                NWNX_Player_UpdateCharacterSheet(oPC);
            }
            else
            {
                SendMessageToPC(oPC, sMsg + "You succumb to your wounds.");
                ApplyEffectToObject(DURATION_TYPE_INSTANT, EffectDeath(FALSE, FALSE), oPC);
            }
            return;
        }
    }

    PersState_Restore(oPC);
}

void main()
{
    object oPC = GetEnteringObject();

    Merit_InitDb();
    Merit_RecordLogin(oPC);
    DelayCommand(3.0, Merit_LoginMessage(oPC));

    // Bestiary kill-tracking: ensure the DB exists and force this character's
    // persistent UUID (stored in the .bic) to be generated, since it is the
    // per-character identity key for all kill records.
    Bst_InitDb();
    GetObjectUUID(oPC);

    // Rest-menu teleport unlocks (merit redemptions 101-107): ensure the
    // saved-slot / return-state tables exist.
    Tele_InitDb();

    // Faction allegiance re-apply (roadmap: faction-scaffolding): restore the
    // Good/Evil allegiance this character chose (and thus the hostile-on-sight
    // reputation against the enemy side) from factiondb. No-op for characters
    // that never picked a side. Delayed so the anchor NPCs and the PC's
    // reputation tables are settled before we AdjustReputation.
    Faction_InitDb();
    DelayCommand(4.5, Faction_ApplyLive(oPC));

    // Premium 2x gold/XP boosts (merit redemptions 201-204): ensure the tables
    // exist, then report any active/pending server + personal subscriptions —
    // who bought each and the estimated end date. Delayed past the login flood.
    Boost_InitDb();
    DelayCommand(4.0, Boost_LoginReport(oPC));

    // Server-info reference journals (Rules/Guilds/Website). Each category's
    // entry 1 has End=1, so these land in the player's Completed section.
    // AddJournalQuestEntry is idempotent (re-adding the same state just resets
    // it), so we deliver unconditionally on every login — this reaches existing
    // characters too, not just first-time logins. mod_enter.nss (the old, never-
    // wired delivery, which also had a "gguild" tag typo) is bypassed entirely.
    AddJournalQuestEntry("rules",        1, oPC, FALSE, FALSE);
    // "guilds" is deliberately NOT delivered: the guild system is retired/
    // suspended (admin call, 2026-07-15). Re-add it here if guilds return.
    AddJournalQuestEntry("website",      1, oPC, FALSE, FALSE);
    AddJournalQuestEntry("modcustoms",   1, oPC, FALSE, FALSE);
    AddJournalQuestEntry("mod_progress", 1, oPC, FALSE, FALSE);
    AddJournalQuestEntry("mod_death",    1, oPC, FALSE, FALSE);
    AddJournalQuestEntry("mod_forge",    1, oPC, FALSE, FALSE);
    AddJournalQuestEntry("mod_systems",  1, oPC, FALSE, FALSE);
    AddJournalQuestEntry("mod_factions", 1, oPC, FALSE, FALSE);
    AddJournalQuestEntry("mod_combat",   1, oPC, FALSE, FALSE);

    // The Forbidden Realms: characters who stole the Forbidden Realms Key from
    // Summanus before the tier shipped never saw an OnAcquireItem for it, so
    // catch them up here. Idempotent and a no-op without the key; delayed so
    // the inventory is hydrated before we scan it.
    DelayCommand(7.0, FRK_LoginCheck(oPC));

    DelayCommand(1.0, ModPostEnter(oPC));

    // Character sheet "Next Level:" fix for levels 40-60 — the NWNX MaxLevel
    // plugin leaves the engine's figure wrong past 40, so we override strref
    // 315 with the real requirement from exptable.2da (nextlvl_inc.nss).
    // Delayed so the player is fully connected before the override is sent;
    // nextlvl_evt.nss keeps it current on every level up / level down.
    DelayCommand(2.0, NextLevel_FixTlk(oPC));

    // Build stamp: nwn-manager generates "nwnmgr_bstamp" at repack with the module's
    // last-edited timestamp + git revision. Resolved at runtime, so it safely no-ops
    // in dev builds where the script isn't packed. Delayed so it lands after the
    // login flood and the merit login message (3s).
    DelayCommand(5.0, ExecuteScript("nwnmgr_bstamp", oPC));

    // Contraband sweep: illegally forged gear jails the bearer on login too,
    // so skipping the Well of Eru doesn't dodge the check. Delayed so the
    // inventory is fully hydrated before we scan it. Chunked (one item per
    // delayed step) to stay under the script instruction cap.
    DelayCommand(6.0, ForgeBeginScan(oPC));

    // Legendary feats, three jobs on login, all delayed past the login flood:
    //
    //  * LegFeat_ApplyAll rebuilds EFFECT-kind bonuses, which do not survive a
    //    logout. It also strips any stale LEGFEAT_EFF effect, which is what
    //    cleans the old buff-style ability bonuses off characters granted feats
    //    by the first build. Base-score (RAW) feats are deliberately NOT
    //    re-applied — their bonus is already in the .bic.
    //  * LegFeat_EnsureAllotment re-derives the entitlement, so a relevel or a
    //    death-loss level is caught even if no level event fired for us. It is
    //    also what revokes picks the character no longer qualifies for.
    //  * The nudge tells a level-60 character with unspent picks how to spend
    //    them. A popup on every login would be intrusive; resting opens one.
    DelayCommand(6.5, LegFeat_ApplyAll(oPC));
    DelayCommand(7.5, LegFeatLoginCheck(oPC));
}
