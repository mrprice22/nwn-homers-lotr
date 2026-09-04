// brd_db.nss - "Roll of the Fallen" boss respawn tracker database helpers.
//
// Campaign DB "respawndb" (file database/respawndb.sqlite3).
//
// Tables:
//   boss_registry (resref PK, name, tag, area_resref, area_name, cr,
//                  respawn_seconds, spawn_type) - the curated list of tracked
//                  bosses, reseeded from this file on every module load.
//                  spawn_type 'placed'    = se_respawn_inc DelayCommand, exact
//                                           respawn respawn_seconds after death;
//                  spawn_type 'encounter' = native encounter ResetTime, the boss
//                                           becomes ELIGIBLE after respawn_seconds
//                                           and returns when its lair encounter
//                                           next triggers.
//   boss_alias    (resref PK, canonical) - variant blueprints that all represent
//                  the same boss (e.g. the five leveled Xanith The Mad blueprints).
//   boss_deaths   (resref PK, died_at, killed_by) - one row per currently-dead
//                  boss; wiped on module load because a restart revives everything.
//
// Membership rule: only bosses that can ever have ONE live instance at a time
// (exactly one placement, or one Max=1 encounter slot). Enforced by
// tests/check_boss_registry.py in the build smoke-test.
//
// Browsed 9-per-page in brd_sign.dlg (the Well of Eru board). Custom tokens:
//   6300-6308 = list row labels   6309 = header / page line
//   6310-6313 = drill-down detail (name, lair, return line, slain-by)
// Per-PC locals:
//   int    "brd_page_off"  row offset (multiples of 9)
//   int    "brd_total"     total dead-boss rows (for [Next page] visibility)
//   string "brd_slot_N"    registry resref shown in list slot N ("" = hidden)

const string BRD_DB = "respawndb";

// ------------------------------------------------------------
// Schema + registry seed

void BRD_SeedBoss(string sResref, string sName, string sTag, string sAreaRes,
                  string sAreaName, float fCR, int nRespawn, string sType)
{
    sqlquery q = SqlPrepareQueryCampaign(BRD_DB,
        "REPLACE INTO boss_registry(resref,name,tag,area_resref,area_name,cr,respawn_seconds,spawn_type)" +
        " VALUES(@r,@n,@t,@ar,@an,@c,@s,@ty)");
    SqlBindString(q, "@r",  sResref);
    SqlBindString(q, "@n",  sName);
    SqlBindString(q, "@t",  sTag);
    SqlBindString(q, "@ar", sAreaRes);
    SqlBindString(q, "@an", sAreaName);
    SqlBindFloat (q, "@c",  fCR);
    SqlBindInt   (q, "@s",  nRespawn);
    SqlBindString(q, "@ty", sType);
    SqlStep(q);
}

void BRD_SeedAlias(string sResref, string sCanonical)
{
    sqlquery q = SqlPrepareQueryCampaign(BRD_DB,
        "REPLACE INTO boss_alias(resref,canonical) VALUES(@r,@c)");
    SqlBindString(q, "@r", sResref);
    SqlBindString(q, "@c", sCanonical);
    SqlStep(q);
}

