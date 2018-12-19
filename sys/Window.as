// Copyright 2018, Earthfiredrake
// Released under the terms of the MIT License
// https://github.com/Earthfiredrake/SWL-FrameworkMod

// Window subsystem implementation
// Dependencies:
//   Subsystems: Config, Localization
//   Library Symbols:
//     [ModName]Window:Movieclip Instance of ModWindow; handles window frame and other chrome
//       Easiest to just copy a window object out of an existing mod and tweak things on it for the new mod
//     [ModName][WindowName]Content:Movieclip Should inherit from com.Components.WindowComponentContent, but is largely custom for each window
// InitObj:
//   WindowName:String (required: no default, can't be "")
//     Used to generate unique identifiers for this window, including DVs and library resource IDs
//     Only needs to be unique within the mod, global identifiers will be further specified with ModName and DVPrefix as needed
//   LoadEvent:Delegate(WindowContent) (optional: not implementing may limit access to mod data)
//     Called once the content object has been loaded, usually used to pass data directly to that clip
//   ResizeLimits:Object {Min:Point, Max:Point} (optional: default disables resizing)
//     Enables the window resize handle and defines the size limits for the window;
//     If included, all values must be defined and sane (some of that will be checked)
//     When enabled will add a "[WindowName]Size" point element to the config settings (This will actually be the size of [WindowName]Content that would create the properly sized window)
//     Content object needs to implement an override of SetSize(width:Number, height:Number)
//       This function should adjust the content clip to fit the dimensions, and then raise SignalSizeChanged
//       TODO: Currently only the resize tab and opening the window (with the saved setting) can affect the window layout
//             If other sources want to adjust window size, will have to refactor to direct changes through Config.ValueChanged
//       TODO: Max size could be optional, most people wouldn't go to the effort of making hugely unwieldy windows
//             Might want to adjust the ReturnWindowToBounds function to catch those sorts of things though
// Handles window creation and display, may be included multiple times to provide additional windows if needed (once modular subsystems handle arbitrary additions)
//   Config system includes a ConfigWindow instance without having to be added separately (though content must be provided)

import flash.geom.Point;

import com.GameInterface.DistributedValue;
import com.Utils.WeakPtr;

// Mod namespace qualified imports and class definition are #included from locally overriden file
#include "Window.lcl.as"
	public static function Create(mod:Mod, initObj:Object):Window {
		// Check required parameters
		if (!initObj.WindowName) {
			DebugUtils.ErrorMsgS("Name is a required parameter and may not be an empty string", {sysName : "Window"});
			return undefined;
		}
		// Check dependencies
		if (!mod.Config) {
			DebugUtils.ErrorMsgS("Subsystem dependency missing: Config", {sysName : initObj.WindowName});
			return undefined;
		}

		return new Window(mod, initObj);
	}

	private function Window(mod:Mod, initObj:Object) {
		ModPtr = new WeakPtr(mod);
		WindowName = initObj.WindowName;
		LoadEvent = initObj.LoadEvent;

		mod.Config.NewSetting(WindowName + "Position", new Point(20, 30));
		if (CheckResizeLimits(initObj.ResizeLimits)) {
			ResizeLimits = initObj.ResizeLimits;
			mod.Config.NewSetting(WindowName + "Size", new Point(-1, -1));
		}

		ShowDV = DistributedValue.Create(Mod.DVPrefix + "Show" + mod.ModName + WindowName);
		ShowDV.SetValue(false);
		ShowDV.SignalChanged.Connect(ShowWindowChanged, this);
	}

	private function CheckResizeLimits(limits:Object):Boolean {
		if (!limits) { return false; }
		var min:Point = limits.Min;
		var max:Point = limits.Max;
		if (min.x == undefined || min.y == undefined || max.x == undefined || max.y == undefined) {
			DebugUtils.ErrorMsgS("Resize limits only partially defined, resize disabled", {sysName : WindowName});
			return false;
		}
		if (min.x > max.x || min.y > max.y) {
			DebugUtils.ErrorMsgS("Resize limits do not define a closed range, resize disabled", {sysName : WindowName});
			return false;
		}
		// Hopefully that covers the most likely mistakes, most devs should realize negative or particularly small/large values aren't wise either
		return true;
	}

	private function ShowWindowChanged(dv:DistributedValue):Void {
		// TODO: There's a problem with this being used directly to close a window, it skips a set of closure events that were added into the ModWindow interface
		if (dv.GetValue()) {
			if (!ModPtr.Get().ModLoadedDV.GetValue()) {
				dv.SetValue(false);
				DebugUtils.ErrorMsgS("Is disabled because it failed to load");
				return;
			}
			if (WindowClip == null) { WindowClip = OpenWindow(); }
		}
		else {
			if (WindowClip != null) {
				WindowClosed();
				WindowClip = null;
			}
		}
	}

	public function ToggleWindow():Boolean {
		if (!ShowDV.GetValue()) { ShowDV.SetValue(true); return true; }
		else { WindowClip.TriggerWindowClose(); return false; }
	}

	public function OpenWindow():MovieClip {
		var mod:Mod = ModPtr.Get();
		// Can't pass a useful cached initObj here, constructors stomp almost all the things I would set
		var clip:MovieClip = mod.HostClip.attachMovie(mod.ModName + "Window", WindowName, mod.HostClip.getNextHighestDepth());

		var localeTitle:String = LocaleManager.FormatString("GUI", WindowName + "Title", mod.ModName);
		clip.SetTitle(localeTitle, "left");

		var position:Point = mod.Config.GetValue(WindowName + "Position");
		clip._x = position.x;
		clip._y = position.y;

		if (ResizeLimits) {
			clip.SignalSizeChanged.Connect(UpdateSize, this);
			clip.PermitResize(ResizeLimits);
		}

		clip.SignalClose.Connect(CloseWindow, this);

		clip.SignalContentLoaded.Connect(TriggerLoadEvent, this); // Defer data binding until display is loaded
		clip.SetContent(mod.ModName + WindowName + "Content");

		return clip;
	}

	private function UpdateSize():Void { ModPtr.Get().Config.SetValue(WindowName + "Size", WindowClip.GetSize()); }

	private function TriggerLoadEvent():Void { LoadEvent(WindowClip.m_Content); }

	private function CloseWindow():Void { ShowDV.SetValue(false); }

	private function WindowClosed():Void {
		var mod = ModPtr.Get();
		ReturnWindowToVisibleBounds(WindowClip, mod.Config.GetDefault(WindowName + "Position"));
		mod.Config.SetValue(WindowName + "Position", new Point(WindowClip._x, WindowClip._y));

		WindowClip.removeMovieClip();
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

	private var ModPtr:WeakPtr;

	private var WindowName:String;
	private var LoadEvent:Function;
	private var ResizeLimits:Object;
	private var ShowDV:DistributedValue; // Using a DV lets other mods (topbars) and chat commands toggle windows
	private var WindowClip:MovieClip = null;
}

