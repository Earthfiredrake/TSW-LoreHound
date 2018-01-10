﻿// Copyright 2017, Earthfiredrake (Peloprata)
// Released under the terms of the MIT License
// https://github.com/Earthfiredrake/TSW-LoreHound

import flash.filters.DropShadowFilter;
import flash.geom.Point;

import com.GameInterface.DistributedValue;
import com.GameInterface.Tooltip.TooltipData;
import com.GameInterface.Tooltip.TooltipInterface;
import com.GameInterface.Tooltip.TooltipManager;
import com.Utils.GlobalSignal;
import com.Utils.Signal;

import efd.LoreHound.lib.etu.GemController;

import efd.LoreHound.lib.ConfigWrapper;
import efd.LoreHound.lib.LocaleManager;
import efd.LoreHound.lib.Mod;

class efd.LoreHound.lib.ModIcon extends MovieClip {
	/// Initialization
	public function ModIcon() {
		super();
		filters = [ShadowFilter];

		// These need to be set with *some* default, so that any saved value is loaded
		// Actual values/defaults will be sorted out after the load, depending on UseTopbar and VTIO states
		Config.NewSetting("IconPosition", new Point(-1, -1));
		Config.NewSetting("IconScale", 100);
		// Defer the hookup of the on-change events until after loading is complete, to avoid accidental topbar changes
		if (Config.IsLoaded) {
			ConfigLoaded();
		} else {
			Config.SignalConfigLoaded.Connect(ConfigLoaded, this);
		}

		GlobalSignal.SignalSetGUIEditMode.Connect(ManageGEM, this);
		SignalGeometryChanged = new Signal();

		// UpdateState customization won't be completed anyway
		// If custom state could persist between sessions, the mod should confirm it on load
		// UpdateState();

		TraceMsg("Icon created");
	}

	// Reset this icon in preperation for topbar integration
	// Topbar handles its own layout and effects so remove the defaults
	public function ConfigureForVTIOTopbar():Void {
		if (!TopbarDoesLayout) {
			TopbarDoesLayout = true;
			_x = 0; _y = 0;
			filters = [];
			// Settings are not used as long as topbar is in use, no need to save them
			Config.DeleteSetting("IconPosition");
			Config.DeleteSetting("IconScale");
			GlobalSignal.SignalSetGUIEditMode.Disconnect(ManageGEM, this);
		}
	}

	// Copy addtional properties and functions to the VTIO topbar's copy of the icon
	// Note: ModFolder does not create a copy, so this is not used for that VTIO mod
	public function CopyToTopbar(copy:ModIcon):ModIcon {
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
		copy.ModName = ModName;
		copy.DevName = DevName;
		copy.Config = Config;
		copy.TopbarDoesLayout = true;
		copy.Tooltip = Tooltip;

		// Required functions (and function variables)
		copy.TraceMsg = TraceMsg;
		copy.UpdateState = UpdateState;
		copy.GetTooltipData = GetTooltipData;
		copy.OpenTooltip = OpenTooltip;
		copy.RefreshTooltip = RefreshTooltip;
		copy.CloseTooltip = CloseTooltip;
		copy.LeftMouseInfo = LeftMouseInfo;
		copy.RightMouseInfo = RightMouseInfo;
		copy.ExtraTooltipInfo = ExtraTooltipInfo;
		copy.onReleaseOutsideAux = onReleaseOutsideAux; // Not copied by either Meeehr or Viper

		// Minimalist config changed, doesn't handle layout messages and has different behaviour on TopbarIntegration
		Config.SignalValueChanged.Connect(CloneConfigChanged, copy);

		copy.gotoAndStop(_currentframe); // Match the current icons
		return copy;
	}

