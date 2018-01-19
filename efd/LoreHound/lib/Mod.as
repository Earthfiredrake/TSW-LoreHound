// Copyright 2017-2018, Earthfiredrake
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
import com.Utils.Signal;

// TODO: Component based behaviour system for lighter weight mods
//       Objective is to remove at least some of these imports
//       Possibly split out some other subsystems and mod behaviours
import efd.LoreHound.lib.ConfigWrapper;
import efd.LoreHound.lib.sys.config.Versioning;
import efd.LoreHound.lib.LocaleManager;

// Mod Framework v1.1.0
// See ModInfo.LibUpgrades for upgrade requirements

//   As part of ongoing attempts at consistent naming, the following DistributedValue names are reserved for use by the framework or Modules.xml:
//   [pfx] is a developer unique prefix (I use 'efd'), [Name] is the name of the mod
//   Unique per mod name:
//     "[pfx]GameEnables[Name]: The variable defined in Modules.xml as a hard disable for the mod; will disable all features (including icon) and prevent loading in future
//     "[pfx][Name]Enabled": Exists for e_ModType_Reactive mods; "Soft" disable that retains icon and doesn't prevent loading in future; Corresponds to "Enabled" config setting
//     "[pfx][Name]Loaded": Set to true when the mod is fully loaded and initialized
//     "[pfx][Name]Config: Name of archive in which main settings are saved (Mods may use secondary archives for some settings)
//     "[pfx][Name]ResetConfig": Trigger to reset settings to defaults from chat
//     "[pfx]Show[Name]Interface": Exists for e_ModType_Interface mods; Toggle mod interface window
//     "[pfx]Show[Name]ConfigUI": Exists if GuiFlag ef_ModGui_NoConfigWindow is not set; Toggle mod settings window
//   Framework shared (Unique per developer, but that may change):
//     "[pfx]ListMods": Causes all installed framework mods to report their current version to system chat
//     "[pfx]NextIconID": Used to create unique offsets on default icon placements, hopefully reducing icon pileups when using multiple [pfx] mods
//     "[pfx]DebugMode": Toggles debug trace messages for all [pfx] mods, may also enable other debug/dev tools
//   From other mods:
//     "VTIO_IsLoaded", "VTIO_RegisterAddon": VTIO hooks, use of these for other reasons may cause problems with many mods

// Base for mod classes
//   Handles initialization and general mod behaviours: (Many of these require Config)
//     Versioning and upgrade detection
//     Topbar integration (VTIO will still list mods without icons in the installed mod list)
//     Handling interface and configuration windows
//     Xml datafile loader
//     Standardized chat output
//     Text localization and string file (via LocaleManager)
//   Additional subsystems that may be included
//     Config (ConfigWrapper.as): Setting serialization and change notification
//     Icon (ModIcon.as): Icon display with topbar integration and GEM layout options (Depends on Config)
//     AutoReport: Mail based reporting system for errors or other information (Depends on Config)
//   Subclass is responsible for:
//     Initialization data, including subsystems and their dependencies
//     Additional setting definitions
//     Processing version upgrades
//     Icon and window content (usually in .fla library under default names)
//     Processing datafile content
//     Doing something useful (or at least interesting)
class efd.LoreHound.lib.Mod {
/// Initialization and Cleanup
	// ModData flags for disabling certain gui elements (ModInfo.GuiFlags)
	public static var ef_ModGui_NoConfigWindow:Number = 1 << 0;
	public static var ef_ModGui_None:Number = (1 << 1) - 1;

	// ModData enum describing basic mod behaviour (ModInfo.Type)
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

