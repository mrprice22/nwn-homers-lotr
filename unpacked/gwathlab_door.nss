// gwathlab_door.nss
// OnClick handler for the Gwathdor Labyrinth (area025) maze doors.
//
// The maze is re-wired randomly every server reboot by gwathlab_wire.nss, which
// stores each door's current destination object tag in the local string
// "MAZE_DEST". NWScript cannot rewrite a door's engine LinkedTo at runtime, so
// the door is flagged as an area transition (LinkedToFlags=1) purely so this
// OnClick fires; the real teleport is done here from MAZE_DEST.
void main()
{
    object oPC = GetClickingObject();
    if (!GetIsPC(oPC)) return;

    string sDest = GetLocalString(OBJECT_SELF, "MAZE_DEST");
    if (sDest == "") return;

    object oT = GetObjectByTag(sDest);
    if (!GetIsObjectValid(oT)) return;

    AssignCommand(oPC, ClearAllActions());
    AssignCommand(oPC, JumpToObject(oT));
}