	/// Config and state changes
	private function ConfigLoaded():Void {
		// Fires after Mod's version but before LoadComplete
		Config.SignalValueChanged.Connect(ConfigChanged, this);

		// Set defaults to reflect UseTopbar status
		// VTIO will not yet be active, and can not be assumed
		if (Config.GetValue("UseTopbar") == Mod.ef_Topbar_Any) {
			Config.ChangeDefault("IconPosition", new Point(1125, TopbarYLock));
			Config.DeleteSetting("IconScale");
			var gameScale:Number = DistributedValue.GetDValue("GUIResolutionScale");
			var iconScale:Number = 56.25 / gameScale; // HACK: Based on 32x32 initial and 18x18 target icon sizes
			_xscale = iconScale;
			_yscale = iconScale;
			LockToTopbar = true;
		} else {
			Config.ChangeDefault("IconPosition", new Point(10, 80));
			UpdateScale();
		}

		// Update to reflect loaded values
		UpdateState();
		var pos:Point = Config.GetValue("IconPosition");
		if (pos.equals(new Point(-1, -1))) {
			// No value was loaded (to replace invalid initial default)
			// Either this is a first load or VTIO has been (but may no longer be) active
			Config.ResetValue("IconPosition"); // Will update position via ConfigChanged callback
		} else {
			_x = pos.x;
			_y = pos.y;
		}
	}

	private function ConfigChanged(setting:String, newValue, oldValue):Void {
		switch (setting) {
			case "Enabled": { UpdateState(); return; }
			case "IconPosition": {
				_x = newValue.x;
				_y = newValue.y;
				return;
			}
			case "IconScale": {
				UpdateScale();
				return;
			}
			case "UseTopbar": {
				TraceMsg("UseTopbar changed");
				// Active VTIO states (just or continuing activation, or disabling existing activation)
				if (TopbarDoesLayout && (newValue & Mod.ef_Topbar_VTIO)) { 
					// VTIO is already active and new mode uses it, no changes required (handles VTIO<->Any changes when VTIO is active; may also handle any changes that activate VTIO)
					return;
				} 
				if (TopbarDoesLayout) { // VTIO is being disabled (newValue must be None)
					// Attempt to reset icon to default state
					// ModFolder is clingy, will need to somehow deregister the icon from it
					// (possibly can be handled at the Mod level?)
					// Other topbars have cloned icons, may need to be handled as well
					TopbarDoesLayout = false;
					filters = [ShadowFilter];
					Config.NewSetting("IconPosition", new Point(10, 80));
					Config.NewSetting("IconScale", 100);
					GlobalSignal.SignalSetGUIEditMode.Connect(ManageGEM, this);
					_visible = true; // If cloned, will have been made invisible by VTIO
					return;
				}
				// VTIO not present, relevant behaviours are between Any and None(VTIO)
				if (LockToTopbar) { // Default topbar lock being returned to free floating behaviour (oldValue == Any, VTIO not enabled, newValue will use behaviour of None)
					LockToTopbar = false;
					Config.NewSetting("IconScale", 100);
					Config.SetValue("IconPosition", new Point(10, 80));
					return;
				}
				if (newValue == Mod.ef_Topbar_Any) {
					LockToTopbar = true;
					var gameScale:Number = DistributedValue.GetDValue("GUIResolutionScale");
					var iconScale:Number = 56.25 / gameScale; // HACK: Based on 32x32 initial and 18x18 target icon sizes
					_xscale = iconScale;
					_yscale = iconScale;
					Config.DeleteSetting("IconScale");
					Config.SetValue("IconPosition", new Point(1125, TopbarYLock)); // HACK: Should put it just to the right of the compass, hopefully away from other things (probably resolution dependant though so may need to tweak this... can use Stage.width?)
				}
				// Remaining states are changes between VTIO (not installed) and None and have no effect
				return;
			}
		}
	}

	// Minimalist ConfigChanged for the cloned copy created by VTIO/Meeehr
	// This is mostly to split off UseTopbar behaviour
	private function CloneConfigChanged(setting:String, newValue, oldValue):Void {
		if (setting == "Enabled") { UpdateState(); }
		if (setting == "UseTopbar" && (newValue == Mod.ef_Topbar_None || oldValue == Mod.ef_Topbar_None)) {
			// With a VTIO icon existing, at some point it was registered. Since changes from VTIO<->Any don't affect VTIO behaviour, only changes to or from None could have any effect
			if (newValue == Mod.ef_Topbar_None) { // VTIO is being disabled (Change events aren't raised if newValue == oldValue)
				_visible = false; // TEMP: For now just hide the cloned icon until I have a better plan
			} else { // By elimination VTIO is being enabled
				_visible = true;
			}
		}
	}

	public function UpdateState():Void {
		gotoAndStop(Config.GetValue("Enabled") ? "active" : "inactive");
		RefreshTooltip();
	}

