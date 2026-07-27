//::///////////////////////////////////////////////
//:: nextlvl_inc
//:: "Next Level" XP display fix for levels 40 - 60.
//::
//:: The NWNX MaxLevel plugin (the lever behind levels 41-60) has a known
//:: upstream bug: from level 40 up, the character sheet's "Next Level:" figure
//:: is wrong -- the engine keeps extrapolating its own hardcoded curve instead
//:: of reading exptable.2da. Everything else works; it is the number on the
//:: sheet that lies, which is exactly the thing levels 41-60 promised to fix.
//::
//:: The documented workaround (NWNX:EE MaxLevel readme) is a per-player TLK
//:: override on strref 315, "Next Level". The character sheet renders that
//:: strref followed by the engine's value, so an override of
//::
//::     "Next Level: 828800\n"
//::
//:: prints the correct number and pushes the engine's wrong one onto a second
//:: line, out of the field's view. The override is per player, so it has to be
//:: (re)applied whenever the player's level can have changed: login, level up,
//:: level down.
//::
//:: The value comes from exptable.2da -- the same table the server levels off,
//:: read at runtime -- so this can never disagree with the real requirement.
//:: Below level 40 the override is cleared and the stock string comes back.
//::
//:: See README.md "Levels 41-60"; hooked from mod_cliententer.nss and
//:: nextlvl_evt.nss.
//:://////////////////////////////////////////////

#include "nwnx_player"

const int NEXTLVL_STRREF   = 315;   // "Next Level"
const int NEXTLVL_FIRST    = 40;    // the engine's figure is wrong from here up
const int NEXTLVL_MAXLEVEL = 60;    // exptable.2da's last real row

// Re-apply (or clear) oPC's "Next Level" TLK override for its current level.
void NextLevel_FixTlk(object oPC);


void NextLevel_FixTlk(object oPC)
{
    if (!GetIsPC(oPC) || GetIsDM(oPC)) return;

    int nLevel = GetHitDice(oPC);

    // Below 40 the stock display is correct. Clear any override left over from
    // a level drain, restoring the global string.
    if (nLevel < NEXTLVL_FIRST)
    {
        NWNX_Player_SetTlkOverride(oPC, NEXTLVL_STRREF, "");
        return;
    }

    string sValue;
    if (nLevel >= NEXTLVL_MAXLEVEL)
    {
        // At the cap there is no next level -- row 60 is the 0xFFFFFFFF
        // unreachable sentinel, so there is no number to show.
        sValue = "Max";
    }
    else
    {
        // exptable.2da is 0-indexed by (level - 1), so the NEXT level's
        // requirement is row nLevel.
        string sXP = Get2DAString("exptable", "XP", nLevel);
        int nXP = StringToInt(sXP);

        // A client or server without the rebuilt lotr_rules.hak reads no row
        // here. Leave the stock display alone rather than print a bare 0.
        if (nXP <= 0)
        {
            NWNX_Player_SetTlkOverride(oPC, NEXTLVL_STRREF, "");
            return;
        }
        sValue = IntToString(nXP);
    }

    // Trailing newline is load-bearing: it pushes the engine's own (wrong)
    // value out of the visible field.
    NWNX_Player_SetTlkOverride(oPC, NEXTLVL_STRREF, "Next Level: " + sValue + "\n");
}
