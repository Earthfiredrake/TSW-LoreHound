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
import com.LoreHound.lib.Config;

class com.LoreHound.LoreHound {

	// Mod info
	private static var c_ModName:String = "LoreHound";
	private static var c_Version:String = "v0.1.1.alpha";
	private static var c_DevName:String = "Peloprata";
	
	private static var c_ModEnabledVar:String = "ReleaseTheLoreHound";
	private static var c_ConfigArchive:String = c_ModName + "Config";

	// Category flags for represented lore types
	private static var ef_LoreType_None:Number = 0;
	private static var ef_LoreType_Common:Number = 1 << 0; // Most lore with fixed locations
	private static var ef_LoreType_Triggered:Number = 1 << 1; // Lore with triggered spawn conditions (often after dungeon bosses)
	private static var ef_LoreType_Drop:Number = 1 << 2; // Lore which drops from monsters
	private static var ef_LoreType_Special:Number = 1 << 3; // Particularly unusual lore: The Shrouded Lore for the Mayan Days bird as an example
	private static var ef_LoreType_Unknown:Number = 1 << 4; // Newly detected lore, will need to be catalogued
	private static var ef_LoreType_All:Number = (1 << 5) - 1;

	// Category flags for extended debug information
	private static var ef_DebugDetails_None:Number = 0 ;
	private static var ef_DebugDetails_FormatString:Number = 1 << 0; // Trimmed contents of format string, to avoid automatic evaluation
	private static var ef_DebugDetails_Location:Number = 1 << 1; // Playfield ID and coordinate vector
	private static var ef_DebugDetails_StatDump:Number = 1 << 2; // Repeatedly calls Dynel.GetStat() (limited by the constant below), recording any stat which is not 0 or undefined.
	private static var ef_DebugDetails_All:Number = (1 << 3) - 1;

	// Configfuration settings saved to archives
	private var m_Config:Config;
	private var m_DebugConfig:Config;

	// Debugging settings

	// Number of stat IDs to test [0,N) when doing a StatDump (this can cause significant performance hitches, particularly with large ranges)
	// This number is high enough to catch all of the values discovered with a test of various static lores (of the first million statIDs)
	// Unfortunately none seem to be useful, would like to test further with drop lores
	private var c_DebugDetails_StatCount:Number;

	private var m_DebugVerify:Boolean; // Do additional tests to detect inaccurate early discards

	// Automated error report system
	private var m_AutoReport:AutoReport;

	public function LoreHound() {		
		// Initialize configuration settings
		m_Config = new Config(c_ConfigArchive);	
		m_Config.NewSetting("Version", c_Version);
		// Notification types
		m_Config.NewSetting("FifoLevel", ef_LoreType_None);
		m_Config.NewSetting("ChatLevel", ef_LoreType_Drop | ef_LoreType_Special | ef_LoreType_Unknown);
		m_Config.NewSetting("LogLevel", ef_LoreType_Unknown);
		m_Config.NewSetting("MailLevel", ef_LoreType_Unknown);
		
		// Debug and testing settings
		m_DebugConfig = new Config();
		// Extended information on non-fifo output (unknown detections always dump extra info)
		m_DebugConfig.NewSetting("Details", ef_DebugDetails_Location);
		// Auto-reporting
		var autoReportConfig = new Config();
		m_DebugConfig.NewSetting("AutoReport", autoReportConfig);
		m_Config.NewSetting("Debug", m_DebugConfig);
		
		// Hook to detect important setting changes
		m_Config.SignalValueChanged.Connect(ConfigChanged, this);
		
		// Variables initialized here will be detected by the ingame debug menu
		c_DebugDetails_StatCount = 1110;
		m_DebugVerify = true;
		
		// Automatic error reporting
		m_AutoReport = new AutoReport(c_ModName, c_Version, c_DevName, autoReportConfig);
		
		// Lore detection signal
		VicinitySystem.SignalDynelEnterVicinity.Connect(LoreSniffer, this);
		
		Utils.PrintChatText("<font color='#00FFFF'>LoreHound</font>: Loaded.");
	}

