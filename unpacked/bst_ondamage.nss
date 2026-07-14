// bst_ondamage — wrapped creature OnDamaged: record PC damage contributors.
//
// Installed by bst_install. Records each distinct PC that has dealt damage to
// this creature (walking the summon/henchman master chain to the owning PC) so
// bst_ondeath can tell Solo from Party kills and credit every contributor.
// Always chains the creature's original OnDamaged handler.
//
// Also feeds the boss enrage-on-retreat system (enr_inc): registry bosses
// mark each damaging PC as "engaged" here; ENR_OnBossDamaged no-ops for
// everything else (cached one-query registry check).

#include "enr_inc"

void main()
{
    object oCre = OBJECT_SELF;

    object oDmg = GetLastDamager(oCre);
    // Summons, henchmen, familiars, animal companions -> credit the owning PC.
    while (GetIsObjectValid(GetMaster(oDmg))) oDmg = GetMaster(oDmg);

    if (GetIsPC(oDmg) && !GetIsDM(oDmg))
    {
        int nN = GetLocalInt(oCre, "bst_ctrb_n");
        int i;
        int bFound = FALSE;
        for (i = 0; i < nN; i++)
        {
            if (GetLocalObject(oCre, "bst_ctrb_" + IntToString(i)) == oDmg)
            {
                bFound = TRUE;
                break;
            }
        }
        if (!bFound)
        {
            SetLocalObject(oCre, "bst_ctrb_" + IntToString(nN), oDmg);
            SetLocalInt(oCre, "bst_ctrb_n", nN + 1);
        }

        // Enrage-on-retreat: registry bosses track this PC as engaged.
        ENR_OnBossDamaged(oCre, oDmg);
    }

    // Chain the creature's original OnDamaged handler, if any.
    string sOrig = GetLocalString(oCre, "bst_orig_dmg");
    if (sOrig != "") ExecuteScript(sOrig, oCre);
}