	// The ModInfo object has the following fields:
	//   Name:String (required, placeholder default "Unnamed")
	//     The name of the mod, for display and used to generate a variety of default identifiers
	//   Version:String (required, placeholder default "0.0.0")
	//     Current build version
	//     Expects "#.#.#[.alpha|.beta]" format (does not enforce, but may cause issues with upgrade system)
	//   MinUpgradableVersion:String (optional, default "0.0.0")
	//     The earliest version from which the current build supports direct update with setting migration
	//     If a prior version upgrades, settings will be reset to defaults to protect against invalid values
	//   LibUpgrades:Array of {mod:VersionString, lib:VersionString} Objects (semi-optional, default undefined)
	//	   Required if library version has changed since the MinUpgradableVersion of the mod
	//     If library version has changed since the previous build:
	//		 Mod version should be bumped (to trigger an update) and this array extended with the previous mod and framework versions (so the update includes the framework)
	//     This will allow the framework to properly handle these infrequent updates
	//     These only need to be retained back to the MinUpgradableVersion
	//     Default behaviour assumes the current version has been in use as far back as upgrades are permitted
	//   Type:e_ModType (optional, default e_ModType_Interface)
	//     Values described above
	//   GuiFlags:ef_ModGui (optional, default undefined)
	//     Set flags to disable certain gui elements. Valid flags are:
	//       ef_ModGui_NoConfigWindow: Do not use a config window
	//         Topbar integration will use tne ModEnabledDV as config target
	//       ef_ModGui_None: Disables all gui elements
	//   Subsystems:Object (optional, default undefined)
	//     A set of keyed pairs Subsystems["Key"] = {Init:Function(Mod, InitObj), InitObj:Object}
	//     Init is a factory method to initialize the required subsystem
	//     InitObj may be adjusted internally prior to the call
	//     Some subsystems have dependencies, Mod ensures correct initialization order but the mod author is responsible for including all dependencies
	//     For full details on dependencies, and param contents, consult the subsystem .as files
	//   Trace (optional, default false)
	//     Enables debug trace messages, usually defined first for ease of commenting out

	//   ArchiveName (optional, default parameter passed by game engine to OnModuleActivated)
	//     Name of archive to use for main config if overriding the one provided by the game

	public function Mod(modInfo:Object, hostMovie:MovieClip) {
		FifoMsg = Delegate.create(this, _FifoMsg);
		ChatMsg = Delegate.create(this, _ChatMsg);
		ErrorMsg = Delegate.create(this, _ErrorMsg);
		TraceMsg = Delegate.create(this, _TraceMsg);
		LogMsg = Delegate.create(this, _LogMsg);

		LoadXmlAsynch = Delegate.create(this, _LoadXmlAsynch);

		GlobalDebugDV = DistributedValue.Create(DVPrefix + "DebugMode");
		GlobalDebugDV.SignalChanged.Connect(SetDebugMode, this);
		DebugTrace = modInfo.Trace || GlobalDebugDV.GetValue();

 		SignalLoadCompleted = new Signal();

		ModListDV = DistributedValue.Create(DVPrefix + "ListMods");
		ModListDV.SignalChanged.Connect(ReportVersion, this);

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
		Version = modInfo.Version;
		if (!modInfo.Type) { modInfo.Type = e_ModType_Interface; }

		SystemsLoaded = { Config: false, LocalizedText: false }
		ModLoadedDV = DistributedValue.Create(ModLoadedVarName);
		ModLoadedDV.SetValue(false);
		if (modInfo.Type == e_ModType_Reactive) {
			ModEnabledDV = DistributedValue.Create(ModEnabledVarName);
			ModEnabledDV.SetValue(true);
			ModEnabledDV.SignalChanged.Connect(ToggleUserEnabled, this);
		}

		LocaleManager.Initialize();
		LocaleManager.SignalStringsLoaded.Connect(StringsLoaded, this);
		LocaleManager.LoadStringFile("Strings");

		HostMovie = hostMovie; // Not needed for console style mods
		ResolutionScaleDV = DistributedValue.Create("GUIResolutionScale");

		if (!(modInfo.GuiFlags & ef_ModGui_NoConfigWindow)) {
			ConfigWindowEscTrigger = new EscapeStackNode();
			ShowConfigDV = DistributedValue.Create(ConfigWindowVarName);
			ShowConfigDV.SetValue(false);
			ShowConfigDV.SignalChanged.Connect(ShowConfigWindowChanged, this);
		}

		if (modInfo.Type == e_ModType_Interface) {
			InterfaceWindowEscTrigger = new EscapeStackNode();
			ShowInterfaceDV = DistributedValue.Create(InterfaceWindowVarName);
			ShowInterfaceDV.SetValue(false);
			ShowInterfaceDV.SignalChanged.Connect(ShowInterfaceWindowChanged, this);
		}

		InitializeModConfig(modInfo);

		LinkVTIO = modInfo.Subsystems.LinkVTIO.Init(this, modInfo.Subsystems.LinkVTIO.InitObj);
		Icon = modInfo.Subsystems.Icon.Init(this, modInfo.Subsystems.Icon.InitObj);
	}

