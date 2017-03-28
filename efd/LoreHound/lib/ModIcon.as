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

import efd.LoreHound.lib.etu.GemController;

import efd.LoreHound.lib.ConfigWrapper;
import efd.LoreHound.lib.LocaleManager;
import efd.LoreHound.lib.Mod;

class efd.LoreHound.lib.ModIcon extends MovieClip {
	/// Initialization
	public function ModIcon() {
		super();
		_x = 10; _y = 80;
		filters = [new DropShadowFilter(50, 1, 0, 0.8, 8, 8, 1, 3, false, false, false)];

		Config.NewSetting("IconPosition", new Point(_x, _y));
		Config.NewSetting("IconScale", 100);
		Config.SignalValueChanged.Connect(ConfigChanged, this);

		ScreenResScaleDV = DistributedValue.Create("GUIResolutionScale");
		ScreenResScaleDV.SignalChanged.Connect(UpdateScale, this);
		GlobalSignal.SignalSetGUIEditMode.Connect(ManageGEM, this);

		UpdateScale();
		// UpdateState customization won't be completed anyway
		// If custom state could persist between sessions, the mod should confirm it on load
		DefaultUpdateState();

		if (LeftAction == undefined && ShowConfigDV != undefined) { LeftAction = ToggleConfigWindow; }
		if (RightAction == undefined) { RightAction = ToggleModEnabled; }

		TraceMsg("Icon created");
	}

	// Reset this object's values for topbar integration
	public function ConfigureForTopbar():Void {
		IsTopbarIcon = true;
		_x = 0; _y = 0;
		filters = [];
		GlobalSignal.SignalSetGUIEditMode.Disconnect(ManageGEM, this);
		ScreenResScaleDV.SignalChanged.Disconnect(UpdateScale, this);
		delete ScreenResScaleDV;
	}

	// Copy addtional properties and functions to the topbar's copy of the icon
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
		copy.ShowConfigDV = ShowConfigDV;
		copy.IsTopbarIcon = true;
		copy.Tooltip = Tooltip;

		// Required functions (and function variables)
		copy.TraceMsg = TraceMsg;
		copy.UpdateState = UpdateState;
		copy.GetTooltipData = GetTooltipData;
		copy.OpenTooltip = OpenTooltip;
		copy.CloseTooltip = CloseTooltip;
		copy.LeftAction = LeftAction;
		copy.RightAction = RightAction;
		copy.onReleaseOutsideAux = onReleaseOutsideAux; // Not copied by either Meeehr or Viper

		Config.SignalValueChanged.Connect(ConfigChanged, copy);

		copy.gotoAndStop(_currentframe); // Match the current icons
		return copy;
	}

	/// Config and state changes
	private function ConfigChanged(setting:String, newValue, oldValue):Void {
		if (setting == "Enabled") {
			UpdateState();
			if (Tooltip != undefined) {OpenTooltip(); }
		}
		if (!IsTopbarIcon) {
			switch (setting) {
				case "IconPosition":
					_x = newValue.x;
					_y = newValue.y;
					break;
				case "IconScale":
					UpdateScale();
					break;
				default: break;
			}
		}
	}

	public var UpdateState:Function = DefaultUpdateState;

	private function DefaultUpdateState():Void { gotoAndStop(Config.GetValue("Enabled") ? "active" : "inactive"); }

	/// Layout and GEM handling
	private function UpdateScale():Void {
		var guiScale:Number = ScreenResScaleDV.GetValue();
		if ( guiScale == undefined) { guiScale = 1; }
		_xscale = guiScale * Config.GetValue("IconScale");
		_yscale = guiScale * Config.GetValue("IconScale");
	}

	private function ManageGEM(unlocked:Boolean):Void {
		if (unlocked && !GemManager) {
			GemManager = GemController.create("GuiEditModeInterface", HostMovie, HostMovie.getNextHighestDepth(), this);
			GemManager.addEventListener( "scrollWheel", this, "ChangeScale" );
			GemManager.addEventListener( "endDrag", this, "ChangePosition" );
		}
		if (!unlocked) {
			GemManager.removeMovieClip();
			GemManager = null;
		}
	}

	private function ChangePosition(event:Object):Void { Config.SetValue("IconPosition", new Point(_x, _y)); }

	private function ChangeScale(event:Object): Void {
		var newScale:Number = Config.GetValue("IconScale") + event.delta * 5;
		newScale = Math.min(200, Math.max(30, newScale));
		Config.SetValue("IconScale", newScale);
		GemManager.invalidate(); // Otherwise GEM overlay doesn't update to reflect new size
	}

	/// Input event handlers
	private function onMousePress(buttonID:Number):Void {
		switch(buttonID) {
			case 1: // Left mouse button
				LeftAction();
				break;
			case 2: // Right mouse button
				RightAction();
				break;
			default:
				TraceMsg("Unexpected mouse button press: " + buttonID);
				break;
		}
	}

	// These actions can be specified (or disabled with null) as part of the clip loading
	// If left undefined, the following two functions will be used as defaults
	private var LeftAction:Function;
	private var RightAction:Function;

	 // Default left, unless ConfigDV is undefined
	private function ToggleConfigWindow():Void { ShowConfigDV.SetValue(!ShowConfigDV.GetValue()); }
	// Default right
	private function ToggleModEnabled():Void {	Config.SetValue("Enabled", !Config.GetValue("Enabled")); }

	private function onRollOver():Void { OpenTooltip(); }
	private function onRollOut():Void { CloseTooltip(); }
	private function onReleaseOutside():Void { CloseTooltip(); }
	private function onReleaseOutsideAux():Void { CloseTooltip(); }

	/// Tooltip
	// Tooltip data can be overriden, but localization support allows the default to be customized significantly
	public var GetTooltipData:Function = GetDefaultTooltipData;

	private function GetDefaultTooltipData():TooltipData {
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
		if (LeftAction) { tooltipStrings.push(LocaleManager.GetString("GUI", "TooltipLeft")); }
		if (RightAction) { tooltipStrings.push(LocaleManager.GetString("GUI", Config.GetValue("Enabled") ? "TooltipRightDisable" : "TooltipRightEnable")); }
		data.AddDescription("<font " + TooltipTextFont + ">" + tooltipStrings.join('\n') + "</font>");

		return data;
	}

	private function OpenTooltip():Void {
		var delay:Number = -1; // Negative, causes manager to use game setting to create delay
		if (Tooltip != undefined) { // Replacing existing, remove delay
			CloseTooltip();
			delay = 0;
		}
		Tooltip = TooltipManager.GetInstance().ShowTooltip(undefined, TooltipInterface.e_OrientationVertical, delay, GetTooltipData());
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
	private static var TooltipPadding = 4;
	private static var TooltipWidth = 150;
	private static var TooltipTitleFont:String = "size='13'";
	private static var TooltipTitleColor:Number = 0xFF8000;
	private static var TooltipCreditFont:String = "size='10'";
	private static var TooltipTextFont:String = "size='11'";

	private var ModName:String;
	private var DevName:String;

	private var Config:ConfigWrapper;
	private var ShowConfigDV:DistributedValue;
	private var IsTopbarIcon:Boolean = false;

	// GUI layout variables do not need to be copied for topbar icon
	private var HostMovie:MovieClip;
	private var GemManager:GemController;
	private var ScreenResScaleDV:DistributedValue;

	private var Tooltip:TooltipInterface;
}
