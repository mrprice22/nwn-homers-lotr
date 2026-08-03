// cbd_damage.nss — Combat Dummy: NWNX Damage DAMAGE event handler.
//
// Registered PER OBJECT by cbd_spawn:
//     NWNX_Damage_SetDamageEventScript("cbd_damage", OBJECT_SELF);
// so it never runs for anything but a dummy and costs the rest of the server
// nothing. OBJECT_SELF is the object taking the damage (the dummy);
// data.oDamager is the source.
//
// Two jobs:
//   1. attribute and accumulate the damage (this is the DPR measurement, and
//      it counts EVERYTHING the owner deals — weapons, spells, on-hit
//      properties);
//   2. ZERO the damage before handing it back, which is what makes the dummy
//      indestructible. HP never moves, so Harm, Drown and every other
//      damage-based "instant kill" are no-ops and no healing loop is needed.
//      (Effect-based deaths are covered by the death immunity in cbd_spawn and,
//      as a last resort, by the respawn in cbd_death.)

#include "nwnx_damage"
#include "cbd_inc"

void main()
{
    struct NWNX_Damage_DamageEventData data = NWNX_Damage_GetDamageEventData();

    object oDummy = OBJECT_SELF;
    if (!GetLocalInt(oDummy, CBD_VAR_IS_DUMMY)) return;

    int nDmg = data.iBludgeoning + data.iPierce + data.iSlash + data.iMagical +
               data.iAcid + data.iCold + data.iDivine + data.iElectrical +
               data.iFire + data.iNegative + data.iPositive + data.iSonic +
               data.iBase +
               data.iCustom1 + data.iCustom2 + data.iCustom3 + data.iCustom4 +
               data.iCustom5 + data.iCustom6 + data.iCustom7 + data.iCustom8 +
               data.iCustom9 + data.iCustom10 + data.iCustom11 + data.iCustom12 +
               data.iCustom13 + data.iCustom14 + data.iCustom15 + data.iCustom16 +
               data.iCustom17 + data.iCustom18 + data.iCustom19;

    object oSrc = data.oDamager;
    object oPC  = CBD_OwnerPC(oSrc);

    // Diagnostic mode (CBD_DEBUG on the dummy) — every packet, with its source
    // and the state that decides whether it is counted. Off by default.
    if (CBD_IsDebug(oDummy))
        CBD_Debug(oDummy, oPC, "damage from " + GetName(oSrc) +
                  " (pc=" + GetName(oPC) + ")" +
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
            }
        }
        else
        {
            // Anyone else — another PC, a henchman, a summon: frozen out, and
            // their damage is discarded from both metrics.
            CBD_Reject(oDummy, oSrc);
        }
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
            CBD_Say(oPC, "The dummy is resetting - wait a moment before the next test.");
        }
    }

    // Nothing gets through, whoever dealt it.
    data.iBludgeoning = 0; data.iPierce   = 0; data.iSlash      = 0;
    data.iMagical     = 0; data.iAcid     = 0; data.iCold       = 0;
    data.iDivine      = 0; data.iElectrical = 0; data.iFire     = 0;
    data.iNegative    = 0; data.iPositive = 0; data.iSonic      = 0;
    data.iBase        = 0;
    data.iCustom1  = 0; data.iCustom2  = 0; data.iCustom3  = 0; data.iCustom4  = 0;
    data.iCustom5  = 0; data.iCustom6  = 0; data.iCustom7  = 0; data.iCustom8  = 0;
    data.iCustom9  = 0; data.iCustom10 = 0; data.iCustom11 = 0; data.iCustom12 = 0;
    data.iCustom13 = 0; data.iCustom14 = 0; data.iCustom15 = 0; data.iCustom16 = 0;
    data.iCustom17 = 0; data.iCustom18 = 0; data.iCustom19 = 0;

    NWNX_Damage_SetDamageEventData(data);
}