	/// Layout and GEM handling
	private function UpdateScale():Void {
		_xscale = Config.GetValue("IconScale");
		_yscale = Config.GetValue("IconScale");
	}

	private function ManageGEM(unlocked:Boolean):Void {
		if (unlocked && !GemManager) {
			GemManager = GemController.create("GuiEditModeInterface", HostMovie, HostMovie.getNextHighestDepth(), this);
			if (!LockToTopbar) { GemManager.addEventListener( "scrollWheel", this, "ChangeScale" ); }
			GemManager.addEventListener( "endDrag", this, "ChangePosition" );
		}
		if (!unlocked) {
			GemManager.removeMovieClip();
			GemManager = null;
		}
	}

	private function ChangePosition(event:Object):Void {
		Config.SetValue("IconPosition", new Point(_x, LockToTopbar ? TopbarYLock : _y));
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
			case 1: // Left mouse button
				LeftMouseInfo.Action();
				break;
			case 2: // Right mouse button
				RightMouseInfo.Action();
				break;
			default:
				TraceMsg("Unexpected mouse button press: " + buttonID);
				break;
		}
	}

	private function onRollOver():Void { OpenTooltip(); }
	private function onRollOut():Void { CloseTooltip(); }
	private function onReleaseOutside():Void { CloseTooltip(); }
	private function onReleaseOutsideAux():Void { CloseTooltip(); }

	// Tuples of an Action to call on mouse click, and a Tooltip returning a descriptive string
	// The Mod class will assign defaults based on the type of the mod, but they can be overriden if desired
	private var LeftMouseInfo:Object;
	private var RightMouseInfo:Object;
	private var ExtraTooltipInfo:Function; // Slot to insert any additional tooltip stuff

	/// Tooltip
	// Tooltip data can be overriden entirely, but is easiset to do with customization of mouse actions and extra info
	private function GetTooltipData():TooltipData {
		var data:TooltipData = new TooltipData();
		data.m_Padding = TooltipPadding;
		data.m_MaxWidth = TooltipWidth; // The content does not affect the layout, so unless something that does (edge of screen perhaps?) gets in the way, this is how wide it will be

		data.m_Title = "<font " + TooltipTitleFont + "><b>" + ModName + "</b></font>";
		var credit:String = LocaleManager.FormatString("GUI", "TooltipCredit", Config.GetValue("Version"), DevName);
		data.m_SubTitle = "<font " + TooltipCreditFont + ">" + credit + "</font>";
		data.m_Color = TooltipTitleColor;

		// The internal newline reduces the spacing between lines compared to two seperate description strings
		// It's a bit tight like this, but the spacing was excessive the other way
		// The array.join makes it easy to skip the \n if there are less than two lines
		var tooltipStrings:Array = new Array();
		if (LeftMouseInfo) { tooltipStrings.push(LocaleManager.FormatString("GUI", "TooltipLeft", LeftMouseInfo.Tooltip())); }
		if (RightMouseInfo) { tooltipStrings.push(LocaleManager.FormatString("GUI", "TooltipRight", RightMouseInfo.Tooltip())); }
		var extra:String = ExtraTooltipInfo();
		if (extra) { tooltipStrings.push(extra); }
		data.AddDescription("<font " + TooltipTextFont + ">" + tooltipStrings.join('\n') + "</font>");

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

	public function RefreshTooltip():Void {
		if (Tooltip) { OpenTooltip(); }
	}

	private function CloseTooltip():Void {
		Tooltip.Close();
		delete Tooltip;
	}

	/// Trace Wrapper
	private function TraceMsg(msg:String, options:Object):Void {
		if (options == undefined) { options = new Object(); }
		options.system = "ModIcon";
		Mod.TraceMsg(msg, options);
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

	private static var TopbarYLock:Number = 2;

	private var ModName:String;
	private var DevName:String;

	private var Config:ConfigWrapper;
	private var TopbarDoesLayout:Boolean = false;

	private var Tooltip:TooltipInterface;

	// GUI layout variables do not need to be copied for topbar icon
	private var LockToTopbar:Boolean = false;
	private var HostMovie:MovieClip;
	private var GemManager:GemController;
	private var SignalGeometryChanged:Signal;
}
