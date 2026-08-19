int CheckIsInInventory (object oChest, object oGem)
{
    object oObj = GetFirstItemInInventory(oChest);
    while (GetIsObjectValid(oObj))
    {
        if (oGem == oObj)
        {return TRUE;}
        oObj = GetNextItemInInventory(oChest);
    }
    return FALSE;
}

void main()
{
    object oPC = GetLastUsedBy();
    object oChestA = GetObjectByTag("ECHO_AIR");
    object oChestF = GetObjectByTag("ECHO_FIRE");
    object oChestE = GetObjectByTag("ECHO_EARTH");
    object oChestW = GetObjectByTag("ECHO_WATER");
    object oGemA = GetObjectByTag("YellowGem");
    object oGemF = GetObjectByTag("BlueGem");
    object oGemE = GetObjectByTag("RedGem");
    object oGemW = GetObjectByTag("GreenGem");
    object oSolveWP = GetWaypointByTag("kal_riddle_solve");

if (GetLocalInt(OBJECT_SELF,"silenced") == 1)
    {
      SpeakString("Thank you.");
      return;
    }

if ((CheckIsInInventory(oChestA,oGemA)) && (CheckIsInInventory(oChestF,oGemF)) && (CheckIsInInventory(oChestW,oGemW)) && (CheckIsInInventory (oChestE,oGemE)))
     {
         SetLocalInt(OBJECT_SELF,"silenced",1);
         CreateObject(OBJECT_TYPE_ITEM, "kallristcryptkey", GetLocation(oSolveWP));
         DelayCommand(1.5,SpeakString("Phew...music to my ears..."));
         GiveXPToCreature(oPC,666);
         SendMessageToPC(oPC,"The noises in the chamber become quieter, less chaotic, and you hear a sigh of relief.");
         SetPlotFlag(OBJECT_SELF, FALSE);
         DelayCommand(1.6,ApplyEffectToObject(DURATION_TYPE_INSTANT,EffectVisualEffect(VFX_FNF_MYSTICAL_EXPLOSION),oPC));
         DestroyObject(OBJECT_SELF, 1.8);
         return;
    }

if (GetLocalInt(OBJECT_SELF,"silenced") != 1)
    {
        SendMessageToPC(oPC,"A disembodied voice coming from the altar, whispers");
        SpeakString("I is not import', 'ere is the thing, follow the rhymes, come back for the blings, Red earth crumblesss, Blue flames glooow, Green water splashesss, Golden 'airs blooow.");
        return;
    }
}


