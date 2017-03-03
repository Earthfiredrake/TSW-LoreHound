// Copyright 2017, Earthfiredrake (Peloprata)
// Released under the terms of the MIT License
// https://github.com/Earthfiredrake/TSW-LoreHound

import com.GameInterface.Chat;
import com.GameInterface.Game.Dynel;
import com.GameInterface.Log;
import com.GameInterface.MathLib.Vector3;
import com.GameInterface.Utils;
import com.GameInterface.VicinitySystem;
import com.Utils.ID32;
import com.Utils.LDBFormat;

import com.LoreHound.lib.AutoReport;
import com.LoreHound.lib.ConfigWrapper;
import com.LoreHound.lib.Mod;

class com.LoreHound.LoreHound extends Mod {
	// Category flags for identifiable lore types
	private static var ef_LoreType_None:Number = 0;
	private static var ef_LoreType_Common:Number = 1 << 0; // Most lore with fixed locations
	private static var ef_LoreType_Triggered:Number = 1 << 1; // Lore with triggered spawn conditions (often after dungeon bosses)
	private static var ef_LoreType_Drop:Number = 1 << 2; // Lore which drops from monsters
	private static var ef_LoreType_Special:Number = 1 << 3; // Particularly unusual lore: The Shrouded Lore for the Mayan Days bird as an example
	private static var ef_LoreType_Unknown:Number = 1 << 4; // Newly detected lore, will need to be catalogued
	private static var ef_LoreType_All:Number = (1 << 5) - 1;

	// Category flags for extended information
	private static var ef_Details_None:Number = 0 ;
	private static var ef_Details_FormatString:Number = 1 << 0; // Trimmed contents of format string, to avoid automatic evaluation
	private static var ef_Details_Location:Number = 1 << 1; // Playfield ID and coordinate vector
	private static var ef_Details_StatDump:Number = 1 << 2; // Repeatedly calls Dynel.GetStat() (limited by the constant below), recording any stat which is not 0 or undefined.
	private static var ef_Details_All:Number = (1 << 3) - 1;

	// Number of stat IDs to test [0,N) when doing a StatDump (this can cause significant performance hitches, particularly with large ranges)
	// This number is high enough to catch all of the values discovered with a test of various static lores (of the first million statIDs)
	// Unfortunately none seem to be useful, would like to test further with drop lores
	private var c_Details_StatCount:Number;

	// Debugging settings
	private var m_DebugVerify:Boolean; // Don't immediately discard dynels which don't match the expected pattern, do further testing to try to protect against early discards

	private var m_AutoReport:AutoReport; // Automated error report system

	public function LoreHound() {
		super("LoreHound", "v0.1.1.alpha", "ReleaseTheLoreHound");
		m_AutoReport = new AutoReport(ModName, Version, DevName); // Initialized first so that its Config is available to be nested

		LoadConfig();
		UpdateInstall();

		// Ingame debug menu registers variables that are initialized here, but not those initialized at class scope
		// - Perhaps flash does static evaluation and decides to collapse constant variables?
		// - Regardless of the why, this will let me tweak these at runtime
		c_Details_StatCount = 1110;
		m_DebugVerify = true;

		RegisterWithTopbar();

		ChatMsg("Is on the prowl.");
	}

	private function InitializeConfig() : Void {
		// Notification types
		Config.NewSetting("FifoLevel", ef_LoreType_None);
		Config.NewSetting("ChatLevel", ef_LoreType_Drop | ef_LoreType_Special | ef_LoreType_Unknown);
		Config.NewSetting("LogLevel", ef_LoreType_Unknown);
		Config.NewSetting("MailLevel", ef_LoreType_Unknown); // This is a flag for testing purposes only, release states should be enabled (for unkown lore only) or disabled

		// Extended information, regardless of this setting:
		// - Is always ommitted from Fifo notifications, to minimize spam
		// - Is always included when detecting Unknown category lore (Location and ID only, to help with identification and categorization)
		Config.NewSetting("Details", ef_Details_Location);

		Config.NewSetting("AutoReport", m_AutoReport.GetConfigWrapper());

		// Hook to detect important setting changes
		Config.SignalValueChanged.Connect(ConfigChanged, this);
	}