	private function StringsLoaded(success:Boolean):Void {
		if (success) { UpdateLoadProgress("LocalizedText"); }
		else { ErrorMsg("Unable to load string table", { fatal : true }); } // Localization support unavailable, not localized
	}

	// Notify when a core subsystem has finished loading to ensure that LoadComplete properly triggers
	// Also a convenient place to override and trigger events that require multiple subsystems to be loaded
	private function UpdateLoadProgress(loadedSystem:String):Boolean {
		TraceMsg(loadedSystem + " Loaded");
		SystemsLoaded[loadedSystem] = true;
		for (var system:String in SystemsLoaded) {
			if (!SystemsLoaded[system]) { return false; }
		}
		TraceMsg("Is fully loaded");
		LoadComplete();
	}

	// TODO: Failure to clear the SystemsLoaded object seems to crash reliably when the interface window opens
	//       Investigate and fix. Low priority, currently SystemsLoaded is being cleared/largely unused
	private function LoadComplete():Void {
		delete SystemsLoaded; // No longer required
		UpdateManager.UpdateInstall();
		// TODO: Load icon invisibly, and only make it visible when loading is successfully complete?
		SignalLoadCompleted.Emit();
		ModLoadedDV.SetValue(true);
	}

	// The game itself toggles the mod's activation state (based on modules.xml criteria)
	public function GameToggleModEnabled(state:Boolean, archive:Archive) {
		if (!state) {
			// DEPRECATED(v1.0.0): Temporary upgrade support
			if (Config.GetValue("TopbarIntegration") == undefined) { Config.SetValue("TopbarIntegration", false); }
			CloseConfigWindow();
			return Config.SaveConfig();
		} else {
			if (!Config.IsLoaded) {	Config.LoadConfig(archive);	}
		}
		EnabledByGame = state;
		Enabled = state;
	}

	// TODO: Completing icon extraction
	public function OnUnload():Void { Icon.FreeID(); }

	private function SetDebugMode(dv:DistributedValue):Void { DebugTrace = dv.GetValue(); }

	// TODO: Won't work if I toggle it back to false immediately... is there a better solution than this?
	private function ReportVersion(dv:DistributedValue):Void { ChatMsg(Version); }

/// Configuration Settings
	// The framework reserves the following Config setting names for internal use:
	//   "Installed": Trigger first run events
	//   "Version": Triggers upgrades (and rollback notifications)
	//   "Enabled": Exists for e_ModType_Reactive mods
	//   "InterfaceWindowPosition": Exists for e_ModType_Interface mods
	//   "ConfigWindowPosition": Exists if GuiFlag ef_ModGui_NoConfigWindow is not set
	//   Icon settings are handled by ModIcon, and will only exist if an icon is in use
	//   "IconPosition": Deleted if VTIO mod is handling layout; otherwise, a single (X) coordinate with TopbarIntegration or a Point without it
	//   "IconScale": Deleted if integrated with any topbar
	//   "TopbarIntegration": VTIO integration without an icon is implied by attachment of VTIOHelper

