// Copyright 2017, Earthfiredrake (Peloprata)
// Released under the terms of the MIT License
// https://github.com/Earthfiredrake/TSW-LoreHound

import flash.geom.Point;

import gfx.utils.Delegate;

import com.GameInterface.DistributedValue;
import com.GameInterface.Log;
import com.GameInterface.Utils;
import com.Utils.Archive;
import com.Utils.Signal;
import GUIFramework.SFClipLoader;

import efd.LoreHound.lib.etModUtils.MovieClipHelper;

import efd.LoreHound.gui.ConfigWindowContent;
import efd.LoreHound.lib.ConfigWrapper;
import efd.LoreHound.lib.ModIcon;

// Base class with general mod utility functions
// The Mod framework reserves the following Config setting names for internal use:
//   "Installed": Used to trigger first run events
//   "Version": Used to detect upgrades (and rollbacks, but that's of limited use)
//   "Enabled": Provides a "soft" disable for the user that doesn't interfere with loading on restart (the config based toggle var does prevent loading if false)
//   "IconPosition": Only used if topbar is not handling icon layout
//   "IconScale": Only used if topbar is not handling icon layout
//   "ConfigWindowPosition"
class efd.LoreHound.lib.Mod {
	public function get ModName():String { return m_ModName; }
	public function get Version():String { return Config.GetValue("Version"); }
	public function get DevName():String { return "Peloprata"; } // Others should replace

	public function get Config():ConfigWrapper { return m_Config; }
	public function get ConfigWindowVar():String { return "Show" + ModName + "ConfigUI"; }

	public function get HostMovie():MovieClip { return m_HostMovie; }
	public function get Icon():ModIcon { return m_ModIcon; }

	public function get DebugTrace():Boolean { return m_DebugTrace; }
	public function set DebugTrace(value:Boolean):Void { m_DebugTrace = value; }

	public function get Enabled():Boolean { return m_Enabled; }
	public function set Enabled(value:Boolean):Void {
		value = m_EnabledByGame && Config.GetValue("Enabled");
		if (value != Enabled) { // State changed
			m_Enabled = value;
			if (value) { Activate(); }
			else { Deactivate(); }
		}
	}

	// The new archive loading scheme delays the loading of config settings until the activation stage
	//   Config object definition can now be spread between the base and subclass constructors
	// The modData object has the following fields:
	//   Name (required, placeholder default "Unnamed")
	//     The name of the mod, for display and used to generate a variety of default identifiers
	//   Version (required, placeholder default "0.0.0")
	//     Current build version
	//     Expects "#.#.#[.alpha|.beta]" format but does not verify
	//   Trace (optional, default false)
	//     Enables debug trace messages
	//   ArchiveName (optional, default undefined)
	//     Name of archive to use for main config if overriding the one provided by the game
	//   IconName (optional, default Name + "Icon")
	//     Library resource id to use as an icon
	//     An empty string can be used if a mod doesn't wish to have an icon (or related settings)
	//   NoTopbar (optional, default false)
	//     Disable integration with a VTIO compatible topbar mod (Viper's or Meeehr's)
	//     Also useful for testing
	public function Mod(modInfo:Object, hostMovie:MovieClip) {
		if (modInfo.Name == undefined || modInfo.Name == "") {
			m_ModName = "Unnamed";
			ChatMsg("Mod requires a name!");
		} else { m_ModName = modInfo.Name; }
		if (modInfo.Version == undefined || modInfo.Version == "") {
			modInfo.Version = "0.0.0";
			ChatMsg("Mod requires a version number!");
		}
		m_DebugTrace = modInfo.Trace != undefined && modInfo.Trace;
		m_HostMovie = hostMovie;

		ChatMsgS = Delegate.create(this, ChatMsg);
		TraceMsgS = Delegate.create(this, TraceMsg);
		LogMsgS = Delegate.create(this, LogMsg);

		m_ShowConfig = DistributedValue.Create(ConfigWindowVar);
		m_ShowConfig.SetValue(false);
		m_ShowConfig.SignalChanged.Connect(ShowConfigWindow, this);
		InitializeModConfig(modInfo);

		var iconName = modInfo.IconName;
		if (iconName != "") {
			if (iconName == undefined) { iconName = ModName + "Icon"; }
			m_ModIcon = ModIcon(MovieClipHelper.attachMovieWithRegister(iconName, ModIcon, "ModIcon", HostMovie, HostMovie.getNextHighestDepth(),
				{ModName: ModName, DevName: DevName, HostMovie: HostMovie, Config: Config, ShowConfigDV: m_ShowConfig}));
		}

		if (!modInfo.NoTopbar) { RegisterWithTopbar(); }
	}

