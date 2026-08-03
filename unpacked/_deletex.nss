// _deletex - NWNX:EE port
//
// Originally used the NWNX2 deletechar plugin via the
// SetLocalString(GetModule(), "NWNX!DELETECHAR!DELETE", ...) IPC magic
// string. Replaced with NWNX_Administration_DeletePlayerCharacter, which
// removes the BIC and (with bPreserveBackup=FALSE) skips the .bak.
//
// Original signature is preserved for callers; sPlayerName is unused now
// because NWNX:EE keys deletion off the in-memory player object, not name
// strings - so callers must pass an oPC. Use the (object) form.

#include "nwnx_admin"

void deletechar(string sPlayerName, string sCharName);
void deletechar_obj(object oPC);

void deletechar(string sPlayerName, string sCharName)
{
    // No safe way to recover an object from name strings post-EE; this entry
    // point is now a no-op kept only for link compatibility. New callers
    // should use deletechar_obj(oPC).
}

void deletechar_obj(object oPC)
{
    if (!GetIsPC(oPC)) return;
    NWNX_Administration_DeletePlayerCharacter(oPC, FALSE);
}
