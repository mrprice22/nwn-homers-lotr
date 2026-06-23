#include "zdlg_include_i"
#include "hgll_func_inc"
const string FIRST_PAGE = "skills_select";
const string SECOND_PAGE = "skills_confirm";
const string THIRD_PAGE = "feat_select";
const string FOURTH_PAGE = "feat_confirm";
const string FIFTH_PAGE = "stat_select";
const string SIXTH_PAGE = "stat_confirm";
const string SEVENTH_PAGE = "final_confirm";

void Init()
{
    string page = GetDlgPageString();
    int nSkill;
    int nFeat;
    int nCount = 0;
    int nCount2 = 0;
    string sCrossClass;
    object oPC = GetPcDlgSpeaker();
    if( page == "" )
        {
        if( GetElementCount(FIRST_PAGE, oPC) == 0 )
            {
            for(nSkill = 0; nSkill < 27; nSkill++) //loop through the skill constants
                {
                if (GetIsSkillAvailable(oPC, nSkill)) //if the PC can take the skill, it is displayed
                    {
                    if (GetCostOfSkill(GetControlClass(oPC), nSkill) == 2)
                        {
                        sCrossClass = " [Cross-Class]";
                        }
                    else
                        {
                        sCrossClass = "";
                        }
                    AddStringElement(GetNameOfSkill(nSkill) + sCrossClass, FIRST_PAGE, oPC );
                    ReplaceIntElement(nCount, nSkill, FIRST_PAGE, oPC); //store the skill int with the skill
                    DoDebug(oPC, "Response Number: " + IntToString(nCount) + ", Skill Number: " + IntToString(nSkill) + ".");
                    nCount ++;
                    }
                }
            AddStringElement ("I cannot or do not wish to select any more skills at this time.", FIRST_PAGE, oPC );
            }
        if( GetElementCount(SECOND_PAGE, oPC) == 0 )
            {
            AddStringElement("Yes.", SECOND_PAGE, oPC );
            AddStringElement("No. I want to start over.", SECOND_PAGE, oPC );
            }
        if( GetElementCount(THIRD_PAGE, oPC) == 0 )
            {
            if (GetGainsFeatOnLevelUp(oPC))
                {
                DelayCommand(0.2, ExecuteScript("hgll_featlist_01", oPC));//these scripts break up the below feat loop into 11 parts to avoid TMI errors
                DelayCommand(0.4, ExecuteScript("hgll_featlist_02", oPC));
                DelayCommand(0.6, ExecuteScript("hgll_featlist_03", oPC));
                DelayCommand(0.8, ExecuteScript("hgll_featlist_04", oPC));
                DelayCommand(1.0, ExecuteScript("hgll_featlist_05", oPC));
                DelayCommand(1.2, ExecuteScript("hgll_featlist_06", oPC));
                DelayCommand(1.4, ExecuteScript("hgll_featlist_07", oPC));
                DelayCommand(1.6, ExecuteScript("hgll_featlist_08", oPC));
                DelayCommand(1.8, ExecuteScript("hgll_featlist_09", oPC));
                DelayCommand(2.0, ExecuteScript("hgll_featlist_10", oPC));
                DelayCommand(2.2, ExecuteScript("hgll_featlist_11", oPC));
                /*
                for(nFeat = 0; nFeat < 1072; nFeat++)//loop through the feat constants
                    {
                    if (GetIsFeatAvailable(nFeat, oPC))//if the PC can take the feat, it is displayed
                        {
                        AddStringElement(GetNameOfFeat(nFeat), THIRD_PAGE, oPC );
                        ReplaceIntElement(nCount2, nFeat, THIRD_PAGE, oPC);//store the skill int with the skill
                        DoDebug(oPC, "Response Number: " + IntToString(nCount2) + ", Feat Number: " + IntToString(nFeat) + ".");
                        nCount2 ++;
                        }
                    }
                */
                }
            }
        if( GetElementCount(FOURTH_PAGE, oPC) == 0)
            {
            AddStringElement("Yes.", FOURTH_PAGE, oPC );
            AddStringElement("No. I want to start over.", FOURTH_PAGE, oPC );
            }
        if( GetElementCount(FIFTH_PAGE, oPC ) == 0)
            {
            AddStringElement("Strength", FIFTH_PAGE, oPC );
            ReplaceIntElement(0, ABILITY_STRENGTH, FIFTH_PAGE, oPC);
            AddStringElement("Dexterity", FIFTH_PAGE, oPC );
            ReplaceIntElement(1, ABILITY_DEXTERITY, FIFTH_PAGE, oPC);
            AddStringElement("Constitution", FIFTH_PAGE, oPC );
            ReplaceIntElement(2, ABILITY_CONSTITUTION, FIFTH_PAGE, oPC);
            AddStringElement("Intelligence", FIFTH_PAGE, oPC );
            ReplaceIntElement(3, ABILITY_INTELLIGENCE, FIFTH_PAGE, oPC);
            AddStringElement("Wisdom", FIFTH_PAGE, oPC );
            ReplaceIntElement(4, ABILITY_WISDOM, FIFTH_PAGE, oPC);
            AddStringElement("Charisma", FIFTH_PAGE, oPC );
            ReplaceIntElement(5, ABILITY_CHARISMA, FIFTH_PAGE, oPC);
            }
        if( GetElementCount(SIXTH_PAGE, oPC) == 0)
            {
            AddStringElement("Yes.", SIXTH_PAGE, oPC );
            AddStringElement("No. I want to start over.", SIXTH_PAGE, oPC );
            }
        if( GetElementCount(SEVENTH_PAGE, oPC ) == 0)
            {
            AddStringElement("Yes.", SEVENTH_PAGE, oPC );
            AddStringElement("No. I want to start over.", SEVENTH_PAGE, oPC );
            }
        }
}

