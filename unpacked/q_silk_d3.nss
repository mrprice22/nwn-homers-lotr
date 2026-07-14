// q_silk_d3 — Spider Silk Harvest OnDeath wrapper (roadmap: spider-silk-harvest)
// Blueprint OnDeath for the sb_creaturekill spider family (spiddire001 Sword
// Spider). Drops harvest silk, then chains the original reward script.
// Bestiary-safe: see q_silk_d1.
#include "q_silk_inc"

void main()
{
    QS_OnSpiderDeath();
    ExecuteScript("sb_creaturekill", OBJECT_SELF);
}
