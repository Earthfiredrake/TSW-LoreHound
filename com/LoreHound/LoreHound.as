// Copyright 2017, Earthfiredrake (Peloprata)
// Released under the terms of the MIT License
// https://github.com/Earthfiredrake/TSW-LoreHound

import com.GameInterface.Chat;
import com.GameInterface.Dynels;
import com.GameInterface.Game.Character;
import com.GameInterface.Game.Dynel;
import com.GameInterface.Log;
import com.GameInterface.Lore;
import com.GameInterface.LoreNode;
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
	private static var ef_Details_None:Number = 0;
	private static var ef_Details_Location:Number = 1 << 0; // Playfield ID and coordinate vector
	private static var ef_Details_FormatString:Number = 1 << 1; // Trimmed contents of format string, to avoid automatic evaluation
	private static var ef_Details_DynelId:Number = 1 << 2;
	private static var ef_Details_StatDump:Number = 1 << 3; // Repeatedly calls Dynel.GetStat() (limited by the constant below), recording any stat which is not 0 or undefined.
	private static var ef_Details_All:Number = (1 << 4) - 1;

	// Various constants found to be useful
	private static var e_DynelType_Object:Number = 51320; // All known lore shares this dynel type with a wide variety of other props
	private static var e_Stats_LoreId:Number = 2000560; // Most lore dynels seem to store the LoreId at this stat index

	// When doing a stat dump, use/change these parameters to determine the range of the stats to dump
	// It will dump the Nth million stat ids, with the mode parameter provided
	// Tradeoff between the length of time locked up, and the number of tests needed
	private var m_Details_StatRange:Number;
	private var m_Details_StatMode:Number;

	private var m_TrackedLore:Object;

	// Debugging settings
	private var m_DebugVerify:Boolean; // Don't immediately discard dynels which don't match the expected pattern, do further testing to try to protect against early discards
	private var m_DebugTestBox:Object; // A place to dump function returns so they can be viewed through debug menu

	private var m_AutoReport:AutoReport; // Automated error report system

	public function LoreHound() {
		super("LoreHound", "v0.1.1.alpha", "ReleaseTheLoreHound");
		DebugTrace = true;
		m_AutoReport = new AutoReport(ModName, Version, DevName); // Initialized first so that its Config is available to be nested

		LoadConfig();
		UpdateInstall();

		// Ingame debug menu registers variables that are initialized here, but not those initialized at class scope
		// - Perhaps flash does static evaluation and decides to collapse constant variables?
		// - Regardless of the why, this will let me tweak these at runtime
		m_Details_StatRange = 1; // Start with the first million
		m_Details_StatMode = 2; // Defaulting to mode 2 based on repeated comments in game source that it is somehow "full"
		m_DebugVerify = true;
		m_DebugTestBox = new Object();
		m_TrackedLore = new Object();

		RegisterWithTopbar();

		// Character teleported also triggers on anima leaps and agartha teleports, while character destructed seems to only trigger when changing zones.
		Character.GetClientCharacter().SignalCharacterDestructed.Connect(ClearTracking, this);

		ChatMsg("Is on the prowl.");
	}

	private function ClearTracking():Void {
		TraceMsg("Player changed zones, tracked lore has been cleared.");
		m_TrackedLore = new Object();
	}

	private function InitializeConfig():Void {
		// Notification types
		Config.NewSetting("FifoLevel", ef_LoreType_None);
		Config.NewSetting("ChatLevel", ef_LoreType_Drop | ef_LoreType_Special | ef_LoreType_Unknown);
		Config.NewSetting("LogLevel", ef_LoreType_Unknown);
		Config.NewSetting("MailLevel", ef_LoreType_Unknown); // This is a flag for testing purposes only, release states should be enabled (for unkown lore only) or disabled

		Config.NewSetting("IgnoreUnclaimedLore", true); // Ignore lore if the player hasn't picked it up already

		// Extended information, regardless of this setting:
		// - Is always ommitted from Fifo notifications, to minimize spam
		// - Some fields are always included when detecting Unknown category lore, to help identify it
		Config.NewSetting("Details", ef_Details_Location);

		Config.NewSetting("AutoReport", m_AutoReport.GetConfigWrapper());
		Config.GetValue("AutoReport").m_DebugTrace = DebugTrace;

		// Hook to detect important setting changes
		Config.SignalValueChanged.Connect(ConfigChanged, this);
	}

	private function ConfigChanged(setting:String, newValue, oldValue):Void {
		switch(setting) {
			case "MailLevel":
				m_AutoReport.IsEnabled = (newValue != ef_LoreType_None);
				break;
			default:
			// Setting does not push changes (is checked on demand)
		}
	}

	public function DoUpdate():Void {
		TraceMsg("Update was detected.");

		// Minimize settings clutter by purging auto-report records of newly categorized IDs
		var autoRepConfig:ConfigWrapper = Config.GetValue("AutoReport");
		autoRepConfig.SetValue("ReportsSent", CleanReportArray(autoRepConfig.GetValue("ReportsSent"), function(id) { return id; }));
		autoRepConfig.SetValue("ReportQueue", CleanReportArray(autoRepConfig.GetValue("ReportQueue"), function(report) { return report.id; }));

		ChatMsg("Has been updated to " + Config.GetDefault("Version"));
	}

	private function CleanReportArray(array:Array, extractor:Function):Array {
		var cleanedArray = new Array();
		for (var i:Number = 0; i < array.length; i++) {
			if (ClassifyID(Number(extractor(array[i]))) == ef_LoreType_Unknown) {
				cleanedArray.push(array[i]);
			}
		}
		TraceMsg("Cleanup removed " + (array.length - cleanedArray.length) + " records, " + cleanedArray.length + " records remain.");
		return cleanedArray;
	}

	public function Activate():Void {
		m_AutoReport.IsEnabled = (Config.GetValue("MailLevel") != ef_LoreType_None);
		VicinitySystem.SignalDynelEnterVicinity.Connect(LoreSniffer, this); // Lore detection hook
		Dynels.DynelGone.Connect(LoreDespawned, this);
		super.Activate();
	}

	public function Deactivate():Void {
		Dynels.DynelGone.Disconnect(LoreDespawned, this);
		VicinitySystem.SignalDynelEnterVicinity.Disconnect(LoreSniffer, this); // Lore detection hook
		m_AutoReport.IsEnabled = false;
		super.Deactivate();
	}

	// Notes on Dynel API:
	//   GetName() - Actually a remoteformat xml tag, for the LDB localization system
	//     Has a type attribute with a value usually 50200 and an id value which is used for categorization
	//   GetID() - The ID type seems to be constant for all lore, and is shared with a wide variety of other props
	//     Instance ids of fixed lore may vary slightly between sessions, seemingly depending on load orders or caching of map info.
	//     Dropped lore seems to use whatever id happens to be available at the time, and demonstrates no consistency between drops.
	//     While unsuited as a unique identifier, instance ids do help differentiate unique hits in a high density area, as they are unique and remain constant for the lifetime of the object.
	//   GetPlayfieldID() - Unsure how to convert this to a playfield name through API; No way to generate Playfield data objects? Currently using lookup table on forum.
	//   GetPosition() - World coordinates (Y is vertical)
	//   GetDistanceToPlayer() - Proximity system triggers at ~20m when approaching a dynel, as well as detecting new dynels within that radius
	//     Lore detected at shorter ranges is almost always spawned in some way. Once spawned, the only way to track its existence is to bounce back and forth across the boundary
	//   IsRendered() - Seems to consider occlusion and clipping but not consistent on lore already claimed
	//   GetStat() - Excessive scanning has found one potentially useful value on some lore dynels
	//     Have now tested the first 50 million indices, with mode 0
	//     Have also tested the first 16 modes at the 2-3 million range with no observable difference between them
	//     #12 - Unknown, consistently 7456524 across current data sample
	//     #23 and #112 - Copies of the format string ID #, matching values used in ClassifyID
	//     #1050 - Unknown, usually 6, though other numbers have been observed
	//     #1102 - Copy of the Dynel instance identifier (dynelId.m_Instance)
	//     #2000560 - Exists on a massive majority of the lore recently observed:
	//                - Known to be missing on some lores (at least one in each of KD, CF, and Agartha)
	//                - Sometimes fails to load on initial detection of dropped lores, but this can be corrected on further detection
	//                - Missing from all Shrouded Lore dynels
	//              - Tag # matching db entries labled "Lore#.Tag#", outside of api access but still very useful info (Thanks Vomher)
	//              - ID number for the lore entry in the journal!
	//     The function seems to be related to the enum _global.Stat, but most of the indices that actually come up are unspecified.
	//       - The only matching value is 1050, mapping to "CarsGroup", whatever that is.
	//       - There are a number of other values in the 2 million range, though none matching 560
	//     Testing unclaimed lore with alts did not demonstrate any notable differences in the reported stats

	// Callback on dynel detection
	private function LoreSniffer(dynelId:ID32):Void {
		if (dynelId.m_Type != e_DynelType_Object && !m_DebugVerify) { return; }

		var dynel:Dynel = Dynel.GetDynel(dynelId);
		var dynelName:String = dynel.GetName();

		// Extract the format string ID number from the xml tag
		var formatStrId:String = dynelName.substring(dynelName.indexOf('id="') + 4);
		formatStrId = formatStrId.substring(0, formatStrId.indexOf('"'));
		var categorizationId:Number = Number(formatStrId);

		// Categorize the detected item
		var loreType:Number = ClassifyID(categorizationId);
		if (loreType == ef_LoreType_Unknown || dynelId.m_Type != e_DynelType_Object) {
			loreType = CheckLocalizedName(dynelName) ? ef_LoreType_Unknown : ef_LoreType_None;
		}
		var loreId:Number = dynel.GetStat(e_Stats_LoreId, 2);
		if (loreType == ef_LoreType_Drop) { // Track dropped lore so that notifications can be made on despawn
			if (m_TrackedLore[dynelId.toString()] == undefined) {
				Dynels.RegisterProperty(dynelId.m_Type, dynelId.m_Instance, _global.enums.Property.e_ObjPos);
			}
			// Refresh this, in case it failed to identify at first
			m_TrackedLore[dynelId.toString()] = loreId;
			TraceMsg("Now tracking lore drop: " + AttemptIdentification(loreId, categorizationId, dynelName));
		}
		if (loreId != undefined && loreId != 0 && Lore.IsLocked(loreId) && Config.GetValue("IgnoreUnclaimedLore")) {
			loreType = ef_LoreType_None;
			TraceMsg("Unclaimed lore ignored.");
		}
		if (loreType != ef_LoreType_None) {
			SendLoreNotifications(loreType, categorizationId, dynel);
		}
	}

	// Triggers when the lore dynel is removed from the client, either because it has despawned or the player has moved too far away
	private function LoreDespawned(type:Number, instance:Number):Void {
		var despawnedId:String = new ID32(type, instance).toString();
		var loreId:Number = m_TrackedLore[despawnedId];
		if (loreId != undefined) {
			if (loreId == 0 || !(Lore.IsLocked(loreId) && Config.GetValue("IgnoreUnclaimedLore"))) {
				var loreName:String = AttemptIdentification(loreId); // Only applies to dropped lore, so it can't be the Shrouded Lore, remaining params permitted to be undefined
				var messageStrings:Array = new Array(
					loreName + "despawned.",
					"Lore despawned or out of range (" + loreName + ")",
					"Lore despawned or out of range (" + loreName + ")",
					"Category: " + ef_LoreType_Drop + " despawned (" + loreName + ")"
				);
				DispatchMessages(ef_LoreType_Drop, -instance, messageStrings);
			}
			m_TrackedLore[despawnedId] = undefined;
		}
	}

	private static function ClassifyID(categorizationId:Number):Number {
		// Here be the magic numbers (probably planted by the Dragon)
		switch (categorizationId) {
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
			case 8508040:  // BS drop (The Wall #4) from Behemoth of the Devouring Plague in KD
			case 9240080:  // Shared by all known monster drop or spawned bestiary lore
				return ef_LoreType_Drop;
			case 7993128: // Shrouded Lore (End of Days)
			case 9135398: // Two one-off lores found in MFB (probably should be grouped as Triggered, want to go back in and verify which was which first)
			case 9135406:
				return ef_LoreType_Special;
			default:
				return ef_LoreType_Unknown;
		}
	}

	private static function CheckLocalizedName(formatStr:String):Boolean {
		// Have the localization system provide a language dependent string to compare with
		// In English this ends up being "Lore", hopefully it is similarly generic and likely to match in other languages
		var testStr:String = LDBFormat.LDBGetText(50200, 7128026); // Format string identifiers for commonly placed lore
		return LDBFormat.Translate(formatStr).indexOf(testStr) != -1;
	}

	private function SendLoreNotifications(loreType:Number, categorizationId:Number, dynel:Dynel) {
		var messageStrings:Array = GetMessageStrings(loreType, categorizationId, dynel);
		var detailStrings:Array = GetDetailStrings(loreType, dynel);
		DispatchMessages(loreType, categorizationId, messageStrings, detailStrings);
	}

	// Index:
	// 0: Fifo message
	// 1: System chat message
	// 2: Log message
	// 3: Mail report
	private static function GetMessageStrings(loreType:Number, categorizationId:Number, dynel:Dynel):Array {
		var loreName = AttemptIdentification(dynel.GetStat(e_Stats_LoreId, 2), categorizationId, dynel.GetName());
		var messageStrings:Array = new Array();
		switch (loreType) {
			case ef_LoreType_Common:
				messageStrings.push( loreName + " nearby.");
				messageStrings.push("Common lore nearby (" + loreName + ")");
				messageStrings.push("Common lore (" + loreName + ")");
				break;
			case ef_LoreType_Triggered:
				messageStrings.push( loreName + " has appeared.");
				messageStrings.push("Triggered lore nearby (" + loreName + ")");
				messageStrings.push("Triggered lore (" + loreName + ")");
				break;
			case ef_LoreType_Drop:
				messageStrings.push( loreName + " dropped.");
				messageStrings.push("Dropped lore nearby (" + loreName + ")");
				messageStrings.push("Dropped lore (" + loreName + ")");
				break;
			case ef_LoreType_Special:
				messageStrings.push( loreName + " nearby.");
				messageStrings.push("Unusual lore nearby (" + loreName + ")");
				messageStrings.push("Unusual lore (" + loreName + ")");
				break;
			case ef_LoreType_Unknown:
				messageStrings.push( loreName + " needs catologuing.");
				messageStrings.push("Unknown lore detected (" + loreName + ")");
				messageStrings.push("Unknown lore (" + loreName + ")");
				break;
			default:
				messageStrings.push("Error, lore type defaulted: " + loreType);
				messageStrings.push("Error, lore type defaulted: " + loreType);
				messageStrings.push("Error, lore type defaulted: " + loreType);
				break;
		}
		messageStrings.push("Category: " + loreType + " (" + loreName + ")");
		return messageStrings;
	}

	// Jackpot!! Connects dynels to LoreNode entries and the rest of the Lore interface:
	// m_Name: Empty for our node, but the parent will contain the topic
	// m_Type: LoreNodes aren't just lore, they also do achivements, mounts, teleports... (this will be 2, not so useful)
	// m_Locked: Has this node been picked up yet?
	// m_Parent/m_Children: Navigate the lore tree
	// Lore.IsVisible(id): Unsure, still doesn't seem to be related to unlocked state
	// Lore.GetTagViewpoint(id): 0 is Buzzing, 1 is Black Signal (both are m_Children for a single topic)
	private static function AttemptIdentification(loreId:Number, categorizationId:Number, dynelName:String):String {
		if (loreId != undefined && loreId != 0) {
			var loreNode:LoreNode = Lore.GetDataNodeById(loreId);
			var loreSource:Number = Lore.GetTagViewpoint(loreId);
			var catCode:String;
			switch (loreSource) {
				case 0: // Buzzing
					catCode = " #";
					break;
				case 1: // Black Signal
					catCode = " BS#";
					break;
				default: // Unknown source
					catCode = " ?#";
					break;
			}
			var parentNode:LoreNode = loreNode.m_Parent;
			var priorSiblings:Number = 1; // Most people number based on type and from a base of 1
			for (var i:Number = 0; i < parentNode.m_Children.length; ++i) {
				var childId:Number = parentNode.m_Children[i].m_Id;
				if (childId == loreId) {
					return parentNode.m_Name + " " + catCode + priorSiblings;
				}
				if (Lore.GetTagViewpoint(childId) == loreSource) {
					++priorSiblings;
				}
			}
		}
		// Shrouded Lore, amusingly, uniformly lacks the loreId field and is the only one known to have an informative localized string.
		if (categorizationId == 7993128) {
			return dynelName;
		}
		return "Unable to identify";
	}

	// This info is ommitted from FIFO messages
	// Unknown lore always requests some info for identification purposes
	private function GetDetailStrings(loreType:Number, dynel:Dynel):Array {
		var details:Number = Config.GetValue("Details");
		var detailStrings:Array = new Array();
		var formatStr:String = dynel.GetName();

		if (loreType == ef_LoreType_Unknown || (details & ef_Details_Location) == ef_Details_Location) {
			// Not entirely clear on what the "attractor" parameter is for, leaving it at 0 causes results to match world coordinates reported through other means (shift F9, topbars)
			// Y is being listed last because it's the vertical component, and most concern themselves with map coordinates (x,z)
			var pos:Vector3 = dynel.GetPosition(0);
			detailStrings.push("Playfield: " + dynel.GetPlayfieldID() + " Coordinates: [" + Math.round(pos.x) + ", " + Math.round(pos.z) + ", " + Math.round(pos.y) + "]");
		}
		if (loreType == ef_LoreType_Unknown || (details & ef_Details_DynelId) == ef_Details_DynelId) {
			detailStrings.push("Dynel ID: " + dynel.GetID().toString());
		}
		if (loreType == ef_LoreType_Unknown || (details & ef_Details_FormatString) == ef_Details_FormatString) {
			detailStrings.push("Category info: " + formatStr.substring(14, formatStr.indexOf('>') - 1 )); // Strips the format string so that it doesn't preprocess
		}
		if ((details & ef_Details_StatDump) == ef_Details_StatDump) {
			// Fishing expedition, trying to find anything potentially useful
			detailStrings.push("Stat Dump: Mode " + m_Details_StatMode);
			var start:Number = (m_Details_StatRange - 1) * 1000000;
			var end:Number = m_Details_StatRange * 1000000;
			for (var statID:Number = start; statID < end; ++statID) {
				var val = dynel.GetStat(statID, m_Details_StatMode);
				if (val != undefined && val != 0 && val != "") {
					detailStrings.push("Stat: #" + statID + " Value: " + val);
				}
			}
		}
		return detailStrings;
	}

	private function DispatchMessages(loreType:Number, categorizationId:Number, messageStrings:Array, detailStrings:Array):Void {
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
			m_AutoReport.AddReport({ id: categorizationId, text: report });
		}
	}

}
