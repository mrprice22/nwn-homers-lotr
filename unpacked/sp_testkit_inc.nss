//::///////////////////////////////////////////////
//:: sp_testkit_inc - is this a realm that hands out tester shortcuts?
//::
//:: ONE place the SP_TESTER_KIT flag is read. Consumers:
//::   welloferuenter.nss  the Well of Eru kit - a Forgekey and a top-up to 6
//::                       Runes of Expansion, on every entry
//::   _cdkeyhome.nss      the "Options of the Homeless" rest-menu conditional
//::   sp_testkit.nss      the [MW Teleports] root rest-menu conditional
//::
//:: WHY THIS IS A PURE REALM PREDICATE, with no Admin_Can* fallback baked in.
//:: sp_devgate_inc.nss folds the admin check into its helper because both of
//:: its consumers guard the same admindb tier. These do not: the Homeless menu
//:: is gated on admins.can_homeless and the MW list on admins.can_admin. A
//:: shared "or the admin" clause here would therefore have to pick one tier and
//:: would silently widen the other - handing every can_admin key the Homeless
//:: teleports on a LIVE season, which is not what this change is for.
//::
//:: So the flag is all this returns, and each consumer keeps its own existing
//:: check beside it. Production behaviour is unchanged by construction: with
//:: SP_TESTER_KIT FALSE every consumer falls through to exactly the test it
//:: performed before.
//::
//:: SP_TESTER_KIT is GENERATED into season_prof_inc.nss from SEASON_ROLE by
//:: bin/season-profile.py (on for dev and test, off for live and archive). Do
//:: not author it - bin/season-promote.sh copies dev's tree over production on
//:: every release, so a hand-edited constant is reverted by the next successful
//:: deploy and the live season quietly starts giving away the Balrog's key.
//:://////////////////////////////////////////////
#include "season_prof_inc"

// TRUE on a realm that hands out tester shortcuts (dev / early access).
int SP_TesterKit();

int SP_TesterKit()
{
    return SP_TESTER_KIT;
}
