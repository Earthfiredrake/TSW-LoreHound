// Copyright 2018, Earthfiredrake
// Released under the terms of the MIT License
// https://github.com/Earthfiredrake/SWL-FrameworkMod

// ConfigHost implementation
// Dependencies:
//   Subsystems: None (Inclusion only)
//   Library Symbols: As required by Window (WindowName = "ConfigWindow")
// InitObj:
//   ArchiveName:String (optional, default uses archive provided by game engine)
//     Alternate archive name to use for settings
//   MinUpgradableVersion:String (optional, default "0.0.0")
//     Earliest version that Versioning will maintain settings when upgrading,
//     Upgrading any earlier version will reset settings to defaults
//   LibUpgrades:Array of {mod:String, lib:String} (semi-optional, default handles no library upgrades)
//     List of final mod versions (if >= MinUpgradableVersion) that used each prior version of the library

// The framework reserves the following Config setting names for internal use:
//   "Enabled": Exists for e_ModType_Reactive mods
//   Added by ConfigHost (Versioning):
//     "Installed": Trigger first run events
//     "Version": Triggers upgrades (and rollback notifications)
//   Added for each window, most commonly "InterfaceWindow" and "ConfigWindow":
//     "[WindowName]Position":
//     "[WindowName]Size": If window permits resizing
//   Added by ModIcon:
//     "IconPosition": Deleted if VTIO mod is handling layout; otherwise, a single (X) coordinate with TopbarIntegration or a Point without it
//     "IconScale": Deleted if integrated with any topbar
//     "TopbarIntegration": VTIO integration without an icon is implied by attachment of VTIOHelper

import com.GameInterface.DistributedValue;
import com.Utils.Archive;

// Mod namespace qualified imports and class definition are #included from locally overriden file
#include "ConfigManager.lcl.as"
	public static function Create(mod:Mod, initObj:Object) {
		return new ConfigManager(mod, initObj);
	}

	public function ConfigManager(mod:Mod, initObj:Object) {
		Config = new ConfigWrapper(initObj.ArchiveName);
		mod.Config = Config;

		UpdateManager = new Versioning(mod, initObj);

		ResetDV = DistributedValue.Create(Mod.DVPrefix + mod.ModName + "ResetConfig");
		ResetDV.SignalChanged.Connect(ResetConfig, this);

		ConfigWindow = Window.Create(mod, {WindowName : "ConfigWindow", LoadEvent : WeakDelegate.Create(this, ConfigWindowLoaded)});
	}

	private function ConfigWindowLoaded(windowContent:Object):Void { windowContent.AttachConfig(Config); }

	private function ResetConfig(dv:DistributedValue):Void {
		if (dv.GetValue()) {
			Config.ResetAll();
			dv.SetValue(false);
		}
	}

	private var Config:ConfigWrapper;
	public var ConfigWindow:Window;

	public var UpdateManager:Versioning;

	private var ResetDV:DistributedValue;
}
