// Copyright 2017-2018, Earthfiredrake
// Released under the terms of the MIT License
// https://github.com/Earthfiredrake/SWL-FrameworkMod

// Icon subsystem implementation
// Dependencies:
//   Subsystems: Config, Localization
//   Library Symbols:
//     [ModName]Icon: Movieclip containing the icon to be displayed, with any alternate icon modes as labeled frames
//       (Symbol name may be overriden, see InitObj.ResName)
// InitObj: (optional, any undefined sub-values will use their own defaults)
//     ResName:String (optional, default ModName + "Icon")
//       The name of the library resource to use as graphical element for the icon
//     All other members are applied as initializers to the ModIcon object prior to construction
//     These functions, which will be called in the context of ModObj, may be provided as overrides:
//       GetFrame:
//          Returns the name of the icon frame to be displayed based on current mod state
//          Default uses existence and state of Config("Enabled") to return "active"|"inactive"
//       LeftMouseInfo: Mouse handler as described below, default undefined
//       RightMouseInfo: Mouse handler as described below, default undefined
//         Mouse handler objects define two functions:
//           Action: Called when the icon is pressed with the linked mouse button
//           Tooltip: Returns a descriptive string to add to the tooltip
//         Standard mouse handlers defined in Mod:
//           IconMouse_ToggleUserEnabled: Toggles the Config("Enabled") setting
//           IconMouse_ToggleInterfaceWindow: Toggles the mod interface window DV
//           IconMouse_ToggleConfigWindow: Toggles the mod config window DV
//       ExtraTooltipInfo: Returns a string of additional info to append to the tooltip, default undefined

import flash.filters.DropShadowFilter;
import flash.geom.Point;

import gfx.utils.Delegate;

import com.GameInterface.DistributedValue;
import com.GameInterface.Tooltip.TooltipData;
import com.GameInterface.Tooltip.TooltipInterface;
import com.GameInterface.Tooltip.TooltipManager;
import com.Utils.GlobalSignal;
import com.Utils.Signal;
import com.Utils.WeakPtr;
import GUIFramework.SFClipLoader;

