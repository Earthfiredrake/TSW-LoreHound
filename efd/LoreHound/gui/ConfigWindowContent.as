// Copyright 2017, Earthfiredrake (Peloprata)
// Released under the terms of the MIT License
// https://github.com/Earthfiredrake/TSW-LoreHound

import gfx.controls.CheckBox;

import com.Components.WindowComponentContent;

import efd.LoreHound.gui.LoreCategorySettingGroup;
import efd.LoreHound.lib.ConfigWrapper;
import efd.LoreHound.lib.LocaleManager;
import efd.LoreHound.LoreHound;

class efd.LoreHound.gui.ConfigWindowContent extends WindowComponentContent {
	private function ConfigWindowContent() { super(); } // Indirect construction only

	private function configUI():Void {
		super.configUI();
		// Disable focus to prevent selections from locking user input until the window closes
		CBModEnabled.disableFocus = true;
		CBIgnoreUnclaimedLore.disableFocus = true;
		CBIgnoreOffSeasonLore.disableFocus = true;
		CBWaypoints.disableFocus = true;
		CBTrackDespawns.disableFocus = true;
		CBErrorReports.disableFocus = true;
		CBExtraTests.disableFocus = true;
		CBDetailTimestamp.disableFocus = true;
		CBDetailLocation.disableFocus = true;
		CBDetailCategory.disableFocus = true;
		CBDetailInstance.disableFocus = true;

		LocaleManager.ApplyLabel(LBDetailGroupTitle);
		LocaleManager.ApplyLabel(LBTimestamp);
		LocaleManager.ApplyLabel(LBLocation);
		LocaleManager.ApplyLabel(LBCategory);
		LocaleManager.ApplyLabel(LBInstance);
		LocaleManager.ApplyLabel(LBOtherGroupTitle);
		LocaleManager.ApplyLabel(LBEnable);
		LocaleManager.ApplyLabel(LBUnclaimed);
		LocaleManager.ApplyLabel(LBInactive);
		LocaleManager.ApplyLabel(LBWaypoints);
		LocaleManager.ApplyLabel(LBDespawn);
		LocaleManager.ApplyLabel(LBAutoReport);
		LocaleManager.ApplyLabel(LBExtraTests);
	}

	public function AttachConfig(config:ConfigWrapper):Void {
		Config = config;
		ConfigUpdated();
		AutoReportConfigUpdated();
		Config.SignalValueChanged.Connect(ConfigUpdated, this);
		Config.GetValue("AutoReport").SignalValueChanged.Connect(AutoReportConfigUpdated, this);

		CBModEnabled.addEventListener("select", this, "CBModEnabled_Select");
		CBIgnoreUnclaimedLore.addEventListener("select", this, "CBIgnoreUnclaimedLore_Select");
		CBIgnoreOffSeasonLore.addEventListener("select", this, "CBIgnoreOffSeasonLore_Select");
		CBWaypoints.addEventListener("select", this, "CBWaypoints_Select");
		CBTrackDespawns.addEventListener("select", this, "CBTrackDespawns_Select");
		CBErrorReports.addEventListener("select", this, "CBErrorReports_Select");
		CBExtraTests.addEventListener("select", this, "CBExtraTests_Select");
		CBDetailTimestamp.addEventListener("select", this, "CBDetailTimestamp_Select");
		CBDetailLocation.addEventListener("select", this, "CBDetailLocation_Select");
		CBDetailCategory.addEventListener("select", this, "CBDetailCategory_Select");
		CBDetailInstance.addEventListener("select", this, "CBDetailInstance_Select");

		// Differentiate child content elements
		PlacedLoreGroup.Init(LoreHound.ef_LoreType_Placed, config);
		TriggerLoreGroup.Init(LoreHound.ef_LoreType_Trigger, config);
		DropLoreGroup.Init(LoreHound.ef_LoreType_Drop, config);
		UnknownLoreGroup.Init(LoreHound.ef_LoreType_Unknown, config);
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
		if (setting == "ShowWaypoints" || setting == undefined) {
			CBWaypoints.selected = Config.GetValue("ShowWaypoints");
		}
		if (setting == "TrackDespawns" || setting == undefined) {
			CBTrackDespawns.selected = Config.GetValue("TrackDespawns");
		}
		if (setting == "ExtraTesting" || setting == undefined) {
			CBExtraTests.selected = Config.GetValue("ExtraTesting");
		}
		if (setting == "Details" || setting == undefined) {
			var details = Config.GetValue("Details");
			CBDetailTimestamp.selected = (details & LoreHound.ef_Details_Timestamp) == LoreHound.ef_Details_Timestamp;
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

	private function CBWaypoints_Select(event:Object):Void {
		Config.SetValue("ShowWaypoints", event.selected);
	}

	private function CBTrackDespawns_Select(event:Object):Void {
		Config.SetValue("TrackDespawns", event.selected);
	}

	private function CBErrorReports_Select(event:Object):Void {
		Config.GetValue("AutoReport").SetValue("Enabled", event.selected);
	}

	private function CBExtraTests_Select(event:Object):Void {
		Config.SetValue("ExtraTesting", event.selected);
	}

	private function CBDetailTimestamp_Select(event:Object):Void {
		Config.SetFlagValue("Details", LoreHound.ef_Details_Timestamp, event.selected);
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

	//Labels
	private var LBDetailGroupTitle:TextField;
	private var LBTimestamp:TextField;
	private var LBLocation:TextField;
	private var LBCategory:TextField;
	private var LBInstance:TextField;
	private var LBOtherGroupTitle:TextField;
	private var LBEnable:TextField;
	private var LBUnclaimed:TextField;
	private var LBInactive:TextField;
	private var LBWaypoints:TextField;
	private var LBDespawn:TextField;
	private var LBAutoReport:TextField;
	private var LBExtraTests:TextField;

	// Checkboxes
	private var CBModEnabled:CheckBox;
	private var CBIgnoreUnclaimedLore:CheckBox;
	private var CBIgnoreOffSeasonLore:CheckBox;
	private var CBWaypoints:CheckBox;
	private var CBTrackDespawns:CheckBox;
	private var CBErrorReports:CheckBox;
	private var CBExtraTests:CheckBox;

	private var CBDetailTimestamp:CheckBox;
	private var CBDetailLocation:CheckBox;
	private var CBDetailCategory:CheckBox;
	private var CBDetailInstance:CheckBox;

	// Lore Groups
	private var PlacedLoreGroup:LoreCategorySettingGroup;
	private var TriggerLoreGroup:LoreCategorySettingGroup;
	private var DropLoreGroup:LoreCategorySettingGroup;
	private var UnknownLoreGroup:LoreCategorySettingGroup;

	private var Config:ConfigWrapper;
}
