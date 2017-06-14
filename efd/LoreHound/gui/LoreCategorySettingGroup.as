// Copyright 2017, Earthfiredrake (Peloprata)
// Released under the terms of the MIT License
// https://github.com/Earthfiredrake/TSW-LoreHound

import gfx.controls.CheckBox;
import gfx.core.UIComponent;

import efd.LoreHound.lib.ConfigWrapper;
import efd.LoreHound.lib.LocaleManager;
import efd.LoreHound.LoreHound;

class efd.LoreHound.gui.LoreCategorySettingGroup extends UIComponent {
	private function LoreCategorySettingGroup() { super(); } // Indirect construction only

	private function configUI():Void {
		super.configUI();
		LocaleManager.ApplyLabel(LBFifoEnabled);
		LocaleManager.ApplyLabel(LBChatEnabled);
		// Disable focus to prevent selections from locking user input until the window closes
		CBFifoEnabled.disableFocus = true;
		CBChatEnabled.disableFocus = true;
	}

	public function Init(loreType:Number, config:ConfigWrapper):Void {
		Type = loreType;
		GroupTitle.text = "SettingGroup";
		switch(loreType) {
		case LoreHound.ef_LoreType_Placed:
			GroupTitle.text += "Placed";
			break;
		case LoreHound.ef_LoreType_Trigger:
			GroupTitle.text += "Trigger";
			break;
		case LoreHound.ef_LoreType_Drop:
			GroupTitle.text += "Drop";
			break;
		case LoreHound.ef_LoreType_Uncategorized:
			GroupTitle.text += "Uncategorized";
			break;
		}
		LocaleManager.ApplyLabel(GroupTitle);

		Config = config;
		ConfigUpdated();
		Config.SignalValueChanged.Connect(ConfigUpdated, this);

		CBFifoEnabled.addEventListener("select", this, "CBFifo_Select");
		CBChatEnabled.addEventListener("select", this, "CBChat_Select");
	}

	private function ConfigUpdated(setting:String, newValue, oldValue):Void {
		if (setting == "FifoLevel" || setting == undefined) {
			CBFifoEnabled.selected = (Config.GetValue("FifoLevel") & Type) == Type;
		}
		if (setting == "ChatLevel" || setting == undefined) {
			CBChatEnabled.selected = (Config.GetValue("ChatLevel") & Type) == Type;
		}
	}

	private function CBFifo_Select(event:Object):Void {
		Config.SetFlagValue("FifoLevel", Type, event.selected);
	}

	private function CBChat_Select(event:Object):Void {
		Config.SetFlagValue("ChatLevel", Type, event.selected);
	}

	private var GroupTitle:TextField;
	private var LBFifoEnabled:TextField;
	private var LBChatEnabled:TextField;
	private var CBFifoEnabled:CheckBox;
	private var CBChatEnabled:CheckBox;

	private var Config:ConfigWrapper;
	private var Type:Number;
}
