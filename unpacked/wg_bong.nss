// wg_bong.nss - OnUsed on the six water pipes of the Smoking Chamber (area024).
// (roadmap: concerning-pipeweed)
//
// Reworked from the original 2000s-era script. What changed and why:
//
//  * It used to hard-check a single item tag ("witchbud"). It now scans for
//    any of the five Shire strains and lights whichever one the smoker is
//    carrying, handing the actual effects off to pw_inc.nss so the high is
//    rest-persistent (a plain temporary effect is scrubbed by rest, which
//    made the penalty half of every strain free).
//  * The legacy tag "witchbud" is accepted as an alias for Longbottom Leaf,
//    so a pouch handed out by Concerning Hobbits is never stranded.
//  * Witch Weed carries ten charges: smoking it spends ONE CHARGE. The other
//    four strains are destroyed on use, as before.
//  * The 20-second forced EffectSleep at the end is GONE. A hard stun on a
//    hub-area placeable fought the new hour-long buff for no good reason.
//  * The 100-case ActionSpeakString table is gone. It was modern song lyrics
//    and off-colour film quotes, and its colour codes were mojibake from a
//    bad encoding round-trip. Replaced with a short per-strain line set.
//  * The cutscene camera swing and the smoke VFX are kept -- they are the
//    good part -- but they are now assigned to the SMOKER. The original
//    assigned them to OBJECT_SELF, which in a placeable OnUsed is the water
//    pipe itself, so the camera move could never reach the player.

#include "cameraslowmo"
#include "pw_inc"

// Tag of the first strain oSmoker is carrying, or "" if none. Order is the
// order Odo lists them in; "witchbud" is the legacy Longbottom pouch.
string PipeFindLeafTag(object oSmoker)
{
    if (GetIsObjectValid(GetItemPossessedBy(oSmoker, "pw_longbottom"))) return "pw_longbottom";
    if (GetIsObjectValid(GetItemPossessedBy(oSmoker, "witchbud")))      return "witchbud";
    if (GetIsObjectValid(GetItemPossessedBy(oSmoker, "pw_oldtoby")))    return "pw_oldtoby";
    if (GetIsObjectValid(GetItemPossessedBy(oSmoker, "pw_southlinch"))) return "pw_southlinch";
    if (GetIsObjectValid(GetItemPossessedBy(oSmoker, "pw_hornblower"))) return "pw_hornblower";
    if (GetIsObjectValid(GetItemPossessedBy(oSmoker, "pw_witchweed")))  return "pw_witchweed";
    return "";
}

// A quiet, in-setting remark once the smoke has settled. Four per strain.
string PipeLine(string sStrain, int nRoll)
{
    if (sStrain == PW_LONGBOTTOM)
    {
        switch (nRoll)
        {
            case 0: return "*a long breath out* Longbottom. Nothing fancy in it, and nothing wrong with it either.";
            case 1: return "You can hear the water in the pipe. You could hear a pin drop in the next room.";
            case 2: return "Old Toby grew the first of it, they say, and the Shire has not improved on it since.";
            case 3: return "*settles back* Half the trouble in the world would keep, if folk sat down first.";
        }
    }
    else if (sStrain == PW_OLDTOBY)
    {
        switch (nRoll)
        {
            case 0: return "*quietly* Roads go ever on... I had the rest of it a moment ago.";
            case 1: return "The Southfarthing at its best. You could name every Took back nine generations just now.";
            case 2: return "*eyes half closed* Old names. Old songs. They come up out of the smoke like fish.";
            case 3: return "There is a great deal to be said for a pipe and a long memory.";
        }
    }
    else if (sStrain == PW_SOUTHLINCH)
    {
        switch (nRoll)
        {
            case 0: return "Bree leaf. The Shire will tell you it is no good. The Shire buys it by the cartload.";
            case 1: return "*grinning* I could talk a Bracegirdle out of his supper right now, and he would thank me.";
            case 2: return "Southlinch, and no apologies for it. Where is the harm in a little Bree-land soil?";
            case 3: return "*expansively* Have I told you -- I have the finest idea. The finest. Listen.";
        }
    }
    else if (sStrain == PW_HORNBLOWER)
    {
        switch (nRoll)
        {
            case 0: return "*slow and steady* Hornblower's own. Let the dark come. I am in no hurry.";
            case 1: return "The heart sits easier. The hands are a good deal further away than they were.";
            case 2: return "They do not sell this. Somebody owed somebody a favour, and here we are.";
            case 3: return "*breathing out* Whatever is waiting out there can wait a little longer.";
        }
    }
    else if (sStrain == PW_WITCHWEED)
    {
        switch (nRoll)
        {
            case 0: return "*very fast* That is not leaf. I know what leaf is, and that is not it.";
            case 1: return "Everything has gone bright at the edges. I can see how the whole thing fits together.";
            case 2: return "*sharply* Where does Odo get this? He will not say. He looks at the door when you ask.";
            case 3: return "Somewhere, and I could not tell you why, there is a chicken.";
        }
    }
    return "";
}

