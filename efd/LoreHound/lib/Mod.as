// Copyright 2017, Earthfiredrake (Peloprata)
// Released under the terms of the MIT License
// https://github.com/Earthfiredrake/TSW-LoreHound

import flash.geom.Point;

import gfx.utils.Delegate;

import com.GameInterface.DistributedValue;
import com.GameInterface.EscapeStack;
import com.GameInterface.EscapeStackNode;
import com.GameInterface.Log;
import com.GameInterface.Utils;
import com.Utils.Archive;
import GUIFramework.SFClipLoader;

import efd.LoreHound.lib.etu.MovieClipHelper;

import efd.LoreHound.lib.ConfigWrapper;
import efd.LoreHound.lib.LocaleManager;
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
			ModName = "Unnamed";
			// Dev message, not localized
			ChatMsg("Mod requires a name!");
		} else { ModName = modInfo.Name; }
		if (modInfo.Version == undefined || modInfo.Version == "") {
			modInfo.Version = "0.0.0";
			// Dev message, not localized
			ChatMsg("Mod expects a version number!");
		}
		HostMovie = hostMovie;

		GlobalDebugDV = DistributedValue.Create(DVPrefix + "DebugMode");
		GlobalDebugDV.SignalChanged.Connect(SetDebugMode, this);
		DebugTrace = modInfo.Trace || GlobalDebugDV.GetValue();

		SystemsLoaded = { Config: false, LocalizedText: false }
		ModLoadedDV = DistributedValue.Create(ModLoadEventVar);
		ModLoadedDV.SetValue(false);

		ChatMsgS = Delegate.create(this, ChatMsg);
		TraceMsgS = Delegate.create(this, TraceMsg);
		LogMsgS = Delegate.create(this, LogMsg);

		LocaleManager.Initialize(ModName + "/Strings.xml");
		LocaleManager.SignalStringsLoaded.Connect(StringsLoaded, this);

		EscStackTrigger = new EscapeStackNode();
		ShowConfigDV = DistributedValue.Create(ConfigWindowVar);
		ShowConfigDV.SetValue(false);
		ShowConfigDV.SignalChanged.Connect(ShowConfigWindow, this);
		ResolutionScaleDV = DistributedValue.Create("GUIResolutionScale");
		InitializeModConfig(modInfo);

		var iconName = modInfo.IconName;
		if (iconName != "") {
			if (iconName == undefined) { iconName = ModName + "Icon"; }
			Icon = ModIcon(MovieClipHelper.attachMovieWithRegister(iconName, ModIcon, "ModIcon", HostMovie, HostMovie.getNextHighestDepth(),
				{ ModName: ModName, DevName: DevName, HostMovie: HostMovie, Config: Config, ShowConfigDV: ShowConfigDV }));
		}

		if (!modInfo.NoTopbar) { RegisterWithTopbar(); }
	}

	private function StringsLoaded(success:Boolean):Void {
		if (success) {
			TraceMsg("Localized strings loaded");
			SystemsLoaded.LocalizedText = true;
			CheckLoadComplete();
		} else {
			// Localization support unavailable, not localized
			ChatMsg("Mod cannot be enabled", true);
			Config.SetValue("Enabled", false);
		}
	}

	private function InitializeModConfig(modInfo:Object):Void {
		Config = new ConfigWrapper(modInfo.ArchiveName);

		Config.NewSetting("Version", modInfo.Version);
		Config.NewSetting("Installed", false); // Will always be saved as true, only remains false if settings do not exist
		Config.NewSetting("Enabled", true); // Whether mod is enabled by the player

		Config.NewSetting("ConfigWindowPosition", new Point(20, 30));

		Config.SignalConfigLoaded.Connect(ConfigLoaded, this);
		Config.SignalValueChanged.Connect(ConfigChanged, this);
	}

	private function ConfigLoaded():Void {
		TraceMsg("Config loaded");
		SystemsLoaded.Config = true;
		CheckLoadComplete();
	}

	private function ConfigChanged(setting:String, newValue, oldValue):Void {
		switch(setting) {
			case "Enabled":
				if (newValue && SystemsLoaded != undefined) {
					ChatMsg("Failed to load required information, and cannot be enabled");
					for (var key:String in SystemsLoaded) {
						if (!SystemsLoaded[key]) { ChatMsg("Missing: " + key, true); }
					}
					Config.SetValue("Enabled", false);
				} else { Enabled = newValue; }
				break;
			default: // Setting does not push changes (is checked on demand)
				break;
		}
	}

	private function ShowConfigWindow(dv:DistributedValue):Void {
		if (dv.GetValue()) { // Open window
			if (ConfigWindowClip == null) {
				ConfigWindowClip = HostMovie.attachMovie(ModName + "SettingsWindow", "SettingsWindow", HostMovie.getNextHighestDepth());
				// Defer the actual binding to config until things are set up
				ConfigWindowClip.SignalContentLoaded.Connect(ConfigWindowLoaded, this);

				var LocaleTitle:String = LocaleManager.FormatString("GUI", "ConfigWindowTitle", ModName);
				ConfigWindowClip.SetTitle(LocaleTitle, "left");
				ConfigWindowClip.SetPadding(10);
				ConfigWindowClip.SetContent(ModName + "ConfigWindowContent");

				ConfigWindowClip.ShowCloseButton(true);
				ConfigWindowClip.ShowStroke(false);
				ConfigWindowClip.ShowResizeButton(false);
				ConfigWindowClip.ShowFooter(false);

				var position:Point = Config.GetValue("ConfigWindowPosition");
				ConfigWindowClip._x = position.x;
				ConfigWindowClip._y = position.y;

				ResolutionScaleDV.SignalChanged.Connect(SetConfigWindowScale, this);
				SetConfigWindowScale();

				EscStackTrigger.SignalEscapePressed.Connect(CloseConfigWindow, this);
				EscapeStack.Push(EscStackTrigger);
				ConfigWindowClip.SignalClose.Connect(CloseConfigWindow, this);
			}
		} else { // Close window
			if (ConfigWindowClip != null) {
				EscStackTrigger.SignalEscapePressed.Disconnect(CloseConfigWindow, this);
				ResolutionScaleDV.SignalChanged.Disconnect(SetConfigWindowScale, this);

				ReturnWindowToVisibleBounds(ConfigWindowClip, Config.GetDefault("ConfigWindowPosition"));
				Config.SetValue("ConfigWindowPosition", new Point(ConfigWindowClip._x, ConfigWindowClip._y));

				ConfigWindowClip.removeMovieClip();
				ConfigWindowClip = null;
			}
		}
	}

	private function ConfigWindowLoaded():Void { ConfigWindowClip.m_Content.AttachConfig(Config); }

	private static function ReturnWindowToVisibleBounds(window:MovieClip, defaults:Point):Void {
		var visibleBounds = Stage.visibleRect;
		if (window._x < 0) { window._x = 0; }
		else if (window._x + window.m_Background._width > visibleBounds.width) {
			window._x = visibleBounds.width - window.m_Background._width;
		}
		if (window._y < defaults.y) { window._y = defaults.y; }
		else if (window._y + window.m_Background._height > visibleBounds.height) {
			window._y = visibleBounds.height - window.m_Background._height;
		}
	}

	private function SetConfigWindowScale():Void {
		var scale:Number = ResolutionScaleDV.GetValue() * 100;
		ConfigWindowClip._xscale = scale;
		ConfigWindowClip._yscale = scale;
	}

	private function CloseConfigWindow():Void { ShowConfigDV.SetValue(false); }

	private function CheckLoadComplete():Void {
		for (var key:String in SystemsLoaded) {
			if (!SystemsLoaded[key]) { return; }
		}
		TraceMsg("Is fully loaded");
		LoadComplete();
	}

	private function LoadComplete():Void {
		delete SystemsLoaded; // No longer required
		UpdateInstall();
		ModLoadedDV.SetValue(true);
	}

	private function UpdateInstall():Void {
		if (!Config.GetValue("Installed")) {
			DoInstall();
			Config.SetValue("Installed", true);
			ChatMsg(LocaleManager.GetString("General", "Installed"));
			ChatMsg(LocaleManager.GetString("General", "InstalledSettings"), true);
			// Decided against having the options menu auto open here
			// Users might not realize that it's a one off event, and consider it a bug
			return; // No existing version to update
		}
		var oldVersion:String = Config.GetValue("Version");
		var newVersion:String = Config.GetDefault("Version");
		var versionChange:Number = CompareVersions(newVersion, oldVersion);
		if (versionChange != 0) { // The version changed, either updated or reverted
			var changeTag:String;
			if (versionChange > 0) {
				changeTag = "Update";
				DoUpdate(newVersion, oldVersion);
			} else {
				changeTag = "Revert";
			}
			// Reset the version number to the new version
			Config.ResetValue("Version");
			ChatMsg(LocaleManager.FormatString("General", changeTag, newVersion));
		}
	}

	// MeeehrUI is legacy compatible with the VTIO interface,
	// but explicit support will make solving unique issues easier
	// Meeehr's should always trigger first if present, and can be checked during the callback.
	private function RegisterWithTopbar():Void {
		MeeehrDV = DistributedValue.Create("meeehrUI_IsLoaded");
		ViperDV = DistributedValue.Create("VTIO_IsLoaded");
		// Try to register now, in case they loaded first, otherwise signup to detect if they load
		if (!(DoTopbarRegistration(MeeehrDV) || DoTopbarRegistration(ViperDV))) {
			MeeehrDV.SignalChanged.Connect(DoTopbarRegistration, this);
			ViperDV.SignalChanged.Connect(DoTopbarRegistration, this);
		}
	}

	private function DoTopbarRegistration(dv:DistributedValue):Boolean {
		if (dv.GetValue() && !IsTopbarRegistered) {
			MeeehrDV.SignalChanged.Disconnect(DoTopbarRegistration, this);
			ViperDV.SignalChanged.Disconnect(DoTopbarRegistration, this);
			// Adjust our default icon to be better suited for topbar integration
			if (Icon != undefined) {
				SFClipLoader.SetClipLayer(SFClipLoader.GetClipIndex(HostMovie), _global.Enums.ViewLayer.e_ViewLayerTop, 2);
				Icon.ConfigureForTopbar();
			}
			// Note: Viper's *requires* all five values, regardless of whether the icon exists or not
			//       Both are capable of handling "undefined" or otherwise invalid icon names
			DistributedValue.SetDValue("VTIO_RegisterAddon", ModName + "|" + DevName + "|" + Version + "|" + ConfigWindowVar + "|" + Icon.toString());
			// Topbar creates its own icon, use it as our target for changes instead
			// Can't actually remove ours though, Meeehr's redirects event handling oddly
			// (It calls back to the original clip, using the new clip as the "this" instance)
			Icon = Icon.CopyToTopbar(HostMovie.Icon);
			IsTopbarRegistered = true;
			TopbarRegistered();
			TraceMsg("Topbar registration complete");
		}
		return IsTopbarRegistered;
	}

	// The game itself toggles the mod's activation state (based on modules.xml criteria)
	public function GameToggleModEnabled(state:Boolean, archive:Archive) {
		EnabledByGame = state;
		Enabled = state;
		if (!state) {
			CloseConfigWindow();
			return Config.SaveConfig();
		} else {
			if (!Config.IsLoaded) {	Config.LoadConfig(archive);	}
		}
	}

	private function SetDebugMode(dv:DistributedValue):Void { DebugTrace = dv.GetValue(); }

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

	public function LogMsg(message:String):Void { Log.Error(ModName, message); }

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
	public static function CompareVersions(firstVer:String, secondVer:String):Number {
		// DEPRECIATED(v0.5.0): "v" prefix on version strings
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

	/// Properites and variables
	public function get Version():String { return Config.GetValue("Version"); }

	public function get Enabled():Boolean { return _Enabled; }
	public function set Enabled(value:Boolean):Void {
		value = EnabledByGame && Config.GetValue("Enabled");
		if (value != _Enabled) { // State changed
			_Enabled = value;
			if (value) { Activate(); }
			else { Deactivate(); }
		}
	}

	public function get ModLoadEventVar():String { return DVPrefix + ModName + "IsLoaded"; }
	public function get ConfigWindowVar():String { return DVPrefix + "Show" + ModName + "ConfigUI"; }

	// Customize based on mod authorship
	public static var DevName:String = "Peloprata";
	public static var DVPrefix:String = "efd"; // Retain this if making a compatible fork of an existing mod

	private static var ChatLeadColor:String = "#00FFFF";

	public var ModName:String;
	public var SystemsLoaded:Object; // Tracks asynchronous data loads so that functions aren't called without proper data
	private var ModLoadedDV:DistributedValue; // Provided as a hook for any mod integration features

	private var _Enabled:Boolean = false;
	private var EnabledByGame:Boolean = false;
	// Enabled by player is a persistant config setting

	public var Config:ConfigWrapper;
	private var ShowConfigDV:DistributedValue; // Used by topbars to provide setting shortcut buttons
	private var ResolutionScaleDV:DistributedValue;
	private var ConfigWindowClip:MovieClip = null;
	private var EscStackTrigger:EscapeStackNode;

	private var HostMovie:MovieClip;
	public var Icon:ModIcon;

	private var IsTopbarRegistered:Boolean = false;
	private var MeeehrDV:DistributedValue;
	private var ViperDV:DistributedValue;

	private var DebugTrace:Boolean;
	private var GlobalDebugDV:DistributedValue; // Used to quickly toggle trace or other debug features of all efd mods
}
