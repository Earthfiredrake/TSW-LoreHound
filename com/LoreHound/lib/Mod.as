// Copyright 2017, Earthfiredrake (Peloprata)
// Released under the terms of the MIT License
// https://github.com/Earthfiredrake/TSW-LoreHound

import com.GameInterface.DistributedValue;
import com.GameInterface.Log;
import com.GameInterface.Tooltip.TooltipData;
import com.GameInterface.Tooltip.TooltipInterface;
import com.GameInterface.Tooltip.TooltipManager;
import com.GameInterface.Utils;
import com.Utils.Signal;

import com.LoreHound.gui.ConfigWindowContent;
import com.LoreHound.lib.ConfigWrapper;

// Base class with general mod utility functions
// The Mod framework reserves the following Config setting names for internal use:
// "Installed": Used to trigger first run events
// "Version": Used to detect upgrades and rollbacks
// "Enabled": Provides a "soft" disable for the user that doesn't interfere with loading on restart
// "IconPosition": Used if a topbar is not installed to position the icon container
// "ConfigWindowPosition":
class com.LoreHound.lib.Mod {

	public function get ModName():String { return m_ModName; }
	public function get Version():String { return m_Version; }
	public function get DevName():String { return "Peloprata"; } // Others should replace
	public function get ToggleVar():String { return m_ToggleVar; } // Name of DistributedValue toggle for mod (as in .xml)

	public function get ConfigWindowVar():String { return "Show" + ModName + "ConfigUI"; }
	public function get ConfigArchiveName():String { return ModName + "Config"; }
	public function get Config():ConfigWrapper { return m_Config; }

	public function get HostMovie():MovieClip { return m_HostMovie; }
	public function get ModIcon():MovieClip { return m_ModIcon; }

	public function get DebugTrace():Boolean { return m_DebugTrace; }
	public function set DebugTrace(value:Boolean):Void { m_DebugTrace = value; }

	public function get Enabled():Boolean { return m_Enabled; }
	public function set Enabled(value:Boolean):Void {
		value = m_EnabledByGame && Config.GetValue("Enabled");
		if (value != Enabled) { // State changed
			m_Enabled = value;
			if (ModIcon.m_Tooltip != undefined) {
				ModIcon.m_Tooltip.Close();
				ModIcon.m_Tooltip = CreateIconTooltip();
			}
			if (value) { Activate(); }
			else { Deactivate(); }
		}
	}

	private static var ChatLeadColor:String = "#00FFFF";

	// Minimal constructor, as derived class cannot defer construction
	public function Mod(modName:String, version:String, toggleVar:String, hostMovie:MovieClip) {
		m_ModName = modName;
		m_Version = version;
		m_ToggleVar = toggleVar;
		m_HostMovie = hostMovie;
		m_ShowConfig = DistributedValue.Create(ConfigWindowVar);
		m_ShowConfig.SetValue(false);
		m_ShowConfig.SignalChanged.Connect(ShowConfigWindow, this);
	}

	// Should be called in derived class constructor, after it has set up requirements of its own Init function
	public function LoadConfig():Void {
		m_Config = new ConfigWrapper(ConfigArchiveName, DebugTrace);
		Config.NewSetting("Version", Version);
		Config.NewSetting("Installed", false); // Will always be saved as true, only remains false if settings do not exist
		Config.NewSetting("Enabled", true); // Whether mod is enabled by the player
		Config.NewSetting("ConfigWindowPosition", {x: 20, y: 20} );

		InitializeConfig(); // Hook for decendent class to customize config options

		// Callback to detect important setting changes
		Config.SignalValueChanged.Connect(ConfigChanged, this);

		Config.LoadConfig();
	}

	// Placeholder function for overriden behaviour
	// Config will be initialized at this point, and can just have settings added
	public function InitializeConfig():Void {
	}

	private function ConfigChanged(setting:String, newValue, oldValue):Void {
		switch(setting) {
			case "Enabled":
				Enabled = newValue;
				break;
			default:
			// Setting does not push changes (is checked on demand)
		}
	}

