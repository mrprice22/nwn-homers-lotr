/*******************************************************************************
* aa_area_exit
*
* by LasCivious Sept 2004
* Called by area's OnExit event.  Clears area encounters, dropped items,
* stores & cleans placeable inventories if no PC is present for a length of time.
*******************************************************************************/

// Set this to FALSE if you do not want placeable inventories cleared
int nClearPlaceInv = FALSE;
// Set the amount of time to wait for cleaning here in seconds
float fDelayTime = 600.0;

void CleanArea(object oArea)
{
  object oTrash = GetFirstObjectInArea(oArea);
  object oInvItem;

  //Check for PCs
  object oPC = GetFirstPC();
  while (GetIsObjectValid(oPC)) {
    if  (GetArea(oPC) == oArea) {
      DeleteLocalInt(oArea, "CleanArea");
      return;
    }
    oPC = GetNextPC();
  }

   while(GetIsObjectValid(oTrash)) {
     string sTagPrefix = GetStringLeft(GetTag(oTrash), 15);
     // Clear remains, dropped items
     if(GetObjectType(oTrash)==OBJECT_TYPE_ITEM ||
        GetStringLowerCase(GetName(oTrash)) == "remains") {
          AssignCommand(oTrash, SetIsDestroyable(TRUE));
          if (GetHasInventory(oTrash)) {
            oInvItem = GetFirstItemInInventory(oTrash);
            while(GetIsObjectValid(oInvItem)) {
              DestroyObject(oInvItem,0.0);
              oInvItem = GetNextItemInInventory(oTrash);
            }
          }
          else DestroyObject(oTrash, 0.0);
      }
      // Clear placeable inventories
      if(GetObjectType(oTrash)==OBJECT_TYPE_PLACEABLE &&
         nClearPlaceInv == FALSE) {
        if (GetHasInventory(oTrash))
        {
          object oInvItem = GetFirstItemInInventory(oTrash);
          while(GetIsObjectValid(oInvItem)) {
            DestroyObject(oInvItem,0.0);
            oInvItem = GetNextItemInInventory(oTrash);
          }
        }
      }
      // Clear encounters
      else if (GetIsEncounterCreature(oTrash) ||
               sTagPrefix == "PWFSE_SPAWNERID")
      {
        AssignCommand(oTrash, SetIsDestroyable(TRUE));
        DestroyObject(oTrash, 0.0);
      }

      oTrash = GetNextObjectInArea(oArea);
   }
   DeleteLocalInt(oArea, "CleanArea");
}

void main()
{
  object oArea = OBJECT_SELF;
  object oPC = GetExitingObject();
  if (!GetIsPC(oPC)) return;

    // Jukebox: cash in listening credit for this player. Guarded by a plain
    // local so an exit from any other area costs one GetLocalInt and no SQL;
    // the literal "jb_listening" matches JB_LISTENING in jb_buff_inc.nss, and
    // tests/check_jukebox_queue.py asserts the two stay in step. Handed off
    // through ExecuteScript rather than an include so this script keeps its
    // own dependencies.
    object oJbLeaver = GetExitingObject();
    if (GetLocalInt(oJbLeaver, "jb_listening"))
    {
        SetLocalObject(OBJECT_SELF, "jb_leaver", oJbLeaver);
        ExecuteScript("jb_area_exit", OBJECT_SELF);
    }

  if (GetLocalInt(oArea, "CleanArea") != 1)
  {
    DelayCommand(fDelayTime, CleanArea(oArea));
    SetLocalInt(oArea, "CleanArea", 1);
  }
}