// Mod namespace qualified imports and class definition are #included from locally overriden file
#include "ModIcon.lcl.as"
	/// Initialization
	public static function Create(mod:Mod, initObj:Object):MovieClip {
		// Check dependencies
		if (!mod.Config) {
			DebugUtils.ErrorMsgS("Subsystem dependency missing: Config", {sysName:"ModIcon"});
			return undefined;
		}

		if (!initObj) { initObj = new Object(); }

		// Check for overloaded Icon resource name
		var iconName:String = initObj.ResName ? initObj.ResName : mod.ModName + "Icon";
		delete initObj.ResName;

		// Add Mod to init object, as unable to pass parameters to constructor
		initObj.ModPtr = new WeakPtr(mod);

		return MovieClipHelper.attachMovieWithRegister(iconName, ModIcon, "ModIcon", mod.HostClip, mod.HostClip.getNextHighestDepth(), initObj);
	}

	private function ModIcon() {
		super();
		Debug = new DebugUtils("ModIcon");

		// Get local copies of commonly used ModObj members
		Config = ModPtr.Get().Config;

		// Get a unique ID for default layout calculations
		// Note: System is not without flaws, subsequently added mods may just rearrange the IDs and stomp anyway
		IconCountDV = DistributedValue.Create("emfNextIconID");
		GetID();

		filters = [ShadowFilter];

		Config.NewSetting("TopbarIntegration", true);
		// Will have a value before saving, temporary undefined used to coerce consistent behaviour on upgrade
		Config.SetValue("TopbarIntegration", undefined); // DEPRECATED(v1.0.0): Temporary upgrade support
		// These need to be set with *some* default, so that any saved value is loaded
		// Actual values/defaults will be sorted out after the load, depending on TopbarIntegration and VTIO states
		Config.NewSetting("IconPosition", new Point(-1, -1));
		Config.NewSetting("IconScale", 100);
		// Defer the hookup of the on-change events until after loading is complete, to avoid accidental topbar changes
		if (Config.IsLoaded) { ConfigLoaded(); }
		else { Config.SignalConfigLoaded.Connect(ConfigLoaded, this); }

		GlobalSignal.SignalSetGUIEditMode.Connect(ManageGEM, this);
		SignalGeometryChanged = new Signal();

		ResolutionDV = DistributedValue.Create("DisplayResolution");
		TopbarLayoutDV = DistributedValue.Create("TopMenuAlignment");
		ResolutionDV.SignalChanged.Connect(SetTopbarPositions, this);
		TopbarLayoutDV.SignalChanged.Connect(SetTopbarPositions, this);

		Debug.TraceMsg("Icon created");
	}

	private function VerifyIDCount(dv:DistributedValue):Void {
		// If ID already in use, push to next value
		if (dv.GetValue() == IconID) { dv.SetValue(IconID + 1); }
	}

	private function GetID():Void {
		if ( IconID != -1) { return; } // Icon already has ID value
		IconID = IconCountDV.GetValue();
		if (!IconID) { IconID = 0; } // Handle the very first ID of a session
		IconCountDV.SetValue(IconID + 1);
		IconCountDV.SignalChanged.Connect(VerifyIDCount, this);
	}

	// Free the ID when this icon no longer requires it (such as when unloaded)
	public function FreeID():Void {
		if ( IconID == -1) { return; } // IconID not assigned
		IconCountDV.SignalChanged.Disconnect(VerifyIDCount, this);
		// Next free ID is this one, unless there's already a lower one
		if (IconCountDV.GetValue() > IconID) { IconCountDV.SetValue(IconID); }
		IconID = -1;
	}

	// Apply settings for manual integration with the default topbar
	// Locks scale and Y coordinate
	public function ConfigureForDefault():Void {
		BringAboveTopbar(true);
		OnBaseTopbar = true;
		SetTopbarPositions();
		Config.DeleteSetting("IconScale");
	}

	private function SetTopbarPositions():Void {
		if (OnBaseTopbar) {
			var resolution:Point = ResolutionDV.GetValue();
			DefaultTopbarX = (resolution.x / 2 + 110 + IconID * 20);
			TopbarY = TopbarLayoutDV.GetValue() ? (resolution.y - 25) : 2;
			Config.ChangeDefault("IconPosition", DefaultTopbarX);
			_y = TopbarY;
			var iconScale:Number = 56.25; // HACK: Based on 32x32 initial and 18x18 target icon sizes
			_xscale = iconScale;
			_yscale = iconScale;
		}
	}

	// Toggles VTIO mode configuration
	// Note: Not an entirely inverse function, some state will be unconditionally restored outside of this
	//   Config settings
	//   Moving below topbar
	public function get VTIOMode():Boolean { return _VTIOMode; } // Can't do private properties... not that "private" really means much in flash anyway
	public function set VTIOMode(value:Boolean) {
		if (value != _VTIOMode) {
			_VTIOMode = value;
			if (value) {
				// Reset this icon in preperation for VTIO integration
				// VTIO mods handle own layout and effects
				FreeID();
				OnBaseTopbar = false;
				BringAboveTopbar(true);
				_x = 0; _y = 0;
				filters = [];
				// Settings are not used as long as topbar is in use, no need to save them
				Config.DeleteSetting("IconPosition");
				Config.DeleteSetting("IconScale");
				GlobalSignal.SignalSetGUIEditMode.Disconnect(ManageGEM, this);
			} else {
				// Restores the state
				var mod:Mod = ModPtr.Get();
				mod.Icon = mod.HostClip.ModIcon;
				GetID();
				filters = [ShadowFilter];
				// Note: Settings are not restored here,
				GlobalSignal.SignalSetGUIEditMode.Connect(ManageGEM, this);
				_visible = true; // If cloned, will have been made invisible
				Refresh();
			}
		}
	}

	// Copy addtional properties and functions to the VTIO topbar's copy of the icon
	// Note: ModFolder does not create a copy, so this is not used for that VTIO mod
	public function CopyToTopbar(copy:ModIcon):Void {
		// Topbar copies the clip, so all the basic movie clip stuff is moved over by itself
		//   - The current frame is reset to 0 though
		// Topbar handles all layout so GEM system is not needed
		// Topbar also copies most of the event handlers (in one way or another)
		//   - onReleaseOutsideAux (for non-left mouse releases off the icon) are not copied by either topbar
		//   - Viper's simply copies them
		//   - Meeehr gets tricky and delegates to the original's function with the copy's data
		//   - Meeehr also adds their own wrapper on top of the onRollover/onRolloff pair (but misses the ReleaseOutside side effect)
		//     - These two in particular could make further customizing icon behaviour after registration risky

		// Required variables
		copy.ModPtr = ModPtr;
		copy.Config = Config;
		copy.Tooltip = Tooltip;

		// Required functions (and function variables)
		copy.Debug = Debug;
		copy.Refresh = Refresh;
		copy.GetFrame = GetFrame;
		copy.GetTooltipData = GetTooltipData;
		copy.OpenTooltip = OpenTooltip;
		copy.CloseTooltip = CloseTooltip;
		copy.LeftMouseInfo = LeftMouseInfo;
		copy.RightMouseInfo = RightMouseInfo;
		copy.ExtraTooltipInfo = ExtraTooltipInfo;
		// Not copied by either Meeehr or Viper
		copy.onDragOut = onDragOut;
		copy.onDragOutAux = onDragOutAux;

		// Minimalist config changed, doesn't handle layout messages and has different behaviour on TopbarIntegration
		Config.SignalValueChanged.Connect(CloneConfigChanged, copy);
	}

	/// Config and state changes
	private function ConfigLoaded():Void {
		// Fires after Mod's version, timing relative to LoadComplete subject to debate
		Config.SignalValueChanged.Connect(ConfigChanged, this);

		// Set defaults to reflect UseTopbar status
		// VTIO may not yet be active, and can not be assumed
		if (Config.GetValue("TopbarIntegration", false)) {
			ConfigureForDefault();
		} else {
			Config.ChangeDefault("IconPosition", new Point(10, 80 + IconID * 40));
			UpdateScale();
		}

		// Update to reflect loaded values
		Refresh();
		if (!VTIOMode) {
			var pos = Config.GetValue("IconPosition");
			if (pos.equals(new Point(-1, -1))) {
				// No value was loaded (to replace invalid initial default)
				// Either this is a first load or VTIO has been (but may no longer be) active
				Config.ResetValue("IconPosition"); // Will update to default position via ConfigChanged callback
			} else {
				if (OnBaseTopbar) {
					_x = pos;
				} else {
					_x = pos.x;
					_y = pos.y;
				}
			}
		}
	}

	private function ConfigChanged(setting:String, newValue, oldValue):Void {
		switch (setting) {
			case "IconPosition": {
				if (OnBaseTopbar) { _x = newValue; }
				else {
					_x = newValue.x;
					_y = newValue.y;
				}
				break;
			}
			case "IconScale": {	UpdateScale(); break; }
			case "TopbarIntegration": {
				if (newValue) {
					// Mod will have already responded, so will already be registered with VTIO if possible
					if (!VTIOMode) {
						ConfigureForDefault();
						Config.ResetValue("IconPosition");
						if (GemManager != null) {
							GemManager.lockAxis(2);
							GemManager.removeEventListener("scrollWheel", this, "ChangeScale");
							SignalGeometryChanged.Emit();
						}
					} else {
						if (GemManager != null) { ManageGEM(false); }
					}
				} else {
					VTIOMode = false;
					OnBaseTopbar = false;
					BringAboveTopbar(false);
					if (oldValue != undefined) { // DEPRECATED(v1.0.0): Temporary upgrade support (use of undefined)
						Config.NewSetting("IconScale", 100);
						Config.NewSetting("IconPosition", new Point(10, 80 + IconID * 40));
					}
					if (GemManager != null) {
						GemManager.lockAxis(0);
						GemManager.addEventListener("scrollWheel", this, "ChangeScale");
						SignalGeometryChanged.Emit();
					}
				}
				break;
			}
		}
	}

	// Minimalist ConfigChanged for the cloned copy created by VTIO/Meeehr
	// This is mostly to split off TopbarIntegration behaviour
	private function CloneConfigChanged(setting:String, newValue, oldValue):Void {
		if (setting == "TopbarIntegration") { _visible = newValue; } // Can't actually remove the cloned icon safely, so just hide/reveal it for now
	}

	// Trigger a re-evaluation of the current icon frame and reloads the tooltip if open
	public function Refresh():Void {
		gotoAndStop(GetFrame.call(ModPtr.Get()));
		if (Tooltip) { OpenTooltip(); }
	}

	// Default icon frame selector, may be overriden via init object
	private function GetFrame():String { return this["Enabled"] ? "active" : "inactive"; }

	/// Layout and GEM handling
	private function BringAboveTopbar(above:Boolean):Void {
		if (above != IsAboveTopbar) {
			var mod:Mod = ModPtr.Get();
			if (above) { SFClipLoader.SetClipLayer(SFClipLoader.GetClipIndex(mod.HostClip), _global.Enums.ViewLayer.e_ViewLayerTop, 2); }
			else { SFClipLoader.SetClipLayer(SFClipLoader.GetClipIndex(mod.HostClip), _global.Enums.ViewLayer.e_ViewLayerMiddle, 10); }
			IsAboveTopbar = above;
		}
	}

	private function UpdateScale():Void {
		_xscale = Config.GetValue("IconScale");
		_yscale = Config.GetValue("IconScale");
	}

	private function ManageGEM(unlock:Boolean):Void {
		if (unlock && !GemManager) {
			var mod:Mod = ModPtr.Get();
			GemManager = GemController.create("GuiEditModeInterface", mod.HostClip, mod.HostClip.getNextHighestDepth(), this);
			GemManager.lockAxis(0);
			if (OnBaseTopbar) { GemManager.lockAxis(2); }
			else { GemManager.addEventListener( "scrollWheel", this, "ChangeScale" ); }
			GemManager.addEventListener( "endDrag", this, "ChangePosition" );
		}
		if (!unlock) {
			GemManager.removeMovieClip();
			GemManager = null;
		}
	}

	private function ChangePosition(event:Object):Void {
		Config.SetValue("IconPosition", OnBaseTopbar ? _x : new Point(_x, _y));
		SignalGeometryChanged.Emit();
	}

	private function ChangeScale(event:Object): Void {
		var newScale:Number = Config.GetValue("IconScale") + event.delta * 5;
		newScale = Math.min(200, Math.max(30, newScale));
		Config.SetValue("IconScale", newScale);
		SignalGeometryChanged.Emit();
	}

	/// Input event handlers
	private function onMousePress(buttonID:Number):Void {
		switch(buttonID) {
			case 1: { LeftMouseInfo.Action.call(ModPtr.Get()); break; }
			case 2: { RightMouseInfo.Action.call(ModPtr.Get()); break; }
			default: { Debug.TraceMsg("Unexpected mouse button press: " + buttonID); }
		}
	}

	private function onRollOver():Void { OpenTooltip(); }
	private function onRollOut():Void { CloseTooltip(); }
	private function onDragOut():Void { CloseTooltip(); }
	private function onDragOutAux():Void { CloseTooltip(); }

	// Tuples of an Action to call on mouse click, and a Tooltip returning a descriptive string
	// The Mod class will assign defaults based on the type of the mod, but they can be overriden if desired
	private var LeftMouseInfo:Object;
	private var RightMouseInfo:Object;
	private var ExtraTooltipInfo:Function; // Slot to insert any additional tooltip stuff

	/// Tooltip
	// Tooltip data can be overriden entirely, but is easiset to do with customization of mouse actions and extra info
	private function GetTooltipData():TooltipData {
		var mod:Mod = ModPtr.Get();
		var data:TooltipData = new TooltipData();
		data.m_Padding = TooltipPadding;
		data.m_MaxWidth = TooltipWidth; // The content does not affect the layout, so unless something that does (edge of screen perhaps?) gets in the way, this is how wide it will be

		data.m_Title = "<font " + TooltipTitleFont + "><b>" + mod.ModName + "</b></font>";
		var credit:String = LocaleManager.FormatString("GUI", "TooltipCredit", Config.GetValue("Version"), Mod.DevName);
		data.m_SubTitle = "<font " + TooltipCreditFont + ">" + credit + "</font>";
		data.m_Color = TooltipTitleColor;

		// The internal newline reduces the spacing between lines compared to two seperate description strings
		// It's a bit tight like this, but the spacing was excessive the other way
		// The array.join makes it easy to skip the \n if there are less than two lines
		var tooltipStrings:Array = new Array();
		if (LeftMouseInfo) { tooltipStrings.push(LocaleManager.FormatString("GUI", "TooltipLeft", LeftMouseInfo.Tooltip.call(mod))); }
		if (RightMouseInfo) { tooltipStrings.push(LocaleManager.FormatString("GUI", "TooltipRight", RightMouseInfo.Tooltip.call(mod))); }
		var extra:String = ExtraTooltipInfo.call(mod);
		if (extra) { tooltipStrings.push(extra); }
		if (tooltipStrings.length > 0) { data.AddDescription("<font " + TooltipTextFont + ">" + tooltipStrings.join('\n') + "</font>"); }

		return data;
	}

	private function OpenTooltip():Void {
		var delay:Number = -1; // Negative, causes manager to use game setting to create delay
		if (Tooltip) { // Replacing existing, remove delay
			CloseTooltip();
			delay = 0;
		}
		Tooltip = TooltipManager.GetInstance().ShowTooltip(undefined, TooltipInterface.e_OrientationVertical, delay, GetTooltipData());
	}

	private function CloseTooltip():Void {
		Tooltip.Close();
		delete Tooltip;
	}

	/// Variables
	private static var ShadowFilter:DropShadowFilter =
		new DropShadowFilter(50, 1, 0, 0.8, 8, 8, 1, 3, false, false, false);

	private static var TooltipPadding = 4;
	private static var TooltipWidth = 150;
	private static var TooltipTitleFont:String = "size='13'";
	private static var TooltipTitleColor:Number = 0xFF8000;
	private static var TooltipCreditFont:String = "size='10'";
	private static var TooltipTextFont:String = "size='11'";

	private var ModPtr:WeakPtr;
	private var Config:Object; // Local copy of ModObj.Config; Ducktyped ConfigWrapper
	private var _VTIOMode:Boolean = false;

	private var Tooltip:TooltipInterface;

	// GUI layout variables do not need to be copied for topbar icon
	private var IsAboveTopbar:Boolean = false;
	private var OnBaseTopbar:Boolean = false;
	private var GemManager:GemController;
	private var SignalGeometryChanged:Signal;

	private var ResolutionDV:DistributedValue;
	private var TopbarLayoutDV:DistributedValue;
	private var DefaultTopbarX:Number;
	private var TopbarY:Number;

	// Used to adjust default icon locations so they no longer stack up awkwardly
	private var IconCountDV:DistributedValue;
	private var IconID:Number = -1;

	private var Debug:DebugUtils;
}
