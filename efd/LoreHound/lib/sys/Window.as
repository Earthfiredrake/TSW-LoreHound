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

		var localeTitle:String = LocaleManager.FormatString("GUI", WindowName + "Title", ModObj.ModName);
		clip.SetTitle(localeTitle, "left");
		clip.SetPadding(10);
		clip.SetContent(ModObj.ModName + WindowName + "Content");
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