	private function InitializeModConfig(modInfo:Object):Void {
		m_Config = new ConfigWrapper(modInfo.ArchiveName);

		Config.NewSetting("Version", modInfo.Version);
		Config.NewSetting("Installed", false); // Will always be saved as true, only remains false if settings do not exist
		Config.NewSetting("Enabled", true); // Whether mod is enabled by the player

		Config.NewSetting("ConfigWindowPosition", new Point(20, 20));

		Config.SignalConfigLoaded.Connect(ConfigLoaded, this);
		Config.SignalValueChanged.Connect(ConfigChanged, this);
	}

	private function ConfigLoaded(initialLoad:Boolean):Void {
		TraceMsg("Config loaded");
		if (initialLoad) { UpdateInstall(); }
	}

	private function ConfigChanged(setting:String, newValue, oldValue):Void {
		switch(setting) {
			case "Enabled":
				Enabled = newValue;
				break;
			default: // Setting does not push changes (is checked on demand)
				break;
		}
	}

	private function ShowConfigWindow(dv:DistributedValue):Void {
		if (dv.GetValue()) {
			if (m_ConfigWindow == null) {
				m_ConfigWindow = m_HostMovie.attachMovie(ModName + "SettingsWindow", "SettingsWindow", m_HostMovie.getNextHighestDepth());
				// Defer the actual binding to config until things are set up
				m_ConfigWindow.SignalContentLoaded.Connect(ConfigWindowLoaded, this);

				m_ConfigWindow.SetTitle(ModName + " Settings", "left");
				m_ConfigWindow.SetPadding(10);
				m_ConfigWindow.SetContent(ModName+ "ConfigWindowContent");

				m_ConfigWindow.ShowCloseButton(true);
				m_ConfigWindow.ShowStroke(false);
				m_ConfigWindow.ShowResizeButton(false);
				m_ConfigWindow.ShowFooter(false);

				var position:Point = Config.GetValue("ConfigWindowPosition");
				KeepInVisibleBounds(position, Config.GetDefault("ConfigWindowPosition"));
				m_ConfigWindow._x = position.x;
				m_ConfigWindow._y = position.y;

				m_ConfigWindow.SignalClose.Connect(ConfigWindowClosed , this);
			}
		} else {
			if (m_ConfigWindow != null) {
				Config.SetValue("ConfigWindowPosition", new Point(m_ConfigWindow._x, m_ConfigWindow._y));
				m_ConfigWindow.removeMovieClip();
				m_ConfigWindow = null;
			}
		}
	}

	private function ConfigWindowLoaded():Void {
		m_ConfigWindow.m_Content.AttachConfig(Config);
	}

