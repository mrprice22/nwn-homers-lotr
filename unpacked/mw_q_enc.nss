// mw_q_enc -- ActionTaken on the intro entry: record first encounter with the
// guide (adds the meta-quest + per-guide "encountered" journal entries).
#include "mw_unlock_inc"
void main() { MW_EncounterJournal(GetPCSpeaker(), MW_GuideFromTag()); }
