// castfeat_inc.nss - the caster feat proxies (roadmap ll-bonus-feat-lists).
//
// THE DEFECT
// ----------
// feat.2da's MINSPELLLVL column means "you must be able to cast spells of this
// level", and the CLIENT filters the level-up feat list on it. Under the NWNX
// MaxLevel plugin the client resolves a caster's maximum castable spell level as
// 0 once that class passes level 40 - the same clamp README.md "Levels 41-60"
// already records for the spell-known picker. So every feat with MINSPELLLVL >= 1
// disappears from both the class-bonus and the general feat list. A pure wizard
// at 47 was left with Brew Potion, Craft Wand and Epic Spell.
//
// THE FIX
// -------
// bin/spellfeat_proxies.py adds an inert PROXY row per (feat, class) that the
// broken filter cannot see, gated to the class at level 41 by MinLevelClass /
// MinLevel and carrying every real prerequisite verbatim. This script is the
// other half: the proxy grants nothing by itself, so something has to hand the
// player the feat they actually picked.
//
// THE PAIRING INVARIANT - HOLD EITHER, HOLD BOTH
// ----------------------------------------------
// A proxy and its stock row are different feat ids, so the engine will happily
// offer one to a character who already holds the other and let them spend a pick
// on a feat they own. Both directions are real: took the stock feat at level 30
// and gets offered the proxy at 41+, or took the proxy and later sees the stock
// row. So the resolver walks the map BOTH ways - proxy without real grants the
// real, real without proxy grants the proxy - and because the engine never
// offers a feat you already have, that alone closes the double-pick with no
// change to the stock rows and nothing to strip back off a player.
//
// This is also why the login sweep is not just belt-and-braces. A character who
// took the stock feat years ago must already hold the proxy BEFORE the level-up
// to 41, because the client builds that level's list before any of our code
// runs. Logging in is what puts it there in time.

#include "castfeat_ids"
#include "nwnx_creature"

// TRUE when lotr_rules.hak's feat.2da is the one loaded.
int CastFeat_HaveTable();

// Restore the pairing invariant on oPC. Idempotent and safe to call on anyone.
void CastFeat_Resolve(object oPC);


int CastFeat_HaveTable()
{
    if (CASTFEAT_COUNT <= 0) return FALSE;

    // The proxy rows live above stock feat.2da's last row, so a server reading
    // the stock table gets "" here. Granting a feat id that does not exist is
    // how you put an unreadable feat on a character sheet - bail instead.
    return Get2DAString("feat", "LABEL", CastFeat_ProxyAt(0)) != "";
}

void CastFeat_Resolve(object oPC)
{
    if (!GetIsPC(oPC) || GetIsDM(oPC)) return;
    if (!CastFeat_HaveTable()) return;

    // AddFeatByLevel files the feat under a level in the .bic's level list,
    // which is what makes it survive a relog. The current level is the honest
    // place for it: it is the level the player was standing on when they earned
    // the pick, or - for the reverse direction - when we noticed the pairing
    // was broken.
    int nLevel = GetHitDice(oPC);
    int nGranted = 0;
    int i;

    for (i = 0; i < CASTFEAT_COUNT; i++)
    {
        int nProxy = CastFeat_ProxyAt(i);
        int nReal  = CastFeat_RealAt(i);

        int bProxy = GetHasFeat(nProxy, oPC, TRUE);
        int bReal  = GetHasFeat(nReal,  oPC, TRUE);
        if (bProxy == bReal) continue;

        if (bProxy)
        {
            // The player picked the proxy. This is the grant that makes the
            // whole mechanism work.
            NWNX_Creature_AddFeatByLevel(oPC, nReal, nLevel);
        }
        else
        {
            // The player already had the real feat. The proxy is inert; it is
            // added only so the level-up page stops offering it.
            NWNX_Creature_AddFeatByLevel(oPC, nProxy, nLevel);
        }
        nGranted++;
    }

    if (nGranted > 0)
        WriteTimestampedLogEntry("[castfeat] " + GetName(oPC) + ": paired "
                                 + IntToString(nGranted) + " caster feat(s)");
}