	public function Activate() {		
		m_Config.LoadConfig();
		
		// Test last saved version for update routine
		var current:Array = m_Config.GetDefault("Version").substr(1).split(".");
		var prior:Array = m_Config.GetValue("Version").substr(1).split(".");
		var updated:Boolean = undefined;
		for (var i = 0; i < Math.min(current.length, prior.length); ++i) {
			if (current[i] != prior[i]) {
				if (i < 3) {
					updated = i < 3 ? 
						Number(current[i]) > Number(prior[i]) : // numeric section differs
						current[i] == "beta"; // alpha/beta flag differs (but exists on both)
				}
				break;			
			}			
		}
		if (updated == undefined) { updated = current.length < prior.length; } // only difference is if one is a test version
		if (updated) {
			Utils.PrintChatText("<font color='#00FFFF'>LoreHound</font>: Update was detected.");
			// Clear the mail records for any properly categorized types
			var mailLevel = m_Config.GetValue("MailLevel");
			var purgeArray = function (array:Array, extractor:Function):Array {
				var cleanedArray = new Array();
				for (var i:Number = 0; i < array.length; i++) {
					var loreType = ClassifyID(Number(extractor(array[i])));
					Utils.PrintChatText("<font color='#00FFFF'>LoreHound</font>: Array cleanup found lore of type " + loreType);
					if ((loreType & mailLevel) == loreType) {
						cleanedArray.push(array[i]);
					}
				}
				if (cleanedArray.length < array.length) {
					Utils.PrintChatText("<font color='#00FFFF'>LoreHound</font>: Array cleanup removed " + array.length - cleanedArray.length + " records");
				}
				return cleanedArray;
			}
			var autoRepConfig:Config = m_DebugConfig.GetValue("AutoReport");
			autoRepConfig.SetValue("ReportsSent", purgeArray(autoRepConfig.GetValue("ReportsSent"), function(id) { return id; }));
			autoRepConfig.SetValue("ReportQueue", purgeArray(autoRepConfig.GetValue("ReportQueue"), function(report) { return report.id; }));		
		}
		// Reset the version number, usually indicating that the upgrade has been completed, but also to allow for reverted versions to upgrade as expected
		m_Config.SetValue("Version", m_Config.GetDefault("Version"));
		
		Utils.PrintChatText("<font color='#00FFFF'>LoreHound</font>: Is on the prowl.");
	}
	
