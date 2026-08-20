//::///////////////////////////////////////////////
//:: sp_meritgate_inc - who may use the merit shop
//::
//:: ONE predicate, used by both halves of the gate:
//::   merit_gate.nss / merit_gate_no.nss   the conversation branch (UX)
//::   merit_redeem.nss                     the three functions that SPEND merit
//::
//:: They must agree, and the second one is the one that matters. The same
//:: mistake in the Ping Pong gate (see sp_devgate_inc.nss) let an admin open a
//:: conversation the committing script then refused in silence.
//::
//:: THE RULE. The merit shop is open to everyone on PRODUCTION only, and to a
//:: whitelisted admin anywhere - dev, early access and retired seasons included.
//:: Merit is account-wide (keyed on the CD key, not the character) and spending
//:: escrows against a real meritdb balance, so a non-production realm redeeming
//:: rewards would burn merit the live season owes the player. Admins keep access
//:: everywhere because somebody has to be able to test the shop before it ships.
//::
//:: SP_MERIT_SHOP is GENERATED into season_prof_inc.nss from SEASON_ROLE by
//:: bin/season-profile.py - never hand-edit it, and never replace this call with
//:: a literal: bin/season-profile.py --check is a repack build gate that fails
//:: the build if either this file or merit_redeem.nss stops reading the flag.
//::
//:: Admin_CanAdmin reads admins.can_admin from the admindb campaign database
//:: (seeded out of band by bin/seed-admindb.sh); no CD key ever ships in the
//:: .mod. Do NOT substitute GetIsDM() - it is TRUE only for an actual DM-client
//:: login, and this server's admin has no DM console, so it would lock the one
//:: person who needs to test the shop out of it.
//:://////////////////////////////////////////////
#include "season_prof_inc"
#include "admin_db"

// TRUE if oPC may redeem merit rewards on this realm.
int SP_MeritShopFor(object oPC);

int SP_MeritShopFor(object oPC)
{
    if (SP_MERIT_SHOP) return TRUE;
    return Admin_CanAdmin(oPC);
}
