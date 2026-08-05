
//Stop Counterspell Cheat 2.1 by driller_nwn@hotmail.com

//Drop by my PW Blackstone_Keep(CEP) located under Roleplay and say hello.

//I had to change the way I was doing this because +scarface+ told of a another exploit that the pervious version didn't stop.
//Thank you +scarface+ for your help in testing.
//This script will stop the counterspell infinite spell exploit without affecting counterspell's normal operation


//Put this code in your OnModuleLoad Event script

//SetModuleSwitch(MODULE_VAR_OVERRIDE_SPELLSCRIPT,TRUE);
//SetModuleOverrideSpellscript("stop_spellcheat");


//Save this in a script named stop_spellcheat

#include "x2_inc_switches"
#include "fat_inc"
#include "q_ent_inc"

int i;

void ClearSpells()
{
   //No need to run more than 15 times
   i = i + 1;
   if(i > 15) return;

    int nAction = GetCurrentAction();

    if(nAction == 4)
       //If you change the time delay a player might be able to cheat
        DelayCommand(0.1,ClearSpells());
       else if(nAction == 31)
        {
        /*
        Kill the cheater.
        I recommend not removing this.
        There is still a possibility a really coordinated player could get a feel for the timing and still be able to exploit.
        This will help ensure that doesn't happen.
       */
        ClearAllActions(TRUE);
        ApplyEffectToObject(DURATION_TYPE_INSTANT,EffectDamage(GetMaxHitPoints()+1000,DAMAGE_TYPE_MAGICAL,DAMAGE_POWER_ENERGY),OBJECT_SELF);
        SetModuleOverrideSpellScriptFinished();
        SendMessageToPC(OBJECT_SELF,"Cheating is not allowed here.");
        }
}


void main()
{

// Soul-fatigue on Heal / Mass Heal (incl. potion activations) - fat_inc.nss
// (roadmap: heal-soul-fatigue). Runs before ClearSpells; the real heal impact
// script still runs after this override returns, and fatigue is delayed past it.
FAT_OnOverrideSpellCast();

// The Thirteenth Ent (roadmap: thirteenth-ent) - the druid restoration ritual
// is a cast of Nature's Balance whose area of effect covers Leaflock, with a
// fresh truffle in the pack. Listener only; no spell script is replaced.
ENT_OnSpellCast();

ClearSpells();

}