	public function Deactivate() {		
		m_Config.SaveConfig();
		Utils.PrintChatText("<font color='#00FFFF'>LoreHound</font>: Is sleeping.");
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

	// Notes on Dynels:
	//   GetName() - Actually a remoteformat xml tag, for the LDB localization system
	//   GetID() - The type seems to be constant for all lore. While somewhat stable, instance ids do not persist with multiple playfield loads so cannot reliably uniquely id any lore
	//     Instance ids are used to provide a short-term identifier to help determine the number of unique hits in a high density area
	//   GetPlayfieldID() - Unsure how to convert this to a playfield name through API; No way to generate Playfield data objects? Currently using lookup table on forum.
	//   GetPosition() - World coordinates (Y is vertical)
	//   GetDistanceToPlayer() - ~20m when approaching lore, drops and triggers may initially be much closer when first detected
	//   IsRendered() - Seems to only consider occlusion and clipping, not consistent on lore already claimed
	//   GetStat() - Unknown if any of these are useful, the mode parameter does not seem to change the value/lack of one, a scan of the first million stats and five modes provided:
	//     #12 - Unknown, consistently 7456524 across current data sample
	//     #23 and #112 - Copies of the format string ID #, matching values used in ClassifyID
	//     #1050 - Unknown, usually 6, though other numbers have been observed
	//     #1102 - Copy of the Dynel instance identifier (dynelId.m_Instance)
	//     While the function definition suggests a relationship with the global Stat enum
	//       the only matching value is 1050, mapping to "CarsGroup", whatever that is
	//   Unfortunately, there does not seem to be any existing connection between the Dynel data, and the Lore entries,
	//     if additional features making use of that relationship are desired, it may require a hardcoded mapping of instance ids for placed/triggered lore
	//     (a script comparing lore coordinates could merge instance ids with an existing list of lore locations)
	//     For the primary purpose of identifying drop lore, it may need to track nearby monsters and detect when they die, which is far less than ideal.
	
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
	
	private function ClassifyID(formatStrId:Number):Number {		
		// Here be the magic numbers (probably planted by the Dragon)		
		switch (formatStrId) {
			case 7128026: // Shared by all known normal fixed location lore
				return ef_LoreType_Common;
			case 7648084: // Pol (Hidden zombie lore)
						  // Pol (Drone spawn) is ??
			case 7661215: // DW6 (Post boss lore spawn)
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
	
	function CheckLocalizedName(formatStr:String):Boolean {
		// Have the localization system provide a language dependent string to compare with
		// In English this ends up being "Lore", hopefully it is similarly generic and likely to match in other languages
		var testStr:String = LDBFormat.LDBGetText(50200, 7128026); // (Format string identifiers for commonly placed lore)
		
		return LDBFormat.Translate(formatStr).indexOf(testStr) != -1;
	}
	
	function SendLoreNotifications(loreType:Number, loreId:Number, dynel:Dynel) {
		var dynelID:ID32 = dynel.GetID();
		var formatStr:String = dynel.GetName();
		
		// Compose message strings
		var fifoMessage:String;
		var chatMessage:String;
		var logMessage:String;			
		switch (loreType) {
			case ef_LoreType_Common:
				fifoMessage = "Lore nearby.";
				chatMessage = "Common lore nearby (" + formatStr + " [" + dynelID.m_Instance + "])";
				logMessage = "Common lore (" + formatStr + " [" + dynelID + "])";
				break;
			case ef_LoreType_Triggered:
				fifoMessage = "A lore has appeared.";
				chatMessage = "Triggered lore nearby (" + formatStr + " [" + dynelID.m_Instance + "])";
				logMessage = "Triggered lore (" + formatStr + " [" + dynelID + "])";
				break;
			case ef_LoreType_Drop:
				fifoMessage = "A lore dropped!";
				chatMessage = "Dropped lore nearby (" + formatStr + " [" + dynelID.m_Instance + "])";
				logMessage = "Dropped lore (" + formatStr + " [" + dynelID + "])";
				break;
			case ef_LoreType_Special:
				fifoMessage = "Unusual lore nearby.";
				chatMessage = "Unusual lore nearby (" + formatStr + " [" + dynelID.m_Instance + "])";
				logMessage = "Special lore (" + formatStr + " [" + dynelID + "])";
				break;
			case ef_LoreType_Unknown:
				fifoMessage = "Unknown lore detected.";
				chatMessage = "Unknown lore detected (" + formatStr + " [" + dynelID + "])";
				logMessage = "Unknown lore (" + formatStr + " [" + dynelID + "])";
				break;
			default:
				fifoMessage = "Error, type defaulted: " + loreType;
				chatMessage = "Error, type defaulted: " + loreType;
				logMessage = "Error, type defaulted: " + loreType;
				break;
		}
		
		// Compose additional debug info if requested
		// (Unknown lore always requires certain information for identification purposes)
		// This info is ommitted from FIFO messages to avoid major screen spam
		var debugDetails:Number = m_DebugConfig.GetValue("Details");
		var debugStrings:Array = new Array();
		if (loreType == ef_LoreType_Unknown || (debugDetails & ef_DebugDetails_FormatString) == ef_DebugDetails_FormatString) {
			debugStrings.push("Identity details: " + formatStr.substring(14, formatStr.indexOf('>') - 1 ));
		}
		if (loreType == ef_LoreType_Unknown || (debugDetails & ef_DebugDetails_Location) == ef_DebugDetails_Location) {
			// Not entirely clear on what the "attractor" parameter is for, but leaving it at 0 lines up with world coordinates reported through other means (shift F9, topbars)
			// In world coordinates, Y is vertical and, as the least relevant coordinate, it is therefore listed last.
			var pos:Vector3 = dynel.GetPosition(0);
			debugStrings.push("Playfield: " + dynel.GetPlayfieldID() + " Coordinates: [" + Math.round(pos.x) + ", " + Math.round(pos.z) + ", " + Math.round(pos.y) + "]");
		}	
		if ((debugDetails & ef_DebugDetails_StatDump) == ef_DebugDetails_StatDump) {
			debugStrings.push("Stat Dump:"); // Fishing expedition, trying to find anything potentially useful
			for (var statID:Number = 0; statID < c_DebugDetails_StatCount; ++statID) {			
				var val = dynel.GetStat(statID, 0);
				if (val != undefined && val != 0) {
					debugStrings.push("Stat: #" + statID + " Value: " + val);
				}		
			}
		}
		
		// Dispatch notifications
		if ((m_Config.GetValue("FifoLevel") & loreType) == loreType) {
			Chat.SignalShowFIFOMessage.Emit(fifoMessage, 0);
			}
		if ((m_Config.GetValue("ChatLevel") & loreType) == loreType) {
			Utils.PrintChatText("<font color='#00FFFF'>LoreHound</font>: " + chatMessage);
			for (var i:Number = 0; i < debugStrings.length; ++i) {
				Utils.PrintChatText(debugStrings[i]);
			}
		}		
		if ((m_Config.GetValue("LogLevel") & loreType) == loreType) {
			Log.Error("LoreHound", logMessage);
			for (var i:Number = 0; i < debugStrings.length; ++i) {
				Log.Error("LoreHound", debugStrings[i]);
			}
		}
		if ((m_Config.GetValue("MailLevel") & loreType) == loreType) {
			var report:String = "Category: " + loreType + " (" + LDBFormat.Translate(formatStr) + " [" + dynelID.m_Instance + "])";
			if (debugStrings.length > 0) {
				report += "\n" + debugStrings.join("\n");			
			}
			m_AutoReport.AddReport({ id: loreId, text: report });
		}
	}

}