// Mouse Events
// There are far too many and each of the three levels of API tweaks them, but here's some notes
// Any object can get global event notifications by passing an object with a set of event handlers to Mouse.addListener():
//   Flash defines the following events for it (with the first set of parameters):
//     onMouseDown() (button:Number, targetPath:String, mouseIdx:Number, x:Number, y:Number, dblClick:Boolean)
//     onMouseMove() (mouseIdx:Number, x:Number, y:Number)
//     onMouseUp() (button:Number, targetPath:String, mouseIdx:Number, x:Number, y:Number)
///    onMouseWheel(delta:Number, scrollTarget:Object) (delta:Number, targetPath:String, mouseIdx:Number, x:Number, y:Number)
//   Scaleform uses different parameters (the second set of parameters)
//     x,y values will always be in the global coordinate frame
//     targetPath is the full display path name of the topmost clip under the mouse (likely with the restrictions described for some MovieClip handlers below)
//     button values are Mouse["LEFT"|"RIGHT"|"MIDDLE"] (can use . notation if linked to the CLIK library)
//     mouseIdx is only important if there are multiple mice/cursors, which there aren't
// MovieClips can have event handlers added directly to the clip:
//   Some behave as global events
//     May only apply to left clicks, further research needed
//     onMouseDown()
//     onMouseMove()
//     onMouseUp()
//   Some only fire if the clip is immediately under the mouse:
//     These ignore invisible clips and also drawn lines (though not filled areas)
//     They also only apply to LEFT mouse clicks
//     onPress()
//     onRelease() // Only if released over this clip
//     onReleaseOutside() // If was pressed over this clip, but released elsewhere
//     onRollOver()
//     onRollOut() // Will not trigger if any mouse button is pressed
//     onDragOver() // An already pressed mouse rolled over
//     onDragOut() // Pressed over this clip, then rolled out
//   It is unclear if Scaleform modifies the parameters of the first group,
//   Two parameters are added to each of the second group, value is questionable but, for reference:
//     All get a mouseIdx as the first parameter
//     Press/Release get a keyboard(-1) | mouse(0) event source flag
//     Roll/Drag get a nextingIdx, which only matters if there are multiple cursors
//   Scaleform adds events to handle the other mouse buttons (RIGHT or MIDDLE)
//     They use the extra parameters above, and a third parameter for the mouse button
//     onPressAux(), onReleaseAux(), onReleaseOutsideAux(), onDragOverAux(), onDragOutAux()
//   The TSW/SWL API adds (from GUIFramework.MouseHandling):
//     These will apply to the highest visible clip, with the function defined, under the mouse
//     onMousePress(buttonIdx:Number, clickCount:Number)
//       Triggered by any mouse button, counts sequential clicks within a timeout
//     onMouseRelease(buttonIdx:Number)
//       Appears to unify onRelease and onReleaseAux
//     onMouseWheel(delta:Number)
//       A local version of the global event