	private function ConfigChanged(setting:String, newValue, oldValue) {
		switch(setting) {
			case "MailLevel":
				m_AutoReport.IsEnabled = (newValue != ef_LoreType_None);
				break;
			default:
			// Setting does not push changes (is checked on demand)
		}
	}

	public function DoUpdate() : Void {
		TraceMsg("Update was detected.");

		// Minimize settings clutter by purging auto-report records of newly categorized IDs
		var autoRepConfig:ConfigWrapper = Config.GetValue("AutoReport");
		autoRepConfig.SetValue("ReportsSent", CleanReportArray(autoRepConfig.GetValue("ReportsSent"), function(id) { return id; }));
		autoRepConfig.SetValue("ReportQueue", CleanReportArray(autoRepConfig.GetValue("ReportQueue"), function(report) { return report.id; }));

		ChatMsg("Has been updated to " + Config.GetDefault("Version"));
	}

	private function CleanReportArray(array:Array, extractor:Function) : Array {
		var cleanedArray = new Array();
		for (var i:Number = 0; i < array.length; i++) {
			if (ClassifyID(Number(extractor(array[i]))) == ef_LoreType_Unknown) {
				cleanedArray.push(array[i]);
			}
		}
		TraceMsg("Cleanup removed " + (array.length - cleanedArray.length) + " records, " + cleanedArray.length + " records remain.");
		return cleanedArray;
	}

	public function Activate() {				
		VicinitySystem.SignalDynelEnterVicinity.Connect(LoreSniffer, this); // Lore detection hook
		m_AutoReport.IsEnabled = (Config.GetValue("MailLevel") != ef_LoreType_None);
		super.Activate();
	}
	
	public function Deactivate() {
		VicinitySystem.SignalDynelEnterVicinity.Disconnect(LoreSniffer, this); // Lore detection hook
		m_AutoReport.IsEnabled = false;
		super.Deactivate();
	}

	// Notes on Dynel API:
	//   GetName() - Actually a remoteformat xml tag, for the LDB localization system
	//   GetID() - The ID type seems to be constant for all lore, and is shared with a wide variety of other props
	//     Instance ids of fixed lore may vary slightly between sessions, seemingly depending on load orders or caching of map info.
	//     Dropped lore seems to use whatever id happens to be available at the time, and demonstrates no consistency between drops.
	//     While unsuited as a unique identifier, instance ids do help differentiate unique hits in a high density area, as they are unique and remain constant for the lifetime of the object.
	//   GetPlayfieldID() - Unsure how to convert this to a playfield name through API; No way to generate Playfield data objects? Currently using lookup table on forum.
	//   GetPosition() - World coordinates (Y is vertical)
	//   GetDistanceToPlayer() - Proximity system triggers at ~20m when approaching a dynel, as well as detecting new dynels within that radius
	//     Lore detected at shorter ranges is almost always spawned in some way. Once spawned, the only way to track its existence is to bounce back and forth across the boundary
	//   IsRendered() - Seems to consider occlusion and clipping but not consistent on lore already claimed
	//   GetStat() - Unknown if any of these are useful, the mode parameter does not seem to change the value/lack of one, a scan of the first million stats and five modes provided:
	//     #12 - Unknown, consistently 7456524 across current data sample
	//     #23 and #112 - Copies of the format string ID #, matching values used in ClassifyID
	//     #1050 - Unknown, usually 6, though other numbers have been observed
	//     #1102 - Copy of the Dynel instance identifier (dynelId.m_Instance)
	//     While the function definition suggests a relationship with the global Stat enum
	//       the only matching value is 1050, mapping to "CarsGroup", whatever that is
	//     Testing on alts of unclaimed lore did not demonstrate any notable differences in the reported stats
	//   Unfortunately, there does not seem to be any accessible connection between the Dynel data, and the unlocked Lore entries,
	//     being able to reliably identify particular lore drops would require some hacky detective work.
	//     For lore with fixed locations: Lookup table of coordinates -> lore descriptions?
	//     For drop lore: Tracking monsters in the vicinity and compare when they die to the lore's arrival? (Not even close to ideal)

