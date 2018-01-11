// Copyright 2017-2018, Earthfiredrake (Peloprata)
// Released under the terms of the MIT License
// https://github.com/Earthfiredrake/TSW-LoreHound

import flash.geom.ColorTransform;

import gfx.controls.CheckBox;
import gfx.controls.DropdownMenu;
import gfx.utils.Delegate;

import com.Components.WindowComponentContent;

import efd.LoreHound.gui.LoreCategorySettingGroup;
import efd.LoreHound.lib.ConfigWrapper;
import efd.LoreHound.lib.LocaleManager;
import efd.LoreHound.lib.Mod;
import efd.LoreHound.LoreHound;
import efd.LoreHound.LoreData;

class efd.LoreHound.gui.ConfigWindowContent extends WindowComponentContent {
	private function ConfigWindowContent() { super(); } // Indirect construction only

	private function configUI():Void {
		// Disable focus to prevent selections from locking user input until the window closes
		CBModEnabled.disableFocus = true;
		CBTopbar.disableFocus = true;
		CBIgnoreOffSeasonLore.disableFocus = true;
		CBTrackDespawns.disableFocus = true;
		CBErrorReports.disableFocus = true;
		CBExtraTests.disableFocus = true;
		CBDetailTimestamp.disableFocus = true;
		CBDetailLocation.disableFocus = true;
		CBDetailCategory.disableFocus = true;
		CBDetailInstance.disableFocus = true;
		CBLogDump.disableFocus = true;

		LocaleManager.ApplyLabel(LBInactive);
		LocaleManager.ApplyLabel(LBDespawn);
		LocaleManager.ApplyLabel(LBAutoReport);
		LocaleManager.ApplyLabel(LBDetailGroupTitle);
		LocaleManager.ApplyLabel(LBTimestamp);
		LocaleManager.ApplyLabel(LBLocation);
		LocaleManager.ApplyLabel(LBCategory);
		LocaleManager.ApplyLabel(LBInstance);
		LocaleManager.ApplyLabel(LBOtherGroupTitle);
		LocaleManager.ApplyLabel(LBEnable);
		LocaleManager.ApplyLabel(LBTopbar);
		LocaleManager.ApplyLabel(LBExtraTests);
		LocaleManager.ApplyLabel(LBLogDump);
		LocaleManager.ApplyLabel(LBWPColour);

		 // Triggers the "Loaded" event, which in turn attaches the config and hooks the change notifiers
		 // Setup (particularly of the dropdown) needs to be done before this, so post calling the parent
		super.configUI();
	}

	public function AttachConfig(config:ConfigWrapper):Void {
		Config = config;
		ConfigUpdated();
		AutoReportConfigUpdated();
		Config.SignalValueChanged.Connect(ConfigUpdated, this);
		Config.GetValue("AutoReport").SignalValueChanged.Connect(AutoReportConfigUpdated, this);

		CBModEnabled.addEventListener("select", this, "CBModEnabled_Select");
		CBTopbar.addEventListener("select", this, "CBTopbar_Select");
		CBIgnoreOffSeasonLore.addEventListener("select", this, "CBIgnoreOffSeasonLore_Select");
		CBTrackDespawns.addEventListener("select", this, "CBTrackDespawns_Select");
		CBErrorReports.addEventListener("select", this, "CBErrorReports_Select");
		CBExtraTests.addEventListener("select", this, "CBExtraTests_Select");
		CBDetailTimestamp.addEventListener("select", this, "CBDetailTimestamp_Select");
		CBDetailLocation.addEventListener("select", this, "CBDetailLocation_Select");
		CBDetailCategory.addEventListener("select", this, "CBDetailCategory_Select");
		CBDetailInstance.addEventListener("select", this, "CBDetailInstance_Select");
		CBLogDump.addEventListener("select", this, "CBLogDump_Select");

		TFWPColour.onChanged = Delegate.create(this, TFWPColour_Changed);

		// Differentiate child content elements
		PlacedLoreGroup.Init(LoreData.ef_LoreType_Placed, config);
		TriggerLoreGroup.Init(LoreData.ef_LoreType_Trigger, config);
		DropLoreGroup.Init(LoreData.ef_LoreType_Drop, config);
		UncategorizedLoreGroup.Init(LoreData.ef_LoreType_Uncategorized, config);
		SpecialItemGroup.Init(LoreData.ef_LoreType_SpecialItem, config);
	}

