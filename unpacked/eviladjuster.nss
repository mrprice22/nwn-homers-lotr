// eviladjuster — legacy/duplicate EVIL adjuster (dialog style, GetLastSpeaker).
// Currently unwired (the live EVIL script is eiladjust). Kept for reference and
// any future re-wire; now routes through factiondb so it persists and applies
// the live reputation via Faction_ApplyLive (capital anchor tags).
#include "faction_db"

void main()
{
    object oPC = GetLastSpeaker();
    Faction_SetAllegiance(oPC, "Evil");
}