void CleanUp()
{
    // Delete the list we create in Init()
    object oPC = GetPcDlgSpeaker();
    DeleteList( FIRST_PAGE, oPC );
    DeleteList( SECOND_PAGE, oPC );
    DeleteList( THIRD_PAGE, oPC );
    DeleteList( FOURTH_PAGE, oPC );
    DeleteList( FIFTH_PAGE, oPC );
    DeleteList( SIXTH_PAGE, oPC );
    DeleteList( SEVENTH_PAGE, oPC );
    DeleteBaseAbilityMarkers(oPC);
}

void PageInit()
{
    string page = GetDlgPageString();
    object oPC= GetPcDlgSpeaker();

    if( page == "" || page == "skill")
        {
        // Then just give the first prompt.
        SetDlgPrompt("Please select a skill to add a point to." +
                     " You have " + IntToString(GetLocalInt(oPC, "PointsAvailable")) +
                     " points remaining to spend.\n" +
                     "(Your available skills are based on your highest-level class: " +
                     GetNameOfClass(GetControlClass(oPC)) + ". " +
                     "Skills restricted to other classes you hold are not shown.)");
        SetDlgResponseList( FIRST_PAGE, oPC );
        }
    else if( page == "skillresponse" )
        {
        SetDlgPrompt("You selected " + GetLocalString(oPC, "LastResponse") +
                     ". Is that the skill you want?");
        SetDlgResponseList( SECOND_PAGE, oPC );
        }
    else if( page == "feat" )
        {
        SetDlgPrompt("Please select the feat you would like to gain this level.");
        SetDlgResponseList( THIRD_PAGE, oPC );
        }
    else if( page == "featresponse" )
        {
        SetDlgPrompt("You selected " + GetLocalString(oPC, "LastResponse") +
                     ". Is that the feat you want?");
        SetDlgResponseList( FOURTH_PAGE, oPC );
        }
    else if( page == "stat" )
        {
        SetDlgPrompt( "Please select the stat you would like to gain this level.");
        SetDlgResponseList( FIFTH_PAGE, oPC );
        }
    else if( page == "statresponse" )
        {
        SetDlgPrompt( "You selected " + GetLocalString(oPC, "LastResponse") +
                      ". Is that the stat you want?");
        SetDlgResponseList( SIXTH_PAGE, oPC );
        }
    else if( page == "finish" )
        {
        SetDlgPrompt( "You will gain the maximum number of hitpoints automatically, as well as any saving throw bonuses. You have selected " +
                      GetLocalString(oPC, "TrackChanges") +
                      "are these the selections you want?");
        SetDlgResponseList( SEVENTH_PAGE, oPC );
        }
}

