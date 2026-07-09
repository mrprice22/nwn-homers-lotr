// gwathlab_wire.nss
// Reboot randomizer for the Gwathdor Labyrinth (area025).
//
// NWScript cannot rewrite a door/trigger's engine transition target at runtime,
// so the maze is driven entirely by the local string "MAZE_DEST" (a destination
// object tag) that gwathlab_door.nss / gwathlab_trig.nss read when a PC uses a
// door or steps on a small-room exit trigger. This script re-rolls those
// destinations once per server start (called from onmoduleload.nss, like
// mw_spawn), producing a fresh, solvable-but-confusing layout every reboot.
//
// Objects (all pre-placed in area025.git.json):
//   * 8 big rooms, doors GwathLab<r>A/B/C   (r = 1..8, 24 doors)
//   * fixed doors GwathLabStart / GwathLabFinish (+ engine doors Enter/Exit)
//   * 12 small rooms: entrance waypoint WP_GwathLabDE## , exit trigger GwathLabDE##
//
// Wiring model:
//   1. Random spanning tree over the 8 big rooms (bidirectional door<->door
//      links, each room capped at its 3 doors).           -> 14 doors used
//   2. Attach Start (bidirectional) and Finish (one-way, leads out to the exit
//      lobby) each to a random room door.                  -> 16 doors used
//   3. Distribute all 12 small rooms across the 8 leftover ("spare") doors as a
//      random mix of DEAD-ENDS (trigger returns you to the door you entered) and
//      one-way CORRIDORS (trigger dumps you at a door in another room). 4 spare
//      doors host a 2-room chain, 4 host a single room (4*2 + 4*1 = 12).
// Result: every door, Start, Finish, all 12 waypoints and all 12 triggers are
// wired; all 20 rooms are used; the Start->Finish route is always solvable.
//
// NWScript has no arrays, so ordered lists live as indexed local vars on the
// module object (the "scratch store"). Every run fully overwrites them, so a
// re-run (with or without reboot) is self-consistent.

// ------------------------- scratch-array helpers ---------------------------
void   SetArrS(object o, string a, int i, string v){ SetLocalString(o, a + IntToString(i), v); }
string GetArrS(object o, string a, int i){ return GetLocalString(o, a + IntToString(i)); }
void   SetArrI(object o, string a, int i, int v){ SetLocalInt(o, a + IntToString(i), v); }
int    GetArrI(object o, string a, int i){ return GetLocalInt(o, a + IntToString(i)); }

void ShuffleS(object o, string a, int n)
{
    int i;
    for (i = n - 1; i > 0; i--)
    {
        int j = Random(i + 1);
        string t = GetArrS(o, a, i);
        SetArrS(o, a, i, GetArrS(o, a, j));
        SetArrS(o, a, j, t);
    }
}

void ShuffleI(object o, string a, int n)
{
    int i;
    for (i = n - 1; i > 0; i--)
    {
        int j = Random(i + 1);
        int t = GetArrI(o, a, i);
        SetArrI(o, a, i, GetArrI(o, a, j));
        SetArrI(o, a, j, t);
    }
}

// ------------------------------ tag helpers --------------------------------
string Pad2(int i){ if (i < 10) return "0" + IntToString(i); return IntToString(i); }

// slot 0/1/2 -> door A/B/C of a big room
string DoorTag(int room, int slot)
{
    string L = "A";
    if (slot == 1) L = "B";
    else if (slot == 2) L = "C";
    return "GwathLab" + IntToString(room) + L;
}

// room number encoded as the single digit after "GwathLab" (positions 0..7)
int RoomOfDoor(string sDoorTag){ return StringToInt(GetSubString(sDoorTag, 8, 1)); }

// ---------------------------- wiring helpers -------------------------------
// One-directional: clicking/entering sFrom teleports the PC to sTo.
void SetDest(string sFrom, string sTo)
{
    object o = GetObjectByTag(sFrom);
    if (GetIsObjectValid(o)) SetLocalString(o, "MAZE_DEST", sTo);
}

// Bidirectional door<->door link.
void LinkBoth(string sA, string sB){ SetDest(sA, sB); SetDest(sB, sA); }

// Take the next unused door of a big room; RDIDX<r> also serves as the room's
// current degree (each door = one connection).
string TakeDoor(object oMod, int room)
{
    int idx = GetLocalInt(oMod, "RDIDX" + IntToString(room));
    string tag = GetArrS(oMod, "RD" + IntToString(room) + "_", idx);
    SetLocalInt(oMod, "RDIDX" + IntToString(room), idx + 1);
    return tag;
}

int FreeDoors(object oMod, int room){ return 3 - GetLocalInt(oMod, "RDIDX" + IntToString(room)); }

