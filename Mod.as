// Copyright 2017-2018, Earthfiredrake
// Released under the terms of the MIT License
// https://github.com/Earthfiredrake/SWL-FrameworkMod

// Mod Framework v1.1.2
// Revision numbers are for internal merge tracking only, and do not require an upgrade notification
// See ConfigManager for notification format for major/minor upgrades

//   The following DistributedValue names are reserved for use by the framework; some are hard-coded, some are just convenient standardized names:
//   [pfx] is a developer unique prefix (I use 'efd'), [Name] is the name of the mod
//   Unique per mod name:
//     "[pfx]GameEnables[Name]": Defined in Modules.xml; a hard disable for the mod; will disable all features (including icon) and prevent loading on charswap, /reloadui, or restart
//     "[pfx][Name]Enabled": "Soft" disable that retains icon and doesn't block loading; Used to disable a mod if an internal "fatal" error occurs
//     "[pfx][Name]Loaded": Set to the version string of the mod once fully loaded and initialized; set false OnUnload
//     "[pfx][Name]Config": Defined in Modules.xml; Archive in which settings are saved, usually used with the Config system
//     "[pfx][Name]DebugMode": Toggles debug trace messages and any other debug/dev tools in an individual mod (persists through /reloadui which is useful for checking load behaviour on a non-tracing build)
//     "[pfx][Name]ResetConfig": Trigger to reset settings to defaults from chat, created by the Config subsystem (all fun and games until somebody loses an icon)
//     "[pfx]Show[Name]ConfigWindow": Toggles the settings window, created by the Config subsystem
//     "[pfx]Show[Name]InterfaceWindow": Toggles an interface window, if one was included in ModData
//   Framework shared; use "emf" prefix and should affect all mods built with the framework:
//     "emfListMods": Mods report their current version and author to system chat
//     "emfNextIconID": Used to create unique offsets on default icon placements, reducing icon pileups when installing multiple mods
//     "emfDebugMode": Toggles debug trace messages globally, may also enable other debug/dev tools (persists through /reloadui)
//   From other mods:
//     "VTIO_IsLoaded", "VTIO_RegisterAddon": VTIO hooks, use of these for other reasons may cause problems with many mods
//     "meeehrUI_IsLoaded": Meeehr's topbar load notifier; Some mods may use it to trigger a VTIO registration, though most (including this) just use the legacy support
//     "ModFolder": Modules.xml enable flag for ModFolder; Used to trigger a workaround for that mod's VTIO behaviour; Setting it while using other topbars may do strange things

// Base for mod classes
//   Handles initialization and general mod behaviours:
//     Xml datafile loader
//     Standardized chat output
//     Text localization and string file (via LocaleManager)
//   Additional subsystems that may be applied:
//     Config (ConfigManager.as):
//       Setting serialization and change notification
//       Versioning and upgrade detection
//       Configuration window
//     Icon (ModIcon.as): Icon display with topbar integration and GEM layout options
//     VTIOHelper: Integration with VTIO compatible mod containers and topbars
//     Window: Interface window management
//     AutoReport: Mail based reporting system for errors or other information
//   Subclass is responsible for:
//     Initialization data, including subsystems and their dependencies
//     Additional setting definitions
//     Processing version upgrades
//     Icon and window content (usually in .fla library under default names)
//     Processing datafile content
//     Doing something useful (or at least interesting)

// When adapting any code for another mod:
//   Always use a unique namespace for the mod on all class, import and __className definitions (in *.lcl.as files)
//     The flash environment caches classes by fully namespace qualified identifier when first encountered
//     Whichever mod loads first gets to be the authoritive definition for all classes it defines
//     This can be helpful if loading order is known (Game API loads before mods), but mods can't otherwise depend on being loaded in any particular order
//   Use similarly unique names, or dynamic linking, for clip library assets
//     Due to similar caching behaviour, where anybody's library asset by that name will use whatever class was linked
//     See etu.MovieClipHelper for functions to do dynamic linking

import gfx.utils.Delegate;

