// Copyright 2017, Earthfiredrake (Peloprata)
// Released under the terms of the MIT License
// https://github.com/Earthfiredrake/TSW-LoreHound

import gfx.controls.CheckBox;
import gfx.core.UIComponent;

import efd.LoreHound.lib.ConfigWrapper;
import efd.LoreHound.LoreHound;

class efd.LoreHound.gui.LoreCategorySettingGroup extends UIComponent {

	private var m_GroupTitle:TextField;
	private var m_CBFifoEnabled:CheckBox;
	private var m_CBChatEnabled:CheckBox;

	private var m_Type:Number;
	private var m_Config:ConfigWrapper;

	private function LoreCategorySettingGroup() {
		super();
	}

	private function configUI():Void {
		super.configUI();
		// Disable focus to prevent selections from locking user input until the window closes
		m_CBFifoEnabled.disableFocus = true;
		m_CBChatEnabled.disableFocus = true;
	}

	public function SetType(loreType:Number):Void {
		m_Type = loreType;
		switch(loreType) {
		case LoreHound.ef_LoreType_Common:
			m_GroupTitle.text = "Standard Lore";
			break;
		case LoreHound.ef_LoreType_Triggered:
			m_GroupTitle.text = "Triggered Lore";
			break;
		case LoreHound.ef_LoreType_Drop:
			m_GroupTitle.text = "Timed Drop Lore";
			break;
		case LoreHound.ef_LoreType_Special:
			m_GroupTitle.text = "Unusual Lore";
			break;
		case LoreHound.ef_LoreType_Unknown:
			m_GroupTitle.text = "Uncategorized Lore";
			break;
		}
	}

	public function AttachConfig(config:ConfigWrapper):Void {
		m_Config = config;
		ConfigUpdated("All");
		m_Config.SignalValueChanged.Connect(ConfigUpdated, this);

		m_CBFifoEnabled.addEventListener("select", this, "CBFifo_Select");
		m_CBChatEnabled.addEventListener("select", this, "CBChat_Select");
	}

	private function ConfigUpdated(setting:String, newValue, oldValue) {
		if (setting == "FifoLevel" || setting == "All") {
			m_CBFifoEnabled.selected = ((m_Config.GetValue("FifoLevel") & m_Type) == m_Type);
		}
		if (setting == "ChatLevel" || setting == "All") {
			m_CBChatEnabled.selected = ((m_Config.GetValue("ChatLevel") & m_Type) == m_Type);
		}
	}

	private function CBFifo_Select(event:Object):Void {
		var level = m_Config.GetValue("FifoLevel");
		if (event.selected) {
			level |= m_Type;
		} else {
			level &= ~m_Type;
		}
		m_Config.SetValue("FifoLevel", level);
	}

	private function CBChat_Select(event:Object):Void {
		var level = m_Config.GetValue("ChatLevel");
		if (event.selected) {
			level |= m_Type;
		} else {
			level &= ~m_Type;
		}
		m_Config.SetValue("ChatLevel", level);
	}
}
