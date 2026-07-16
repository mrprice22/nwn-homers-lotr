// q_wpm_dummy -- the Weapon Masters' proving post (roadmap:
// weapon-master-quest). OnUsed of the first practice post in the Guard's
// training row below the walls of Minas Tirith (minastirith.git.json,
// existing placed instance 6 of plc_cmbtdummy reused -- retagged
// WMTrialPost and made usable; it was Static with no scripts, so there is
// nothing to chain, and no code referenced the old shared "Combat Dummy"
// tag). Runs the sworn-blade trial for a PC on the rite:
//
//   * The one-blade-one-life fail condition: strike bare-handed, or with
//     any weapon whose Weapon of Choice feat the PC does not have
//     (QWPM_IsSwornBlade -- baseitems.2da WeaponOfChoiceFeat via
//     Get2DAString + GetHasFeat), and the attempt fails with a flavor
//     message; nothing is granted. Retry allowed -- draw the sworn weapon
//     and strike again. Deterministic: the feat is the test, no dice.
//   * Sworn blade in hand at stage 1: gives the notch, stage 1 -> 2 +
//     journal 2. At stage 2 with the notch lost, re-gives it (never
//     duplicates -- GetItemPossessedBy guard; the item is plot + cursed
//     and only the finish consumes it).
//
// Does nothing for PCs not on the rite -- to everyone else it is just a
// scarred practice post.
#include "q_wpm_inc"

void main()
{
    object oPC = GetLastUsedBy();
    if (!GetIsPC(oPC)) return;

    int nStage = QWPM_GetStage(oPC);
    if (nStage < QWPM_STAGE_ACCEPTED || nStage > QWPM_STAGE_NOTCH) return;
    if (QWPM_HasNotch(oPC)) return;

    object oWeapon = GetItemInSlot(INVENTORY_SLOT_RIGHTHAND, oPC);

    // The fail conditions: bare hands, or a blade the hand is not sworn
    // to. The post has out-stood prouder men.
    if (!GetIsObjectValid(oWeapon))
    {
        FloatingTextStringOnCreature(
            "You square up to the post bare-handed. The scarred wood has "
            + "out-stood a thousand borrowed blades and it will out-stand "
            + "your fists: the trial asks for the one weapon your soul is "
            + "sworn to. Draw it and strike again.",
            oPC, FALSE);
        return;
    }
    if (!QWPM_IsSwornBlade(oPC))
    {
        FloatingTextStringOnCreature(
            "The blow lands, and the post barely marks. This is not the "
            + "weapon your soul is sworn to -- the trial asks for your "
            + "chosen blade, the one the Weapon Masters would know your "
            + "hand by. Draw it and strike again.",
            oPC, FALSE);
        return;
    }

    CreateItemOnObject(QWPM_NOTCH_RES, oPC, 1);

    if (nStage == QWPM_STAGE_ACCEPTED)
    {
        QWPM_SetStage(oPC, QWPM_STAGE_NOTCH);
        AddJournalQuestEntry(QWPM_QUEST, 2, oPC, FALSE, FALSE);
    }

    FloatingTextStringOnCreature(
        "One stroke, and the seasoned oak opens along the grain -- your "
        + "sworn blade cuts where a century of masters cut before, and a "
        + "notch of scarred wood comes away in your hand. Carry it to "
        + "Halmir.",
        oPC, FALSE);
}
