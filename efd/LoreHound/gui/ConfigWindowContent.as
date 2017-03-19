// Copyright 2017, Earthfiredrake (Peloprata)
// Released under the terms of the MIT License
// https://github.com/Earthfiredrake/TSW-LoreHound

import com.Components.WindowComponentContent;
import gfx.controls.CheckBox;

import efd.LoreHound.gui.LoreCategorySettingGroup;
import efd.LoreHound.lib.ConfigWrapper;
import efd.LoreHound.LoreHound;

class efd.LoreHound.gui.ConfigWindowContent extends WindowComponentContent {
	public function ConfigWindowContent() {
		super();
	}

	private function configUI():Void {
		super.configUI();
		// Disable focus to prevent selections from locking user input until the window closes
		CBModEnabled.disableFocus = true;
		CBIgnoreUnclaimedLore.disableFocus = true;
		CBIgnoreOffSeasonLore.disableFocus = true;
		CBErrorReports.disableFocus = true;
		CBNewContent.disableFocus = true;
		CBDetailLocation.disableFocus = true;
		CBDetailCategory.disableFocus = true;
		CBDetailInstance.disableFocus = true;
	}

	public function AttachConfig(config:ConfigWrapper) {
		Config = config;
		ConfigUpdated();
		AutoReportConfigUpdated();
		Config.SignalValueChanged.Connect(ConfigUpdated, this);
		Config.GetValue("AutoReport").SignalValueChanged.Connect(AutoReportConfigUpdated, this);

		CBModEnabled.addEventListener("select", this, "CBModEnabled_Select");
		CBIgnoreUnclaimedLore.addEventListener("select", this, "CBIgnoreUnclaimedLore_Select");
		CBIgnoreOffSeasonLore.addEventListener("select", this, "CBIgnoreOffSeasonLore_Select");
		CBErrorReports.addEventListener("select", this, "CBErrorReports_Select");
		CBNewContent.addEventListener("select", this, "CBNewContent_Select");
		CBDetailLocation.addEventListener("select", this, "CBDetailLocation_Select");
		CBDetailCategory.addEventListener("select", this, "CBDetailCategory_Select");
		CBDetailInstance.addEventListener("select", this, "CBDetailInstance_Select");

		// Differentiate child content elements
		CommonLoreGroup.SetType(LoreHound.ef_LoreType_Common);
		TriggeredLoreGroup.SetType(LoreHound.ef_LoreType_Triggered);
		DropLoreGroup.SetType(LoreHound.ef_LoreType_Drop);
		SpecialLoreGroup.SetType(LoreHound.ef_LoreType_Special);
		UnknownLoreGroup.SetType(LoreHound.ef_LoreType_Unknown);

		CommonLoreGroup.AttachConfig(config);
		TriggeredLoreGroup.AttachConfig(config);
		DropLoreGroup.AttachConfig(config);
		SpecialLoreGroup.AttachConfig(config);
		UnknownLoreGroup.AttachConfig(config);
	}

	private function ConfigUpdated(setting:String, newValue, oldValue):Void {
		if (setting == "Enabled" || setting == undefined) {
			CBModEnabled.selected = Config.GetValue("Enabled");
		}
		if (setting == "IgnoreUnclaimedLore" || setting == undefined) {
			CBIgnoreUnclaimedLore.selected = Config.GetValue("IgnoreUnclaimedLore");
		}
		if (setting == "IgnoreOffSeasonLore" || setting == undefined) {
			CBIgnoreOffSeasonLore.selected = Config.GetValue("IgnoreOffSeasonLore");
		}
		if (setting == "CheckNewContent" || setting == undefined) {
			CBNewContent.selected = Config.GetValue("CheckNewContent");
		}
		if (setting == "Details" || setting == undefined) {
			var details = Config.GetValue("Details");
			CBDetailLocation.selected = (details & LoreHound.ef_Details_Location) == LoreHound.ef_Details_Location;
			CBDetailCategory.selected = (details & LoreHound.ef_Details_FormatString) == LoreHound.ef_Details_FormatString;
			CBDetailInstance.selected = (details & LoreHound.ef_Details_DynelId) == LoreHound.ef_Details_DynelId;
		}
	}

	private function AutoReportConfigUpdated(setting:String, newValue, oldValue):Void {
		if (setting == "Enabled" || setting == undefined) {
			CBErrorReports.selected = Config.GetValue("AutoReport").GetValue("Enabled");
		}
	}

	/// Selection event handlers
	private function CBModEnabled_Select(event:Object):Void {
		Config.SetValue("Enabled", event.selected);
	}

	private function CBIgnoreUnclaimedLore_Select(event:Object):Void {
		Config.SetValue("IgnoreUnclaimedLore", event.selected);
	}

	private function CBIgnoreOffSeasonLore_Select(event:Object):Void {
		Config.SetValue("IgnoreOffSeasonLore", event.selected);
	}

	private function CBErrorReports_Select(event:Object):Void {
		Config.GetValue("AutoReport").SetValue("Enabled", event.selected);
	}

	private function CBNewContent_Select(event:Object):Void {
		Config.SetValue("CheckNewContent", event.selected);
	}

	private function CBDetailLocation_Select(event:Object):Void {
		Config.SetFlagValue("Details", LoreHound.ef_Details_Location, event.selected);
	}

	private function CBDetailCategory_Select(event:Object):Void {
		Config.SetFlagValue("Details", LoreHound.ef_Details_FormatString, event.selected);
	}

	private function CBDetailInstance_Select(event:Object):Void {
		Config.SetFlagValue("Details", LoreHound.ef_Details_DynelId, event.selected);
	}

	// Checkboxes
	private var CBModEnabled:CheckBox;
	private var CBIgnoreUnclaimedLore:CheckBox;
	private var CBIgnoreOffSeasonLore:CheckBox;
	private var CBErrorReports:CheckBox;
	private var CBNewContent:CheckBox;

	private var CBDetailLocation:CheckBox;
	private var CBDetailCategory:CheckBox;
	private var CBDetailInstance:CheckBox;

	// Lore Groups
	private var CommonLoreGroup:LoreCategorySettingGroup;
	private var TriggeredLoreGroup:LoreCategorySettingGroup;
	private var DropLoreGroup:LoreCategorySettingGroup;
	private var SpecialLoreGroup:LoreCategorySettingGroup;
	private var UnknownLoreGroup:LoreCategorySettingGroup;

	private var Config:ConfigWrapper;
}
