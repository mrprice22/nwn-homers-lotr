void main()
{

if(GetLastSpell() == SPELL_LESSER_DISPEL || GetLastSpell() == SPELL_REMOVE_CURSE || GetLastSpell() == SPELL_DISPEL_MAGIC)
  {
   object oFlame;
   object oGrave= GetObjectByTag("undead_headstone");
   object oPC = GetLastSpellCaster();
   int iXP;
   effect eVisual= EffectVisualEffect(VFX_IMP_UNSUMMON);
   SetLocalInt(GetModule(), "Undead_Dispelled", 1);
   oFlame = GetObjectByTag("undeadlight");
   ActionDoCommand(DestroyObject(oFlame));
   ApplyEffectToObject(DURATION_TYPE_INSTANT, eVisual, oGrave);
   AddJournalQuestEntry("cursedgrave", 2, oPC);
   iXP = GetJournalQuestExperience("cursedgrave");
   GiveXPToCreature(oPC, iXP);
  }
}