void HandleSelection()
{
    string page = GetDlgPageString();
    object oPC= GetPcDlgSpeaker();
    int nElements;
    int selection = GetDlgSelection();
    int nSkill;
    int nFeat;
    int nStat;
    int nHP;
    int nLootable;
    string sName;
    string sLeto;
    string sTrack;
    string sChange;
    string sCrossClass;
    int nChange;
    int nTInt;
    int nSLRSkill;
    int nSLRCount;
    int nPointsAvailable;
    int nLevel;
    if( page == "" || page == "skill")
        {
        nElements = GetElementCount(FIRST_PAGE, oPC);
        if (selection == (nElements -1))//last element - they can't (or don't want to) select any more skills
            {
            if (GetGainsFeatOnLevelUp(oPC))//if not, and they get a feat, go to the feat page
                {
                SetDlgPageString( "feat" );
                }
            else if (GetGainsStatOnLevelUp(oPC))//if no skill points left, and no feat is received this level, and they get a stat, go to the stat page
                {
                SpeakString( "You did not recieve a feat this level.", TALKVOLUME_TALK );
                SetDlgPageString( "stat" );
                }
            else //if no skill points left, and no feat or stat is received this level, go to the final page
                {
                SpeakString( "You did not recieve a feat or a stat point this level.", TALKVOLUME_TALK );
                SetDlgPageString( "finish" );
                }
            }
        else //they selected a skill
            {
            nSkill = GetIntElement( selection, FIRST_PAGE, oPC );
            //add to last selection string and int
            sName = GetNameOfSkill(nSkill);
            DoDebug(oPC, "Skill selected: " + sName);
            SetLocalString(oPC, "LastResponse", sName);
            SetLocalInt(oPC, "LastResponseInt", nSkill);
            SetLocalInt(oPC, "SkillIndex", selection);
            SetDlgPageString( "skillresponse" );
            }
        }
    else if ( page == "skillresponse" )
        {
        switch( selection )
            {
            case 0: // Yes
                // add to leto and tracking strings
                sLeto = GetLocalString(oPC, "LetoscriptLL");//String to track Letoscript changes to be made
                sTrack = GetLocalString(oPC, "TrackChanges");//String to track description of changes to be made
                sChange = GetLocalString(oPC, "LastResponse") + ", ";
                nChange = GetLocalInt(oPC, "LastResponseInt");
                DoDebug(oPC, "LastResponseInt: " + IntToString(nChange));
                HGLL_AddSkillPoint(oPC, nChange);
                sLeto += AddSkillPoint(nChange);
                SetLocalString(oPC, "LetoscriptLL", sLeto);
                sTrack += sChange;
                SetLocalString(oPC, "TrackChanges", sTrack);
                // add 1 to the skill's tracking int
                nTInt = GetLocalInt(oPC, GetNameOfTrackingInt(nChange));
                nTInt++;
                SetLocalInt(oPC, GetNameOfTrackingInt(nChange), nTInt);
                DoDebug(oPC, GetNameOfTrackingInt(nChange) + IntToString(nTInt));
                DoDebug(oPC, "TInt Set: " + GetNameOfTrackingInt(nChange) + IntToString(GetLocalInt(oPC, GetNameOfTrackingInt(nChange))));
                // subtract cost of skill from points available
                nPointsAvailable = GetLocalInt(oPC, "PointsAvailable");
                nPointsAvailable = nPointsAvailable - (GetCostOfSkill(GetControlClass(oPC), nChange));
                SetLocalInt(oPC, "PointsAvailable", nPointsAvailable);
                // if they have maxed out the skill or don't have points left for it remove it from the list
                DeleteList(FIRST_PAGE, oPC);
                if( GetElementCount(FIRST_PAGE, oPC) == 0 )
                    {
                    for(nSLRSkill = 0; nSLRSkill < 27; nSLRSkill++) //loop through the skill constants
                        {
                        if (GetIsSkillAvailable(oPC, nSLRSkill)) //if the PC can take the skill, it is displayed
                            {
                            if (GetCostOfSkill(GetControlClass(oPC), nSLRSkill) == 2)
                                {
                                sCrossClass = " [Cross-Class]";
                                }
                            else
                                {
                                sCrossClass = "";
                                }
                            AddStringElement(GetNameOfSkill(nSLRSkill) + sCrossClass, FIRST_PAGE, oPC );
                            ReplaceIntElement(nSLRCount, nSLRSkill, FIRST_PAGE, oPC); //store the skill int with the skill
                            DoDebug(oPC, "Response Number: " + IntToString(nSLRCount) + ", Skill Number: " + IntToString(nSLRSkill) + ".");
                            nSLRCount ++;
                            }
                        }
                    AddStringElement ("I cannot or do not wish to select any more skills at this time.", FIRST_PAGE, oPC );
                    }
                // if they have skill points left, go back to start page
                if (nPointsAvailable > 0)
                    {
                    SetDlgPageString( "skill" );
                    }
                else if (GetGainsFeatOnLevelUp(oPC))//if not, and they get a feat, go to the feat page
                    {
                    SetDlgPageString( "feat" );
                    }
                else if (GetGainsStatOnLevelUp(oPC))//if no skill points left, and no feat is received this level, and they get a stat, go to the stat page
                    {
                    SpeakString( "You did not recieve a feat this level.", TALKVOLUME_TALK );
                    SetDlgPageString( "stat" );
                    }
                else //if no skill points left, and no feat or stat is received this level, go to the final page
                    {
                    SpeakString( "You did not recieve a feat or a stat point this level.", TALKVOLUME_TALK );
                    SetDlgPageString( "finish" );
                    }
                break;
            case 1: // No
                EndDlg();
                break;
            }
        }
    else if ( page == "feat" )
        {
        nFeat = GetIntElement( selection, THIRD_PAGE, oPC );
        //add to last selection string and int
        sName = GetNameOfFeat(nFeat);
        SetLocalString(oPC, "LastResponse", sName);
        SetLocalInt(oPC, "LastResponseInt", nFeat);
        SetDlgPageString( "featresponse" );
        }
    else if ( page == "featresponse" )
        {
        switch( selection )
            {
            case 0: // Yes
                // add to leto and tracking strings
                sLeto = GetLocalString(oPC, "LetoscriptLL");//String to track Letoscript changes to be made
                sTrack = GetLocalString(oPC, "TrackChanges");//String to track description of changes to be made
                sChange = GetLocalString(oPC, "LastResponse") + ", ";
                nChange = GetLocalInt(oPC, "LastResponseInt");
                HGLL_AddFeat(oPC, nChange);
                sLeto += AddFeat(nChange);
                SetLocalString(oPC, "LetoscriptLL", sLeto);
                sTrack += sChange;
                SetLocalString(oPC, "TrackChanges", sTrack);
                if (GetGainsStatOnLevelUp(oPC))
                    {
                    SetDlgPageString( "stat" );
                    }
                else
                    {
                    SpeakString( "You did not recieve a stat point this level.", TALKVOLUME_TALK );
                    SetDlgPageString( "finish" );
                    }
                break;
            case 1: // No
                EndDlg();
                break;
            }
        }
    else if ( page == "stat" )
        {
        nStat = GetIntElement( selection, FIFTH_PAGE, oPC );
        //add to last selection string and int
        sName = GetNameOfAbility(nStat);
        SetLocalString(oPC, "LastResponse", sName);
        SetLocalInt(oPC, "LastResponseInt", nStat);
        DoDebug(oPC, "Stat Int: " + IntToString(nStat));
        SetDlgPageString( "statresponse" );
        }
    else if ( page == "statresponse" )
        {
        switch( selection )
            {
            case 0: // Yes
                // add to leto and tracking strings
                sLeto = GetLocalString(oPC, "LetoscriptLL");//String to track Letoscript changes to be made
                sTrack = GetLocalString(oPC, "TrackChanges");//String to track description of changes to be made
                sChange = GetLocalString(oPC, "LastResponse") + ", ";
                nChange = GetLocalInt(oPC, "LastResponseInt");
                HGLL_AddStatPoint(oPC, nChange);
                sLeto += AddStatPoint(nChange);
                DoDebug(oPC, "Leto String: " + sLeto);
                SetLocalString(oPC, "LetoscriptLL", sLeto);
                sTrack += sChange;
                SetLocalString(oPC, "TrackChanges", sTrack);
                SetDlgPageString( "finish" );
                break;
            case 1: // No
                EndDlg();
                break;
            }
        }
    else if ( page == "finish" )
        {
        switch( selection )
            {
            case 0: // Yes
                 sLeto = GetLocalString(oPC, "LetoscriptLL");//String to track Letoscript changes to be made (now unused; see hgll_leto_inc port notes)
                 nHP = GetHitPointsGainedOnLevelUp(oPC);//calcualate hit point gain
                 nLevel = HGLL_GetDocumentedLevel(oPC);
                 HGLL_AddHitPoints(oPC, nHP, nLevel);
                 if (GetGainsSavesOnLevelUp(oPC))
                    {
                    HGLL_ModifySaves(oPC);
                    }
                 nLootable = HGLL_GetDocumentedLevel(oPC);//track the PC's HGLL level
                 if (nLootable < 41)
                    {
                    HGLL_SetDocumentedLevel(oPC, 41);
                    }
                 else
                    {
                    nLootable++;
                    HGLL_SetDocumentedLevel(oPC, nLootable);
                    }
                 //SubtractXPForNextLL(oPC);
                 nPointsAvailable = GetLocalInt(oPC, "PointsAvailable");//check to see if any skill points left over
                 NWNX_Object_SetInt(oPC, "hgll_points_avail", nPointsAvailable, TRUE);//if so, store them for use for next level
                 HGLL_FlushChanges(oPC);
                 EndDlg();
                 break;
            case 1: // No
                EndDlg();
                break;
            }
        }
}

void main()
{
    int iEvent = GetDlgEventType();
    switch( iEvent )
        {
        case DLG_INIT:
            Init();
            break;
        case DLG_PAGE_INIT:
            PageInit();
            break;
        case DLG_SELECTION:
            HandleSelection();
            break;
        case DLG_ABORT:
            SpeakString( "Legendary leveler conversation ended.", TALKVOLUME_TALK );
            CleanUp();
            break;
        case DLG_END:
            SpeakString( "Legendary leveler conversation ended.", TALKVOLUME_TALK );
            CleanUp();
            break;
        }
}
