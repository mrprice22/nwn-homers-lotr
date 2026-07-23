//:: mw_qg_spawn -- OnSpawn for MeaningWave quiz quest-giver NPCs.
//:: Makes them fully non-combatant: immortal + plot (cannot be killed) plus a
//:: permanent Sanctuary so no creature -- even hostile/opposite factions -- ever
//:: targets or attacks them. Chains the stock x2_def_spawn first so ambient /
//:: walk-waypoint behaviour is preserved. Their combat event scripts are nulled
//:: (mw_qg_noop) on the blueprints so they never retaliate or initiate combat.
//:: roadmap: mw-questgiver-ignore-combat
void main()
{
    // Preserve stock ambient behaviour (walk waypoints, listening patterns).
    ExecuteScript("x2_def_spawn", OBJECT_SELF);

    // Belt-and-suspenders: these NPCs must never die or be reduced in combat.
    SetImmortal(OBJECT_SELF, TRUE);
    SetPlotFlag(OBJECT_SELF, TRUE);

    // Sanctuary with an unbeatable DC => no creature ever selects them as a
    // target, regardless of faction. Supernatural + permanent so it cannot be
    // dispelled and never expires. It never breaks, because these NPCs take no
    // hostile action.
    effect eSanc = SupernaturalEffect(EffectSanctuary(100));
    ApplyEffectToObject(DURATION_TYPE_PERMANENT, eSanc, OBJECT_SELF);
}
