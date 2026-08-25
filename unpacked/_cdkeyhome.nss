// "Options for the Homeless" conditional. Whitelist lives in the "admindb"
// campaign database (admins.can_homeless), not in source.
//
// On a tester realm the subtree below this link is opened to everyone: it holds
// nothing but the teleport list (Castle of Homeless, Balrog, Weathertop,
// Hobbiton, Angmar, Dunharrow, Lord of the Dark Arts, Basilisk Lair) and an
// Exit, which is pure travel time on a realm whose progress is thrown away. The
// Admin_CanHomeless fallback below is what still gates it on live - see
// sp_testkit_inc.nss for why the flag check is not folded into that helper.
#include "sp_testkit_inc"
#include "admin_db"

int StartingConditional()
{
    if (SP_TesterKit()) return TRUE;
    return Admin_CanHomeless(GetPCSpeaker());
}
