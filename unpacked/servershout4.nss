// Login notices. The season-2 early-access warning is coloured with the
// module's cyan token so it reads as a different KIND of message from the
// standing Discord/wiki reminders next to it.
//
// The colour comes from the "color" include, NOT an inline "<c...>" literal:
// a colour token is three RAW bytes, and the high bytes (0xAE/0xFE here) would
// make this file invalid UTF-8 - which breaks bin/season-brand.py, since it
// reads this very file with read_text(encoding="utf-8") to rehost the wiki
// link. color.nss already holds those bytes and nothing parses it as UTF-8.
// (Do not copy merit_redeem.nss's MERIT_PH: its 0xFF was mangled into the
// UTF-8 replacement char long ago, so it emits five bytes where three belong.)
#include "color"
#include "season_prof_inc"

void main()
{

object oPC = GetEnteringObject();

if (!GetIsPC(oPC)) return;

int DoOnce = GetLocalInt(oPC, GetTag(OBJECT_SELF));

if (DoOnce==TRUE) return;

SetLocalInt(oPC, GetTag(OBJECT_SELF), TRUE);

FloatingTextStringOnCreature("Join the discord at https://discord.gg/VpAtSpe - check the Announcements channel for recent updates and new codes you can use ingame for rewards!", oPC);
FloatingTextStringOnCreature("View the Wiki at dev.homerslotr.com", oPC);

// The early-access wipe warning. Shown only where progress really is
// temporary: SP_WIPE_NOTICE is TRUE for SEASON_ROLE=test and FALSE everywhere
// else (see bin/season-profile.py).
//
// This block used to be DELETED by hand at go-live, which was the single most
// confusing thing the cutover could ship if forgotten - a live realm telling
// every player their progress is about to be erased. It is a flag now because
// dev and production share this file: a hand deletion in production would be
// restored by dev's copy at the next promotion.
//
// The TEXT is still hand-written - dates and ports change every season, and a
// generated script has no business authoring a player announcement. Only
// whether it appears is derived.
if (SP_WIPE_NOTICE)
{
    FloatingTextStringOnCreature(ColorString("*** SEASON 2 TEST REALM *** Everything you do here - characters, levels, gear, gold, banks, bestiary, boss kills, teleport slots - WILL BE WIPED when Season 2 goes live on the evening of August 5th, 2026. Season 1 stays online on port 5121.", COLOR_LIGHT_BLUE), oPC);
    FloatingTextStringOnCreature(ColorString("Merit you earn in early access DOES still count. But do NOT redeem merit for the 2x gold/XP boosts or for tournament gear until after go-live - you would pay the merit and lose the reward in the wipe. Teleport unlocks, graffiti, the wallet, Become a DM and player homes are safe to redeem any time.", COLOR_LIGHT_BLUE), oPC);
}

}