	private function InitializeModConfig(modInfo:Object):Void {
		Config = new ConfigWrapper(modInfo.ArchiveName);
		ConfigResetDV = DistributedValue.Create(ModResetVarName);
		ConfigResetDV.SignalChanged.Connect(ResetConfig, this);

		UpdateManager = new Versioning(this, modInfo);

		if (ModEnabledDV != undefined) { Config.NewSetting("Enabled", true); } // Whether mod is enabled by the player

		if (ShowInterfaceDV != undefined) { Config.NewSetting("InterfaceWindowPosition", new Point(20, 30)); }
		if (ShowConfigDV != undefined) { Config.NewSetting("ConfigWindowPosition", new Point(20, 30)); }

		Config.SignalConfigLoaded.Connect(ConfigLoaded, this);
		Config.SignalValueChanged.Connect(ConfigChanged, this);
	}

	private function ConfigLoaded():Void { UpdateLoadProgress("Config"); }

	private function ConfigChanged(setting:String, newValue, oldValue):Void {
		if (setting == "Enabled") {
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
		}
	}

	private function ResetConfig(dv:DistributedValue):Void {
		if (dv.GetValue()) {
			Config.ResetAll();
			dv.SetValue(false);
		}
	}

/// Standard Icon Mouse Behaviour Packages
	public var IconMouse_ToggleUserEnabled:Object = { Action : ToggleUserEnabled, Tooltip : ToggleUserEnabledTooltip };
	public var IconMouse_ToggleInterfaceWindow:Object = { Action : ToggleInterfaceWindow, Tooltip : ToggleInterfaceWindowTooltip };
	public var IconMouse_ToggleConfigWindow:Object = { Action : ToggleConfigWindow, Tooltip : ToggleConfigWindowTooltip };

	// Implementations
	private function ToggleUserEnabled(dv:DistributedValue):Void {
		var value:Boolean = dv != undefined ? dv.GetValue() : !Config.GetValue("Enabled");
		Config.SetValue("Enabled", value);
	}
	private function ToggleUserEnabledTooltip():String {
		return LocaleManager.GetString("GUI", Config.GetValue("Enabled") ? "TooltipModOff" : "TooltipModOn");
	}

	private function ToggleInterfaceWindow():Void {
		if (! ShowInterfaceDV.GetValue()) {	ShowInterfaceDV.SetValue(true); }
		else { TriggerWindowClose.apply(InterfaceWindowClip); }
	}
	private function ToggleInterfaceWindowTooltip():String { return LocaleManager.GetString("GUI", "TooltipShowInterface"); }

	private function ToggleConfigWindow():Void {
		if (!ShowConfigDV.GetValue()) { ShowConfigDV.SetValue(true);}
		else { TriggerWindowClose.apply(ConfigWindowClip); }
	}
	private function ToggleConfigWindowTooltip():String { return LocaleManager.GetString("GUI", "TooltipShowSettings"); }

/// Window Display
	private function OpenWindow(windowName:String, loadEvent:Function, closeEvent:Function, escNode:EscapeStackNode):MovieClip {
		var clip:MovieClip = HostMovie.attachMovie(ModName + windowName, windowName, HostMovie.getNextHighestDepth());
		clip.SignalContentLoaded.Connect(loadEvent, this); // Defer config bindings until content is loaded

		var localeTitle:String = LocaleManager.FormatString("GUI", windowName + "Title", ModName);
		clip.SetTitle(localeTitle, "left");
		clip.SetPadding(10);
		clip.SetContent(ModName + windowName + "Content");
		clip.ShowCloseButton(true);
		clip.ShowStroke(false);
		clip.ShowRezieButton(false);
		clip.ShowFooter(false);

		var position:Point = Config.GetValue(windowName + "Position");
		clip._x = position.x;
		clip._y = position.y;
		SetWindowScale.call(clip, ResolutionScaleDV);
		ResolutionScaleDV.SignalChanged.Connect(SetWindowScale, clip);

		escNode.SignalEscapePressed.Connect(TriggerWindowClose, clip);
		EscapeStack.Push(escNode);
		clip.SignalClose.Connect(closeEvent, this);

		return clip;
	}