	// Callback on dynel detection
	private function LoreSniffer(dynelId:ID32):Void {
		// All known lore shares this dynel type with a wide variety of other props
		if (dynelId.m_Type != 51320 && !m_DebugVerify) { return; }

		var dynel:Dynel = Dynel.GetDynel(dynelId);
		var dynelName:String = dynel.GetName();

		// Extract the format string ID number from the xml tag
		var formatStrId:String = dynelName.substring(dynelName.indexOf('id="') + 4);
		formatStrId = formatStrId.substring(0, formatStrId.indexOf('"'));
		var loreId:Number = Number(formatStrId);

		// Categorize the detected item
		var loreType:Number = ClassifyID(loreId);
		if (loreType == ef_LoreType_Unknown || dynelId.m_Type != 51320) {
			loreType = CheckLocalizedName(dynelName) ? ef_LoreType_Unknown : ef_LoreType_None;
		}

		if (loreType != ef_LoreType_None) {
			SendLoreNotifications(loreType, loreId, dynel);
		}
	}

	private static function ClassifyID(formatStrId:Number):Number {
		// Here be the magic numbers (probably planted by the Dragon)
		switch (formatStrId) {
			case 7128026: // Shared by all known fixed location lore
				return ef_LoreType_Common;
			case 7648084: // Pol (Hidden zombie, after #1)
							// Pol (Drone spawn) is ??
			case 7661215: // DW6 (Post boss lore spawn)
			case 7648451: // Ankh (Orochi adds, after #1)
			case 7648450: // Ankh (Mummy adds, after #3)
			case 7648449: // Ankh (Pit dwellers)
			case 7647988: // HF6 (Post boss lore spawn)
			case 7647983: // Fac6 (Post boss lore spawn)
			case 7647985: // Fac5 (Post boss lore spawn)
			case 7647986: // Fac3 (Post boss lore spawn)
			case 7573298: // HE6 (Post boss lore spawn)
				return ef_LoreType_Triggered;
			case 9240080:  // Shared by all known monster drop bestiary lore
				return ef_LoreType_Drop;
			case 7993128: // Shrouded Lore (End of Days)
			case 9135398: // Two one-off lores found in MFB
			case 9135406:
				return ef_LoreType_Special;
			default:
				return ef_LoreType_Unknown;
		}
	}

	private static function CheckLocalizedName(formatStr:String):Boolean {
		// Have the localization system provide a language dependent string to compare with
		// In English this ends up being "Lore", hopefully it is similarly generic and likely to match in other languages
		var testStr:String = LDBFormat.LDBGetText(50200, 7128026); // (Format string identifiers for commonly placed lore)

		return LDBFormat.Translate(formatStr).indexOf(testStr) != -1;
	}

	private function SendLoreNotifications(loreType:Number, loreID:Number, dynel:Dynel) {
		var dynelID:ID32 = dynel.GetID();
		var formatStr:String = dynel.GetName();

		var messageStrings:Array = GetMessageStrings(loreType, formatStr, dynelID);
		var detailStrings:Array = GetDetailStrings(loreType, dynel);

		DispatchMessages(loreType, loreID, messageStrings, detailStrings);
	}

