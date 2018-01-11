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

// Mod Framework v1.1.0
// See ModInfo.LibUpgrades for upgrade requirements

// The framework reserves the following DistributedValue names (where [pfx] is a developer specific prefix (I use 'efd'), and [Name] is the mod name):
//   "[pfx][Name]Loaded": Set to true when the mod is fully loaded and initialized
//   "[pfx][Name]Enabled": Exists for e_ModType_Reactive mods; "Soft" disable that doesn't prevent loading on restart (Modules.xml toggle var does); Corresponds to "Enabled" config setting
//   "[pfx][Name]ResetConfig": Trigger to reset settings to defaults from chat
//   "[pfx]Show[Name]Interface": Exists for e_ModType_Interface mods; Toggle mod interface window
//   "[pfx]Show[Name]ConfigUI": Exists if GuiFlag ef_ModGui_NoConfigWindow is not set; Toggle mod settings window
//   "[pfx]NextIconID": Used to create unique offsets on default icon placements, hopefully reducing icon pileups when using multiple [pfx] mods
//   "[pfx]DebugMode": Toggles debug trace messages for all [pfx] mods, may also enable other debug/dev tools
//   "VTIO_IsLoaded", "VTIO_RegisterAddon": VTIO hooks, use of these for other reasons may cause problems with many mods

// Base for mod classes
//   Handles initialization and general mod behaviours:
//     Setting serialization and change notification (via ConfigWrapper)
//     Versioning and upgrade detection
//     Icon behaviour and topbar integration (via ModIcon)
//     Handling interface and configuration windows
//     Xml datafile loader
//     Standardized chat output
//     Text localization and string file (via LocaleManager)
//   Does not deal with the AutoReport subsystem, which can be optionally added from the subclass
//   Subclass is responsible for:
//     Initialization data
//     Additional setting definitions
//     Processing version upgrades
//     Icon and window content (usually in .fla library under default names)
//     Processing datafile content
//     Doing something useful (or at least interesting)
class efd.LoreHound.lib.Mod {
/// Initialization and Cleanup
	// ModData flags for disabling certain gui elements (ModInfo.GuiFlags)
	public static var ef_ModGui_NoIcon:Number = 1 << 0;
	public static var ef_ModGui_NoConfigWindow:Number = 1 << 1;
	public static var ef_ModGui_Console:Number = ef_ModGui_NoIcon | ef_ModGui_NoConfigWindow;
	public static var ef_ModGui_NoTopbar:Number = 1 << 2;
	public static var ef_ModGui_None:Number = (1 << 3) - 1;

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
	//   Type:e_ModType (optional, default e_ModType_Interface)
	//     Values described above
	//   ArchiveName (optional, default undefined (uses parameter passed by game))
	//     Name of archive to use for main config if overriding the one provided by the game
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
	//   GuiFlags:ef_ModGui (optional, default undefined)
	//     Set flags to disable certain gui elements. Valid flags are:
	//       ef_ModGui_NoIcon: Display no icon (may still integrate with VTIO topbar to appear on mod list)
	//       ef_ModGui_NoConfigWindow: Do not use a config window,
	//         Topbar integration will use tne ModEnabledDV as config target
	//       ef_ModGui_Console: (NoIcon | NoConfigWindow) also removes HostMovie variable, so cannot have an interface window either
	//       ef_ModGui_NoTopbar: Disable topbar integration (VTIO or built in)
	//       ef_ModGui_None: Disables all gui elements
	//   IconData:Object (optional, any undefined sub-values will use their own defaults)
	//     ResName:String (optional, default ModName + "Icon")
	//       The name of the library resource to use as graphical elements to the icon
	//     All other members are applied as initializers to the ModIcon object prior to construction
	//     These values are set internally and will not be passed if provided:
	//       ModName, DevName, HostMovie, Config
	//     These functions, which will be called in the context of the Mod object, may be provided as overrides:
	//       GetFrame: Returns the name of the icon frame to be displayed based on current mod state
	//       LeftMouseInfo: Mouse handler as described below
	//       RightMouseInfo: Mouse handler as described below
	//         Mouse handler object defining two functions:
	//           Action: Called when that mouse button is pressed on the icon
	//           Tooltip: Returns a string describing the action for part of the tooltip
	//       ExtraTooltipInfo: Returns a string of additional info to append to the tooltip
	//   Trace (optional, default false)
	//     Enables debug trace messages
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
		LibUpgrades = modInfo.LibUpgrades;

