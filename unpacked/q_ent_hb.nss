// The Thirteenth Ent (roadmap: thirteenth-ent)
// Fangorn Forest (fangornforest) OnHeartbeat: the truffles of the deep loam
// hide from eyes and hands. They rise only while a druid who has taken
// Leaflock's trial is walking the wood IN BOAR FORM, and sink again the
// moment no such druid is left in the area.
#include "q_ent_inc"

void main()
{
    object oArea = OBJECT_SELF;
    int bHunter = FALSE;

    object oObj = GetFirstPC();
    while (GetIsObjectValid(oObj))
    {
        if (GetArea(oObj) == oArea && ENT_IsTruffleHunter(oObj))
        {
            bHunter = TRUE;
            break;
        }
        oObj = GetNextPC();
    }

    if (bHunter)
    {
        if (!ENT_TrufflesUp())
        {
            ENT_SpawnTruffles();
            if (ENT_TrufflesUp())
                ENT_Tell(oObj, "The loam sharpens under your snout. Pale knots "
                             + "of truffle are pushing up through the leaf-mould.");
        }
        return;
    }

    if (ENT_TrufflesUp())
        ENT_ClearTruffles(oArea);
}
