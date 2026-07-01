void main()
{
    object oEntering = GetEnteringObject();
    if (!GetIsPC(oEntering)) return;
    SetLocalInt(oEntering, "SPFAIL_RUNNING", 1);
    ExecuteScript("_spfail_cycle", oEntering);
}