import com.GameInterface.Chat; // FIFO messages
import com.GameInterface.DistributedValue;
import com.GameInterface.Utils; // Chat messages *shrug*
import com.Utils.Archive;
import com.Utils.Signal;

// Mod namespace qualified imports and class definition are #included from locally overriden file
#include "Mod.lcl.as"
/// Initialization and Cleanup
	// The ModInfo object has the following fields:
	//   Debug (optional, default false)
	//     Enables debug trace messages, usually defined first for easy commenting out
	//   Name:String (required, placeholder default "Unnamed")
	//     The name of the mod, for display and used to generate a variety of default identifiers
	//   Version:String (required, placeholder default "0.0.0")
	//     Current build version
	//     Expects "#.#.#[.alpha|.beta]" format (does not enforce, but may cause issues with upgrade system)
	//   Subsystems:Object (optional, default undefined)
	//     A set of keyed pairs Subsystems["Key"] = {Init:Function(Mod, InitObj), InitObj:Object}
	//     Init is a factory method to initialize the required subsystem
	//     InitObj may be adjusted internally prior to the call
	//     Some subsystems have dependencies, Mod ensures correct initialization order but the mod author is responsible for including all dependencies
	//     For full details on dependencies, and param contents, consult the subsystem .as files

	// TODO: Subsystems are currently locked into particular keys
	//       Would like to make this a more flexible component based system

	public function Mod(modInfo:Object, hostClip:MovieClip) {
		Debug = DebugUtils.StaticInit(modInfo.Name || "Unnamed", DevName, DVPrefix, modInfo.Debug);
		DebugUtils.SignalFatalError.Connect(OnFatalError, this);

		FifoMsg = Delegate.create(this, _FifoMsg);
		ChatMsg = Delegate.create(this, _ChatMsg);

		LoadXmlAsynch = Delegate.create(this, _LoadXmlAsynch);

		if (!modInfo.Name) {
			modInfo.Name = "Unnamed";
			Debug.ErrorMsg("Mod requires a name");
		} else { ModName = modInfo.Name; }
		if (!modInfo.Version) {
			modInfo.Version = "0.0.0";
			Debug.ErrorMsg("Mod expects a version number");
		}
		ModName = modInfo.Name;
		Version = modInfo.Version;

 		SignalLoadCompleted = new Signal();
		SystemsLoaded = { LocalizedText: false };
		if (modInfo.Subsystems.Config != undefined) { SystemsLoaded.Config = false; }
		ModLoadedDV = DistributedValue.Create(ModLoadedVarName);
		ModLoadedDV.SetValue(false);
		ModEnabledDV = DistributedValue.Create(ModEnabledVarName);
		ModEnabledDV.SetValue(undefined);
		ModEnabledDV.SignalChanged.Connect(ModEnabledChanged, this);

		ModListDV = DistributedValue.Create("emfListMods");
		ModListDV.SignalChanged.Connect(ReportVersion, this);

		LocaleManager.Initialize();
		LocaleManager.SignalStringsLoaded.Connect(StringsLoaded, this);
		LocaleManager.LoadStringFile("Strings");

		HostClip = hostClip; // Not needed for console style mods

		ConfigHost = modInfo.Subsystems.Config.Init(this, modInfo.Subsystems.Config.InitObj);
		// TODO: Some mods won't have to serialize this, because it only makes sense as an error disable
		Config.NewSetting("Enabled", true);
		Config.SignalConfigLoaded.Connect(ConfigLoaded, this);

		InterfaceWindow = modInfo.Subsystems.Interface.Init(this, modInfo.Subsystems.Interface.InitObj);
		LinkVTIO = modInfo.Subsystems.LinkVTIO.Init(this, modInfo.Subsystems.LinkVTIO.InitObj);
		Icon = modInfo.Subsystems.Icon.Init(this, modInfo.Subsystems.Icon.InitObj);
	}

	private function StringsLoaded(success:Boolean):Void {
		if (success) { UpdateLoadProgress("LocalizedText"); }
		else { Debug.ErrorMsg("Unable to load string table", { fatal : true }); } // Localization support unavailable, not localized
	}

	// Notify when a core subsystem has finished loading to ensure that LoadComplete properly triggers
	// Also a convenient place to override and trigger events that require multiple subsystems to be loaded
	// TODO: Timeout warning to notify of systems that fail to properly register their state
	private function UpdateLoadProgress(loadedSystem:String):Boolean {
		Debug.TraceMsg(loadedSystem + " Loaded");
		SystemsLoaded[loadedSystem] = true;
		for (var system:String in SystemsLoaded) {
			if (!SystemsLoaded[system]) { return false; }
		}
		LoadComplete();
	}

	// TODO: Failure to clear the SystemsLoaded object seems to crash reliably when the interface window opens
	//       Investigate and fix. Low priority, currently SystemsLoaded is being cleared/largely unused
	private function LoadComplete():Void {
		delete SystemsLoaded; // No longer required
		ConfigHost.UpdateManager.UpdateInstall();
		// TODO: Load icon invisibly, and only make it visible when loading is successfully complete?
		SignalLoadCompleted.Emit();
		ModLoadedDV.SetValue(Version);
		Debug.TraceMsg("Is fully loaded");
		ModEnabledDV.SetValue(Config != undefined ? Config.GetValue("Enabled", true) : true);
	}

	// The game itself toggles the mod's activation state (based on modules.xml criteria)
	// Provides archive for Config system serialization
	public function GameToggleModEnabled(state:Boolean, archive:Archive) {
		if (!state) {
			// DEPRECATED(v1.0.0): Temporary upgrade support
			if (Config.GetValue("TopbarIntegration") == undefined) { Config.SetValue("TopbarIntegration", false); }

			ConfigHost.ConfigWindow.CloseWindow();
			EnabledByGame = false;
			CheckEnableState();
			return Config.SaveConfig();
		} else {
			if (!Config.IsLoaded) { Config.LoadConfig(archive); }
			EnabledByGame = true;
			CheckEnableState();
		}
	}

	//  Flash triggered enable state DV has changed
	private function ModEnabledChanged(dv:DistributedValue):Void {
		var newValue:Boolean = dv.GetValue();
		// Certain bugs (cyclic strong references) can result in an instance of the mod remaining in memory despite being removed from the visual tree during a /reloadui
		// This attempts to detect those instances, by hooking a warning that will be triggered if the mod constructor is called while another instance still exists
		if (newValue == undefined) { Debug.DevMsg("A prior instance was not fully cleaned up before construction of a new instance"); }
		if (newValue && (FatalError || SystemsLoaded != undefined)) {
			if (FatalError) {
				Debug.ErrorMsg("Unable to activate due to a previous fatal error");
				Debug.ErrorMsg("Original Error: " + FatalError, { noHeader : true });
			} else {
				Debug.ErrorMsg("Failed to load required components, and cannot be enabled");
				for (var key:String in SystemsLoaded) {
					if (!SystemsLoaded[key]) { Debug.ErrorMsg("Missing: " + key, { noHeader : true }); }
				}
			}	
			dv.SetValue(false);
			return;
		}
		CheckEnableState();
		Config.SetValue("Enabled", dv.GetValue());
		if (Icon == undefined) {
			// No Icon, probably means it's a console style mod
			// Provide alternate notification
			ChatMsg(LocaleManager.GetString("General", newValue ? "Enabled" : "Disabled"));
		}
	}

	private function CheckEnableState() {
		var newState:Boolean = (Boolean)(EnabledByGame && ModEnabledDV.GetValue()); // Cast due to ModEnabledDV possibly null
		if (newState != Enabled) { // State changed
			Enabled = newState;
			if (newState) { Activate(); }
			else { Deactivate(); }
			Icon.Refresh();
		}
	}

	// TODO: Figure out what else needs to be hooked up to DebugUtils.SignalFatalError
    private function OnFatalError(error:String) { FatalError = error; }

	public function OnUnload():Void {
		ModLoadedDV.SetValue(false);
		Icon.FreeID(); // TODO: Move this into Icon, probably by raising an event
		removeMovieClip(Icon);
		LoadXmlAsynch = undefined;
		FifoMsg = undefined;
		ChatMsg = undefined;
	}

	// Each mod ends up getting two notifications, whichever mod is first gets a true+false, other mods get false+false
	private function ReportVersion(dv:DistributedValue):Void {
		if (!VersionReported) { ChatMsg(Version + " : " + DevName); }
		VersionReported = !VersionReported;
		if (dv.GetValue()) { dv.SetValue(false); }
	}

