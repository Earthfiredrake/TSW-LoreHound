// Copyright 2017, Earthfiredrake (Peloprata)
// Released under the terms of the MIT License
// https://github.com/Earthfiredrake/TSW-LoreHound

import com.LoreHound.LoreHound;

var efd_LoreHound:LoreHound;

function onLoad():Void {
	efd_LoreHound = new LoreHound();
}

function OnModuleActivated():Void {
	efd_LoreHound.Activate();
}

function OnModuleDeactivated():Void {
	efd_LoreHound.Deactivate();
}
