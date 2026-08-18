// Forbidden Realms: Enter -- arrival flavour (roadmap: forbidden-realms-key-tier)
//
// OnEnter of the ForbiddenRealmsWelcome trigger in area027, at (26.95, 13.50):
// the near half of the room, just short of ForbiddenRealmsDoor, so it fires as a
// party comes out of the wolf tunnel and first sees the sealed door.
//
// Once per character. Same idiom as the module's other narrative triggers
// (phe4r.nss, icehi.nss): GetEnteringObject + PC check + a local-int once-guard
// + FloatingTextStringOnCreature. No effects, no saves, no journal changes.
//
// The second half of the message branches on whether the player is carrying the
// Forbidden Realms Key, reusing FRK_HasKey rather than inventing new state.

#include "q_frk_inc"

const string WTOP_FR_SEEN = "WTOP_FR_WELCOME";

void main()
{
    object oPC = GetEnteringObject();
    if (!GetIsPC(oPC)) return;
    if (GetLocalInt(oPC, WTOP_FR_SEEN)) return;
    SetLocalInt(oPC, WTOP_FR_SEEN, TRUE);

    string sText = "The wolf-tunnel gives out into worked stone. Coloured fire "
                 + "drifts in the dark ahead of you, and across the chamber "
                 + "stands a door that no hand cut in living memory. ";

    if (FRK_HasKey(oPC))
        sText += "Seven marks are set into its ward, and the key at your belt "
               + "has gone cold against you.";
    else
        sText += "Seven marks are set into its ward. It does not answer "
               + "knocking.";

    FloatingTextStringOnCreature(sText, oPC, FALSE);
}