		SystemsLoaded = { Config: false, LocalizedText: false }
		ModLoadedDV = DistributedValue.Create(ModLoadedVarName);
		ModLoadedDV.SetValue(false);
		if (modInfo.Type == e_ModType_Reactive) {
			ModEnabledDV = DistributedValue.Create(ModEnabledVarName);
			ModEnabledDV.SetValue(true);
			ModEnabledDV.SignalChanged.Connect(ChangeModEnabled, this);
		}

		LocaleManager.Initialize();
		LocaleManager.SignalStringsLoaded.Connect(StringsLoaded, this);
		LocaleManager.LoadStringFile("Strings");

		if ((modInfo.GuiFlags & ef_ModGui_Console) != ef_ModGui_Console) {
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
		}
		InitializeModConfig(modInfo);

		if (!(modInfo.GuiFlags & ef_ModGui_NoIcon)) { CreateIcon(modInfo); }
	}

	private function StringsLoaded(success:Boolean):Void {
		if (success) {
			TraceMsg("Localized strings loaded");
			SystemsLoaded.LocalizedText = true;
			CheckLoadComplete();
		} else {
			// Localization support unavailable, not localized
			ErrorMsg("Unable to load string table", { fatal : true });
		}
	}

	private function CheckLoadComplete():Void {
		for (var key:String in SystemsLoaded) {
			if (!SystemsLoaded[key]) { return; }
		}
		TraceMsg("Is fully loaded");
		LoadComplete();
	}

	// TODO: Failure to clear the SystemsLoaded object seems to crash reliably when the interface window opens
	//       Investigate and fix. Low priority, currently SystemsLoaded is being cleared/largely unused
	private function LoadComplete():Void {
		delete SystemsLoaded; // No longer required
		UpdateInstall();
		// TODO: Load icon invisibly, and only make it visible when loading is successfully complete?
		// DEPRECATED(v1.0.0): Temporary upgrade support (use of 'undefined')
		var integration:Boolean = Config.GetValue("TopbarIntegration", false);
		if (integration == undefined || integration) { LinkWithTopbar(); }
		ModLoadedDV.SetValue(true);
	}

	// The game itself toggles the mod's activation state (based on modules.xml criteria)
	public function GameToggleModEnabled(state:Boolean, archive:Archive) {
		if (!state) {
			if (Config.GetValue("TopbarIntegration") == undefined) { Config.SetValue("TopbarIntegration", false); } // DEPRECATED(v1.0.0): Temporary upgrade support
			CloseConfigWindow();
			return Config.SaveConfig();
		} else {
			if (!Config.IsLoaded) {	Config.LoadConfig(archive);	}
		}
		EnabledByGame = state;
		Enabled = state;
	}

	public function OnUnload():Void { Icon.FreeID(); }

	private function SetDebugMode(dv:DistributedValue):Void { DebugTrace = dv.GetValue(); }

