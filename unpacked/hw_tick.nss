// hw_tick - Harvest of Shadows: the module-heartbeat half (~6s).
//
// ExecuteScript'd once per beat from bleeding.nss. Does nothing outside the
// date window beyond a once-a-minute calendar read. Inside it, per PC:
//   * darkens the PC's area the first time anyone is in it;
//   * every other beat, re-registers the pumpkin attack aura for the PC's
//     area (once per area per beat, however many PCs share it);
//   * if the PC has moved 5m+ since the last beat, rolls for a pumpkin
//     (town areas often, hostile areas rarely);
//   * now and then plays a spooky sound from a nearby pumpkin.

#include "hw_inc"

void main()
{
    object oMod = GetModule();
    int nBeat = GetLocalInt(oMod, "hw_beat") + 1;
    SetLocalInt(oMod, "hw_beat", nBeat);

    // The window can open or close on a running server.
    if (nBeat % 10 == 0)
    {
        int nOld = HW_Phase();
        int nNew = HW_ReadPhase();
        if (nNew != nOld)
        {
            SetLocalInt(oMod, "hw_phase", nNew);
            if (nOld == HW_PHASE_ACTIVE) HW_SweepAll(nNew == HW_PHASE_CLAIM);
            if (nNew == HW_PHASE_ACTIVE)      HW_Begin();
            else if (nNew == HW_PHASE_CLAIM)  HW_SpawnBoard();
            else                              HW_SweepAll(FALSE);
        }
    }
    // Prize effects (auras, glows, the wisp) run all year, not just in October:
    // once a minute, put back whatever a login, death or respawn stripped.
    if (nBeat % 10 == 5)
    {
        object oP = GetFirstPC();
        while (GetIsObjectValid(oP))
        {
            if (!GetIsDM(oP)) HW_RefreshPrizeFx(oP);
            oP = GetNextPC();
        }
    }

    if (HW_Phase() != HW_PHASE_ACTIVE) return;

    int bAura = (nBeat % 2 == 0);
    object oPC = GetFirstPC();
    while (GetIsObjectValid(oPC))
    {
        object oArea = GetArea(oPC);
        if (!GetIsDM(oPC) && !GetIsDead(oPC) && GetIsObjectValid(oArea)
            && !HW_AreaExcluded(GetResRef(oArea)))
        {
            HW_DarkenArea(oArea);

            if (bAura && GetLocalInt(oArea, "hw_aura_beat") != nBeat)
            {
                SetLocalInt(oArea, "hw_aura_beat", nBeat);
                HW_RecomputeAura(oArea, oPC);
            }

            location lNow = GetLocation(oPC);
            location lWas = GetLocalLocation(oPC, "hw_last");
            if (GetAreaFromLocation(lWas) == oArea
                && GetDistanceBetweenLocations(lNow, lWas) >= 5.0)
            {
                int nTier = HW_AreaTier(GetResRef(oArea));
                if (nTier == 0)
                {
                    if (Random(HW_TRAVEL_CHANCE_TOWN) == 0)
                        HW_SpawnPumpkin(HW_Scatter(lNow, 4.0, 8.0), "town");
                }
                else if (Random(HW_TRAVEL_CHANCE_HOSTILE) == 0)
                    HW_SpawnPumpkin(HW_Scatter(lNow, 4.0, 8.0), "cursed");
            }
            SetLocalLocation(oPC, "hw_last", lNow);

            HW_Spook(oPC);
        }
        oPC = GetNextPC();
    }
}
