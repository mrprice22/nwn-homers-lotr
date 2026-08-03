// cbd_damage.nss - Combat Dummy: NWNX Damage DAMAGE event handler.
//
// Registered PER OBJECT by cbd_spawn:
//     NWNX_Damage_SetDamageEventScript("cbd_damage", OBJECT_SELF);
// so it never runs for anything but a dummy and costs the rest of the server
// nothing. OBJECT_SELF is the object taking the damage (the dummy);
// data.oDamager is the source.
//
// Two jobs:
//   1. attribute and accumulate the damage (this is the DPR measurement, and
//      it counts EVERYTHING the owner deals - weapons, spells, on-hit
//      properties);
//   2. let the damage LAND and heal it straight back off, which is what makes
//      the dummy indestructible.
//
// It used to zero every damage field instead. That worked, but it cost the
// tester the single most useful thing on screen: with no HP change the engine
// prints no damage line and no "damage reduction absorbs" feedback, so a
// combat test could not be checked against the combat log at all (UAT round 3).
// Now the hit applies normally and CBD_Restore puts the dummy back to full on
// the next pulse. Death immunity (cbd_spawn) and the respawn (cbd_death) are
// still behind that, for the one hit big enough to outrun the restore.

#include "nwnx_damage"
#include "cbd_inc"