	// TODO: This only works on top and left of screen, need to account for Window size on other sides
	private static function KeepInVisibleBounds(position:Point, defaults:Point):Void{
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

	private function UpdateInstall():Void {
		if (!Config.GetValue("Installed")) {
			DoInstall();
			Config.SetValue("Installed", true);
			ChatMsg("Has been installed.");
			ChatMsg("Please take a moment to review the options.", true);
			// Decided against having the options menu auto open here
			// Users might not realize that it's a one off event, and consider it a bug
			return; // No existing version to update
		}
		var oldVersion:String = Config.GetValue("Version");
		var newVersion:String = Config.GetDefault("Version");
		var versionChange:Number = CompareVersions(newVersion, oldVersion);
		if (versionChange != 0) { // The version changed, either updated or reverted
			var changeType:String = "Reverted";
			if (versionChange > 0) {
				changeType = "Updated";
				DoUpdate(newVersion, oldVersion);
			}
			// Reset the version number, as the change has occured
			Config.ResetValue("Version");
			ChatMsg(changeType + " to v" + newVersion);
		}
	}

	// MeeehrUI is legacy compatible with the VTIO interface,
	// but explicit support will make solving unique issues easier
	// Meeehr's should always trigger first if present, and can be checked during the callback.
	private function RegisterWithTopbar():Void {
		m_MeeehrUI = DistributedValue.Create("meeehrUI_IsLoaded");
		m_ViperTIO = DistributedValue.Create("VTIO_IsLoaded");
		// Try to register now, in case they loaded first, otherwise signup to detect if they load
		if (!(DoRegistration(m_MeeehrUI) || DoRegistration(m_ViperTIO))) {
			m_MeeehrUI.SignalChanged.Connect(DoRegistration, this);
			m_ViperTIO.SignalChanged.Connect(DoRegistration, this);
		}
	}

	private function DoRegistration(dv:DistributedValue):Boolean {
		if (dv.GetValue() && !m_IsTopbarRegistered) {
			m_MeeehrUI.SignalChanged.Disconnect(DoRegistration, this);
			m_ViperTIO.SignalChanged.Disconnect(DoRegistration, this);
			// Adjust our default icon to be better suited for topbar integration
			if (m_ModIcon != undefined) {
				SFClipLoader.SetClipLayer(SFClipLoader.GetClipIndex(m_HostMovie), _global.Enums.ViewLayer.e_ViewLayerTop, 2);
				m_ModIcon.ConfigureForTopbar();
			}
			// Note: Viper's *requires* all five values, regardless of whether the icon exists or not
			//       Both are capable of handling "undefined" or otherwise invalid icon names
			DistributedValue.SetDValue("VTIO_RegisterAddon", ModName + "|" + DevName + "|" + Version + "|" + ConfigWindowVar + "|" + m_ModIcon.toString());
			// Topbar creates its own icon, use it as our target for changes instead
			// Can't actually remove ours though, Meeehr's redirects event handling oddly
			// (It calls back to the original clip, using the new clip as the "this" instance)
			m_ModIcon.CopyToTopbar(HostMovie.Icon);
			m_ModIcon = HostMovie.Icon;
			m_IsTopbarRegistered = true;
			TopbarRegistered();
			TraceMsg("Topbar registration complete");
		}
		return m_IsTopbarRegistered;
	}

	// The game itself toggles the mod's activation state (based on modules.xml criteria)
	public function GameToggleModEnabled(state:Boolean, archive:Archive) {
		m_EnabledByGame = state;
		Enabled = state;
		if (!state) {
			m_ShowConfig.SetValue(false);
			return Config.SaveConfig();
		} else {
			if (!Config.IsLoaded) {	Config.LoadConfig(archive);	}
		}
	}

	/// Text output utility functions
	// Leader text should not be supressed on initial message for any particular notification, only on immediately subsequent lines
	public function ChatMsg(message:String, suppressLeader:Boolean):Void {
		if (!suppressLeader) {
			Utils.PrintChatText("<font color='" + ChatLeadColor + "'>" + ModName + "</font>: " + message);
		} else { Utils.PrintChatText(message); }
	}

	public function TraceMsg(message:String, supressLeader:Boolean):Void {
		if (DebugTrace) { ChatMsg("Trace - " + message, supressLeader);	}
	}

	public function LogMsg(message:String):Void {
		Log.Error(ModName, message);
	}

	// Static delegates to the ones above
	// So other components can access them without needing a reference
	// Recommend wrapping the call in a local version, that inserts an identifer for the subcomponent involved
	public static var ChatMsgS:Function;
	public static var TraceMsgS:Function;
	public static var LogMsgS:Function;

	// Compares two version strings (format "#.#.#[.alpha|.beta]")
	// Return value encodes the field at which they differ (1: major, 2: minor, 3: build, 4: prerelease tag)
	// If positive, then the first version is higher, negative means first version was lower
	// A return of 0 indicates that the versions were the same
	public static function CompareVersions(firstVer:String, secondVer:String) : Number {
		// Support depreciated "v" prefix on version strings
		if (firstVer.charAt(0) == "v") { firstVer = firstVer.substr(1); }
		if (secondVer.charAt(0) == "v") { secondVer = secondVer.substr(1); }

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
				break;
			}
		}
		// Version number is the same, but one may still have a pre-release tag
		if (first.length != second.length) {
			return first.length > second.length ? -4 : 4;
		}
		return 0;
	}

	/// The following empty functions are provided as override hooks for subclasses to implement
	private function DoInstall():Void { }
	private function DoUpdate(newVersion:String, oldVersion:String):Void { }
	private function Activate():Void { }
	private function Deactivate():Void { }
	private function TopbarRegistered():Void { }

	private static var ChatLeadColor:String = "#00FFFF";

	private var m_ModName:String;

	private var m_Enabled:Boolean = false;
	private var m_EnabledByGame:Boolean = false;
	// Enabled by player is a persistant config setting

	private var m_Config:ConfigWrapper;
	private var m_ShowConfig:DistributedValue; // Used by topbars to provide setting shortcut buttons
	private var m_ConfigWindow:MovieClip = null;

	private var m_HostMovie:MovieClip;
	private var m_ModIcon:ModIcon;

	private var m_MeeehrUI:DistributedValue;
	private var m_ViperTIO:DistributedValue;
	private var m_IsTopbarRegistered:Boolean = false;

	private var m_DebugTrace:Boolean;
}
