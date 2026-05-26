//On module load
//Example of OnLoad Script


//***************************************************************************
// CONSTANTS



//***************************************************************************


//PCs Autosaving
#include "pc_export_inc"


void main()
{

//****************************************************************************
//PCs Autosaving function
pc_export_onmoduleload();
//----------------------------------------------------------------------------

// Spawn Meaningwave NPCs at their designated waypoints
ExecuteScript("mw_spawn", GetModule());

}   //end of main