/// Configuration Settings
	// The framework reserves the following Config setting names for internal use:
	//   "Installed": Trigger first run events
	//   "Version": Triggers upgrades (and rollback notifications)
	//   "Enabled": Exists for e_ModType_Reactive mods
	//   "TopbarIntegration": Exists if GuiFlag ef_ModGui_NoTopbar is not set
	//   "IconPosition": Deleted if VTIO mod is handling layout; otherwise, a single (X) coordinate with TopbarIntegration or a Point without it
	//   "IconScale": Deleted if integrated with any topbar
	//   "InterfaceWindowPosition": Exists for e_ModType_Interface mods
	//   "ConfigWindowPosition": Exists if GuiFlag ef_ModGui_NoConfigWindow is not set

	private function InitializeModConfig(modInfo:Object):Void {
		Config = new ConfigWrapper(modInfo.ArchiveName);
		ConfigResetDV = DistributedValue.Create(ModResetVarName);
		ConfigResetDV.SignalChanged.Connect(ResetConfig, this);

		Config.NewSetting("Version", modInfo.Version);
		Config.NewSetting("Installed", false); // Will always be saved as true, only remains false if settings do not exist
		if (ModEnabledDV != undefined) { Config.NewSetting("Enabled", true); } // Whether mod is enabled by the player

		if (!(modInfo.GuiFlags & ef_ModGui_NoTopbar)) {
			Config.NewSetting("TopbarIntegration", true);
			// Will have a value before saving, temporary undefined used to coerce consistent behaviour on upgrade
			Config.SetValue("TopbarIntegration", undefined); // DEPRECATED(v1.0.0): Temporary upgrade support
			ViperDV = DistributedValue.Create("VTIO_IsLoaded");
		}
		if (ShowInterfaceDV != undefined) { Config.NewSetting("InterfaceWindowPosition", new Point(20, 30)); }
		if (ShowConfigDV != undefined) { Config.NewSetting("ConfigWindowPosition", new Point(20, 30)); }

		Config.SignalConfigLoaded.Connect(ConfigLoaded, this);
		Config.SignalValueChanged.Connect(ConfigChanged, this);
		// Change notification hook may be deferred until load, if needed
	}

	private function ConfigLoaded():Void {
		TraceMsg("Config loaded");
		SystemsLoaded.Config = true;
		CheckLoadComplete();
	}

	private function ConfigChanged(setting:String, newValue, oldValue):Void {
		switch(setting) {
			case "Enabled": {
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
			}
			case "TopbarIntegration": {
				if (newValue) {
					BringAboveTopbar(true);
					if (ViperDV.GetValue()) { LinkWithTopbar(); }
				} else {
					BringAboveTopbar(false);
					if (ViperDV.GetValue()) {
						Icon = HostMovie.ModIcon;
						DetachTopbarListeners();
						// NOTE: A /reloadui is strongly recommended after "detaching" from a VTIO topbar
						//       As VTIO does not provide a method of de-registering, the mod tries to fake it (to varied success)
						ChatMsg(LocaleManager.GetString("General", "RemoveVTIO"));
					}
				}
				break;
			}
			default: // Setting does not push changes (is checked on demand)
				break;
		}
	}

	private function ResetConfig(dv:DistributedValue):Void {
		if (dv.GetValue()) {
			Config.ResetAll();
			dv.SetValue(false);
		}
	}

