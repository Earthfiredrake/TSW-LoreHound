// Copyright 2018, Earthfiredrake
// Released under the terms of the MIT License
// https://github.com/Earthfiredrake/TSW-LoreHound

import flash.geom.Point;

import com.GameInterface.DistributedValue;
import com.GameInterface.EscapeStack;
import com.GameInterface.EscapeStackNode;

import efd.LoreHound.lib.LocaleManager;
import efd.LoreHound.lib.Mod;

// Window subsystem implementation
// Dependencies:
//   Subsystems: Config, Localization
//   Library Symbols:
//     [ModName]Window: Movieclip linked to (tsw/swl) com.Components.WinComp, with window frame and other chrome
//     [ModName][WindowName]Content: Movieclip containing the panel to display within the window
// InitObj:
//   WindowName:String Used to generate unique identifiers for this window, including DVs and library resource IDs
//   LoadEvent:Delegate(WindowContent) Called once the content object has been loaded, usually used to provide data to the content object
// Handles window creation and display, may be included multiple times to provide additional windows if needed (once modular subsystems handle arbitrary additions)
//   Config system includes a ConfigWindow instance without having to be added seperately

class efd.LoreHound.lib.sys.Window {
	public static function Create(mod:Mod, initObj:Object):Window {
		// Check dependencies
		if (!mod.Config) {
			Mod.ErrorMsg("Subsystem dependency missing: Config", {system : "Window"});
			return undefined;
		}

		return new Window(mod, initObj);
	}

	private function Window(mod:Mod, initObj:Object) {
		ModObj = mod;
		WindowName = initObj.WindowName;
		LoadEvent = initObj.LoadEvent;

		mod.Config.NewSetting(WindowName + "Position", new Point(20, 30));

		ShowDV = DistributedValue.Create(Mod.DVPrefix + "Show" + mod.ModName + WindowName);
		ShowDV.SetValue(false);
		ShowDV.SignalChanged.Connect(ShowWindowChanged, this);
		EscNode = new EscapeStackNode();
		ResolutionScaleDV = DistributedValue.Create("GUIResolutionScale");
	}

	private function ShowWindowChanged(dv:DistributedValue):Void {
		if (dv.GetValue()) {
			if (ModObj.ModLoadedDV.GetValue() == false) {
				dv.SetValue(false);
				Mod.ErrorMsg("Did not load properly, and has been disabled.");
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

	public function ToggleWindow():Void {
		if (!ShowDV.GetValue()) { ShowDV.SetValue(true); }
		else { TriggerWindowClose.apply(WindowClip); }
	}

	public function OpenWindow():MovieClip {
		var clip:MovieClip = ModObj.HostMovie.attachMovie(ModObj.ModName + "Window", WindowName, ModObj.HostMovie.getNextHighestDepth());

		clip.SignalContentLoaded.Connect(TriggerLoadEvent, this); // Defer config bindings until content is loaded
		clip.SetContent(ModObj.ModName + WindowName + "Content");

		var localeTitle:String = LocaleManager.FormatString("GUI", WindowName + "Title", ModObj.ModName);
		clip.SetTitle(localeTitle, "left");
		clip.SetPadding(10);
		clip.ShowCloseButton(true);
		clip.ShowStroke(false);
		clip.ShowResizeButton(false); // TODO: Should be possible to set and use this
		clip.ShowFooter(false);

		var position:Point = ModObj.Config.GetValue(WindowName + "Position");
		clip._x = position.x;
		clip._y = position.y;
		SetWindowScale.call(clip, ResolutionScaleDV);
		ResolutionScaleDV.SignalChanged.Connect(SetWindowScale, clip);

		EscNode.SignalEscapePressed.Connect(TriggerWindowClose, clip);
		EscapeStack.Push(EscNode);
		clip.SignalClose.Connect(CloseWindow, this);

		return clip;
	}

	private function TriggerLoadEvent():Void { LoadEvent(WindowClip.m_Content); }

	private function CloseWindow():Void { ShowDV.SetValue(false); }

	private function WindowClosed():Void {
		ResolutionScaleDV.SignalChanged.Disconnect(SetWindowScale, WindowClip);
		EscNode.SignalEscapePressed.Disconnect(TriggerWindowClose, WindowClip);

		ReturnWindowToVisibleBounds(WindowClip, ModObj.Config.GetDefault(WindowName + "Position"));
		ModObj.Config.SetValue(WindowName + "Position", new Point(WindowClip._x, WindowClip._y));

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

	// Event handlers called in the context of the WindowClip
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

	private var ModObj:Mod;
	private var ResolutionScaleDV:DistributedValue;

	private var WindowName:String;
	private var LoadEvent:Function;
	private var ShowDV:DistributedValue; // Using a DV lets other mods (topbars) and chat commands toggle windows
	private var EscNode:EscapeStackNode;
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
