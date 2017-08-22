// Copyright 2017, Earthfiredrake (Peloprata)
// Released under the terms of the MIT License
// https://github.com/Earthfiredrake/TSW-LoreHound

import gfx.controls.CheckBox;
import gfx.core.UIComponent;

import efd.LoreHound.lib.ConfigWrapper;
import efd.LoreHound.lib.LocaleManager;
import efd.LoreHound.LoreHound;
import efd.LoreHound.LoreData;

class efd.LoreHound.gui.LoreCategorySettingGroup extends UIComponent {
	private function LoreCategorySettingGroup() { super(); } // Indirect construction only

	private function configUI():Void {
		super.configUI();
		LocaleManager.ApplyLabel(LBWaypointsEnabled);
		LocaleManager.ApplyLabel(LBFifoEnabled);
		LocaleManager.ApplyLabel(LBChatEnabled);
		LocaleManager.ApplyLabel(LBLoreStatesTitle);
		LocaleManager.ApplyLabel(LBAlertUncollected);
		LocaleManager.ApplyLabel(LBAlertCollected);
		// Disable focus to prevent selections from locking user input until the window closes
		CBWaypointsEnabled.disableFocus = true;
		CBFifoEnabled.disableFocus = true;
		CBChatEnabled.disableFocus = true;
		CBAlertUncollected.disableFocus = true;
		CBAlertCollected.disableFocus = true;
	}

	public function Init(loreType:Number, config:ConfigWrapper):Void {
		Type = loreType;
		GroupTitle.text = "SettingGroup";
		switch(loreType) {
		case LoreData.ef_LoreType_Placed:
			GroupTitle.text += "Placed";
			break;
		case LoreData.ef_LoreType_Trigger:
			GroupTitle.text += "Trigger";
			break;
		case LoreData.ef_LoreType_Drop:
			GroupTitle.text += "Drop";
			break;
		case LoreData.ef_LoreType_Uncategorized:
			GroupTitle.text += "Uncategorized";
			break;
		}
		LocaleManager.ApplyLabel(GroupTitle);

		Config = config;
		ConfigUpdated();
		Config.SignalValueChanged.Connect(ConfigUpdated, this);

		CBWaypointsEnabled.addEventListener("select", this, "CBWaypoint_Select");
		CBFifoEnabled.addEventListener("select", this, "CBFifo_Select");
		CBChatEnabled.addEventListener("select", this, "CBChat_Select");
		CBAlertUncollected.addEventListener("select", this, "CBUncollected_Select");
		CBAlertCollected.addEventListener("select", this, "CBCollected_Select");
	}

	private function ConfigUpdated(setting:String, newValue, oldValue):Void {
		if (setting == "WaypointAlerts" || setting == undefined) {
			CBWaypointsEnabled.selected = (Config.GetValue("WaypointAlerts") & Type) == Type;
		}
		if (setting == "FifoAlerts" || setting == undefined) {
			CBFifoEnabled.selected = (Config.GetValue("FifoAlerts") & Type) == Type;
		}
		if (setting == "ChatAlerts" || setting == undefined) {
			CBChatEnabled.selected = (Config.GetValue("ChatAlerts") & Type) == Type;
		}
		if (setting == "AlertForUncollected" || setting == undefined) {
			CBAlertUncollected.selected = (Config.GetValue("AlertForUncollected") & Type) == Type;
		}
		if (setting == "AlertForCollected" || setting == undefined) {
			CBAlertCollected.selected = (Config.GetValue("AlertForCollected") & Type) == Type;
		}
	}

	private function SetConfigFlag(flag:String, value:Boolean) {
		Config.SetFlagValue(flag, Type, value);
	}

	private function CBWaypoint_Select(event:Object):Void {
		SetConfigFlag("WaypointAlerts", event.selected);
	}

	private function CBFifo_Select(event:Object):Void {
		SetConfigFlag("FifoAlerts", event.selected);
	}

	private function CBChat_Select(event:Object):Void {
		SetConfigFlag("ChatAlerts", event.selected);
	}

	private function CBUncollected_Select(event:Object):Void {
		SetConfigFlag("AlertForUncollected", event.selected);
	}

	private function CBCollected_Select(event:Object):Void {
		SetConfigFlag("AlertForCollected", event.selected);
	}

	private var GroupTitle:TextField;
	private var LBWaypointsEnabled:TextField;
	private var LBFifoEnabled:TextField;
	private var LBChatEnabled:TextField;
	private var LBLoreStatesTitle:TextField;
	private var LBAlertUncollected:TextField;
	private var LBAlertCollected:TextField;

	private var CBWaypointsEnabled:CheckBox;
	private var CBFifoEnabled:CheckBox;
	private var CBChatEnabled:CheckBox;
	private var CBAlertUncollected:CheckBox;
	private var CBAlertCollected:CheckBox;

	private var Config:ConfigWrapper;
	private var Type:Number;
}
