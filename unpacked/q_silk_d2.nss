// q_silk_d2 - Spider Silk Harvest OnDeath wrapper (roadmap: spider-silk-harvest)
// Blueprint OnDeath for the 350ondeathtopart spider family (spidwra001 Lava
// Climber, spidphase001 Death Weeper, spidswrd001 Black Spear Spider). Drops
// harvest silk, then chains the original reward script. Bestiary-safe: see
// q_silk_d1.
#include "q_silk_inc"

void main()
{
    QS_OnSpiderDeath();
    ExecuteScript("350ondeathtopart", OBJECT_SELF);
}
