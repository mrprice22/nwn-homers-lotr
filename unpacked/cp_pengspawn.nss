// cp_pengspawn -- OnSpawn for the Crash Party load penguins (cp_loadmob).
//
// Starts the idle-life loop in cp_pengai.nss, and does nothing else -- no
// standard AI include, because these are scenery with opinions, not combatants.
//
// ## The initial delay is not decoration
//
// A dial press creates 25 penguins inside one frame. If each started ticking
// immediately they would stay in lockstep forever, all doing their scheduled
// work in the same frame every time -- a self-inflicted spike, on the very
// object whose job is to make load MEASURABLE rather than lumpy. The random
// first delay smears them across the interval and they stay smeared.

void main()
{
    // 0-20s, so a whole dial press worth of penguins fans out immediately.
    DelayCommand(IntToFloat(Random(20)) + 1.0, ExecuteScript("cp_pengai", OBJECT_SELF));
}
