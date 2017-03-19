// Copyright 2017, Earthfiredrake (Peloprata)
// Released under the terms of the MIT License
// https://github.com/Earthfiredrake/TSW-LoreHound

import gfx.controls.CheckBox;
import gfx.core.UIComponent;

import efd.LoreHound.lib.ConfigWrapper;
import efd.LoreHound.LoreHound;

class efd.LoreHound.gui.LoreCategorySettingGroup extends UIComponent {
	private function LoreCategorySettingGroup() {
		super();
	}

	private function configUI():Void {
		super.configUI();
		// Disable focus to prevent selections from locking user input until the window closes
		CBFifoEnabled.disableFocus = true;
		CBChatEnabled.disableFocus = true;
	}

	public function SetType(loreType:Number):Void {
		Type = loreType;
		switch(loreType) {
		case LoreHound.ef_LoreType_Common:
			GroupTitle.text = "Standard Lore";
			break;
		case LoreHound.ef_LoreType_Triggered:
			GroupTitle.text = "Triggered Lore";
			break;
		case LoreHound.ef_LoreType_Drop:
			GroupTitle.text = "Timed Drop Lore";
			break;
		case LoreHound.ef_LoreType_Special:
			GroupTitle.text = "Unusual Lore";
			break;
		case LoreHound.ef_LoreType_Unknown:
			GroupTitle.text = "Uncategorized Lore";
			break;
		}
	}

	public function AttachConfig(config:ConfigWrapper):Void {
		Config = config;
		ConfigUpdated();
		Config.SignalValueChanged.Connect(ConfigUpdated, this);

		CBFifoEnabled.addEventListener("select", this, "CBFifo_Select");
		CBChatEnabled.addEventListener("select", this, "CBChat_Select");
	}

	private function ConfigUpdated(setting:String, newValue, oldValue) {
		if (setting == "FifoLevel" || setting == undefined) {
			CBFifoEnabled.selected = ((Config.GetValue("FifoLevel") & Type) == Type);
		}
		if (setting == "ChatLevel" || setting == undefined) {
			CBChatEnabled.selected = ((Config.GetValue("ChatLevel") & Type) == Type);
		}
	}

	private function CBFifo_Select(event:Object):Void {
		Config.SetFlagValue("FifoLevel", Type, event.selected);
	}

	private function CBChat_Select(event:Object):Void {
		Config.SetFlagValue("ChatLevel", Type, event.selected);
	}

	private var GroupTitle:TextField;
	private var CBFifoEnabled:CheckBox;
	private var CBChatEnabled:CheckBox;

	private var Config:ConfigWrapper;
	private var Type:Number;
}