void BRD_InitDb()
{
    sqlquery q;

    q = SqlPrepareQueryCampaign(BRD_DB,
        "CREATE TABLE IF NOT EXISTS boss_registry (" +
        "resref TEXT PRIMARY KEY," +
        "name TEXT NOT NULL," +
        "tag TEXT NOT NULL," +
        "area_resref TEXT NOT NULL," +
        "area_name TEXT NOT NULL," +
        "cr REAL NOT NULL DEFAULT 0," +
        "respawn_seconds INTEGER NOT NULL DEFAULT 900," +
        "spawn_type TEXT NOT NULL DEFAULT 'placed')");
    SqlStep(q);

    q = SqlPrepareQueryCampaign(BRD_DB,
        "CREATE TABLE IF NOT EXISTS boss_alias (" +
        "resref TEXT PRIMARY KEY, canonical TEXT NOT NULL)");
    SqlStep(q);

    q = SqlPrepareQueryCampaign(BRD_DB,
        "CREATE TABLE IF NOT EXISTS boss_deaths (" +
        "resref TEXT PRIMARY KEY," +
        "died_at TEXT NOT NULL," +
        "killed_by TEXT)");
    SqlStep(q);

    // A restart revives every boss (DelayCommand timers die; areas reload from
    // the .git), so pending death rows are stale by definition.
    q = SqlPrepareQueryCampaign(BRD_DB, "DELETE FROM boss_deaths");
    SqlStep(q);

    // Reseed the registry so this file is the single source of truth.
    q = SqlPrepareQueryCampaign(BRD_DB, "DELETE FROM boss_registry");
    SqlStep(q);
    q = SqlPrepareQueryCampaign(BRD_DB, "DELETE FROM boss_alias");
    SqlStep(q);

    // BEGIN GENERATED REGISTRY - produced by bin/gen-boss-registry.py
    // Do not hand-edit; run the generator to refresh (see CLAUDE-boss-tracker.md).
    BRD_SeedBoss("creature016", "Theoden's Chosen", "TheodensChosen", "area013", "Helm's Deep: Cave", 9540.0, 1200, "placed");
    BRD_SeedBoss("weathertopkin004", "Weathertop King", "WeathertopKing", "area028", "Weather Top's Hidden Court", 3400.0, 1200, "placed");
    BRD_SeedBoss("weathertopque003", "Weathertop Queen", "WeathertopQueen", "area028", "Weather Top's Hidden Court", 3100.0, 1200, "placed");
    BRD_SeedBoss("summanus", "Summanus", "Summanus", "falseheaven", "Numenor: Noirinan", 2938.0, 1200, "encounter");
    BRD_SeedBoss("gandalf001", "Gandalf the Gray", "Gandalf", "shirehobbiton001", "Hobbiton", 1914.0, 1200, "placed");
    BRD_SeedBoss("highwizardofgo_2", "High Wizard of Gondor", "HighWizardofGondor", "towerofthehighwi", "Tower of the High Wizard: The High Wizard's Chamber", 1795.0, 1200, "placed");
    BRD_SeedBoss("creature019", "Sauron The Abhorred", "Constantinethesecond", "area016", "Mount Doom: Halls of Sauron", 1768.0, 1200, "placed");
    BRD_SeedBoss("gwathdorlord001", "Gwathdor Lord of the Dark Arts", "GwathdorLord", "gwaththrone", "Gwathdor: Throne of the Lord", 1615.0, 1200, "placed");
    BRD_SeedBoss("creature009", "Boromir, Steward of Gondor", "BoromirStewardofGondor", "minastirith", "Minas Tirith: City", 1461.0, 1200, "placed");
    BRD_SeedBoss("creature003", "Denethor, Steward of Gondor", "DenethorStewardofGondor", "area005", "Minas Tirith: Keep", 1459.0, 1200, "placed");
    BRD_SeedBoss("legolasgreenl001", "Legolas Greenleaf - Silvan Prince of Mirkwood", "LegolasGreenleaf", "area023", "Mirkwoods - Halls of Greenleafs", 1418.0, 1200, "encounter");
    BRD_SeedBoss("witchking", "Witch King Leader of The Nine", "WitchKing", "thewitchkingsthr", "The Witch King's Throne", 1198.0, 1200, "placed");
    BRD_SeedBoss("radagastthebro_2", "Radagast the Brown", "RadagasttheBrown", "rhosgobeltower", "Rhosgobel: Tower", 1086.0, 1200, "placed");
    BRD_SeedBoss("thecursedone002", "Heir of Haldor", "TheCursedOne", "forgottenking", "Dimholt: The Forgotten King", 1066.0, 1200, "placed");
    BRD_SeedBoss("themightysmag002", "The Mighty Smaug", "TheMightySmaug", "darkcavern", "The Ruins of Dale: Cavern", 1048.0, 1200, "placed");
    BRD_SeedBoss("gollum", "Gollum", "Gollum", "area007", "Gollum's Chambers", 1029.0, 1200, "placed");
    BRD_SeedBoss("templemistress_2", "Temple Mistress", "TempleMistress", "blackgatge", "Morannon - The Black Gate", 980.0, 1200, "placed");
    BRD_SeedBoss("creature007", "Khamul The Ringwraith (Dol Guldur)", "Khamul", "area031", "Dol Guldur: Tower Of Black Magic Nazgul Quaters", 965.0, 1200, "encounter");
    BRD_SeedBoss("creature007_2", "Khamul The Ringwraith (Carn Dum)", "Khamul", "carndumthrone", "Carn Dum: Throne", 839.0, 1200, "placed");
    BRD_SeedBoss("elrond001_2", "Elrond", "Elrond", "rivendellupperha", "Rivendell Upper Halls", 829.0, 1200, "placed");
    BRD_SeedBoss("harethofthehalad", "Hareth of the Haladin", "HarethoftheHaladin", "edoras", "Edoras", 811.0, 1200, "placed");
    BRD_SeedBoss("creature023_2", "The Rancid Skinner Green Mortal of Khamul", "Skinner", "dolguldurcast001", "Dol Guldur: Tower Of Black Magic Depths", 810.0, 1200, "placed");
    BRD_SeedBoss("adwarfguardia001", "Gloin King Under the Mountain", "GloinKingUndertheMountain", "lonelymountainma", "Lonely Mountain: Main Hall", 799.0, 1200, "placed");
    BRD_SeedBoss("creature005", "Arwen, The Evenstar", "ArwenTheEvenstar", "rivendellupperha", "Rivendell Upper Halls", 767.0, 1200, "placed");
    BRD_SeedBoss("aragornsonofarat", "Aragorn Son of Arathorn", "AragornSonofArathorn", "minastirithgates", "Minas Tirith: Gates", 712.0, 1200, "placed");
    BRD_SeedBoss("eowyntheshieldma", "Eowyn the Shieldmaiden", "EowyntheShieldmaiden", "area008", "Helm's Deep: Keep", 693.0, 1200, "placed");
    BRD_SeedBoss("shadowlordof_2", "Shadow Lord of Dol Guldur", "ShadowLordof", "dolguldur", "Mirkwood: Dol Guldur", 660.0, 1200, "placed");
    BRD_SeedBoss("ulmothevalar_2", "Ulmo the Valar", "UlmotheValar", "area022", "Valinor: Realm of the spirits", 650.0, 1200, "placed");
    BRD_SeedBoss("angmar", "Angmar", "ms_Angmar", "area009", "Angmar's Lair", 637.0, 1200, "placed");
    BRD_SeedBoss("sarumanthewhi001", "Saruman the White", "ms_orth17", "towerofothancsar", "Tower of Orthanc: Saruman's Chambers", 627.0, 1200, "placed");
    BRD_SeedBoss("thehighmageofbar", "Gothmog Lord of Barad-Dur", "LordofBaradDur", "baraddurkeep", "Barad-Dur: Keep", 604.0, 1200, "placed");
    BRD_SeedBoss("grimbeorntheo001", "Grimbeorn the Old Lord of the Beornings", "GrimbeorntheOld", "beorn", "Beorn", 587.0, 1200, "placed");
    BRD_SeedBoss("basilisk008", "Basilisk King", "BasiliskKing", "area003", "Mirkwood: Crypt Chamber", 564.0, 1200, "encounter");
    BRD_SeedBoss("azagoth001", "The Balrog of Moria", "TheBalrogofMoria", "thebalrogofmoria", "Moria: The Balrog of Moria", 555.0, 1200, "encounter");
    BRD_SeedBoss("highpriestofmora", "High Priest of Morannon", "HighPriestofMorannon", "thetempleofmoran", "The Temple of Morannon", 495.0, 1200, "placed");
    BRD_SeedBoss("thranduil_2", "Thranduil, King of Eryn Lasgalen", "ThranduilKingofErynLasgalen", "thranduilshall", "Mirkwood: Thranduil's Hall", 476.0, 1200, "placed");
    BRD_SeedBoss("shadowlordof001", "Shadow Priestess of Dol Guldur", "ShadowLordof", "cavesofdolguldur", "Caves of Dol Guldur", 463.0, 1200, "placed");
    BRD_SeedBoss("creature002", "Faramir, Prince of Ithillien", "Faramir", "citidelofstars", "Osgiliath: Citidal of the Stars", 451.0, 1200, "placed");
    BRD_SeedBoss("shopkeep002_2", "High Priest of Gondor", "NW_PriestofGondor", "minastirithtemp", "Minas Tirith: Temple", 447.0, 1200, "placed");
    BRD_SeedBoss("creature017_2", "Eothain Captian of Helm's Deep", "othain", "helmsdeep001", "Helm's Deep", 440.0, 1200, "placed");
    BRD_SeedBoss("maggotfarmer", "Maggot Farmer", "MaggotFarmer", "bywater", "Bywater", 436.0, 1200, "placed");
    BRD_SeedBoss("akhorahil006_2", "Morgrond Captian of Dol Guldur", "MorgrondCaptian", "dolguldurcity", "Dol Guldur City", 433.0, 1200, "placed");
    BRD_SeedBoss("gimli_2", "Gimli", "Gimli", "halloftruth", "The Halls of Truth", 418.0, 1200, "placed");
    BRD_SeedBoss("kerufall003", "Kerufall", "ms_keru1", "kerufallslair", "Kerufall's Lair", 418.0, 1200, "encounter");
    BRD_SeedBoss("urukai010", "The White Hand Destroyer", "ms_iseno10", "isengardouterrim", "Isengard (Outerrim)", 374.0, 1200, "placed");
    BRD_SeedBoss("gondorianwiza001", "Sarah the Librarian", "GreaterGondorianWizard", "towerofthehig001", "Tower of the High Wizard: The Library", 372.0, 1200, "placed");
    BRD_SeedBoss("gondorianguar005", "Wart Gondorian Gate Captain", "ms_minas22122", "minastirithgates", "Minas Tirith: Gates", 341.0, 1200, "placed");
    BRD_SeedBoss("theoden002", "Theoden King of Rohan", "ms_edort5", "theodenshall", "Theoden's Hall", 338.0, 1200, "placed");
    BRD_SeedBoss("bauglirthegene_2", "Deekin the General", "DeekintheGeneral", "orcarmory", "Orc Armory", 336.0, 1200, "placed");
    BRD_SeedBoss("badass_2", "Fell Beast", "balsum", "kallristcryptlow", "Kallrist Crypt", 333.0, 1200, "placed");
    BRD_SeedBoss("glorfindel002", "Glorfindel", "Glorfindel", "thevalleyofriven", "The Valley of Rivendell", 323.0, 1200, "placed");
    BRD_SeedBoss("creature013", "Sarumon's Master Experiment", "SarumonsMasterExperiment", "towerofothancsar", "Tower of Orthanc: Saruman's Chambers", 316.0, 1200, "placed");
    BRD_SeedBoss("strongminitao002", "Gwathdor Minitaour", "StrongMinitaour", "gwathtomb", "Gwathdor: Tomb", 280.0, 1200, "placed");
    BRD_SeedBoss("akhorahil004", "Dol Guldur Orc General", "DolGuldurOrcGeneral", "dolguldurcity", "Dol Guldur City", 277.0, 1200, "placed");
    BRD_SeedBoss("creature012_2", "Thragg, Gate Commander", "ThraggGateCommander", "blackgatge", "Morannon - The Black Gate", 267.0, 1200, "placed");
    BRD_SeedBoss("rangerofthe002", "Tren Notteel", "Rangerofthe", "rivendell", "Rivendell", 267.0, 1200, "placed");
    BRD_SeedBoss("frost001", "Frost", "Frost", "emynarnen", "Emyn Arnen: Peak", 256.0, 1200, "encounter");
    BRD_SeedBoss("greaterelvenw003", "Celeborn", "ms_lorien21", "lothlorienflets", "Lothlorien: Flets", 250.0, 1200, "placed");
    BRD_SeedBoss("anaraliathewidow", "Anaralia, The widow maker", "AnaraliaThewidowmaker", "mirkwoodcentrale", "Mirkwood: Central East", 248.0, 1200, "placed");
    BRD_SeedBoss("kainnatheward001", "Kainna the War Dancer", "ms_isen24", "isengardinnerrim", "Isengard (Innerrim)", 239.0, 1200, "placed");
    BRD_SeedBoss("jester", "Jester", "Jester", "area008", "Helm's Deep: Keep", 236.0, 1200, "placed");
    BRD_SeedBoss("creature020", "Mashano, Messenger To The Witch King", "MashanoMessengerToTheWitchKing", "nazgulguildhouse", "House of Nazgul", 236.0, 1200, "placed");
    BRD_SeedBoss("shelob001", "Shelob", "ms_shel1", "shelobslair", "Shelob's Lair", 220.0, 1200, "encounter");
    BRD_SeedBoss("adwarfajudica003", "Fifur the Craftsman", "FifurtheCraftsman", "thehallsoftruth", "Temple of Marr", 212.0, 1200, "placed");
    BRD_SeedBoss("arohirrimsold006", "Card Mennard", "ms_edor1", "edoras", "Edoras", 201.0, 1200, "placed");
    BRD_SeedBoss("gntfire003", "Gorg the General", "ms_gund27", "mountgundabadlev", "Mount Gundabad", 191.0, 1200, "placed");
    BRD_SeedBoss("garbag", "Garbag Gulon", "Garbag", "orcarmory", "Orc Armory", 179.0, 1200, "placed");
    BRD_SeedBoss("trollking", "Troll King", "TrollKing", "thetrollshalls", "The Trollshaws", 155.0, 1200, "placed");
    BRD_SeedBoss("galadriel", "Galadriel", "Galadriel", "lothlorien", "Lothlorien: Main", 150.0, 1200, "placed");
    BRD_SeedBoss("railthewhiteh001", "Rail the White Hand Blaster", "ms_isen1", "isengardinnerrim", "Isengard (Innerrim)", 146.0, 1200, "placed");
    BRD_SeedBoss("drgblue004", "The Ice Queen", "TheIceQueen", "icequeennest", "Ice Queen: Nest", 133.0, 1200, "placed");
    BRD_SeedBoss("themutantterror", "The Mutant Terror", "TheMutantTerror", "balinstomb", "Balin's Tomb", 132.0, 1200, "encounter");
    BRD_SeedBoss("cultmember002_3", "Numanan Numerocks Second Hand", "ms_carn26", "carndumcity", "Carn Dum: City", 130.0, 1200, "placed");
    BRD_SeedBoss("cultmember002_2", "Numarok The Black Hand", "ms_carn26", "area078", "Carn Dum: Numerok's Den", 130.0, 1200, "placed");
    BRD_SeedBoss("urukai013", "Marshall of the White Hand", "ms_orth5", "toweroforthanc", "Tower of Orthanc", 107.0, 1200, "placed");
    BRD_SeedBoss("drowfight023_2", "Elor Desh", "BlackNumenorianMilitia", "carndum", "Carn Dum", 106.0, 1200, "placed");
    BRD_SeedBoss("railthewhiteh003", "Fail the White Hand Blaster", "ms_isenm1", "isengardmagicroo", "Isengard (Magic Room)", 96.0, 1200, "placed");
    BRD_SeedBoss("drowrogue024_2", "Morfiril Cendel", "BlackNumenorianShadowMaster", "carndumtemple", "Carn Dum: Temple", 89.0, 1200, "placed");
    BRD_SeedBoss("gondorianguar0_4", "Gondorian Bowman", "ms_minas1", "watchmandefender", "Minas Tirith: Watchman Defender's Head Quarters", 85.0, 1200, "placed");
    BRD_SeedBoss("gondorianguar0_2", "Gondorian Guardsman", "ms_minas2", "watchmandefender", "Minas Tirith: Watchman Defender's Head Quarters", 80.0, 1200, "placed");
    BRD_SeedBoss("adwarfajudica0_3", "Dellinth the Advocet", "ms_lone37", "halloftruth", "The Halls of Truth", 63.0, 1200, "placed");
    // END GENERATED REGISTRY

}