	private function WindowClosed(windowClip:MovieClip, windowName:String, escNode:EscapeStackNode):Void {
		ResolutionScaleDV.SignalChanged.Disconnect(SetWindowScale, windowClip);
		escNode.SignalEscapePressed.Disconnect(TriggerWindowClose, windowClip);

		ReturnWindowToVisibleBounds(windowClip, Config.GetDefault(windowName + "Position"));
		Config.SetValue(windowName + "Position", new Point(windowClip._x, windowClip._y));

		windowClip.removeMovieClip();
	}

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

	private function TriggerWindowClose():Void {
		var target:Object = this;
		target.SignalClose.Emit(target);
		target.m_Content.Close();
	}

	private function SetWindowScale(scaleDV:DistributedValue):Void {
		var scale:Number = scaleDV.GetValue() * 100;
		var target:Object = this;
		target._xscale = scale;
		target._yscale = scale;
	}

	private function ShowConfigWindowChanged(dv:DistributedValue):Void {
		if (dv.GetValue()) { // Open window
			if (ModLoadedDV.GetValue() == false) {
				dv.SetValue(false);
				Mod.ErrorMsg("Did not load properly, and has been disabled.");
				return;
			}
			if (ConfigWindowClip == null) {
				ConfigWindowClip = OpenWindow("ConfigWindow", ConfigWindowLoaded, CloseConfigWindow, ConfigWindowEscTrigger);
			}
		} else { // Close window
			if (ConfigWindowClip != null) {
				WindowClosed(ConfigWindowClip, "ConfigWindow", ConfigWindowEscTrigger);
				ConfigWindowClip = null;
			}
		}
	}

	private function ConfigWindowLoaded():Void { ConfigWindowClip.m_Content.AttachConfig(Config); }

	private function CloseConfigWindow():Void { ShowConfigDV.SetValue(false); }

	private function ShowInterfaceWindowChanged(dv:DistributedValue):Void {
		if (dv.GetValue()) { // Open window
			if (ModLoadedDV.GetValue() == false) {
				dv.SetValue(false);
				Mod.ErrorMsg("Did not load properly, and has been disabled.");
				return;
			}
			if (InterfaceWindowClip == null)
			{
				InterfaceWindowClip = OpenWindow("InterfaceWindow", InterfaceWindowLoaded, CloseInterfaceWindow, InterfaceWindowEscTrigger);
			}
		} else {// Close window
			if (InterfaceWindowClip != null) {
				WindowClosed(InterfaceWindowClip, "InterfaceWindow", InterfaceWindowEscTrigger);
				InterfaceWindowClip = null;
			}
		}
	}

	private function InterfaceWindowLoaded():Void { }

	private function CloseInterfaceWindow():Void { ShowInterfaceDV.SetValue(false); }

/// Data File Loader
	// Loads an XML file from a path local to the mod's directory
	// The '.xml' suffix is added if not present
	public function _LoadXmlAsynch(fileName:String, callback:Function):XML {
		if (fileName.substr(-4) != ".xml") {
			fileName += ".xml";
		}
		var loader:XML = new XML();
		loader.ignoreWhite = true;
		loader.onLoad = callback;
		loader.load(ModName + "\\" + fileName);
		return loader;
	}
	public static var LoadXmlAsynch:Function; // Static delegate

/// Text Output
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

