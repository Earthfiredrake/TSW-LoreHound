// Copyright 2018, Earthfiredrake
// Released under the terms of the MIT License
// https://github.com/Earthfiredrake/SWL-FrameworkMod

// Config subsystem component for mod and framework versioning and upgrades
// Handles framework setting migrations, and requests migration from mod if needed

import flash.geom.Point; // DEPRECATED(v1.0.0): Temporary upgrade support

import com.GameInterface.DistributedValue; // DEPRECATED(v1.0.0): Temporary upgrade support

// Mod namespace qualified imports and class definition are #included from locally overriden file
#include "Versioning.lcl.as"
	public function Versioning(mod:Mod, initObj:Object) {
		ModObj = mod;
		Config = mod.Config;

		MinUpgradableVersion = initObj.MinUpgradableVersion ? initObj.MinUpgradableVersion : "0.0.0";
		LibUpgrades = initObj.LibUpgrades;

		Config.NewSetting("Installed", false); // Will always be saved as true, only remains false if settings do not exist
		Config.NewSetting("Version", mod.Version);
	}

/// Versioning and Upgrades
	public function UpdateInstall():Void {
		Config.ChangeDefault("Installed", true);
		if (!Config.GetValue("Installed")) {
			// Fresh install, use the actual default value instead of the update placeholder
			Config.ResetValue("TopbarIntegration"); // DEPRECATED(v1.0.0): Temporary upgrade support
			ModObj.InstallMod(); // Mod specific install behaviour
			Config.SetValue("Installed", true);
			Mod.ChatMsg(LocaleManager.GetString("General", "Installed"));
			Mod.ChatMsg(LocaleManager.GetString("General", "ReviewSettings"), { noPrefix : true });
			// Decided against having the options menu auto open here
			// Users might not realize that it's a one off event
			return; // No existing version to update
		}
		var oldVersion:String = Config.GetValue("Version");
		var newVersion:String = Config.GetDefault("Version");
		var versionChange:Number = CompareVersions(newVersion, oldVersion);
		if (versionChange != 0) { // The version changed, either updated or reverted
			if (versionChange > 0) {
				// Verify upgrade restrictions
				if (CompareVersions(MinUpgradableVersion, oldVersion) > 0) {
					Mod.ChatMsg(LocaleManager.FormatString("General", "NoMigration", oldVersion));
					Config.ResetAll();
				} else {
					for (var i:Number = 0; i < LibUpgrades.length; ++i) {
						if (CompareVersions(LibUpgrades[i].mod, oldVersion) >= 0) {
							UpdateLib(LibUpgrades[i].lib); // Library updates
							break;
						}
					}
					ModObj.UpdateMod(newVersion, oldVersion); // Mod specific updates
				}
			}
			// Reset the version number to the new version
			Config.ResetValue("Version");
			Mod.ChatMsg(LocaleManager.FormatString("General", versionChange > 0 ? "Update" : "Revert", newVersion));
			Mod.ChatMsg(LocaleManager.GetString("General", "ReviewSettings"), { noPrefix : true });
		}
	}

	private function UpdateLib(oldVersion:String):Void {
		// v1.1: changes how GUIResolutionScale is used, and adjusts saved ui locations to compensate
		if (CompareVersions("1.1.0", oldVersion) > 0) {
			var scale:Number = DistributedValue.GetDValue("GUIResolutionScale");
			if (Config.HasSetting("InterfaceWindowPosition")) {
				var pos:Point = Config.GetValue("InterfaceWindowPosition");
				Config.SetValue("InterfaceWindowPosition", new Point(pos.x * scale, pos.y * scale));
			}
			if (Config.HasSetting("ConfigWindowPosition")) {
				var pos:Point = Config.GetValue("ConfigWindowPosition");
				Config.SetValue("ConfigWindowPosition", new Point(pos.x * scale, pos.y * scale));
			}
			if (Config.HasSetting("IconPosition")) {
				// Either a Point or a Number
				var pos = Config.GetValue("IconPosition");
				Config.SetValue("IconPosition", Config.GetValue("TopbarIntegration") ? pos * scale :  new Point(pos.x * scale, pos.y * scale));
			}
		}
	}

	// Compares two version strings (format "#.#.#[.alpha|.beta]")
	// Return value encodes the field at which they differ (1: major, 2: minor, 3: build, 4: prerelease tag)
	// If positive, then the first version is higher, negative means first version was lower
	// A return of 0 indicates that the versions were the same
	public static function CompareVersions(firstVer:String, secondVer:String):Number {
		var first:Array = firstVer.split(".");
		var second:Array = secondVer.split(".");
		for (var i = 0; i < Math.min(first.length, second.length); ++i) {
			if (first[i] != second[i]) {
				if (i < 3) {
					return Number(first[i]) < Number(second[i]) ? -(i + 1) : i + 1;
				} else {
					// One's alpha and the other is beta, all other values the same
					return first[i] == "alpha" ? -4 : 4;
				}
			}
		}
		// Version number is the same, but one may still have a pre-release tag
		if (first.length != second.length) {
			return first.length > second.length ? -4 : 4;
		}
		return 0;
	}

	private var ModObj:Mod;
	private var Config:Object; // Local copy of ModObj.Config; Ducktyped ConfigWrapper
	private var MinUpgradableVersion:String; // Minimum installed version allowing setting migration during update
	private var LibUpgrades:Array; // List of library version upgrades as {mod:version, lib:version} pairs
}
