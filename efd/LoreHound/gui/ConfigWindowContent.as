﻿// Copyright 2017, Earthfiredrake (Peloprata)
// Released under the terms of the MIT License
// https://github.com/Earthfiredrake/TSW-LoreHound

import com.Components.WindowComponentContent;
import gfx.controls.CheckBox;

import efd.LoreHound.gui.LoreCategorySettingGroup;
import efd.LoreHound.lib.ConfigWrapper;
import efd.LoreHound.LoreHound;

class efd.LoreHound.gui.ConfigWindowContent extends WindowComponentContent {

	// Checkboxes
	private var m_CBModEnabled:CheckBox;
	private var m_CBIgnoreUnclaimedLore:CheckBox;
	private var m_CBIgnoreOffSeasonLore:CheckBox;
	private var m_CBErrorReports:CheckBox;

	private var m_CBDetailLocation:CheckBox;
	private var m_CBDetailCategory:CheckBox;
	private var m_CBDetailInstance:CheckBox;

	// Lore Groups
	private var m_CommonLoreGroup:LoreCategorySettingGroup;
	private var m_TriggeredLoreGroup:LoreCategorySettingGroup;
	private var m_DropLoreGroup:LoreCategorySettingGroup;
	private var m_SpecialLoreGroup:LoreCategorySettingGroup;
	private var m_UnknownLoreGroup:LoreCategorySettingGroup;

	// Configuration setting name "All" is reserved as a special event trigger
	private var m_Config:ConfigWrapper;

	public function ConfigWindowContent() {
		super();
	}

	private function configUI():Void {
		super.configUI();
		// Disable focus to prevent selections from locking user input until the window closes
		m_CBModEnabled.disableFocus = true;
		m_CBIgnoreUnclaimedLore.disableFocus = true;
		m_CBIgnoreOffSeasonLore.disableFocus = true;
		m_CBErrorReports.disableFocus = true;
		m_CBDetailLocation.disableFocus = true;
		m_CBDetailCategory.disableFocus = true;
		m_CBDetailInstance.disableFocus = true;
	}

	public function AttachConfig(config:ConfigWrapper) {
		m_Config = config;
		ConfigUpdated("All");
		m_Config.SignalValueChanged.Connect(ConfigUpdated, this);

		m_CBModEnabled.addEventListener("select", this, "CBModEnabled_Select");
		m_CBIgnoreUnclaimedLore.addEventListener("select", this, "CBIgnoreUnclaimedLore_Select");
		m_CBIgnoreOffSeasonLore.addEventListener("select", this, "CBIgnoreOffSeasonLore_Select");
		m_CBErrorReports.addEventListener("select", this, "CBErrorReports_Select");
		m_CBDetailLocation.addEventListener("select", this, "CBDetailLocation_Select");
		m_CBDetailCategory.addEventListener("select", this, "CBDetailCategory_Select");
		m_CBDetailInstance.addEventListener("select", this, "CBDetailInstance_Select");

		// Differentiate child content elements
		m_CommonLoreGroup.SetType(LoreHound.ef_LoreType_Common);
		m_TriggeredLoreGroup.SetType(LoreHound.ef_LoreType_Triggered);
		m_DropLoreGroup.SetType(LoreHound.ef_LoreType_Drop);
		m_SpecialLoreGroup.SetType(LoreHound.ef_LoreType_Special);
		m_UnknownLoreGroup.SetType(LoreHound.ef_LoreType_Unknown);

		m_CommonLoreGroup.AttachConfig(config);
		m_TriggeredLoreGroup.AttachConfig(config);
		m_DropLoreGroup.AttachConfig(config);
		m_SpecialLoreGroup.AttachConfig(config);
		m_UnknownLoreGroup.AttachConfig(config);
	}

	private function ConfigUpdated(setting:String, newValue, oldValue):Void {
		if (setting == "Enabled" || setting == "All") {
			m_CBModEnabled.selected = m_Config.GetValue("Enabled");
		}
		if (setting == "IgnoreUnclaimedLore" || setting == "All") {
			m_CBIgnoreUnclaimedLore.selected = m_Config.GetValue("IgnoreUnclaimedLore");
		}
		if (setting == "IgnoreOffSeasonLore" || setting == "All") {
			m_CBIgnoreOffSeasonLore.selected = m_Config.GetValue("IgnoreOffSeasonLore");
		}
		if (setting == "SendReports" || setting == "All") {
			m_CBErrorReports.selected = m_Config.GetValue("SendReports");
		}
		if (setting == "Details" || setting == "All") {
			var details = m_Config.GetValue("Details");
			m_CBDetailLocation.selected = (details & LoreHound.ef_Details_Location) == LoreHound.ef_Details_Location;
			m_CBDetailCategory.selected = (details & LoreHound.ef_Details_FormatString) == LoreHound.ef_Details_FormatString;
			m_CBDetailInstance.selected = (details & LoreHound.ef_Details_DynelId) == LoreHound.ef_Details_DynelId;
		}
	}

	/// Selection event handlers
	private function CBModEnabled_Select(event:Object):Void {
		m_Config.SetValue("Enabled", event.selected);
	}

	private function CBIgnoreUnclaimedLore_Select(event:Object):Void {
		m_Config.SetValue("IgnoreUnclaimedLore", event.selected);
	}

	private function CBIgnoreOffSeasonLore_Select(event:Object):Void {
		m_Config.SetValue("IgnoreOffSeasonLore", event.selected);
	}

	private function CBErrorReports_Select(event:Object):Void {
		m_Config.SetValue("SendReports", event.selected);
	}

	private function CBDetailLocation_Select(event:Object):Void {
		var details = m_Config.GetValue("Details");
		if (event.selected) {
			details |= LoreHound.ef_Details_Location;
		} else {
			details &= ~LoreHound.ef_Details_Location;
		}
		m_Config.SetValue("Details", details);
	}

	private function CBDetailCategory_Select(event:Object):Void {
		var details = m_Config.GetValue("Details");
		if (event.selected) {
			details |= LoreHound.ef_Details_FormatString;
		} else {
			details &= ~LoreHound.ef_Details_FormatString;
		}
		m_Config.SetValue("Details", details);
	}

	private function CBDetailInstance_Select(event:Object):Void {
		var details = m_Config.GetValue("Details");
		if (event.selected) {
			details |= LoreHound.ef_Details_DynelId;
		} else {
			details &= ~LoreHound.ef_Details_DynelId;
		}
		m_Config.SetValue("Details", details);
	}

}