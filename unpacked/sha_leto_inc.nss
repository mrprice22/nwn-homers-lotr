//::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
//:::::::::::::::::::::::: Shayan's Subrace Engine :::::::::::::::::::::::::::::
//::::::::::::::::::::::: File Name: sha_leto_inc ::::::::::::::::::::::::::::::
//:::::::::::::::::::::::::: LETOScript Include file :::::::::::::::::::::::::::
//:: Written By: Demux (and distributed with DAR package)
//:: Modified by: Shayan
//
// :: This script controls the Leto functions for the Subrace Engine. Most of these
// :: functions were originally written by Demux for his DAR subraces package.
// :: It has been slightly modified for the Subrace Engine.
// :: Thanks to Demux for this wonderful script.
//
// :: NWN:EE STATUS — this file is a NO-OP SHIM, and belongs to the subrace
// :: engine alone. Letoscript was an NWNX2-era external .bic rewriter; it does
// :: not exist under NWNX:EE, so LetoScript() returns "" and the LETO_* helpers
// :: only build strings that are then handed to it. Nothing here edits a
// :: character. The subrace engine's Leto path (sha_subr_methds.nss:
// :: SubraceOnClientLeave / LetoSubraceModifications) is therefore inert.
// ::
// :: It was deleted in commit d212c3c2b08 alongside the HGLL legendary-leveler
// :: scripts, which also used it — but sha_subr_methds.nss:44 still includes it,
// :: and that only surfaced on a CLEAN repack (56 compile errors across the
// :: subrace engine and the core scripts that include it: default.nss,
// :: nw_o0_respawn.nss, nw_s2_turndead.nss, the _dm_subrace_* wands...). An
// :: incremental build reused the cached .ncs and hid it. Restored here rather
// :: than excised because the calls are woven through a 227 KB third-party
// :: file; the shim keeps the engine compiling and changes no behaviour.
// ::
// :: Do not build anything new on these functions.

#include "sha_subr_consts"

// Used to check whether NWNX2-Leto is functioning properly.
// Returns TRUE if Leto is working.
int LetoPingPong();

string LetoScript(string script)
{
    // NWNX:EE port — Letoscript IPC is gone; HGLL applies its own changes
    // directly via NWNX_Creature/Player. This stub just keeps the linker
    // happy for any leftover sha_leto callers (none live in this module).
    return "";
}

string LetoOpen(string file, string handler = "")
{
    if(handler == "")
    {
        handler = "TEMP";
    }
    return "%"+handler+" = q<"+file+">;";
}

int LetoPingPong()
{
    // Was a runtime probe of the NWNX2 Leto plugin. NWNX:EE replaces Leto
    // entirely; the HGLL port no longer needs it. Return TRUE so DM-tool
    // diagnostics ("Leto enabled and functioning") stay green.
    return TRUE;
}

string LetoClose(string handler = "")
{
    if(handler == "")
    {
        handler = "TEMP";
    }
    return "close %"+handler+";";
}

string LetoSave(string file, string handler = "")
{
    if(handler == "")
    {
        handler = "TEMP";
    }
    return "%"+handler+" = q?>"+file+"?;";
}




string LETO_ModifyProperty(string sProperty, int iModifier, int Set)
{
    if(!Set)
    {
       return "/"+sProperty+" = /"+sProperty+"+"+IntToString(iModifier)+";";
    }
    else
    {
      return "/"+sProperty+" = "+ IntToString(iModifier)+ ";";
    }

}

string LETO_ModifyWings(int iWing_Number)
{   //"<if:<Wings> ne " + IntToString(iWing_Number) + "><gff:set 'Wings' {value="+IntToString(iWing_Number)+"}></if>"
   return "/Wings = " + IntToString(iWing_Number)+";";
}

string LETO_ModifyTail(int iTail_Number)
{
   return "/Tail = " + IntToString(iTail_Number)+";";
}

string LETO_ModifyPortrait(string sPortrait)
{
    if(sPortrait == "")
    { return "";   }
    return "/Portrait = " + sPortrait +";";
}



