//::///////////////////////////////////////////////
//:: FileName athelasrespawn
//:://////////////////////////////////////////////
//:: OnOpen refill for the Athelas plant (Glorfindel's Curative quest).
//:: Re-creates the "athelas" ingredient item on a timer so that more than
//:: one player can gather it between server resets. Modeled on
//:: athelasrefill.nss, but spawns the quest item instead of loot.
//:://////////////////////////////////////////////
void main()
{
    object oItem = OBJECT_INVALID;
    int respawntime = 1500;

    // Check object for the time it was last opened and see if it is time to respawn
    int lastopened = GetLocalInt(OBJECT_SELF,"CS_Opened");
    // CS_Openend = 0 on not found, GetLocalInt error return
    int currenttime = GetTimeSecond()+60*GetTimeMinute()+3600*GetTimeHour();
    if (currenttime > lastopened + respawntime)
    {
        // respawntime seconds passed?
        SetLocalInt(OBJECT_SELF,"NW_DO_ONCE",0);
    }
     if (lastopened > currenttime)
    {
        // maybe a whole day passed? or it's midnight?
        SetLocalInt(OBJECT_SELF,"NW_DO_ONCE",0);
    }

    // Respawn the Athelas plant
    if (GetLocalInt(OBJECT_SELF,"NW_DO_ONCE") == 0)
    {
      oItem = GetFirstItemInInventory();
      while ( oItem != OBJECT_INVALID )
      {
         DestroyObject( oItem, 0.0 );
         oItem = GetNextItemInInventory();
      }
      CreateItemOnObject("athelas", OBJECT_SELF, 1);
      SetLocalInt(OBJECT_SELF,"CS_Opened",GetTimeSecond()+60*GetTimeMinute()+3600*GetTimeHour());
      SetLocalInt(OBJECT_SELF,"NW_DO_ONCE",1);
    }
}
