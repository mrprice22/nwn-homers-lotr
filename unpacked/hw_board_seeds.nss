// hw_board_seeds - the participation prize (OBJECT_SELF = PC): one Bag of
// Pumpkin Seeds per character per year, for anyone with at least one gut
// handed in. Deliver first, then record, so a failed hand-over can retry.

#include "hw_inc"

void main()
{
    object oPC = OBJECT_SELF;
    if (HW_GetGuts(oPC) < 1) return;
    sqlquery q = SqlPrepareQueryCampaign(HW_DB,
        "SELECT seeds FROM hw_guts WHERE year=@y AND ident=@i");
    SqlBindInt(q, "@y", HW_Year());
    SqlBindString(q, "@i", HW_Ident(oPC));
    if (!SqlStep(q) || SqlGetInt(q, 0) != 0) return;

    object oBag = CreateItemOnObject("hw26_seeds", oPC);
    if (!GetIsObjectValid(oBag)) return;
    q = SqlPrepareQueryCampaign(HW_DB,
        "UPDATE hw_guts SET seeds=1 WHERE year=@y AND ident=@i");
    SqlBindInt(q, "@y", HW_Year());
    SqlBindString(q, "@i", HW_Ident(oPC));
    SqlStep(q);
    SendMessageToPC(oPC, COLOR_ORANGE + "The Gourd Board gives you a Bag of Pumpkin Seeds for your trouble." + COLOR_END);
}