	// Bypasses localization, for errors that can't count on localization support
	// Additional option "fatal": Force disables the mod
	private function _ErrorMsg(message:String, options:Object):Void {
		if (!options.noPrefix) {
			var sysPrefix:String = options.system ? (options.system + " - ") : "";
			message = "<font color='#EE0000'>" + ModName +"</font>:"  + (options.fatal ? " FATAL " : " ") + "ERROR - " + sysPrefix + message + "!";
		}
		Utils.PrintChatText(message);
		if (options.fatal) {
			_ErrorMsg("  Mod disabled", { noPrefix : true });
			// TODO: This setting of Enabled should ensure that Enabled is actually a thing
			//       Should it also ensure that the "Loaded" DV is cleared to lock down interface?
			Config.SetValue("Enabled", false);
		}
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

/// Subclass Extension Stubs
	public function InstallMod():Void { }
	public function UpdateMod(newVersion:String, oldVersion:String):Void { }
	private function Activate():Void { }
	private function Deactivate():Void { }
	private function TopbarRegistered(firstTime:Boolean):Void { }

/// Properties and Variables
	public var Version:String;

	public function get Enabled():Boolean { return _Enabled; }
	public function set Enabled(value:Boolean):Void {
		// TODO: This check for Config("Enabled") should be cleaned up for cases where it doesn't exist
		//       Should game trigger Activate/Deactivate pairs for those mods? (affects fallback value choice)
		value = EnabledByGame && Config.GetValue("Enabled");
		if (value != _Enabled) { // State changed
			_Enabled = value;
			if (value) { Activate(); }
			else { Deactivate(); }
		}
	}

	public function get ModLoadedVarName():String { return DVPrefix + ModName + "Loaded"; }
	public function get ModEnabledVarName():String { return DVPrefix + ModName + "Enabled"; }
	public function get ModResetVarName():String { return DVPrefix + ModName + "ResetConfig"; }
	public function get ConfigWindowVarName():String { return DVPrefix + "Show" + ModName + "ConfigUI"; }
	public function get InterfaceWindowVarName():String { return DVPrefix + "Show" + ModName + "Interface"; }

	// Customize based on mod authorship
	public static var DevName:String = "Peloprata";
	public static var DVPrefix:String = "efd"; // Retain this if making a compatible fork of an existing mod

	public var ModName:String;
	public var SystemsLoaded:Object; // Tracks asynchronous data loads so that functions aren't called without proper data, removed once loading complete
	private var ModLoadedDV:DistributedValue; // Locks-out interface when mod fails to load, may also be used for cross-mod integration
	private var ModListDV:DistributedValue;

	private var _Enabled:Boolean = false;
	private var EnabledByGame:Boolean = false;
	// Player enable/disable only applies to reactive mods at this point
	// DV and related config setting will be undefined for interface mods
	private var ModEnabledDV:DistributedValue; // Only reflects the player's setting, doesn't toggle everytime the game triggers it
	// Enabled by player is a persistant config setting

	public var Config:ConfigWrapper;
	private var UpdateManager:Versioning;
	private var ConfigResetDV:DistributedValue; // DV so that it can be flagged from chat when nothing else works
	private var ShowConfigDV:DistributedValue; // Needs to be DV as topbars use it for providing settings from the mod list; if undefined, no config window is available
	private var ResolutionScaleDV:DistributedValue;
	private var ConfigWindowClip:MovieClip = null;
	private var ConfigWindowEscTrigger:EscapeStackNode;

	private var ShowInterfaceDV:DistributedValue; // Provided as DV for /setoption force opening of interface
	private var InterfaceWindowClip:MovieClip = null;
	private var InterfaceWindowEscTrigger:EscapeStackNode;

	public var HostMovie:MovieClip;
	public var Icon:MovieClip;
	private var LinkVTIO:Object;

	public var SignalLoadCompleted:Signal;

	private var DebugTrace:Boolean;
	private var GlobalDebugDV:DistributedValue; // Used to quickly toggle trace or other debug features of all efd mods
}
