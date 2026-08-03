// _hashome - StartingConditional for the rest-menu "Home" teleport option.
// TRUE only if the speaking PC's CD key owns a player house (admindb houses
// row). Drives whether the "Home" row appears at the top of the Teleports menu.
#include "admin_db"
int StartingConditional()
{
    return Admin_HasHome(GetPCSpeaker());
}
