// The Forbidden Realms (roadmap: forbidden-realms-key-tier)
// Numenor: Noirinan (falseheaven) OnEnter wrapper: run the area's original
// OnEnter ("ent" -- anti-kiting leash + DM spawn count), then make sure the
// sealed barrow-gate is standing at AP_forbiddenrealmskeytier_1. Same
// wrapper-chaining pattern as q_ftr_enter / q_hrp_ent1 / prsg_enter.
#include "q_frk_inc"
#include "setti_loot_inc"

void main()
{
    ExecuteScript("ent", OBJECT_SELF);

    if (GetIsPC(GetEnteringObject()))
    {
        FRK_SpawnGate(FRK_WP_GATE, FRK_WP_TOMB);

        // Re-arm the three Setti coffers: re-lock any that has cooled down and
        // sits empty, so a returning player finds fresh, gated loot again. Timed
        // to entry because nothing runs during the idle cooldown hour. See
        // setti_loot_inc.nss / numenor-chests roadmap item.
        SettiRearm();
    }
}
