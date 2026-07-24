// eviladjust2 — legacy/duplicate EVIL adjuster (OnUsed style, GetLastUsedBy).
// Currently unwired (the live EVIL script is eiladjust). Kept for reference;
// now routes through factiondb so it persists and applies the live reputation
// via Faction_ApplyLive. NOTE: the previous version used lowercase
// "goodfaction"/"evilfaction" tags, which never matched the real anchors
// (Goodfaction/Evilfaction) and silently no-opped.
#include "faction_db"

void main()
{
    object oPC = GetLastUsedBy();
    if (!Faction_CanSwitchTo(oPC, "Evil")) return;   // oath to the West forbids it
    Faction_SetAllegiance(oPC, "Evil");
}