/// Configuration Settings
	private function ConfigLoaded():Void {
		Config.SignalValueChanged.Connect(ConfigChanged, this);
		UpdateLoadProgress("Config");
	}

	// Config changed handler will not be triggered by initial loading
	// Update handlers get an initial shot at the loaded settings
	private function ConfigChanged(setting:String, newValue, oldValue):Void {
		switch(setting) {
			case "Enabled" : {
				ModEnabledDV.SetValue(newValue);
				break;
			}
		}
	}

/// Standard Icon Mouse Behaviour Packages
	public var IconMouse_ToggleUserEnabled:Object = { Action : ToggleUserEnabled, Tooltip : ToggleUserEnabledTooltip };
	public var IconMouse_ToggleInterfaceWindow:Object = { Action : ToggleInterfaceWindow, Tooltip : ToggleInterfaceWindowTooltip };
	public var IconMouse_ToggleConfigWindow:Object = { Action : ToggleConfigWindow, Tooltip : ToggleConfigWindowTooltip };

	// Implementations
	private function ToggleUserEnabled():Void { ModEnabledDV.SetValue(!ModEnabledDV.GetValue()); }
	private function ToggleUserEnabledTooltip():String { return LocaleManager.GetString("GUI", ModEnabledDV.GetValue() ? "TooltipModOff" : "TooltipModOn"); }

	private function ToggleInterfaceWindow():Void { InterfaceWindow.ToggleWindow(); }
	private function ToggleInterfaceWindowTooltip():String { return LocaleManager.GetString("GUI", "TooltipShowInterface"); }

	private function ToggleConfigWindow():Void { ConfigHost.ConfigWindow.ToggleWindow(); }
	private function ToggleConfigWindowTooltip():String { return LocaleManager.GetString("GUI", "TooltipShowSettings"); }

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

	// Static delegates to the ones above (and Debug)
	// So other components can access them without needing a reference
	// Recommend wrapping the call in a local version, that inserts an identifer for the subcomponent involved
	public static var FifoMsg:Function;
	public static var ChatMsg:Function;