// ------------------------------------------------------------
// Recording

string BRD_Canonical(string sResref)
{
    sqlquery q = SqlPrepareQueryCampaign(BRD_DB,
        "SELECT canonical FROM boss_alias WHERE resref=@r");
    SqlBindString(q, "@r", sResref);
    if (SqlStep(q)) return SqlGetString(q, 0);
    return sResref;
}

// Walk the master chain to the owning PC; OBJECT_INVALID if none is a PC.
object BRD_OwningPC(object o)
{
    while (GetIsObjectValid(GetMaster(o))) o = GetMaster(o);
    if (GetIsPC(o) && !GetIsDM(o)) return o;
    return OBJECT_INVALID;
}

// Record a tracked boss's death (no-op for anything not in the registry).
// Called from bst_ondeath, so the bestiary damage-contributor list
// (bst_ctrb_N locals, gathered by bst_ondamage) is available on the corpse;
// the killing blow's owning PC is folded in for one-shot kills.
void BRD_RecordDeath(object oCre)
{
    string sRef = BRD_Canonical(GetResRef(oCre));

    sqlquery qc = SqlPrepareQueryCampaign(BRD_DB,
        "SELECT 1 FROM boss_registry WHERE resref=@r");
    SqlBindString(qc, "@r", sRef);
    if (!SqlStep(qc)) return;

    string sKilledBy = "";
    object oKiller = BRD_OwningPC(GetLastKiller());
    int bKillerListed = FALSE;

    int nN = GetLocalInt(oCre, "bst_ctrb_n");
    int i;
    for (i = 0; i < nN; i++)
    {
        object m = GetLocalObject(oCre, "bst_ctrb_" + IntToString(i));
        if (!GetIsObjectValid(m) || !GetIsPC(m) || GetIsDM(m)) continue;
        if (m == oKiller) bKillerListed = TRUE;
        if (sKilledBy != "") sKilledBy += ", ";
        sKilledBy += GetName(m);
    }
    if (GetIsObjectValid(oKiller) && !bKillerListed)
    {
        if (sKilledBy != "") sKilledBy += ", ";
        sKilledBy += GetName(oKiller);
    }
    if (sKilledBy == "") sKilledBy = "unknown forces";

    sqlquery q = SqlPrepareQueryCampaign(BRD_DB,
        "REPLACE INTO boss_deaths(resref,died_at,killed_by)" +
        " VALUES(@r,datetime('now'),@k)");
    SqlBindString(q, "@r", sRef);
    SqlBindString(q, "@k", sKilledBy);
    SqlStep(q);
}

