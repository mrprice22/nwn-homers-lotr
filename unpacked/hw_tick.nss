// hw_tick - Harvest of Shadows: the module-heartbeat half (~6s).
//
// ExecuteScript'd once per beat from bleeding.nss. Does nothing outside the
// date window beyond a once-a-minute calendar read. Inside it, per PC:
//   * darkens the PC's area the first time anyone is in it;
//   * every other beat, re-registers the pumpkin attack aura for the PC's
//     area (once per area per beat, however many PCs share it);
//   * counts the distance the PC walks and drops a pumpkin every 40-100m in
//     town areas, every 150-300m in hostile ones (test realms say so in chat);
//   * now and then plays a spooky sound from a nearby pumpkin;
//   * sends skeletons abandoned in an emptied area to the Pumpkin King.

#include "hw_inc"
#include "season_prof_inc"

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
        // Occupancy, for HW_DrainAbandoned: any PC counts, dead or not.
        if (!GetIsDM(oPC) && GetIsObjectValid(oArea))
            SetLocalInt(oArea, "hw_pc_beat", nBeat);
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
            if (GetAreaFromLocation(lWas) == oArea)
            {
                // Cap a beat's distance so an in-area jump is not a free pumpkin.
                float fMoved = GetDistanceBetweenLocations(lNow, lWas);
                if (fMoved > 40.0) fMoved = 40.0;
                float fWalked = GetLocalFloat(oPC, "hw_walked") + fMoved;
                int nTier = HW_AreaTier(GetResRef(oArea));
                int nDue = GetLocalInt(oPC, "hw_walk_due");
                if (nDue <= 0)
                {
                    nDue = (nTier == 0)
                        ? HW_TRAVEL_TOWN_MIN + Random(HW_TRAVEL_TOWN_SPAN + 1)
                        : HW_TRAVEL_HOSTILE_MIN + Random(HW_TRAVEL_HOSTILE_SPAN + 1);
                    SetLocalInt(oPC, "hw_walk_due", nDue);
                }
                if (fWalked >= IntToFloat(nDue))
                {
                    object oPk = HW_SpawnPumpkin(HW_Scatter(lNow, 4.0, 8.0),
                                                 nTier == 0 ? "town" : "cursed");
                    if (SP_DEV_TOOLS)
                        SendMessageToPC(oPC, "[HW dev] travel pumpkin after "
                            + IntToString(FloatToInt(fWalked)) + "m (tier "
                            + IntToString(nTier) + "): "
                            + (GetIsObjectValid(oPk) ? "spawned" : "refused (area cap)"));
                    fWalked = 0.0;
                    DeleteLocalInt(oPC, "hw_walk_due");
                }
                SetLocalFloat(oPC, "hw_walked", fWalked);
            }
            SetLocalLocation(oPC, "hw_last", lNow);

            HW_Spook(oPC);
        }
        oPC = GetNextPC();
    }

    // Skeletons left behind in an emptied area march to the Pumpkin King.
    HW_DrainAbandoned(nBeat);
}
