// q_silk_d1 - Spider Silk Harvest OnDeath wrapper (roadmap: spider-silk-harvest)
// Blueprint OnDeath for the gpondeath spider family (spidgiant001 Giant
// Spider, spiderboss001 Spider-Queen). Drops harvest silk, then chains the
// original reward script. Bestiary-safe: bst_install stores this script as
// bst_orig_death at spawn, so bst_ondeath records the kill first and chains
// here via ExecuteScript.
#include "q_silk_inc"

void main()
{
    QS_OnSpiderDeath();
    ExecuteScript("gpondeath", OBJECT_SELF);
}
