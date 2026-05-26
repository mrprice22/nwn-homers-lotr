// mw_finale_done -- dialogue conditional: PC already collected the mixtape.
#include "mw_unlock_inc"
int StartingConditional()
{
    return GetCampaignInt(MW_DB, "finale", GetPCSpeaker());
}
