// Copyright 2017, Earthfiredrake (Peloprata)
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
		_x = 10; _y = 80;
		filters = [new DropShadowFilter(50, 1, 0, 0.8, 8, 8, 1, 3, false, false, false)];

		Config.NewSetting("IconPosition", new Point(_x, _y));
		Config.NewSetting("IconScale", 100);
		Config.SignalValueChanged.Connect(ConfigChanged, this);

		ScreenResScaleDV = DistributedValue.Create("GUIResolutionScale");
		ScreenResScaleDV.SignalChanged.Connect(UpdateScale, this);
		GlobalSignal.SignalSetGUIEditMode.Connect(ManageGEM, this);
		SignalGeometryChanged = new Signal();

		UpdateScale();
		// UpdateState customization won't be completed anyway
		// If custom state could persist between sessions, the mod should confirm it on load
		UpdateState();

		TraceMsg("Icon created");
	}

	// Reset this icon in preperation for topbar integration
	// Topbar handles its own layout and effects so remove the defaults
	public function ConfigureForTopbar():Void {
		IsTopbarIcon = true;
		_x = 0; _y = 0;
		filters = [];
		// Settings are not used as long as topbar is in use, no need to save them
		Config.DeleteSetting("IconPosition");
		Config.DeleteSetting("IconScale");
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
		copy.IsTopbarIcon = true;
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

		Config.SignalValueChanged.Connect(ConfigChanged, copy);

		copy.gotoAndStop(_currentframe); // Match the current icons
		return copy;
	}

	/// Config and state changes
	private function ConfigChanged(setting:String, newValue, oldValue):Void {
		if (setting == "Enabled") { UpdateState(); }
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

	public function UpdateState():Void {
		gotoAndStop(Config.GetValue("Enabled") ? "active" : "inactive");
		RefreshTooltip();
	}

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
	private static var TooltipPadding = 4;
	private static var TooltipWidth = 150;
	private static var TooltipTitleFont:String = "size='13'";
	private static var TooltipTitleColor:Number = 0xFF8000;
	private static var TooltipCreditFont:String = "size='10'";
	private static var TooltipTextFont:String = "size='11'";

	private var ModName:String;
	private var DevName:String;

	private var Config:ConfigWrapper;
	private var IsTopbarIcon:Boolean = false;

	// GUI layout variables do not need to be copied for topbar icon
	private var HostMovie:MovieClip;
	private var GemManager:GemController;
	private var ScreenResScaleDV:DistributedValue;
	private var SignalGeometryChanged:Signal;

	private var Tooltip:TooltipInterface;
}