	private function ShowConfigWindow(dv:DistributedValue):Void {
		if (dv.GetValue()) {
			TraceMsg("Config window requested.");
			if (m_ConfigWindow == null) {
				m_ConfigWindow = m_HostMovie.attachMovie(ModName + "SettingsWindow", "SettingsWindow", m_HostMovie.getNextHighestDepth());
				// Defer the actual binding to config until things are set up
				m_ConfigWindow.SignalContentLoaded.Connect(ConfigWindowLoaded, this);

				m_ConfigWindow.SetTitle(ModName + " Settings", "left");
				m_ConfigWindow.SetPadding(10);
				m_ConfigWindow.SetContent("ConfigWindowContent");

				m_ConfigWindow.ShowCloseButton(true);
				m_ConfigWindow.ShowStroke(false);
				m_ConfigWindow.ShowResizeButton(false);
				m_ConfigWindow.ShowFooter(false);

				var position:Object = Config.GetValue("ConfigWindowPosition");
				KeepInVisibleBounds(position, Config.GetDefault("ConfigWindowPosition"));
				m_ConfigWindow._x = position.x;
				m_ConfigWindow._y = position.y;

				m_ConfigWindow.SignalClose.Connect(ConfigWindowClosed , this);
			}
		} else {
			TraceMsg("Config window closed.");
			if (m_ConfigWindow != null) {
				Config.SetValue("ConfigWindowPosition", { x: m_ConfigWindow._x, y: m_ConfigWindow._y });
				m_ConfigWindow.removeMovieClip();
				m_ConfigWindow = null;
			}
		}
	}

	private function ConfigWindowLoaded():Void {
		TraceMsg("Load Complete");
		m_ConfigWindow.m_Content.AttachConfig(Config);
	}

	// TODO: This only works on top and left of screen, need to account for Window size on other sides
	private function KeepInVisibleBounds(position:Object, defaults:Object):Void{
		var visibleBounds = Stage.visibleRect;
		if (position.x > visibleBounds.width || position.x < 0) {
			position.x = defaults.x;
		}
		if (position.y > visibleBounds.height || position.y < 0) {
			position.y = defaults.y;
		}
	}

	private function ConfigWindowClosed():Void {
		m_ShowConfig.SetValue(false);
	}

	// Should be called in derived class constructor, after config has been loaded
	public function UpdateInstall():Void {
		if (!Config.GetValue("Installed")) {
			DoInstall();
			Config.SetValue("Installed", true);
			ChatMsg("Has been installed.");
			Utils.PrintChatText("Please take a moment to review the options.");
			// Thought about having the options menu auto open here, but decided that was a bad idea
			// Users might not realize that it's a one off event, and worry that it will always open when they start up
			return; // No existing version to update
		}
		var oldVersion:String = Config.GetValue("Version");
		var newVersion:String = Config.GetDefault("Version");
		var versionChange:Number = CompareVersions(newVersion, oldVersion);
		if (versionChange != 0) { // The version changed, either updated or reverted
			var changeType:String;
			if (versionChange > 0) {
				changeType = "Updated";
				DoUpdate(newVersion, oldVersion);
			} else {
				changeType = "Reverted";
				DoRollback(newVersion, oldVersion);
			}
			// Reset the version number, as the change has occured
			Config.ResetValue("Version");
			ChatMsg(changeType + " to " + newVersion);
		}
	}

	// Placeholder function for overriden behaviour
	public function DoInstall():Void {
	}

	// Placeholder function for overriden behaviour
	public function DoUpdate(newVersion:String, oldVersion:String):Void {
	}

	// Placeholder function for overriden behaviour
	// Unlikely to be needed, but the hook's here if desired
	public function DoRollback(newVersion:String, oldVersion:String):Void {
	}

	public function LoadIcon(iconName:String):Void {
		if (iconName == undefined) { iconName = "ModIcon"; }
		var capture = this; // Have to explicitly capture the local object, or it tries to implicitly find things in the mod icon movieclip
		m_ModIcon = m_HostMovie.attachMovie(iconName, "ModIcon", m_HostMovie.getNextHighestDepth());
		m_ModIcon.onMousePress = function(buttonID:Number) {
			switch(buttonID) {
				case 1: // Left mouse button
					capture.m_ShowConfig.SetValue(!capture.m_ShowConfig.GetValue());
					break;
				case 2: // Right mouse button
					capture.Config.SetValue("Enabled", !capture.Config.GetValue("Enabled"));
					break;
				default:
					capture.TraceMsg("Unexpected mouse button press: " + buttonID);
			}
		};
		m_ModIcon.onRollOver = function() {
			// Note: "this" inside of the event handlers actually ends up being the mod icon movieclip
			if (this.m_Tooltip != undefined) { return; } // Already exists, why recreate it?
			this.m_Tooltip = capture.CreateIconTooltip();
		}
		m_ModIcon.onRollOut = function() {
			if (this.m_Tooltip != undefined) {
				this.m_Tooltip.Close();
				this.m_Tooltip = undefined;
			}
		}
	}

