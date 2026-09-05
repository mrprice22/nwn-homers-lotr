// graf_in_app.nss - StartingConditional: TRUE below the top level, so the
// "[Back to ...]" reply only shows where there is somewhere to go back to.
#include "graf_inc"
int StartingConditional()
{
    return GetLocalInt(GetPCSpeaker(), "graf_mode") > 0;
}