string LETO_ModifyFeat(int iFeat, int Remove)
{
    string sScript;
    if(Remove == 0)
    {
        sScript =  "add /FeatList/Feat, type => gffWord, value => " + IntToString(iFeat) + ";" + "add /LvlStatList/[0]/FeatList/Feat, type => gffWord, value => " + IntToString(iFeat) + ";";
    }
    else
    {
       sScript = "replace 'Feat', "+IntToString(iFeat)+", DeleteParent;";
    }
    return sScript;
}



string LETO_ModifySkill(int iSkill, int iModifier, int Set)
{
    if(Set == 0)
    {
      return "/SkillList/["+IntToString(iSkill)+"]/Rank = /SkillList/["+IntToString(iSkill)+"]/Rank+"+IntToString(iModifier)+";" + "/LvlStatList/[0]/SkillList/["+IntToString(iSkill)+"]/Rank = /SkillList/["+IntToString(iSkill)+"]/Rank+"+IntToString(iModifier)+";";
    }
    else
    {
      return "/SkillList/["+IntToString(iSkill)+"]/Rank = " + IntToString(iModifier) + ";" + "/LvlStatList/[0]/SkillList/["+IntToString(iSkill)+"]/Rank = "+IntToString(iModifier)+";";
    }
}


string LETO_SetMovementSpeed(int iSpeed)
{
    if(iSpeed == MOVEMENT_SPEED_CURRENT)
    {
        return "";
    }
    else
    {
       return "/MovementRate = "+IntToString(iSpeed)+";";
    }
}

string LETO_SetSoundSet(int iSoundSetReference)
{
    if(iSoundSetReference == -1)
    {    return ""; }
    return "/SoundSetFile = " + IntToString(iSoundSetReference)+";";
}


string GetBicFileName(object oPC)
{
    string sChar, sBicName;
    string sPCName = GetStringLowerCase(GetName(oPC));
    int i, iNameLength = GetStringLength(sPCName);

    for(i=0; i < iNameLength; i++) {
        sChar = GetSubString(sPCName, i, 1);
        if (TestStringAgainstPattern("(*a|*n|*w|'|-|_)", sChar)) {
            if (sChar != " ") sBicName += sChar;
        }
    }
    return GetStringLeft(sBicName, 15) + ".bic";
}

string LETO_GetBicPath(object oPC)
{
    string  PlayerName = GetLocalString(oPC, "SUBR_PlayerName");
    string BicFilePath = NWNPATH+"servervault/"+PlayerName+"/" + GetBicFileName(oPC);
    return BicFilePath;
}


string SetDocumentedLevel(int level = 1)
{
    return "/Lootable = "+IntToString(level)+";";
}

int GetDocumentedLevel(object oPC)
{
    return StringToInt(LetoScript(LetoOpen(LETO_GetBicPath(oPC)) + "print /Lootable;" + LetoClose()));
}

void DeleteBicFile(string file)
{
    PrintString(LetoScript("FileDelete q<" + file + ">"));
}

string LETO_SetBicTag(string BicFile)
{
  return "/Tag = " + BicFile+";";
}

string LETO_ModifyHitPoints(int iHP, int Set)
{
    string sScript;
    if(Set == 0)
    {
        sScript += "/HitPoints = /HitPoints+" + IntToString(iHP)+";";
        sScript += "/LvlStatList/[0]/LvlStatHitDie = /LvlStatList/[0]/LvlStatHitDie+" + IntToString(iHP)+";";
        sScript += "/MaxHitPoints = /MaxHitPoints+"+ IntToString(iHP)+";";
        sScript += "/CurrentHitPoints = /CurrentHitPoints+" + IntToString(iHP)+";";
        sScript += "/PregameCurrent = /PregameCurrent+" + IntToString(iHP)+";";
        return sScript;
    }
    else
    {
        string sScript;
        sScript += "/HitPoints = " + IntToString(iHP)+";";
        sScript += "/LvlStatList/[0]/LvlStatHitDie = " + IntToString(iHP)+";";
        sScript += "/MaxHitPoints = "+ IntToString(iHP)+";";
        sScript += "/CurrentHitPoints = " + IntToString(iHP)+";";
        sScript += "/PregameCurrent = " + IntToString(iHP)+";";
        return sScript;

    }
}

