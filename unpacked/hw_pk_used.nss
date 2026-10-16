// hw_pk_used - clicking a pumpkin attacks it. The only way to clear one.
void main()
{
    object oPC = GetLastUsedBy();
    if (!GetIsObjectValid(oPC)) return;
    AssignCommand(oPC, ActionAttack(OBJECT_SELF));
}