// ------------------------------------------------------------
// Board conversation (brd_sign.dlg)

// "12m 30s" / "45s"
string BRD_FmtRemain(int nSec)
{
    if (nSec < 0) nSec = 0;
    int nMin = nSec / 60;
    int nS   = nSec % 60;
    if (nMin > 0) return IntToString(nMin) + "m " + IntToString(nS) + "s";
    return IntToString(nS) + "s";
}

// TRUE when a living creature with sTag stands in area sAreaRes.
int BRD_BossAlive(string sTag, string sAreaRes)
{
    int n = 0;
    object o = GetObjectByTag(sTag, n);
    while (GetIsObjectValid(o))
    {
        if (GetObjectType(o) == OBJECT_TYPE_CREATURE && !GetIsDead(o)
            && GetResRef(GetArea(o)) == sAreaRes)
            return TRUE;
        n++;
        o = GetObjectByTag(sTag, n);
    }
    return FALSE;
}

// Drop rows whose boss is back: placed bosses respawn exactly on schedule, so
// an expired row is stale; encounter bosses only return when the lair
// re-triggers, so keep their row ("ready to return") until the boss is seen
// alive in its area.
void BRD_CleanupExpired(object oPC)
{
    sqlquery q = SqlPrepareQueryCampaign(BRD_DB,
        "SELECT d.resref, r.tag, r.area_resref, r.spawn_type" +
        " FROM boss_deaths d JOIN boss_registry r ON r.resref=d.resref" +
        " WHERE r.respawn_seconds - (strftime('%s','now') - strftime('%s',d.died_at)) <= 0");
    int nDel = 0;
    while (SqlStep(q))
    {
        string sRef  = SqlGetString(q, 0);
        string sTag  = SqlGetString(q, 1);
        string sArea = SqlGetString(q, 2);
        string sType = SqlGetString(q, 3);
        if (sType == "placed" || BRD_BossAlive(sTag, sArea))
        {
            SetLocalString(oPC, "brd_del_" + IntToString(nDel), sRef);
            nDel++;
        }
    }
    int i;
    for (i = 0; i < nDel; i++)
    {
        sqlquery qd = SqlPrepareQueryCampaign(BRD_DB,
            "DELETE FROM boss_deaths WHERE resref=@r");
        SqlBindString(qd, "@r", GetLocalString(oPC, "brd_del_" + IntToString(i)));
        SqlStep(qd);
        DeleteLocalString(oPC, "brd_del_" + IntToString(i));
    }
}