void main()
{
    struct NWNX_Damage_DamageEventData data = NWNX_Damage_GetDamageEventData();

    object oDummy = OBJECT_SELF;
    if (!GetLocalInt(oDummy, CBD_VAR_IS_DUMMY)) return;

    // EVERY field goes through CBD_Amt: NWNX reports an unused damage type as
    // -1, not 0. Summing them raw subtracts one point per unused type, which is
    // how a 33-point greatsword hit measured as 2 and a 28-point hit as -3 and
    // was then dropped as "no damage" (UAT rounds 3 and 4).
    int nDmg = CBD_Amt(data.iBludgeoning) + CBD_Amt(data.iPierce) +
               CBD_Amt(data.iSlash) + CBD_Amt(data.iMagical) +
               CBD_Amt(data.iAcid) + CBD_Amt(data.iCold) +
               CBD_Amt(data.iDivine) + CBD_Amt(data.iElectrical) +
               CBD_Amt(data.iFire) + CBD_Amt(data.iNegative) +
               CBD_Amt(data.iPositive) + CBD_Amt(data.iSonic) +
               CBD_Amt(data.iBase) +
               CBD_Amt(data.iCustom1) + CBD_Amt(data.iCustom2) +
               CBD_Amt(data.iCustom3) + CBD_Amt(data.iCustom4) +
               CBD_Amt(data.iCustom5) + CBD_Amt(data.iCustom6) +
               CBD_Amt(data.iCustom7) + CBD_Amt(data.iCustom8) +
               CBD_Amt(data.iCustom9) + CBD_Amt(data.iCustom10) +
               CBD_Amt(data.iCustom11) + CBD_Amt(data.iCustom12) +
               CBD_Amt(data.iCustom13) + CBD_Amt(data.iCustom14) +
               CBD_Amt(data.iCustom15) + CBD_Amt(data.iCustom16) +
               CBD_Amt(data.iCustom17) + CBD_Amt(data.iCustom18) +
               CBD_Amt(data.iCustom19);

    // Who dealt it. data.oDamager is NOT reliable for weapon damage - UAT round
    // 3 measured "6 attacks, 0 damage" for a whole set because every packet
    // arrived with an unusable damager, resolved to no PC, and was thrown away
    // as an intruder's. CBD_ResolveSrc falls back to the attacker the attack
    // event stashed, which is always valid.
    object oSrc = CBD_ResolveSrc(oDummy, data.oDamager);
    object oPC  = CBD_OwnerPC(oSrc);

    // Diagnostic mode (CBD_DEBUG on the dummy) - every packet, with its source
    // and the state that decides whether it is counted. Off by default.
    if (CBD_IsDebug(oDummy))
        CBD_Debug(oDummy, oPC, "damage from " + GetName(oSrc) +
                  " (raw=" + GetName(data.oDamager) +
                  ", pc=" + GetName(oPC) + ")" +
                  " active=" + IntToString(GetLocalInt(oDummy, CBD_VAR_ACTIVE)) +
                  " cool=" + IntToString(GetLocalInt(oDummy, CBD_VAR_COOL)) +
                  " total=" + IntToString(nDmg) + ":" +
                  CBD_DbgField("base",  data.iBase) +
                  CBD_DbgField("bludg", data.iBludgeoning) +
                  CBD_DbgField("pierce", data.iPierce) +
                  CBD_DbgField("slash", data.iSlash) +
                  CBD_DbgField("magic", data.iMagical) +
                  CBD_DbgField("fire",  data.iFire) +
                  CBD_DbgField("cold",  data.iCold) +
                  CBD_DbgField("elec",  data.iElectrical) +
                  CBD_DbgField("acid",  data.iAcid) +
                  CBD_DbgField("sonic", data.iSonic) +
                  CBD_DbgField("div",   data.iDivine) +
                  CBD_DbgField("neg",   data.iNegative) +
                  CBD_DbgField("pos",   data.iPositive));

    if (GetLocalInt(oDummy, CBD_VAR_ACTIVE))
    {
        if (GetIsObjectValid(oPC) && oPC == GetLocalObject(oDummy, CBD_VAR_OWNER))
        {
            if (nDmg > 0)
            {
                CBD_Touch(oDummy);
                SetLocalInt(oDummy, CBD_VAR_DMG_RND,
                            GetLocalInt(oDummy, CBD_VAR_DMG_RND) + nDmg);
                SetLocalInt(oDummy, CBD_VAR_DMG_TOT,
                            GetLocalInt(oDummy, CBD_VAR_DMG_TOT) + nDmg);

                if (CBD_IsDebug(oDummy))
                    CBD_Debug(oDummy, oPC, "  counted +" + IntToString(nDmg) +
                              " (round " +
                              IntToString(GetLocalInt(oDummy, CBD_VAR_DMG_RND)) +
                              ", session " +
                              IntToString(GetLocalInt(oDummy, CBD_VAR_DMG_TOT)) + ")");
            }
            else if (CBD_IsDebug(oDummy))
                CBD_Debug(oDummy, oPC, "  IGNORED: packet carried no damage");
        }
        else if (GetIsObjectValid(oPC))
        {
            if (CBD_IsDebug(oDummy))
                CBD_Debug(oDummy, oPC, "  DISCARDED: not the session owner (" +
                          GetName(GetLocalObject(oDummy, CBD_VAR_OWNER)) + ")");

            // Another PC, a henchman, a summon: frozen out, and their damage is
            // discarded from both metrics. Only ever taken when the source
            // resolves to a REAL and different player - damage we cannot
            // attribute falls through to the owner above via CBD_ResolveSrc,
            // because silently discarding it is what broke the measurement.
            CBD_Reject(oDummy, oSrc);
        }
        else if (CBD_IsDebug(oDummy))
            CBD_Debug(oDummy, OBJECT_INVALID,
                      "  DISCARDED: no player behind this damage at all");
    }
    else if (!GetLocalInt(oDummy, CBD_VAR_COOL) && GetIsObjectValid(oPC) && nDmg > 0)
    {
        // First blood on an idle dummy starts the session, and this hit counts
        // as part of round 1.
        CBD_StartSession(oDummy, oPC);
        SetLocalInt(oDummy, CBD_VAR_DMG_RND, nDmg);
        SetLocalInt(oDummy, CBD_VAR_DMG_TOT, nDmg);
    }
    else if (GetLocalInt(oDummy, CBD_VAR_COOL) && GetIsObjectValid(oPC))
    {
        if (!GetLocalInt(oDummy, CBD_VAR_WARNED))
        {
            SetLocalInt(oDummy, CBD_VAR_WARNED, 1);
            CBD_Notice(oPC, "The dummy is resetting - wait a moment before the next test.");
        }
    }

    // The damage is handed back UNTOUCHED so the engine applies it and prints
    // it: per-type numbers, resistances, damage reduction. The dummy is put
    // back to full on the next pulse instead.
    if (nDmg > 0) CBD_ScheduleRestore(oDummy);
}