	// Index:
	// 0: Fifo message
	// 1: System chat message
	// 2: Log message
	// 3: Mail report
	private static function GetMessageStrings(loreType:Number, formatStr:String, dynelID:ID32):Array {
		var messageStrings:Array = new Array();
		switch (loreType) {
			case ef_LoreType_Common:
				messageStrings.push("Lore nearby.");
				messageStrings.push("Common lore nearby (" + formatStr + " [" + dynelID.m_Instance + "])");
				messageStrings.push("Common lore (" + formatStr + " [" + dynelID + "])");
				break;
			case ef_LoreType_Triggered:
				messageStrings.push("A lore has appeared.");
				messageStrings.push("Triggered lore nearby (" + formatStr + " [" + dynelID.m_Instance + "])");
				messageStrings.push("Triggered lore (" + formatStr + " [" + dynelID + "])");
				break;
			case ef_LoreType_Drop:
				messageStrings.push("A lore dropped!");
				messageStrings.push("Dropped lore nearby (" + formatStr + " [" + dynelID.m_Instance + "])");
				messageStrings.push("Dropped lore (" + formatStr + " [" + dynelID + "])");
				break;
			case ef_LoreType_Special:
				messageStrings.push("Unusual lore nearby.");
				messageStrings.push("Unusual lore nearby (" + formatStr + " [" + dynelID.m_Instance + "])");
				messageStrings.push("Unusual lore (" + formatStr + " [" + dynelID + "])");
				break;
			case ef_LoreType_Unknown:
				messageStrings.push("Unknown lore detected.");
				messageStrings.push("Unknown lore detected (" + formatStr + " [" + dynelID + "])");
				messageStrings.push("Unknown lore (" + formatStr + " [" + dynelID + "])");
				break;
			default:
				messageStrings.push("Error, lore type defaulted: " + loreType);
				messageStrings.push("Error, lore type defaulted: " + loreType);
				messageStrings.push("Error, lore type defaulted: " + loreType);
				break;
		}
		messageStrings.push("Category: " + loreType + " (" + LDBFormat.Translate(formatStr) + " [" + dynelID.m_Instance + "])");
		return messageStrings;
	}

	// This info is ommitted from FIFO messages
	// Unknown lore always requests format string and location for identification purposes
	private function GetDetailStrings(loreType:Number, dynel:Dynel):Array {
		var details:Number = Config.GetValue("Details");
		var detailStrings:Array = new Array();
		var formatStr:String = dynel.GetName();

		if (loreType == ef_LoreType_Unknown || (details & ef_Details_FormatString) == ef_Details_FormatString) {
			detailStrings.push("Identity details: " + formatStr.substring(14, formatStr.indexOf('>') - 1 )); // Strips the format string so that it doesn't preprocess
		}
		if (loreType == ef_LoreType_Unknown || (details & ef_Details_Location) == ef_Details_Location) {
			// Not entirely clear on what the "attractor" parameter is for, leaving it at 0 causes results to match world coordinates reported through other means (shift F9, topbars)
			// Y is being listed last because it's the vertical component, and most concern themselves with map coordinates (x,z)
			var pos:Vector3 = dynel.GetPosition(0);
			detailStrings.push("Playfield: " + dynel.GetPlayfieldID() + " Coordinates: [" + Math.round(pos.x) + ", " + Math.round(pos.z) + ", " + Math.round(pos.y) + "]");
		}
		if ((details & ef_Details_StatDump) == ef_Details_StatDump) {
			detailStrings.push("Stat Dump:"); // Fishing expedition, trying to find anything potentially useful
			for (var statID:Number = 0; statID < c_Details_StatCount; ++statID) {
				var val = dynel.GetStat(statID, 0);
				if (val != undefined && val != 0) {
					detailStrings.push("Stat: #" + statID + " Value: " + val);
				}
			}
		}

		return detailStrings;
	}

	private function DispatchMessages(loreType:Number, loreID:Number, messageStrings:Array, detailStrings:Array) : Void {
		if ((Config.GetValue("FifoLevel") & loreType) == loreType) {
			Chat.SignalShowFIFOMessage.Emit(messageStrings[0], 0);
			}
		if ((Config.GetValue("ChatLevel") & loreType) == loreType) {
			ChatMsg(messageStrings[1]);
			for (var i:Number = 0; i < detailStrings.length; ++i) {
				// Direct access to avoid repeating header blob
				Utils.PrintChatText(detailStrings[i]);
			}
		}
		if ((Config.GetValue("LogLevel") & loreType) == loreType) {
			LogMsg(messageStrings[2]);
			for (var i:Number = 0; i < detailStrings.length; ++i) {
				LogMsg(detailStrings[i]);
			}
		}
		if ((Config.GetValue("MailLevel") & loreType) == loreType) {
			var report:String = messageStrings[3];
			if (detailStrings.length > 0) {
				report += "\n" + detailStrings.join("\n");
			}
			m_AutoReport.AddReport({ id: loreID, text: report });
		}
	}

}
