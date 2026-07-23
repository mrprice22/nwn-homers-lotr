// goodadjuster2 — legacy/duplicate GOOD adjuster (OnUsed style, GetLastUsedBy).
// Currently unwired (no placeable/dialog references it), kept for reference and
// any future re-wire. Now routes through factiondb so it persists, and — via
// Faction_ApplyLive — uses the correct capital anchor tags. NOTE: the previous
// version used lowercase "goodfaction"/"evilfaction" tags, which never match
// the real anchors (Goodfaction/Evilfaction) and silently no-opped.
#include "faction_db"

void main()
{
    object oPC = GetLastUsedBy();
    Faction_SetAllegiance(oPC, "Good");
}
