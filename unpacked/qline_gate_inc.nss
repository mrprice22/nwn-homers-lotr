// Class / prestige quest-line kill switch
// (roadmap: class-quest-lines, prestige-quests)
//
// The ten base-class lines and the twelve prestige-order trials were pulled
// back on 2026-08-14 for creative rework: they repeat each other too closely,
// their rewards need retuning, and they shipped in one batch too large to test.
// Nothing is deleted -- the scripts, includes, giver blueprints, conversations,
// reward items, campaign DBs and the placed AP_ waypoints all stay in the tree,
// so bringing a line back is an edit, not a rebuild.
//
// Consumers:
//   q_<x>_spawn.nss      (10 class givers, plus q_hrp_spawn / q_kwn_spawn)
//   prsg_c_<order>.nss   (12 prestige StartingConditionals on Halmir's root)
//
// TO RE-ENABLE A LINE: delete its token from sOff below. Nothing else. Keys are
// the script prefix -- ftr wiz rog clr rng drd pld mnk bard sor -- plus "prsg"
// for the whole prestige-order set.
//
// Halmir the Grey himself is deliberately NOT gated: prsg_spawn.nss still runs,
// because he has been repurposed as the general in-game quest signpost (and he
// carries the Legendary Feats re-pick, which must keep working).

int QL_LineOff(string sLine)
{
    string sOff = "|ftr|wiz|rog|clr|rng|drd|pld|mnk|bard|sor|prsg|";
    return FindSubString(sOff, "|" + sLine + "|") >= 0;
}
