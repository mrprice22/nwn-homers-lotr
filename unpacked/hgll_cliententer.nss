// hgll_cliententer — NWNX:EE port
//
// Originally cleared a queued Letoscript string left over from logout (the
// NWNX2 plugin replayed it on next login). NWNX:EE applies HGLL changes
// in-memory at the moment they happen, so there's nothing to replay.
// We still wipe the legacy locals in case they're hanging around on
// pre-port characters.

#include "pers_state_inc"

// Death amulet check + persistent state restore. Delayed so the engine's
// own post-login passes (inventory hydration, spellbook sync, "fresh PC"
// HP/spell resets) have settled before we read or override state.
void HgllPostEnter(object oPC)
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
    SetLocalString(oPC, "LetoScript", "");
    SetLocalString(oPC, "LetoscriptLL", "");

    DelayCommand(1.0, HgllPostEnter(oPC));
}
