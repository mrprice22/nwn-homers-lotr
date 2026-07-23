//:: mw_qg_noop -- shared no-op combat handler for MeaningWave quiz quest-givers.
//:: Assigned to OnPhysicalAttacked / OnDamaged / OnCombatRoundEnd / OnPerception
//:: / OnSpellCastAt so these NPCs never fight back and never initiate combat.
//:: They are also immortal + plot + permanently Sanctuary'd (see mw_qg_spawn),
//:: so nothing targets them in the first place.
//:: roadmap: mw-questgiver-ignore-combat
void main()
{
}