// Build the current list page: only currently-slain bosses, mightiest (highest
// CR) first, time-to-return at the end of each label.
void BRD_BuildPage(object oPC)
{
    BRD_CleanupExpired(oPC);

    int nOff = GetLocalInt(oPC, "brd_page_off");

    sqlquery qc = SqlPrepareQueryCampaign(BRD_DB,
        "SELECT COUNT(*) FROM boss_deaths d" +
        " JOIN boss_registry r ON r.resref=d.resref");
    int nTotal = 0;
    if (SqlStep(qc)) nTotal = SqlGetInt(qc, 0);
    SetLocalInt(oPC, "brd_total", nTotal);

    int i;
    for (i = 0; i < 9; i++)
    {
        DeleteLocalString(oPC, "brd_slot_" + IntToString(i));
        SetCustomToken(6300 + i, "");
    }

    if (nTotal == 0)
    {
        SetCustomToken(6309,
            "All the great powers of Middle-earth stir once more. None lie slain.");
        return;
    }

    int nPages = (nTotal + 8) / 9;
    int nPage  = nOff / 9 + 1;
    SetCustomToken(6309, IntToString(nTotal)
        + (nTotal == 1 ? " power lies" : " powers lie")
        + " slain, mightiest first.  (Page " + IntToString(nPage)
        + " of " + IntToString(nPages) + ")");

    sqlquery q = SqlPrepareQueryCampaign(BRD_DB,
        "SELECT d.resref, r.name, r.spawn_type," +
        " r.respawn_seconds - (strftime('%s','now') - strftime('%s',d.died_at))" +
        " FROM boss_deaths d JOIN boss_registry r ON r.resref=d.resref" +
        " ORDER BY r.cr DESC, r.name ASC LIMIT 9 OFFSET @off");
    SqlBindInt(q, "@off", nOff);

    i = 0;
    while (SqlStep(q) && i < 9)
    {
        string sRef    = SqlGetString(q, 0);
        string sName   = SqlGetString(q, 1);
        string sType   = SqlGetString(q, 2);
        int    nRemain = SqlGetInt(q, 3);

        SetLocalString(oPC, "brd_slot_" + IntToString(i), sRef);

        string sWhen;
        if (nRemain > 0)      sWhen = "returns in " + BRD_FmtRemain(nRemain);
        else                  sWhen = "ready to return";  // expired encounter boss
        SetCustomToken(6300 + i, sName + "  -  " + sWhen);
        i++;
    }
}

