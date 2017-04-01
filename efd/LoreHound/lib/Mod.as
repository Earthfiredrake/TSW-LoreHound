// Copyright 2017, Earthfiredrake (Peloprata)
// Released under the terms of the MIT License
// https://github.com/Earthfiredrake/TSW-LoreHound

import flash.geom.Point;

import gfx.utils.Delegate;

import com.GameInterface.Chat; // FIFO messages
import com.GameInterface.DistributedValue;
import com.GameInterface.EscapeStack;
import com.GameInterface.EscapeStackNode;
import com.GameInterface.Log;
import com.GameInterface.Utils; // Chat messages *shrug*
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
	// Mod info flags for disabling certain gui elements
	// Passed as GuiFlags member
	public static var ef_ModGui_NoIcon:Number = 1 << 0;
	public static var ef_ModGui_NoConfigWindow:Number = 1 << 1;
	public static var ef_ModGui_Console:Number = ef_ModGui_NoIcon | ef_ModGui_NoConfigWindow;
	public static var ef_ModGui_NoTopbar:Number = 1 << 2;
	public static var ef_ModGui_None:Number = (1 << 3) - 1;

	//   Mod provides a interface on request which does minimal background processing (ex: Fashionista, UC)
	//   Standard icon behaviours are open the interface on left, advanced options menu on right
	//   Not sure what this would look like as a console style mod... some sort of DV triggered effect I suppose
	//   Topbar settings icon will open config window if available
	public static var e_ModType_Interface:Number = 1;
	//   Mod hooks to game notifications and responds when triggered (ex: LoreHound, NBG)
	//   Provides option to be toggled between enabled/disbled states
	//   Standard icon behaviours are options window on left and toggle mod on right
	//   Topbar settings icon will open config window, or toggle state if no window is specified
	public static var e_ModType_Reactive:Number = 2;

	// The new archive loading scheme delays the loading of config settings until the activation stage
	//   Config object definition can now be spread between the base and subclass constructors
	// The modData object has the following fields:
	//   Name:String (required, placeholder default "Unnamed")
	//     The name of the mod, for display and used to generate a variety of default identifiers
	//   Version:String (required, placeholder default "0.0.0")
	//     Current build version
	//     Expects "#.#.#[.alpha|.beta]" format but does not verify
	//   Type:e_ModType (optional, default e_ModType_Interface)
	//     Values described above
	//   ArchiveName (optional, default undefined (uses parameter passed by game))
	//     Name of archive to use for main config if overriding the one provided by the game
	//   MinUpgradableVersion:String (optional, default "0.0.0")
	//     The earliest version from which the current build supports direct update with setting migration
	//     If a prior version upgrades, settings will be reset to defaults to protect against invalid values
	//   GuiFlags:ef_ModGui (optional, default undefined)
	//     Set flags to disable certain gui elements. Valid flags are:
	//       ef_ModGui_NoIcon: Display no mod or topbar icon
	//       ef_ModGui_NoConfigWindow: Do not use a config window,
	//         topbar integration will use tne ModEnabledDV as config target
	//       ef_ModGui_Console: (NoIcon | NoConfigWindow) also removes HostMovie variable
	//       ef_ModGui_NoTopbar: Disable VTIO compatible topbar integration
	//         also useful for testing how it behaves without one
	//       ef_ModGui_None: Disables all gui elements
	//   IconData:Object (optional, any undefined sub-values will use their own defaults)
	//     ResName:String (optional, default ModName + "Icon")
	//       The name of the library resource to use as graphical elements to the icon.
	//     Above values are removed prior to initialization of the ModIcon
	//     Any overiden functions are wrapped in a Delegate(this) before being passed along
	//       They unfortunately cannot be wrapped in delegates in advance, as initialization requires compile constants
	//     Remaining values are applied as initializers prior to construction
	//	   The following values are added to it and should not be overriden or conflicted with:
	//       ModName, DevName, HostMovie, Config
	//     Values which may be overriden by the mod:
	//	     UpdateState:Function Sets the icon frame to be displayed based on current mod state
	//       LeftMouseInfo:Object Mouse handler as described below
	//       RightMouseInfo:Object Mouse handler as described below
	//         A mouse handler object defines two functions, neither of which should specify which mouse button was involved:
	//           Action: which implements the action taken when that mouse button is pressed on the icon
	//           Tooltip: which returns a string describing that action for display as part of the tooltip
	//       ExtraTooltipInfo:Function returning a string of additional tooltip info to display below the basic usage info
	//   Trace (optional, default false)
	//     Enables debug trace messages
	public function Mod(modInfo:Object, hostMovie:MovieClip) {
		FifoMsg = Delegate.create(this, _FifoMsg);
		ChatMsg = Delegate.create(this, _ChatMsg);
		ErrorMsg = Delegate.create(this, _ErrorMsg);
		TraceMsg = Delegate.create(this, _TraceMsg);
		LogMsg = Delegate.create(this, _LogMsg);

		GlobalDebugDV = DistributedValue.Create(DVPrefix + "DebugMode");
		GlobalDebugDV.SignalChanged.Connect(SetDebugMode, this);
		DebugTrace = modInfo.Trace || GlobalDebugDV.GetValue();

		if (modInfo.Name == undefined || modInfo.Name == "") {
			ModName = "Unnamed";
			// Dev message, not localized
			ErrorMsg("Mod requires a name");
		} else { ModName = modInfo.Name; }
		if (modInfo.Version == undefined || modInfo.Version == "") {
			modInfo.Version = "0.0.0";
			// Dev message, not localized
			ErrorMsg("Mod expects a version number");
		}
		if (!modInfo.Type) { modInfo.Type = e_ModType_Interface; }
		MinUpgradableVersion = modInfo.MinUpgradableVersion ? modInfo.MinUpgradableVersion : "0.0.0";

		SystemsLoaded = { Config: false, LocalizedText: false }
		ModLoadedDV = DistributedValue.Create(ModLoadedVarName);
		ModLoadedDV.SetValue(false);
		if (modInfo.Type == e_ModType_Reactive) {
			ModEnabledDV = DistributedValue.Create(ModEnabledVarName);
			ModEnabledDV.SetValue(true);
			ModEnabledDV.SignalChanged.Connect(ChangeModEnabled, this);
		}

		LocaleManager.Initialize(ModName + "/Strings.xml");
		LocaleManager.SignalStringsLoaded.Connect(StringsLoaded, this);

		if ((modInfo.GuiFlags & ef_ModGui_Console) != ef_ModGui_Console) {
			HostMovie = hostMovie; // Not needed for console style mods
		}

		if (!(modInfo.GuiFlags & ef_ModGui_NoConfigWindow)) {
			EscStackTrigger = new EscapeStackNode();
			ShowConfigDV = DistributedValue.Create(ConfigWindowVarName);
			ShowConfigDV.SetValue(false);
			ShowConfigDV.SignalChanged.Connect(ShowConfigWindow, this);
			ResolutionScaleDV = DistributedValue.Create("GUIResolutionScale");
		}
		InitializeModConfig(modInfo);

		if (!(modInfo.GuiFlags & ef_ModGui_NoIcon)) { CreateIcon(modInfo); }

		if (!(modInfo.GuiFlags & ef_ModGui_NoTopbar)) { RegisterWithTopbar(); }
	}

	private function StringsLoaded(success:Boolean):Void {
		if (success) {
			TraceMsg("Localized strings loaded");
			SystemsLoaded.LocalizedText = true;
			CheckLoadComplete();
		} else {
			// Localization support unavailable, not localized
			ErrorMsg("Mod cannot be enabled", { noPrefix : true });
			Config.SetValue("Enabled", false);
		}
	}

	private function InitializeModConfig(modInfo:Object):Void {
		Config = new ConfigWrapper(modInfo.ArchiveName);

		Config.NewSetting("Version", modInfo.Version);
		Config.NewSetting("Installed", false); // Will always be saved as true, only remains false if settings do not exist
		if (ModEnabledDV != undefined) { Config.NewSetting("Enabled", true); } // Whether mod is enabled by the player

		if (ShowConfigDV != undefined) { Config.NewSetting("ConfigWindowPosition", new Point(20, 30)); }

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
					// May not have loaded localization system
					ErrorMsg("Failed to load required information, and cannot be enabled");
					for (var key:String in SystemsLoaded) {
						if (!SystemsLoaded[key]) { ErrorMsg("Missing: " + key, { noPrefix : true }); }
					}
					Config.SetValue("Enabled", false);
				} else {
					Enabled = newValue;
					ModEnabledDV.SetValue(newValue);
					if (Icon == undefined) {
						// No Icon, probably means it's a console style mod
						// Provide alternate notification
						ChatMsg(LocaleManager.GetString("General", newValue ? "Enabled" : "Disabled"));
					}
				}
				break;
			default: // Setting does not push changes (is checked on demand)
				break;
		}
	}

	private function CreateIcon(modInfo:Object):Void {
		var iconData:Object = modInfo.IconData ? modInfo.IconData : new Object();
		var iconName:String = iconData.ResName ? iconData.ResName : ModName + "Icon";
		delete iconData.ResName;

		iconData.ModName = ModName;
		iconData.DevName = DevName;
		iconData.HostMovie = HostMovie;
		iconData.Config = Config;

		if (iconData.UpdateState) {
			iconData.UpdateState = Delegate.create(this, iconData.UpdateState);
		}

		if (!iconData.LeftMouseInfo) {
			if (modInfo.Type == e_ModType_Interface) {
				iconData.LeftMouseInfo = { Action : Delegate.create(this, ToggleInterface), Tooltip : ToggleInterfaceTooltip };
			} else if (modInfo.Type == e_ModType_Reactive && ShowConfigDV != undefined) {
				iconData.LeftMouseInfo = { Action : Delegate.create(this, ToggleConfigWindow), Tooltip : ToggleConfigTooltip };
			}
		} else {
			iconData.LeftMouseInfo.Action = Delegate.create(this, iconData.LeftMouseInfo.Action);
			iconData.LeftMouseInfo.Tooltip = Delegate.create(this, iconData.LeftMouseInfo.Tooltip);
		}
		if (!iconData.RightMouseInfo) {
			if (modInfo.Type == e_ModType_Reactive) {
				iconData.RightMouseInfo = { Action : Delegate.create(this, ChangeModEnabled), Tooltip : Delegate.create(this, ToggleModTooltip) };
			} else if (modInfo.Type == e_ModType_Interface && ShowConfigDV != undefined) {
				iconData.RightMouseInfo = { Action : Delegate.create(this, ToggleConfigWindow), Tooltip : ToggleConfigTooltip };
			}
		}  else {
			iconData.RightMouseInfo.Action = Delegate.create(this, iconData.LeftMouseInfo.Action);
			iconData.RightMouseInfo.Tooltip = Delegate.create(this, iconData.LeftMouseInfo.Tooltip);
		}
		if (iconData.ExtraTooltipInfo) { iconData.ExtraTooltipInfo = Delegate.create(this, iconData.ExtraTooltipInfo); }

		Icon = ModIcon(MovieClipHelper.attachMovieWithRegister(iconName, ModIcon, "ModIcon", HostMovie, HostMovie.getNextHighestDepth(), iconData));
	}

	private function ChangeModEnabled(dv:DistributedValue):Void {
		var value:Boolean = dv != undefined ? dv.GetValue() : !Config.GetValue("Enabled");
		Config.SetValue("Enabled", value);
	}

	private function ToggleModTooltip():String {
		return LocaleManager.GetString("GUI", Config.GetValue("Enabled") ? "TooltipModOff" : "TooltipModOn");
	}

	private function ToggleConfigWindow():Void { ShowConfigDV.SetValue(!ShowConfigDV.GetValue()); }
	private static function ToggleConfigTooltip():String { return LocaleManager.GetString("GUI", "TooltipShowSettings"); }

	private function ToggleInterface():Void {
		// TODO: Decide how to trigger an interface display
	}

	private static function ToggleInterfaceTooltip():String { return LocaleManager.GetString("GUI", "TooltipShowInterface"); }

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
		Icon.UpdateState();
		UpdateInstall();
		ModLoadedDV.SetValue(true);
	}

	private function UpdateInstall():Void {
		if (!Config.GetValue("Installed")) {
			DoInstall();
			Config.SetValue("Installed", true);
			ChatMsg(LocaleManager.GetString("General", "Installed"));
			if (ShowConfigDV != undefined) {
				ChatMsg(LocaleManager.GetString("General", "ReviewSettings"), { noPrefix : true });
				// Decided against having the options menu auto open here
				// Users might not realize that it's a one off event, and consider it a bug
			}
			return; // No existing version to update
		}
		var oldVersion:String = Config.GetValue("Version");
		var newVersion:String = Config.GetDefault("Version");
		var versionChange:Number = CompareVersions(newVersion, oldVersion);
		if (versionChange != 0) { // The version changed, either updated or reverted
			if (versionChange > 0) {
				// Verify upgrade restrictions
				if (CompareVersions(MinUpgradableVersion, oldVersion) > 0) {
					ChatMsg(LocaleManager.FormatString("General", "NoMigration", oldVersion));
					Config.ResetAll();
				} else { DoUpdate(newVersion, oldVersion); }
			}
			// Reset the version number to the new version
			Config.ResetValue("Version");
			ChatMsg(LocaleManager.FormatString("General", versionChange > 0 ? "Update" : "Revert", newVersion));
			if (ShowConfigDV != undefined) {
				ChatMsg(LocaleManager.GetString("General", "ReviewSettings"), { noPrefix : true });
			}
		}
		delete MinUpgradableVersion; // No longer required
	}

	// MeeehrUI is legacy compatible with the VTIO interface,
	// but explicit support will make solving unique issues easier
	// Meeehr's should always trigger first if present, and can be checked during the callback.
	private function RegisterWithTopbar():Void {
		MeeehrDV = DistributedValue.Create("meeehrUI_IsLoaded");
		ViperDV = DistributedValue.Create("VTIO_IsLoaded");
		// Try to register now, in case they loaded first, otherwise signup to detect if they load
		if (!(DoTopbarRegistration(MeeehrDV) || DoTopbarRegistration(ViperDV))) {
			MeeehrDV.SignalChanged.Connect(DeferRegistration, this);
			ViperDV.SignalChanged.Connect(DeferRegistration, this);
		}
	}
	
	private function DeferRegistration(dv:DistributedValue) {
		// Running multiple mods based on this framework was causing other mods (TSWACT) to fail topbar registration
		// Current theory is there's some type of process time limiter on callbacks before they get discarded
		// As this framework does some potentially heavy lifting during this stage (adjusting clip layer)
		// Defer it slightly to give the program more time to deal with other mods
		setTimeout(Delegate.create(this, DoTopbarRegistration), 1, dv);
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
			var topbarInfo:Array = new Array(ModName, DevName, Version, undefined, Icon.toString());
			topbarInfo[3] = ShowConfigDV != undefined ? ConfigWindowVarName : ModEnabledVarName;
			DistributedValue.SetDValue("VTIO_RegisterAddon", topbarInfo.join('|'));
			// Topbar creates its own icon, use it as our target for changes instead
			// Can't actually remove ours though, Meeehr's redirects event handling oddly
			// (It calls back to the original clip, using the new clip as the "this" instance)
			Icon = Icon.CopyToTopbar(HostMovie.Icon);
			IsTopbarRegistered = true;
			TopbarRegistered();
			// Once registered, topbar DVs are no longer required
			// If discrimination between Viper and Meeehr is needed, consider expanding TopbarRegistered to be an enum
			delete MeeehrDV;
			delete ViperDV;
			TraceMsg("Topbar registration complete");
		}
		return IsTopbarRegistered;
	}

	// The game itself toggles the mod's activation state (based on modules.xml criteria)
	public function GameToggleModEnabled(state:Boolean, archive:Archive) {
		if (!state) {
			CloseConfigWindow();
			return Config.SaveConfig();
		} else {
			if (!Config.IsLoaded) {	Config.LoadConfig(archive);	}
		}
		EnabledByGame = state;
		Enabled = state;
	}

	private function SetDebugMode(dv:DistributedValue):Void { DebugTrace = dv.GetValue(); }

	/// Text output utility functions
	// Options object supports the following properties:
	//   system:String - Name of subsystem to include in the prefix
	//   noPrefix:Boolean - Will not display mod or subsystem name if true
	//     Initial messages should probably display this, but it is optional for immediate followup messages
	// Additional properties may be defined for use by the mod itself
	// It is discarded before passing the remaining parameters to the LocaleManager formatting system
	// Parameters passed to the format string are:
	//   %1% : The message text
	//   %2% : The mod prefix text if not disabled
	//   %3% : The subsystem prefix text if it exists and is not disabled
	//   %4%+ : Arbitrary additional parameters passed in by the mod
	// If a format string expects a certain number of parameters, but does not recieve that many it will:
	//   Ignore any extra or unused parameters
	//   Display 'undefined' if an expected parameter is missing
	//     It is therefore important that any additional parameters passed in be defaulted to ""
	private function _FifoMsg(message:String, options:Object):Void {
		var prefixes:Array = GetPrefixes(options);
		arguments.splice(1, 1, prefixes[0], prefixes[1]);
		var args:Array = new Array("General", "FifoMessage").concat(arguments);
		Chat.SignalShowFIFOMessage.Emit(LocaleManager.FormatString.apply(undefined, args), 0);
	}

	private function _ChatMsg(message:String, options:Object):Void {
		var prefixes:Array = GetPrefixes(options);
		arguments.splice(1, 1, prefixes[0], prefixes[1]);
		var args:Array = new Array("General", "ChatMessage").concat(arguments);
		Utils.PrintChatText(LocaleManager.FormatString.apply(undefined, args));
	}

	// Bypasses localization, for fatal errors that can't count on localization support
	private function _ErrorMsg(message:String, options:Object):Void {
		if (!options.noPrefix) {
			var sysPrefix:String = options.system ? (options.system + " - ") : "";
			message = "<font color='#EE0000'>" + ModName +"</font>: ERROR - " + sysPrefix + message + "!";
		}
		Utils.PrintChatText(message);
	}

	private function _TraceMsg(message:String, options:Object):Void {
		// Debug messages, should be independent of localization system to allow traces before it loads
		if (DebugTrace) {
			if (!options.noPrefix) {
				var sysPrefix:String = options.system ? (options.system + " - ") : "";
				message = "<font color='#FFB555'>" + ModName +"</font>: Trace - " + sysPrefix + message;
			}
		 	Utils.PrintChatText(message);
		}
	}

	// Debug logging, not localized
	public function _LogMsg(message:String):Void { Log.Error(ModName, message); }

	private function GetPrefixes(options:Object):Array {
		var prefixes:Array = new Array("", "");
		if (!options.noPrefix) {
			prefixes[0] = LocaleManager.FormatString("General", "ModMessagePrefix", ModName);
			if (options.system != undefined) {
				prefixes[1] = LocaleManager.FormatString("General", "SubsystemMessagePrefix", options.system);
			}
		}
		return prefixes;
	}

	// Static delegates to the ones above
	// So other components can access them without needing a reference
	// Recommend wrapping the call in a local version, that inserts an identifer for the subcomponent involved
	public static var FifoMsg:Function;
	public static var ChatMsg:Function;
	public static var ErrorMsg:Function;
	public static var TraceMsg:Function;
	public static var LogMsg:Function;

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

	public function get ModLoadedVarName():String { return DVPrefix + ModName + "Loaded"; }
	public function get ModEnabledVarName():String { return DVPrefix + ModName + "Enabled"; }
	public function get ConfigWindowVarName():String { return DVPrefix + "Show" + ModName + "ConfigUI"; }

	// Customize based on mod authorship
	public static var DevName:String = "Peloprata";
	public static var DVPrefix:String = "efd"; // Retain this if making a compatible fork of an existing mod

	public var ModName:String;
	public var SystemsLoaded:Object; // Tracks asynchronous data loads so that functions aren't called without proper data, removed once loading complete
	private var MinUpgradableVersion:String; // Minimum installed version for setting migration during update; Discarded after update
	private var ModLoadedDV:DistributedValue; // Provided as a hook for any mod integration features

	private var _Enabled:Boolean = false;
	private var EnabledByGame:Boolean = false;
	// Player enable/disable only applies to reactive mods at this point
	// DV and related config setting will be undefined for interface mods
	private var ModEnabledDV:DistributedValue; // Only reflects the player's setting, doesn't toggle everytime the game triggers it
	// Enabled by player is a persistant config setting

	public var Config:ConfigWrapper;
	private var ShowConfigDV:DistributedValue; // Needs to be DV as topbars use it for providing settings from the mod list; if undefined, no config window is available
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
