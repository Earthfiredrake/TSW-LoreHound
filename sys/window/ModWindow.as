// Copyright 2018, Earthfiredrake
// Released under the terms of the MIT License
// https://github.com/Earthfiredrake/SWL-FrameworkMod

import gfx.utils.Delegate;

import com.Components.WinComp;
import com.GameInterface.DistributedValue;
import com.GameInterface.EscapeStack;
import com.GameInterface.EscapeStackNode;

// Mod namespace qualified imports and class definition are #included from locally overriden file
#include "ModWindow.lcl.as"
	private function ModWindow() { // Indirect construction
		super();

		m_ShowFooter = false;
		m_ShowResize = false;
		m_ShowStroke = false;

		EscNode = new EscapeStackNode();
		EscNode.SignalEscapePressed.Connect(TriggerWindowClose, this);
		EscapeStack.Push(EscNode);

		ResolutionScaleDV = DistributedValue.Create("GUIResolutionScale");
		ResolutionScaleDV.SignalChanged.Connect(SetResolutionScale, this);
		SetResolutionScale(ResolutionScaleDV);
	}

	private function configUI():Void {
		super.configUI();
		if (m_ShowResize) {
			// Adjust WinComp event handling
			m_ResizeButton.onPress = Delegate.create(this, SlotResizePress);
			m_ResizeButton.onMouseUp = Delegate.create(this, SlotResizeRelease);
			m_ResizeButton.onRelease = undefined;
			m_ResizeButton.onReleaseOutside = undefined;
			m_ResizeButton.disableFocus = true;
		}
	}

	public function PermitResize(limits:Object):Void {
		SetMinHeight(limits.Min.y);
		SetMinWidth(limits.Min.x);
		SetMaxHeight(limits.Max.y);
		SetMaxWidth(limits.Max.x);

		m_ShowResize = true;
	}

	private function SetResolutionScale(dv:DistributedValue):Void {
		var scale:Number = dv.GetValue() * 100;
		_xscale = scale;
		_yscale = scale;
	}

	public function TriggerWindowClose():Void {
		SignalClose.Emit(this);
		m_Content.Close();
	}

	private function SlotResizePress() { m_ResizeButton.onMouseMove = Delegate.create(this, MouseResizeMovingHandler); }

	private function SlotResizeRelease() { m_ResizeButton.onMouseMove = undefined; }

	private var EscNode:EscapeStackNode;
	private var ResolutionScaleDV:DistributedValue;
}
