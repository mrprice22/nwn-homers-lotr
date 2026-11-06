// lootlab_force.nss - Loot Lab: toggle "force creature drops on my kills".
// While ON (PC local LOOT_FORCE_DROPS), every creature this admin helps kill
// rolls its drop as if its chance were 1000 per mille, and loot_ondeath sends
// one "LOOT: <name> class=.. cr=.. lvl=.. area=.. -> n item(s)" line - the only
// practical way to UAT a 4% drop.
// Roadmap: lo-creature-drops. Loot Lab action (emotewand.dlg Entry 19). See lootlab_inc.nss.
#include "lootlab_inc"

void main()
{
    object oPC = LL_Speaker();
    if (!LL_Authorised(oPC)) return;
    int bOn = !GetLocalInt(oPC, "LOOT_FORCE_DROPS");
    if (bOn) SetLocalInt(oPC, "LOOT_FORCE_DROPS", 1);
    else DeleteLocalInt(oPC, "LOOT_FORCE_DROPS");
    SendMessageToPC(oPC, "Loot Lab: force creature drops on your kills is " + (bOn ? "ON." : "OFF."));
}