/// Versioning and Upgrades
	private function UpdateInstall():Void {
		if (!Config.GetValue("Installed")) {
			// Fresh install, use the actual default value instead of the update placeholder
			Config.ResetValue("TopbarIntegration"); // DEPRECATED(v1.0.0): Temporary upgrade support
			InstallMod(); // Mod specific install behaviour
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
				} else {
					for (var i:Number = 0; i < LibUpgrades.length; ++i) {
						if (CompareVersions(LibUpgrades[i].mod, oldVersion) >= 0) {
							UpdateLib(LibUpgrades[i].lib); // Library updates
							break;
						}
					}
					UpdateMod(newVersion, oldVersion); // Mod specific updates
				}
			}
			// Reset the version number to the new version
			Config.ResetValue("Version");
			ChatMsg(LocaleManager.FormatString("General", versionChange > 0 ? "Update" : "Revert", newVersion));
			if (ShowConfigDV != undefined) {
				ChatMsg(LocaleManager.GetString("General", "ReviewSettings"), { noPrefix : true });
			}
		}
		// No longer required
		delete MinUpgradableVersion;
		delete LibUpgrades;
	}

	private function UpdateLib(oldVersion:String):Void {
		// v1.1: changes how GUIResolutionScale is used, and adjusts saved ui locations to compensate
		if (CompareVersions("1.1.0", oldVersion) > 0) {
			var scale:Number = ResolutionScaleDV.GetValue();
			if (Config.HasSetting("InterfaceWindowPosition")) {
				var pos:Point = Config.GetValue("InterfaceWindowPosition");
				Config.SetValue("InterfaceWindowPosition", new Point(pos.x * scale, pos.y * scale));
			}
			if (Config.HasSetting("ConfigWindowPosition")) {
				var pos:Point = Config.GetValue("ConfigWindowPosition");
				Config.SetValue("ConfigWindowPosition", new Point(pos.x * scale, pos.y * scale));
			}
			if (Config.HasSetting("IconPosition")) {
				// Either a Point or a Number, would be much simpler if Point handled the *= operator
				// Duplication of SetValue is due to error that (pos *= scale) was attempting to assign a Number to a Point
				//   Despite explicitly restricting that branch to things that aren't points...
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

/// Topbar registration
	// Most container mods support the legacy VTIO interface
	private function LinkWithTopbar():Void {
		// Try to register now, in case they loaded first, otherwise signup to detect if they load
		DoTopbarRegistration(ViperDV);
		ViperDV.SignalChanged.Connect(DoTopbarRegistration, this);
		// DEPRECATED(v1.0.0) Temporary upgrade support (condition guard)
		if (Config.GetValue("TopbarIntegration")) {
			BringAboveTopbar(true);
		}
	}

	private function DoTopbarRegistration(dv:DistributedValue):Void {
		if (dv.GetValue()) {
			// DEPRECATED(v1.0.0) Temporary upgrade support (this section)
			Config.SetValue("TopbarIntegration", true);
			BringAboveTopbar(true);

			// Adjust icon to be better suited for topbar integration
			Icon.VTIOMode = true;

			// Doing this more than once messes with Meeehr's, will have to find alternate workaround for ModFolder
			if (!RegisteredWithTopbar) {
				// Note: Viper's *requires* all five values, regardless of whether the icon exists or not
				//       Both are capable of handling "undefined" or otherwise invalid icon names
				var topbarInfo:Array = [ModName, DevName, Version, ShowConfigDV != undefined ? ConfigWindowVarName : ModEnabledVarName, Icon.toString()];
				DistributedValue.SetDValue("VTIO_RegisterAddon", topbarInfo.join('|'));
			}
			// VTIO creates its own icon, use it as our target for changes instead
			// Can't actually remove ours though, Meeehr's redirects event handling oddly
			// (It calls back to the original clip, using the new clip as the "this" instance)
			// And just to be different, ModFolder doesn't create a copy at all, it just uses the one we give it
			// In which case we don't want to lose our current reference
			if (HostMovie.Icon != undefined) {
				Icon = Icon.CopyToTopbar(HostMovie.Icon);
				Icon.Refresh();
				HostMovie.ModIcon._visible = false; // Usually the topbar will do this for us, but it's not so good about it during a re-register
			}
			TopbarRegistered(!RegisteredWithTopbar);
			RegisteredWithTopbar = true;
			// Once registered, topbar DVs are no longer required; except by ModFolder which has a nasty habit of failing to register the first time around
			if (!DistributedValue.GetDValue("ModFolder")) {
				// Deferred to prevent mangling ongoing signal handling
				setTimeout(Delegate.create(this, DetachTopbarListeners), 1, dv);
			}
		} else {
			// Workaround for ModFolder, which has a nasty habit of leaving the VTIO_IsLoaded flag set during reloads
			// Would be very nice to get in contact with Icarus on this
			// Seem to have found a way to do this that doesn't cause problems with Meeehr's and doesn't require explicit checks for ModFolder
			RegisteredWithTopbar = false;
		}
	}

	private function BringAboveTopbar(above:Boolean):Void {
		if (above != IsAboveTopbar && Icon != undefined) {
			if (above) { SFClipLoader.SetClipLayer(SFClipLoader.GetClipIndex(HostMovie), _global.Enums.ViewLayer.e_ViewLayerTop, 2); }
			else { SFClipLoader.SetClipLayer(SFClipLoader.GetClipIndex(HostMovie), _global.Enums.ViewLayer.e_ViewLayerMiddle, 10); }
			IsAboveTopbar = above;
		}
	}

	// This needs to be deferred so that the disconnection doesn't muddle the ongoing processing
	private function DetachTopbarListeners():Void {	ViperDV.SignalChanged.Disconnect(DoTopbarRegistration, this); }

/// Icon
	private function CreateIcon(modInfo:Object):Void {
		var iconData:Object = modInfo.IconData ? modInfo.IconData : new Object();
		var iconName:String = iconData.ResName ? iconData.ResName : ModName + "Icon";
		delete iconData.ResName;

		iconData.ModName = ModName;
		iconData.DevName = DevName;
		iconData.HostMovie = HostMovie;
		iconData.Config = Config;

		if (iconData.GetFrame) {
			iconData.GetFrame = Delegate.create(this, iconData.GetFrame);
		}

		if (!iconData.LeftMouseInfo) {
			if (modInfo.Type == e_ModType_Interface) {
				iconData.LeftMouseInfo = { Action : Delegate.create(this, ToggleInterfaceWindow), Tooltip : ToggleInterfaceTooltip };
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

	// Mouse handlers
	//   See above or ModType descriptions for default hooking
	private function ChangeModEnabled(dv:DistributedValue):Void {
		var value:Boolean = dv != undefined ? dv.GetValue() : !Config.GetValue("Enabled");
		Config.SetValue("Enabled", value);
	}
	private function ToggleModTooltip():String {
		return LocaleManager.GetString("GUI", Config.GetValue("Enabled") ? "TooltipModOff" : "TooltipModOn");
	}

	private function ToggleConfigWindow():Void {
		if (!ShowConfigDV.GetValue()) {
			ShowConfigDV.SetValue(true);
		} else {
			TriggerWindowClose.apply(ConfigWindowClip);
		}
	}
	private static function ToggleConfigTooltip():String { return LocaleManager.GetString("GUI", "TooltipShowSettings"); }

	private function ToggleInterfaceWindow():Void {
		if (! ShowInterfaceDV.GetValue()) {// Show the interface
			ShowInterfaceDV.SetValue(true);
		} else {
			// Close the interface;
			TriggerWindowClose.apply(InterfaceWindowClip);
		}
	}
	private static function ToggleInterfaceTooltip():String { return LocaleManager.GetString("GUI", "TooltipShowInterface"); }

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
	private function InstallMod():Void { }
	private function UpdateMod(newVersion:String, oldVersion:String):Void { }
	private function Activate():Void { }
	private function Deactivate():Void { }
	private function TopbarRegistered(firstTime:Boolean):Void { }

/// Properties and Variables
	public function get Version():String { return Config.GetValue("Version"); }

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
	private var MinUpgradableVersion:String; // Minimum installed version for setting migration during update; Discarded after update
	private var LibUpgrades:Array; // List of library version upgrades as {mod:version, lib:version} pairs; Discarded after update
	private var ModLoadedDV:DistributedValue; // Locks-out interface when mod fails to load, may also be used for cross-mod integration

	private var _Enabled:Boolean = false;
	private var EnabledByGame:Boolean = false;
	// Player enable/disable only applies to reactive mods at this point
	// DV and related config setting will be undefined for interface mods
	private var ModEnabledDV:DistributedValue; // Only reflects the player's setting, doesn't toggle everytime the game triggers it
	// Enabled by player is a persistant config setting

	public var Config:ConfigWrapper;
	private var ConfigResetDV:DistributedValue; // DV so that it can be flagged from chat when nothing else works
	private var ShowConfigDV:DistributedValue; // Needs to be DV as topbars use it for providing settings from the mod list; if undefined, no config window is available
	private var ResolutionScaleDV:DistributedValue;
	private var ConfigWindowClip:MovieClip = null;
	private var ConfigWindowEscTrigger:EscapeStackNode;

	private var ShowInterfaceDV:DistributedValue; // Provided as DV for /setoption force opening of interface
	private var InterfaceWindowClip:MovieClip = null;
	private var InterfaceWindowEscTrigger:EscapeStackNode;

	private var HostMovie:MovieClip;
	public var Icon:ModIcon;

	private var IsAboveTopbar:Boolean = false; // Display layer has been changed to render above topbar
	// private var MeeehrDV:DistributedValue;
	private var ViperDV:DistributedValue;
	private var RegisteredWithTopbar:Boolean = false;

	private var DebugTrace:Boolean;
	private var GlobalDebugDV:DistributedValue; // Used to quickly toggle trace or other debug features of all efd mods
}