// Populate the drill-down detail tokens for one slain boss.
void BRD_BuildDetail(object oPC, string sResref)
{
    SetCustomToken(6310, "");
    SetCustomToken(6311, "");
    SetCustomToken(6312, "");
    SetCustomToken(6313, "");

    sqlquery q = SqlPrepareQueryCampaign(BRD_DB,
        "SELECT r.name, r.area_name, r.spawn_type, d.killed_by," +
        " r.respawn_seconds - (strftime('%s','now') - strftime('%s',d.died_at))" +
        " FROM boss_deaths d JOIN boss_registry r ON r.resref=d.resref" +
        " WHERE d.resref=@r");
    SqlBindString(q, "@r", sResref);
    if (!SqlStep(q))
    {
        SetCustomToken(6310, "The ink has faded; this power walks again.");
        return;
    }

    string sType   = SqlGetString(q, 2);
    int    nRemain = SqlGetInt(q, 4);

    SetCustomToken(6310, SqlGetString(q, 0));
    SetCustomToken(6311, SqlGetString(q, 1));

    string sWhen;
    if (nRemain > 0)
    {
        sWhen = "Expected to return in " + BRD_FmtRemain(nRemain) + ".";
        if (sType == "encounter")
            sWhen += " It rises only when its lair is next disturbed.";
    }
    else
        sWhen = "It may return the moment its lair is next disturbed.";
    SetCustomToken(6312, sWhen);

    string sKilledBy = SqlGetString(q, 3);
    if (sKilledBy == "") sKilledBy = "unknown forces";
    SetCustomToken(6313, sKilledBy);
}