void main()
{
    object oSmoker = GetLastUsedBy();

    if (!GetIsPC(oSmoker)) return;

    string sTag = PipeFindLeafTag(oSmoker);
    if (sTag == "")
    {
        AssignCommand(oSmoker, ActionSpeakString(
            "*taps out the empty bowl* Nothing to smoke, and no leaf grows in here."));
        return;
    }

    object oLeaf   = GetItemPossessedBy(oSmoker, sTag);
    string sStrain = PW_StrainForItemTag(sTag);
    if (sStrain == "") return;

    AssignCommand(oSmoker, ClearAllActions());

    // The cutscene: the smoker sinks back while the camera swings around.
    SetCutsceneMode(oSmoker, TRUE);
    DelayCommand(10.0, SetCutsceneMode(oSmoker, FALSE));
    AssignCommand(oSmoker, StoreCameraFacing());
    DelayCommand(1.5, AssignCommand(oSmoker,
        PlayAnimation(ANIMATION_LOOPING_DEAD_BACK, 1.0, 8.0)));
    DelayCommand(1.7, ApplyEffectToObject(DURATION_TYPE_TEMPORARY,
        EffectVisualEffect(VFX_DUR_FREEZE_ANIMATION), oSmoker, 5.0));
    GestaltCameraMove(1.7, GetFacing(oSmoker) + 90.0, 18.0, 30.0,
        GetFacing(oSmoker) + 450.0, 12.0, 50.0, 5.0, 40.0, oSmoker);

    // The smoke.
    DelayCommand(0.3, ApplyEffectToObject(DURATION_TYPE_INSTANT,
        EffectVisualEffect(VFX_FNF_SMOKE_PUFF), oSmoker));
    DelayCommand(0.5, ApplyEffectToObject(DURATION_TYPE_INSTANT,
        EffectVisualEffect(VFX_DUR_GHOSTLY_PULSE), oSmoker));
    DelayCommand(0.5, ApplyEffectToObject(DURATION_TYPE_INSTANT,
        EffectVisualEffect(VFX_FNF_SCREEN_BUMP), oSmoker));

    // The high itself -- stored, rest-persistent, one strain at a time.
    PW_Light(oSmoker, sStrain);

    string sLine = PipeLine(sStrain, Random(4));
    if (sLine != "")
        DelayCommand(5.0, AssignCommand(oSmoker, ActionSpeakString(sLine)));

    // Consumption. Witch Weed is a ten-smoke pouch; everything else is a
    // single fill and burns up with it.
    if (sStrain == PW_WITCHWEED)
    {
        int nCharges = GetItemCharges(oLeaf);
        if (nCharges <= 1)
            DestroyObject(oLeaf);
        else
            SetItemCharges(oLeaf, nCharges - 1);
    }
    else
    {
        DestroyObject(oLeaf);
    }
}
