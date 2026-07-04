void dmw_CleanUp(object oMySpeaker)
{
   int nCount;
   int nCache;
   DeleteLocalObject(oMySpeaker, "dmfi_univ_target");
   DeleteLocalLocation(oMySpeaker, "dmfi_univ_location");
   DeleteLocalObject(oMySpeaker, "dmw_item");
   DeleteLocalString(oMySpeaker, "dmw_repamt");
   DeleteLocalString(oMySpeaker, "dmw_repargs");
   nCache = GetLocalInt(oMySpeaker, "dmw_playercache");
   for(nCount = 1; nCount <= nCache; nCount++)
   {
      DeleteLocalObject(oMySpeaker, "dmw_playercache" + IntToString(nCount));
   }
   DeleteLocalInt(oMySpeaker, "dmw_playercache");
   nCache = GetLocalInt(oMySpeaker, "dmw_itemcache");
   for(nCount = 1; nCount <= nCache; nCount++)
   {
      DeleteLocalObject(oMySpeaker, "dmw_itemcache" + IntToString(nCount));
   }
   DeleteLocalInt(oMySpeaker, "dmw_itemcache");
   for(nCount = 1; nCount <= 10; nCount++)
   {
      DeleteLocalString(oMySpeaker, "dmw_dialog" + IntToString(nCount));
      DeleteLocalString(oMySpeaker, "dmw_function" + IntToString(nCount));
      DeleteLocalString(oMySpeaker, "dmw_params" + IntToString(nCount));
   }
   DeleteLocalString(oMySpeaker, "dmw_playerfunc");
   DeleteLocalInt(oMySpeaker, "dmw_started");
}


void main()

{
   object oPC;
   object oItem=GetItemActivated();
   object oActivator=GetItemActivator();
// object oCaller = GetItemActivator();
// object oTarget = GetItemActivatedTarget();
// string sTag = GetTag(oItem);




   if(GetTag(oItem)=="DyeKit")
   {
      // Repointed to the ZEP appearance/dye station (see dmfi_activate.nss).
      AssignCommand(oActivator, ActionStartConversation(oActivator, "x0_skill_ctrap", TRUE, FALSE));
      return;
   }
   //if(GetTag(oItem)=="00")
  // {
   //   AssignCommand(oActivator, ActionStartConversation(oActivator, "00", TRUE));
   //   return;
  // }
   if(GetTag(oItem)=="recall")
   {
   object oPC;
oPC = GetItemActivator();
object oTarget;
location lTarget;
oTarget = GetWaypointByTag("respawn");
lTarget = GetLocation(oTarget);
if (GetAreaFromLocation(lTarget)==OBJECT_INVALID) return;
AssignCommand(oPC, ClearAllActions());
DelayCommand(1.0, AssignCommand(oPC, ActionJumpToLocation(lTarget)));
oTarget = oPC;
int nInt;
nInt = GetObjectType(oTarget);
if (nInt != OBJECT_TYPE_WAYPOINT) ApplyEffectToObject(DURATION_TYPE_INSTANT, EffectVisualEffect(VFX_IMP_LIGHTNING_S), oTarget);
else ApplyEffectAtLocation(DURATION_TYPE_INSTANT, EffectVisualEffect(VFX_IMP_LIGHTNING_S), GetLocation(oTarget));
   }
   if(GetTag(oItem)=="EmoteWand")
   {
      AssignCommand(oActivator, ActionStartConversation(oActivator, "emotewand", TRUE));
      return;
   }
   if(GetTag(oItem)=="PCQuill")
   {
    ExportSingleCharacter(oPC);
    SendMessageToPC(oPC, "The module, " + GetModuleName() + ", is saving the PC, " + GetName(oPC));
    PrintString(GetPCPlayerName(oPC) + " has saved their PC, " + GetName(oPC) + ".");
  }
   if(GetTag(oItem)=="AutoFollow")
   {
      object oTarget = GetItemActivatedTarget();

      if(GetIsObjectValid(oTarget))
      {
         AssignCommand ( oActivator, ActionForceFollowObject(oTarget));
      }
      return;
   }
       if(GetTag(oItem)=="DMsHelper")
   {

      object oMyActivator = GetItemActivator();
      object oMyTarget = GetItemActivatedTarget();
      SetLocalObject(oMyActivator, "dmwandtarget", oMyTarget);
      location lMyLoc = GetItemActivatedTargetLocation();
      SetLocalLocation(oMyActivator, "dmwandloc", lMyLoc);

      //Make the activator start a conversation with itself
      AssignCommand(oMyActivator, ActionStartConversation(oMyActivator, "dmwand", TRUE));
      return;
   }
      if(GetTag(oItem)=="WandOfFX")
   {

       // get the wand's activator and target, put target info into local vars on activator
      object oPC = GetItemActivator();
      object oMyTarget = GetItemActivatedTarget();
      SetLocalObject(oPC, "FXWandTarget", oMyTarget);
      location lTargetLoc = GetItemActivatedTargetLocation();
      SetLocalLocation(oPC, "FXWandLoc", lTargetLoc);

      object oTest=GetFirstPC();
      string sTestName = GetPCPlayerName(oPC);
      // Test to make sure the activator is a DM, or is a DM
      // controlling a creature.


      {


      }

      //Make the activator start a conversation with itself
      AssignCommand(oPC, ActionStartConversation(oPC, "fxwand", TRUE));
      return;

   }


oItem    = GetItemActivated();
oPC      = GetItemActivator();
string sItemTag = GetTag(oItem);



if (sItemTag == "bundlethranduil")
        {
            ExecuteScript("bundle_thranduil", oPC);
            return;
        }

if (sItemTag == "bombfuse")
        {
            ExecuteScript("bombfuse", oPC);
            return;
        }
}