	// Can't generally rely on newValue/oldValue for initial population
	private function ConfigUpdated(setting:String, newValue, oldValue):Void {
		if (setting == "Enabled" || setting == undefined) {
			CBModEnabled.selected = Config.GetValue("Enabled");
		}
		if (setting == "TopbarIntegration" || setting == undefined) {
			CBTopbar.selected = Config.GetValue("TopbarIntegration");
		}
		if (setting == "IgnoreOffSeasonLore" || setting == undefined) {
			CBIgnoreOffSeasonLore.selected = Config.GetValue("IgnoreOffSeasonLore");
		}
		if (setting == "TrackDespawns" || setting == undefined) {
			CBTrackDespawns.selected = Config.GetValue("TrackDespawns");
		}
		if (setting == "ExtraTesting" || setting == undefined) {
			CBExtraTests.selected = Config.GetValue("ExtraTesting");
		}
		if (setting == "CartographerLogDump" || setting == undefined) {
			CBLogDump.selected = Config.GetValue("CartographerLogDump");
		}
		if (setting == "WaypointColour" || setting == undefined) {
			TFWPColour.text = Config.GetValue("WaypointColour").toString(16).toUpperCase();
			var colour = new ColorTransform();
			colour.rgb = Config.GetValue("WaypointColour");
			MCWPColourPatch.transform.colorTransform = colour;
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

	private function CBTopbar_Select(event:Object):Void {
		Config.SetValue("TopbarIntegration", event.selected);
	}

	private function CBIgnoreOffSeasonLore_Select(event:Object):Void {
		Config.SetValue("IgnoreOffSeasonLore", event.selected);
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

	private function CBLogDump_Select(event:Object):Void {
		Config.SetValue("CartographerLogDump", event.selected);
	}

	private function TFWPColour_Changed(field:TextField):Void {
		// TODO: This is a finicky way of dealing with the problem, results in frequent changes, no actual reset on invalid values
		var value:Number = parseInt(field.text, 16);
		if (value != NaN) {
			Config.SetValue("WaypointColour", value);
		} else {
			field.text = Config.GetValue("WaypointColour").toString(16);
		}
	}

	//Labels
	private var LBInactive:TextField;
	private var LBDespawn:TextField;
	private var LBAutoReport:TextField;

	private var LBDetailGroupTitle:TextField;
	private var LBTimestamp:TextField;
	private var LBLocation:TextField;
	private var LBCategory:TextField;
	private var LBInstance:TextField;

	private var LBOtherGroupTitle:TextField;
	private var LBEnable:TextField;
	private var LBTopbar:TextField;
	private var LBExtraTests:TextField;
	private var LBLogDump:TextField;
	private var LBWPColour:TextField;

	private var MCWPColourPatch:MovieClip;

	// Checkboxes
	private var CBModEnabled:CheckBox;
	private var CBTopbar:CheckBox;
	private var CBIgnoreOffSeasonLore:CheckBox;
	private var CBTrackDespawns:CheckBox;
	private var CBErrorReports:CheckBox;
	private var CBExtraTests:CheckBox;
	private var CBLogDump:CheckBox;

	private var CBDetailTimestamp:CheckBox;
	private var CBDetailLocation:CheckBox;
	private var CBDetailCategory:CheckBox;
	private var CBDetailInstance:CheckBox;

	// Text Field
	private var TFWPColour:TextField;

	// Lore Groups
	private var PlacedLoreGroup:LoreCategorySettingGroup;
	private var TriggerLoreGroup:LoreCategorySettingGroup;
	private var DropLoreGroup:LoreCategorySettingGroup;
	private var UncategorizedLoreGroup:LoreCategorySettingGroup;
	private var SpecialItemGroup:LoreCategorySettingGroup;

	private var Config:ConfigWrapper;
}
