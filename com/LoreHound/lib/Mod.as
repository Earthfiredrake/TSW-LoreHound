// Copyright 2017, Earthfiredrake (Peloprata)
// Released under the terms of the MIT License
// https://github.com/Earthfiredrake/TSW-LoreHound

import com.GameInterface.DistributedValue;
import com.GameInterface.Log;
import com.GameInterface.Utils;
import com.Utils.Signal;

import com.LoreHound.lib.ConfigWrapper;

// Base class with general mod utility functions
// The Mod framework reserves the Config setting names "Version" and "Installed" for internal use
class com.LoreHound.lib.Mod {

	public function get ModName():String { return m_ModName; }
	public function get Version():String { return m_Version; }
	public function get DevName():String { return "Peloprata"; } // Others should replace
	public function get ToggleVar():String { return m_ToggleVar; } // Name of DistributedValue toggle for mod (as in .xml)

	public function get ConfigArchiveName():String { return ModName + "Config"; }
	public function get Config():ConfigWrapper { return m_Config; }

	public function get DebugTrace():Boolean { return m_DebugTrace; }
	public function set DebugTrace(value:Boolean):Void { m_DebugTrace = value; }

	private static var ChatLeadColor:String = "#00FFFF";

	// Minimal constructor, as derived class cannot defer construction
	public function Mod(modName:String, version:String, toggleVar:String) {
		m_DebugTrace = true;
		m_ModName = modName;
		m_Version = version;
		m_ToggleVar = toggleVar;
	}

	// Should be called in derived class constructor, after it has set up requirements of its own Init function
	public function LoadConfig():Void {
		m_Config = new ConfigWrapper(ConfigArchiveName);
		Config.NewSetting("Version", Version);
		Config.NewSetting("Installed", false); // Will always be saved as true, only remains false if settings do not exist
		InitializeConfig();
		Config.LoadConfig();
	}

	// Placeholder function for overriden behaviour
	// Config will be initialized at this point, and can just have settings added
	public function InitializeConfig():Void {
	}

	// Should be called in derived class constructor, after config has been loaded
	public function UpdateInstall():Void {
		if (!Config.GetValue("Installed")) {
			DoInstall();
			Config.SetValue("Installed", true);
			return; // No existing version to update
		}
		var versionChange:Number = CompareVersions(Config.GetDefault("Version"), Config.GetValue("Version"));
		if (versionChange != 0) { // The version changed, either updated or reverted
			if (versionChange > 0) { DoUpdate(); }
			// Reset the version number, as the change has occured
			Config.SetValue("Version", Config.GetDefault("Version"));
		}
	}

	// Placeholder function for overriden behaviour
	public function DoInstall():Void {
	}

	// Placeholder function for overriden behaviour
	public function DoUpdate():Void {
	}

	// MeeehrUI will work with only the VTIO interface,
	// but explicit support will make solving unique issues easier
	// Meeehr's should always trigger first if present, and can be checked during the callback.
	public function RegisterWithTopbar():Void {
		m_MeeehrUI = DistributedValue.Create("meeehrUI_IsLoaded");
		m_ViperTIO = DistributedValue.Create("VTIO_IsLoaded");	
		m_MeeehrUI.SignalChanged.Connect(DoRegistration, this);
		m_ViperTIO.SignalChanged.Connect(DoRegistration, this);
		DoRegistration(m_MeeehrUI);
		DoRegistration(m_ViperTIO);
	}

	private function DoRegistration(dv:DistributedValue):Void {
		if (dv.GetValue() && !m_IsRegistered) {
			m_MeeehrUI.SignalChanged.Disconnect(DoRegistration, this);
			m_ViperTIO.SignalChanged.Disconnect(DoRegistration, this);			
			DistributedValue.SetDValue("VTIO_RegisterAddon", ModName + "|" + DevName + "|" + Version + "|" + ToggleVar + "|" + ""); // Final would be icon
			m_IsRegistered = true;			
		}
	}

	// Placeholder function for overriden behaviour
	public function Activate() {
		TraceMsg("Activated");
	}

	// Override for additional processing, but call inherited version.
	public function Deactivate() {
		// Tradeoff:
		//   Saving here will be more frequent but protect against crashes better
		//   Most calls quick polls of Config dirty flag with no actual save request
		Config.SaveConfig();
		TraceMsg("Deactivated");
	}

	// Text output utilities
	public function ChatMsg(message:String):Void {
		Utils.PrintChatText("<font color='" + ChatLeadColor + "'>" + ModName + "</font>: " + message);
	}

	public function TraceMsg(message:String):Void {
		if (DebugTrace) {
			ChatMsg("Trace - " + message);
		}
	}

	public function LogMsg(message:String):Void {
		Log.Error(ModName, message);
	}

	// Compares two version strings (format v#.#.#[.alpha|.beta])
	// Return value encodes the field at which they differ (1: major, 2: minor, 3: build, 4: prerelease tag)
	// If positive, then the first version is higher, negative means first version was lower
	// A return of 0 indicates that the versions were the same
	private static function CompareVersions(firstVer:String, secondVer:String) : Number {
		var first:Array = firstVer.substr(1).split(".");
		var second:Array = secondVer.substr(1).split(".");
		for (var i = 0; i < Math.min(first.length, second.length); ++i) {
			if (first[i] != second[i]) {
				if (i < 3) {
					return Number(first[i]) < Number(second[i]) ? -(i + 1) : i + 1;
				} else {
					// One's alpha and the other is beta, all other values the same
					return first[i] == "alpha" ? -4 : 4;
				}
				break;
			}
		}
		// Version number is the same, but one may still have a pre-release tag
		if (first.length != second.length) {
			return first.length > second.length ? -4 : 4;
		}
		return 0;
	}

	private var m_ModName:String;
	private var m_Version:String;
	private var m_ToggleVar:String;
	private var m_Config:ConfigWrapper;
	private var m_DebugTrace:Boolean = false;
	
	private var m_MeeehrUI:DistributedValue; 
	private var m_ViperTIO:DistributedValue;
	private var m_IsRegistered:Boolean = false;
}
