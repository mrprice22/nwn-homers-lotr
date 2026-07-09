// gwathlab_trig.nss
// OnEnter handler for the Gwathdor Labyrinth (area025) small-room exit triggers
// (GwathLabDE01..12). Each small room has one entrance waypoint and this one
// exit trigger. gwathlab_wire.nss stores the trigger's per-reboot destination
// object tag in the local string "MAZE_DEST" (either the door the player entered
// from -> dead end, or a forward door -> one-way corridor). Walking onto the
// trigger teleports the PC there.
void main()
{
    object oPC = GetEnteringObject();
    if (!GetIsPC(oPC)) return;

    string sDest = GetLocalString(OBJECT_SELF, "MAZE_DEST");
    if (sDest == "") return;

    object oT = GetObjectByTag(sDest);
    if (!GetIsObjectValid(oT)) return;

    AssignCommand(oPC, ClearAllActions());
    AssignCommand(oPC, JumpToObject(oT));
}