// Pick a random big room that still has an unused door.
int PickRoomWithFreeDoor(object oMod)
{
    int start = 1 + Random(8);
    int c;
    for (c = 0; c < 8; c++)
    {
        int room = 1 + ((start - 1 + c) % 8);
        if (FreeDoors(oMod, room) > 0) return room;
    }
    return 0; // unreachable given the accounting (16 of 24 doors used)
}

// A landing door for a one-way corridor: any door in a room other than sFromDoor's.
string CorridorTarget(string sFromDoor)
{
    int myRoom = RoomOfDoor(sFromDoor);
    int rr;
    do { rr = 1 + Random(8); } while (rr == myRoom);
    return DoorTag(rr, Random(3));
}

// =================================== main ==================================
void main()
{
    object oMod = GetModule();
    int r;

    // 1. Per-room shuffled door lists; RDIDX<r> = next free door / degree.
    for (r = 1; r <= 8; r++)
    {
        string a = "RD" + IntToString(r) + "_";
        SetArrS(oMod, a, 0, DoorTag(r, 0));
        SetArrS(oMod, a, 1, DoorTag(r, 1));
        SetArrS(oMod, a, 2, DoorTag(r, 2));
        ShuffleS(oMod, a, 3);
        SetLocalInt(oMod, "RDIDX" + IntToString(r), 0);
        SetLocalInt(oMod, "CONN" + IntToString(r), 0);
    }

    // 2. Random spanning tree over the 8 big rooms (randomized Prim, degree<=3).
    int startRoom = 1 + Random(8);
    SetLocalInt(oMod, "CONN" + IntToString(startRoom), 1);
    int connCount = 1;
    while (connCount < 8)
    {
        // random unconnected room U
        int U;
        do { U = 1 + Random(8); } while (GetLocalInt(oMod, "CONN" + IntToString(U)));

        // random connected room V with a free door (a tree of k nodes always
        // leaves a connected node below the degree cap, so this always finds one)
        int V = 0;
        int startv = 1 + Random(8);
        int c;
        for (c = 0; c < 8; c++)
        {
            int cand = 1 + ((startv - 1 + c) % 8);
            if (GetLocalInt(oMod, "CONN" + IntToString(cand)) && FreeDoors(oMod, cand) > 0)
            { V = cand; break; }
        }

        LinkBoth(TakeDoor(oMod, U), TakeDoor(oMod, V));
        SetLocalInt(oMod, "CONN" + IntToString(U), 1);
        connCount++;
    }

    // 3. Attach Start (bidirectional) and Finish (one-way, leads to the exit).
    LinkBoth("GwathLabStart", TakeDoor(oMod, PickRoomWithFreeDoor(oMod)));
    SetDest(TakeDoor(oMod, PickRoomWithFreeDoor(oMod)), "GwathLabFinish");
    SetDest("GwathLabFinish", "GwathLabExit");

    // 4. Collect the 8 leftover ("spare") doors and shuffle them.
    int spareN = 0;
    for (r = 1; r <= 8; r++)
    {
        int idx = GetLocalInt(oMod, "RDIDX" + IntToString(r));
        string a = "RD" + IntToString(r) + "_";
        int k;
        for (k = idx; k < 3; k++)
        {
            SetArrS(oMod, "SPARE", spareN, GetArrS(oMod, a, k));
            spareN++;
        }
    }
    ShuffleS(oMod, "SPARE", spareN);

    // 5. Shuffle the 12 small-room ids and hang them off the spare doors:
    //    first 4 spare doors get a 2-room chain, the last 4 get a single room.
    int m;
    for (m = 0; m < 12; m++) SetArrI(oMod, "SR", m, m + 1);
    ShuffleI(oMod, "SR", 12);

    int srPtr = 0;
    int s;
    for (s = 0; s < spareN; s++)
    {
        string D = GetArrS(oMod, "SPARE", s);
        int chain = (s < 4) ? 2 : 1;          // 4*2 + 4*1 = 12 small rooms
        int bDeadEnd = (Random(2) == 0);      // random dead-end vs one-way corridor

        int a1 = GetArrI(oMod, "SR", srPtr); srPtr++;
        SetDest(D, "WP_GwathLabDE" + Pad2(a1));      // door -> first small room

        if (chain == 1)
        {
            // single room: its trigger returns to D (dead-end) or forwards away
            if (bDeadEnd) SetDest("GwathLabDE" + Pad2(a1), D);
            else          SetDest("GwathLabDE" + Pad2(a1), CorridorTarget(D));
        }
        else
        {
            int a2 = GetArrI(oMod, "SR", srPtr); srPtr++;
            SetDest("GwathLabDE" + Pad2(a1), "WP_GwathLabDE" + Pad2(a2)); // deeper
            if (bDeadEnd) SetDest("GwathLabDE" + Pad2(a2), D);
            else          SetDest("GwathLabDE" + Pad2(a2), CorridorTarget(D));
        }
    }
}
