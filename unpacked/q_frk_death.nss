// The Forbidden Realms (roadmap: forbidden-realms-key-tier)
// OnDeath for the three barrow-court blueprints (weathertopkin003 /
// weathertopque003 / weathertoparc002). Chains the module's default undead
// death handler, then records the kill for the killer's whole party so a group
// all completes the quest together.
#include "q_frk_inc"

void main()
{
    ExecuteScript("x2_def_ondeath", OBJECT_SELF);

    string sResRef = GetResRef(OBJECT_SELF);
    string sKey;
    if      (sResRef == FRK_RR_KING)   sKey = "frk_king";
    else if (sResRef == FRK_RR_QUEEN)  sKey = "frk_queen";
    else if (sResRef == FRK_RR_ARCHER) sKey = "frk_archer";
    else return;

    object oKiller = GetLastKiller();
    if (!GetIsObjectValid(oKiller)) return;

    object oMember = GetFirstFactionMember(oKiller, TRUE);
    while (GetIsObjectValid(oMember))
    {
        if (GetArea(oMember) == GetArea(OBJECT_SELF))
            FRK_RecordKill(oMember, sKey);
        oMember = GetNextFactionMember(oKiller, TRUE);
    }
}
