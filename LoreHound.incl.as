// Copyright 2017, Earthfiredrake (Peloprata)
// Released under the terms of the MIT License
// https://github.com/Earthfiredrake/TSW-LoreHound

import com.LoreHound.LoreHound;

var efd_LoreHound:LoreHound;
// Function trigger descriptions are based upon the following settings in Modules.xml
// flags = "GMF_DONT_UNLOAD" // Don't unload/reload the entire mod every time it's disabled
// criteria contains "GUIMODEFLAGS_INPLAY | GUIMODEFLAGS_ENABLEALLGUI" // Enable only if the player is in play,

// Called when the clip is first loaded
// - When the player logs in a character, including on relogs
function onLoad():Void {
	efd_LoreHound = new LoreHound();
}

// Often called in pairs, deactivating and reactivating the mod as the criteria evaluation changes
// Due to the frequency of this occuring, these should be relatively light functions
// Activate is called once immediately after onLoad
// Paired calls are made when: Changing zones, cutscenes play, the player anima leaps or is otherwise teleported
// Deactivate is called once immediately prior to OnUnload
function OnModuleActivated():Void {
	efd_LoreHound.Activate();
}

function OnModuleDeactivated():Void {
	efd_LoreHound.Deactivate();
}

// Called just before the game unloads the clip
// - When the user logs out, or returns to character selection (unconfirmed)
function OnUnload():Void {
}