	// Default tooltip, data can be overriden or expanded by child classes
	public function GetIconTooltipData():TooltipData {
		var toggle:String = Enabled ? "Disable" : "Enable";
		var data:TooltipData = new TooltipData();
		data.AddAttribute("", "<font face=\'_StandardFont\' size=\'13\' color=\'#FF8000\'><b>" + ModName + "</b></font>");
		data.AddAttribute("", "<font face=\'_StandardFont\' size=\'10\'>By " + DevName + " " + Version + "</font>");
		// Descriptions are always listed at the bottom, after a divider line from any attributes
        data.AddDescription("<font face=\'_StandardFont\' size=\'12\' color=\'#FFFFFF\'>Left click: Show Options</font>");
        data.AddDescription("<font face=\'_StandardFont\' size=\'12\' color=\'#FFFFFF\'>Right click: " + toggle + " Mod</font>");
        data.m_Padding = 4;
        data.m_MaxWidth = 200;
		return data;
	}

	private function CreateIconTooltip():TooltipInterface {
		// The negative delay causes the manager itself to manage the delay based on the player's setting
		return TooltipManager.GetInstance().ShowTooltip(undefined, TooltipInterface.e_OrientationVertical, -1, GetIconTooltipData());
	}

	// MeeehrUI is legacy compatible with the VTIO interface,
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
		if (dv.GetValue() && !m_IsTopbarRegistered) {
			m_MeeehrUI.SignalChanged.Disconnect(DoRegistration, this);
			m_ViperTIO.SignalChanged.Disconnect(DoRegistration, this);
			DistributedValue.SetDValue("VTIO_RegisterAddon", ModName + "|" + DevName + "|" + Version + "|" + ConfigWindowVar + "|" + m_ModIcon.toString());
			// Topbar creates its own icon, use it as our target for changes instead
			// Can't actually remove ours though, as the mechanism used to copy it requires ours be available to hook up the events properly
			m_ModIcon = HostMovie.Icon;
			// The copy will default to frame 1 (inactive), and may not be properly updated if the topbar loaded after this mod
			m_ModIcon.gotoAndStop(Enabled ? 2 : 1);
			m_IsTopbarRegistered = true;
			TraceMsg("Topbar registration complete.");
		}
	}

	// The game itself toggles the mod's activation state (based on modules.xml criteria)
	public function GameToggleModEnabled(state:Boolean):Void {
		m_EnabledByGame = state;
		Enabled = state;
		if (!state) {
			m_ShowConfig.SetValue(false);
		}
	}

	// Mod is activated
	public function Activate():Void {
		ModIcon.gotoAndStop(2); // Use the Enabled icon
		TraceMsg("Activated");
	}

	// Mod is deactivated
	public function Deactivate():Void {
		// Tradeoff:
		//   Saving here will be more frequent but protect against crashes better
		//   Most calls quick polls of Config dirty flag with no actual save request
		Config.SaveConfig();
		ModIcon.gotoAndStop(1); // Use the Disabled icon
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
	private var m_Enabled:Boolean = false;
	private var m_EnabledByGame:Boolean = false;
	// Enabled by player is a persistant config setting

	private var m_Config:ConfigWrapper;
	private var m_ShowConfig:DistributedValue;
	private var m_ConfigWindow:MovieClip = null;

	private var m_HostMovie:MovieClip;
	private var m_ModIcon:MovieClip;

	private var m_MeeehrUI:DistributedValue;
	private var m_ViperTIO:DistributedValue;
	private var m_IsTopbarRegistered:Boolean = false;

	private var m_DebugTrace:Boolean = false;
}