/// Subclass Extension Stubs
	public function InstallMod():Void { }
	public function UpdateMod(newVersion:String, oldVersion:String):Void { }
	private function Activate():Void { }
	private function Deactivate():Void { }

/// Properties and Variables
	public var ModName:String;
	public var Version:String;
	// Customize based on mod authorship
	public static var DevName:String = "Peloprata";
	public static var DVPrefix:String = "efd";

	public function get ModLoadedVarName():String { return DVPrefix + ModName + "Loaded"; }
	public var ModLoadedDV:DistributedValue; // Locks-out interface when mod fails to load, may also be used for basic cross-mod integration
	public var SystemsLoaded:Object; // Tracks asynchronous data loads so that functions aren't called without proper data, removed once loading complete
	public var FatalError:String;
	public var SignalLoadCompleted:Signal;

	public function get ModEnabledVarName():String { return DVPrefix + ModName + "Enabled"; }
	private var ModEnabledDV:DistributedValue; // Doesn't reflect game toggles, only the player or internal mod disabling
	private var EnabledByGame:Boolean = false;
	private var Enabled:Boolean = false; // PlayerEnabled && GameEnabled

	private var ModListDV:DistributedValue;
	private var VersionReported:Boolean = false;

	public var ConfigHost:Object; // Ducktyped ConfigManager
	public var Config:Object; // Ducktyped ConfigWrapper

	private var InterfaceWindow:Object; // Ducktyped Window

	public var HostClip:MovieClip;
	public var Icon:MovieClip; // Ducktyped ModIcon
	private var LinkVTIO:Object; // Ducktyped VTIOHelper

	private var Debug:DebugUtils;
}
