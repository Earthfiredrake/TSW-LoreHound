// Copyright 2017, Earthfiredrake (Peloprata)
// Released under the terms of the MIT License
// https://github.com/Earthfiredrake/TSW-LoreHound

import flash.geom.Point;

import gfx.utils.Delegate;

import com.GameInterface.Chat;
import com.GameInterface.Dynels;
import com.GameInterface.Game.Dynel;
import com.GameInterface.Log;
import com.GameInterface.Lore;
import com.GameInterface.LoreNode;
import com.GameInterface.MathLib.Vector3;
import com.GameInterface.Utils;
import com.GameInterface.VicinitySystem;
import com.GameInterface.WaypointInterface;
import com.Utils.Format;
import com.Utils.ID32;
import com.Utils.LDBFormat;

import efd.LoreHound.lib.AutoReport;
import efd.LoreHound.lib.ConfigWrapper;
import efd.LoreHound.lib.Mod;

class efd.LoreHound.LoreHound extends Mod {
	private static var ModInfo:Object = {
		// Debug settings at top so that commenting out leaves no hanging ','
		// Trace : true,
		Name : "LoreHound",
		Version : "0.6.6.alpha"
	}

	// Category flags for identifiable lore types
	private static var ef_LoreType_None:Number = 0;
	public static var ef_LoreType_Placed:Number = 1 << 0; // Most lore with fixed locations
	public static var ef_LoreType_Trigger:Number = 1 << 1; // Lore with triggered spawn conditions, seems to stay spawned once triggered (often after dungeon bosses)
	public static var ef_LoreType_Drop:Number = 1 << 2; // Lore which drops from monsters, or otherwise spawns with a time limit
	private static var ef_LoreType_Despawn:Number = 1 << 3; // Special type for generating despawn messages (will be output as Drop lore)
	public static var ef_LoreType_Unknown:Number = 1 << 4; // Newly detected lore, will need to be catalogued
	private static var ef_LoreType_All:Number = (1 << 5) - 1;

	// Category flags for extended information
	private static var ef_Details_None:Number = 0;
	public static var ef_Details_Location:Number = 1 << 0; // Playfield name and coordinate vector
	public static var ef_Details_FormatString:Number = 1 << 1; // Trimmed contents of format string, to avoid automatic evaluation
	public static var ef_Details_DynelId:Number = 1 << 2;
	public static var ef_Details_Timestamp:Number = 1 << 3;
	private static var ef_Details_StatDump:Number = 1 << 4; // Repeatedly calls Dynel.GetStat() (limited by the constant below), recording any stat which is not 0 or undefined.
	private static var ef_Details_All:Number = (1 << 5) - 1;

	// Flags for ongoing icon states
	private static var ef_IconState_Alert = 1 << 0;
	private static var ef_IconState_Report = 1 << 1;

	/// Initialization
	public function LoreHound(hostMovie:MovieClip) {
		super(ModInfo, hostMovie);
		// Ingame debug menu registers variables that are initialized here, but not those initialized at class scope
		// - Perhaps flash does static evaluation and decides to collapse constant variables?
		// - Regardless of the why, this will let me tweak these at runtime
		DumpToLog = false;
		DetailStatRange = 1; // Start with the first million
		DetailStatMode = 2; // Defaulting to mode 2 based on repeated comments in game source that it is somehow "full"

		TrackedLore = new Object();
		WaypointInterface.SignalPlayfieldChanged.Connect(ClearTracking, this);

		ReportManager = new AutoReport(ModName, Version, DevName);

		InitializeConfig();

		Icon.UpdateState = function(stateFlag:Number, enable:Boolean) {
			if (stateFlag != undefined) {
				switch (enable) {
					case true: { this.StateFlags |= stateFlag; break; }
					case false: { this.StateFlags &= ~stateFlag; break; }
					case undefined: { this.StateFlags ^= stateFlag; break; }
				}
			}
			if (Config.GetValue("Enabled")) { // Should this also deactivate if the game turns it off? Use the proprety Enabled instead.
				if ((this.StateFlags & LoreHound.ef_IconState_Alert) == LoreHound.ef_IconState_Alert) { this.gotoAndStop("alerted"); return; }
				if ((this.StateFlags & LoreHound.ef_IconState_Report) == LoreHound.ef_IconState_Report) { this.gotoAndStop("reporting"); return; }
				this.gotoAndStop("active");
			} else {
				this.gotoAndStop("inactive");
			}
		};

		TraceMsg("Initialized");
	}

	private function InitializeConfig():Void {
		// Notification types
		Config.NewSetting("FifoLevel", ef_LoreType_None);
		Config.NewSetting("ChatLevel", ef_LoreType_Drop | ef_LoreType_Unknown);

		Config.NewSetting("IgnoreUnclaimedLore", true); // Ignore lore if the player hasn't picked it up already
		Config.NewSetting("IgnoreOffSeasonLore", true); // Ignore event lore if the event isn't running (TODO: Test this when a game event is running)
		Config.NewSetting("TrackDespawns", true); // Track lore drops for when they despawn
		Config.NewSetting("SendReports", false); // DEPRECIATED(v0.6.0): Setting removed
		Config.NewSetting("CheckNewContent", false); // Does extra tests to detect lore that isn't on the index list at all yet (ie: new content!)

		// Extended information, regardless of this setting:
		// - Is always ommitted from Fifo notifications, to minimize spam
		// - Some fields are always included when detecting Unknown category lore, to help identify it
		Config.NewSetting("Details", ef_Details_Location);

		var autoReportConfig:ConfigWrapper = ReportManager.Config;
		autoReportConfig.SignalValueChanged.Connect(AutoReportConfigChanged, this);
		Config.NewSetting("AutoReport", autoReportConfig);
	}

	private function AutoReportConfigChanged(setting:String, newValue, oldValue):Void {
		switch(setting) {
			case "Enabled":
			case "QueuedReports":
				Icon.UpdateState(ef_IconState_Report, ReportManager.HasReportsPending);
				break;
			default: break;
		}
	}

	/// Mod framework extensions and overrides
	private function ConfigLoaded(initialLoad:Boolean):Void {
		super.ConfigLoaded(initialLoad);
		if (initialLoad) {
			Config.DeleteSetting("SendReports"); // DEPRECIATED(v0.6.0): Setting removed
		}
	}

	private function ConfigChanged(setting:String, newValue, oldValue):Void {
		switch(setting) {
			case "TrackDespawns":
				if (!newValue) { ClearTracking(); }
				break;
			default:
				super.ConfigChanged(setting, newValue, oldValue);
		}
	}

	private function DoUpdate(newVersion:String, oldVersion:String):Void {
		// Minimize settings clutter by purging auto-report records of newly categorized IDs
		ReportManager.CleanupReports(IsCategorizedLore);

		// Version specific updates
		// Note: v0.1.x-alpha did not have the version tag, and so can't be detected
		if (oldVersion == "v0.4.0.beta") {
			// Point support added to ConfigWrapper, and position settings were updated accordingly
			// Also the last version to have the "v" embedded in the version string
			var oldPoint = Config.GetValue("ConfigWindowPosition");
			Config.SetValue("ConfigWindowPosition", new Point(oldPoint.x, oldPoint.y));
			oldPoint = Config.GetValue("IconPosition");
			Config.SetValue("IconPosition", new Point(oldPoint.x, oldPoint.y));
		}
		// After v0.5.0-beta: Points now saved using built in support from Archive
		//   Should not require additional update code
		if (CompareVersions("0.5.0.beta", oldVersion) >= 0) {
			// Enabled state of autoreport system is now internal to that config group
			if (Config.GetValue("SendReports")) {
				Config.GetValue("AutoReport").SetValue("Enabled", true);
			}
		}
		if (CompareVersions("0.6.5.alpha", oldVersion) >=0) {
			// Removed "Unusual" lore category, value now occupied by "Despawn" special flag
			Config.SetFlagValue("FifoLevel", ef_LoreType_Despawn, false);
			Config.SetFlagValue("ChatLevel", ef_LoreType_Despawn, false);
		}
	}

	private static function IsCategorizedLore(categoryId:Number):Boolean {
		var category:Number = ClassifyID(categoryId);
		return category != ef_LoreType_Unknown && category != ef_LoreType_None;
	}

	private function Activate():Void {
		ReportManager.IsEnabled = true; // Only updates this component's view of the mod state
		VicinitySystem.SignalDynelEnterVicinity.Connect(LoreSniffer, this);
		Dynels.DynelGone.Connect(LoreDespawned, this);
	}

	private function Deactivate():Void {
		// For most teleports this will be renabled before the despawn notification is sent
		//   Oddly the despawn notification will be sent even if we deregister from the dynel stat
		// When changing zones however, despawn and detection notices are both sent during the deactivated period
		// Detection notices between the deactivate-activate pair have a strange habit of providing the correct LoreId, but being unable to link to an actual lore object
		Dynels.DynelGone.Disconnect(LoreDespawned, this);
		VicinitySystem.SignalDynelEnterVicinity.Disconnect(LoreSniffer, this);
		ReportManager.IsEnabled = false; // Only updates this component's view of the mod state
	}

	private function TopbarRegistered():Void {
		// Topbar icon does not copy custom state variable, so needs explicit refresh
		Icon.UpdateState(ef_IconState_Report, ReportManager.HasReportsPending);
	}

	// Override to add timestamps before the lead text
	private function ChatMsg(message:String, suppressLeader:Boolean, forceTimestamp:Boolean) {
		var timestamp:String = "";
		if (forceTimestamp) {
			var time:Date = new Date();
			timestamp = Format.Printf("[%02d:%02d] ", time.getHours(), time.getMinutes());
		}
		var lead:String = suppressLeader ? "" : "<font color='" + ChatLeadColor + "'>" + ModName + "</font>: ";
		Utils.PrintChatText(timestamp + lead + message);
	}

	// Notes on Dynel API:
	//   GetName() - For objects a remoteformat xml tag, for the localization database system (LDB)
	//     Template is: <remoteformat id="#" category="#" key="text" knubot="#"></remoteformat>
	//	     Chat (and many other output systems) will attempt to automatically format this, and discards from the '<' if a tag lacks a matching '>'
	//         Behaviour if the </> tag is missing is beyond the needs of this mod, and hasn't been tested
	//     id: The string ID in the LDB, the ones I'm interested in almost always map to "Lore" in the english database
	//       The devs have a habit of adding multiple copies of the same word, used in different instances, which could be massively frustrating, but is a useful initial categorization aid here
	//         Suspect that they too are using this # elsewhere in the code to differentiate behaviours
	//     category: The string table to pull from? Constantly 50200 whenever I've checked
	//     key: Some sort of hash? May vary by id# or string content (shrouded and regular lore have different values), but seems constant within a group
	//     knubot: No idea at all. Always seems to be 0 for what it's worth.
	//   GetID() - The ID type seems to be constant (51320) for all lore, but is shared with a wide variety of other props
	//       Other types:
	//         50000 - used by all creatures (players, pets, npcs, monsters, etc.)
	//         51322 - loot bags
	//       As a note for later, the other category uses a different GetName() system (is pre-localized, rather than the xml tag used by objects)
	//     Instance ids of fixed lore may vary slightly between sessions, seemingly depending on load orders or caching of map info.
	//     Dropped lore seems to use whatever instance id happens to be free, and demonstrates no consistency between drops.
	//     While unsuited as a unique identifier, instance ids do help differentiate unique hits in a high density area, as they are unique and remain constant for the lifetime of the object.
	//   GetPlayfieldID() - Can be converted to a localized string using the LDBFormat uitlity, with the category "Playfieldnames" (Discovered in Meeehr's topbar)
	//   GetPosition() - World coordinates (Y is vertical)
	//   GetDistanceToPlayer() - Proximity system triggers at ~20m when approaching a dynel, as well as detecting new dynels within that radius
	//     Lore detected at shorter ranges is almost always spawned in some way, though I haven't needed to use this to assist with categories
	//   IsRendered() - Seems to consider occlusion and clipping but not consistent on lore already claimed
	//   GetStat() - Excessive scanning has found one useful value on most lore dynels
	//     Have now tested the first 50 million indices, with mode 0
	//     Have also tested the first 16 modes at the 2-3 million range with no observable difference between them
	//     #12 - Unknown, consistently 7456524 across current data sample
	//     #23 and #112 - Copies of the format string ID #, matching values used in ClassifyID
	//     #1050 - Unknown, usually 6, though other numbers have been observed
	//     #1102 - Copy of the Dynel instance identifier (dynelId.m_Instance)
	//     #2000560 - Exists on a massive majority of the lore recently observed:
	//                - Missing from all Shrouded Lore and other event lore (presumably because it's inactive, TODO: Test this theory, in July)
	//                - Sometimes fails to load before a dropped lore triggers the detection, a few quick retries is usually enough time for it to load
	//              - Tag # matching db entries labled "Lore#.Tag#", outside of api access but still very useful info (Thanks Vomher)
	//              - ID number for the lore entry in the journal!
	//     The function seems to be related to the enum _global.Stat, but most of the indices that actually come up are unspecified.
	//       - The only matching value is 1050, mapping to "CarsGroup", whatever that is.
	//       - There are a number of other values in the 2 million range, though none matching 560
	//     Unlisted values and missing IDs return 0
	//     Testing unclaimed lore with alts did not demonstrate any notable differences in the reported stats

	/// Lore detection and sorting
	private function LoreSniffer(dynelId:ID32, repeat:Number):Void {
		if (dynelId.m_Type != e_DynelType_Object) { return; } // Dynel is not of supertype associated with lore

		var dynel:Dynel = Dynel.GetDynel(dynelId);
		var dynelName:String = dynel.GetName();

		// Extract the format string ID number from the xml tag
		var formatStrId:String = dynelName.substring(dynelName.indexOf('id="') + 4);
		formatStrId = formatStrId.substring(0, formatStrId.indexOf('"'));
		var categorizationId:Number = Number(formatStrId);

		// Categorize the detected item
		var loreType:Number = ClassifyID(categorizationId);
		if (loreType == ef_LoreType_None) {
			if (Config.GetValue("CheckNewContent") && ExpandedDetection(dynel)) { loreType = ef_LoreType_Unknown; } // It's so new it hasn't been added to the index list yet
			else { return; }
		}

		ProcessAndNotify(dynel, loreType, categorizationId, 0);
	}

	// Callback for timeout delegate if loreId is uninitialized
	private function ProcessAndNotify(dynel:Dynel, loreType:Number, categorizationId:Number, repeat:Number):Void {
		if (ProcessLore(dynel, loreType, categorizationId, repeat)) {
			SendLoreNotifications(loreType, categorizationId, dynel);
		}
	}

	private function ProcessLore(dynel:Dynel, loreType:Number, categorizationId:Number, repeat:Number):Boolean {
		// Type based filtering and preprocessing
		// Attempts to ensure that a lore has a valid loreId, and starts tracking of dropped lores
		// Also filters out the various "Ignore" settings
		var loreId:Number = dynel.GetStat(e_Stats_LoreId, 2);
		if (Config.GetValue("IgnoreOffSeasonLore") && loreId == 0 && loreType == ef_LoreType_Placed) {
			return false; // Ignoring offseason lore
		}
		// dynelId, loreType, categorizationId, dynel, loreId

		if (loreType != ef_LoreType_Placed) {
			// Lore spawned without a valid loreId should correct itself quickly, retest after a short delay
			// Also including Unknown lore as it may be uncategorized drop lore
			if (loreId == 0 && repeat < 5) {
				TraceMsg("Spawned lore required repeat: " + (repeat + 1));
				setTimeout(Delegate.create(this, ProcessAndNotify), 1, dynel, loreType, categorizationId, repeat + 1);
				return false; // The retries will eventually deal with notification
			}
			// Track dropped lore so that notifications can be made on despawn
			// While could hook to the DynelLeave proximity detector, this method should be more efficient
			if (loreType == ef_LoreType_Drop && Config.GetValue("TrackDespawns")) {
				var dynelId:ID32 = dynel.GetID();
				if (TrackedLore[dynelId.toString()] == undefined) {
					// Don't care about the value, but the request is required to get DynelGone events
					Dynels.RegisterProperty(dynelId.m_Type, dynelId.m_Instance, _global.enums.Property.e_ObjPos);
					TrackedLore[dynelId.toString()] = loreId;
					Icon.UpdateState(ef_IconState_Alert, true);
				}
			}
		}
		if (Config.GetValue("IgnoreUnclaimedLore") && loreId != 0 && Lore.IsLocked(loreId) && loreType != ef_LoreType_Unknown) {
			// Ignoring unclaimed lore
			// Do this after the tracking hook, as the user is likely to claim the lore
			return false;
		}
		if ((Config.GetValue("FifoLevel") & loreType) != loreType && (Config.GetValue("ChatLevel") & loreType) != loreType &&
			(loreType != ef_LoreType_Unknown || !ReportManager.IsEnabled) && !DumpToLog) {
			return false; // No notification to be made, don't bother generating strings
		}
		return true;
	}

	/// Dropped lore despawn tracking

	// Triggers when the lore dynel is removed from the client, either because it has despawned or the player has moved too far away
	// With no dynel to query, all required info has to be known values or cached
	private function LoreDespawned(type:Number, instance:Number):Void {
		var despawnedId:String = new ID32(type, instance).toString();
		var loreId:Number = TrackedLore[despawnedId];
		// Conform to the player's choice of notification on unclaimed lore, should they have left it unclaimed
		if (loreId == 0 || !(Lore.IsLocked(loreId) && Config.GetValue("IgnoreUnclaimedLore"))) {
			var messageStrings:Array = GetMessageStrings(ef_LoreType_Despawn, loreId); //
			DispatchMessages(messageStrings, ef_LoreType_Drop); // No details or raw categorizationID
		}
		delete TrackedLore[despawnedId];
		for (var key:String in TrackedLore) {
			return; // There's still at least one lore being tracked, don't clear the icon
		}
		Icon.UpdateState(ef_IconState_Alert, false);
	}

	private function ClearTracking():Void {
		for (var key:String in TrackedLore) {
			var id:Array = key.split(":");
			Dynels.UnregisterProperty(id[0], id[1], _global.enums.Property.e_ObjPos);
		}
		delete TrackedLore;
		TrackedLore = new Object();
		Icon.UpdateState(ef_IconState_Alert, false);
	}

	/// Lore identification

	private static function ClassifyID(categorizationId:Number):Number {
		// Here be the magic numbers (probably planted by the Dragon)
		switch (categorizationId) {
			case 7128026: // Shared by all known fixed location lore
				// Also includes: (rejected candidates for suspected unknown IDs)
				// - Lore from end of Brotherly Loathe (drops from boss)
				// - Lore on docks in One Kill Ahead (appears after cutscene)
				// - Lore at pachinko machine in Pachinko Model (appears after use)
				// - Lore in boardroom inaccessible (does not appear?) until after penthouse fight
				// - Lore on penthouse balcony (spawns after fight)
				// - Lore for the faction allies in KD gained by speaking to their leaders
				// - Lore from interaction with Akashi
			case 7993128: // Shrouded Lore (End of Days)
				return ef_LoreType_Placed;
			case 7648084: // Pol (Hidden zombie after #1)
			case 7648085: // Pol (Drone spawn) (missing from string table)
			case 7653135: // HR6 (Post boss lore spawn)
			case 7661215: // DW6 (Post boss lore spawn)
			case 7648451: // Ankh (Orochi Agent after #1)
			case 7648450: // Ankh (Wretched Receptacles (Ankh #5))
			case 7648452: // Ankh (Disembalmed Atenist after #3 (Ankh #8))
			case 7648449: // Ankh (Pit Dwellers)
			case 7647988: // HF6 (Post boss lore spawn)
			case 7647983: // Fac6 (Post boss lore spawn)
			case 7647985: // Fac5 (Post boss lore spawn)
			case 7647986: // Fac3 (Post boss lore spawn)
			case 7573298: // HE6 (Post boss lore spawn), also used for Faust Omega "Knowledge" room
			case 8507997: // CK carpark (HiE BS #1) spawns (on top floor) upon reaching bottom floor
			case 8508000: // CK carpark (HiE BS #2) spawns after picking up the evidence
			case 9125445: // MFA (Smiler mech after #5)
			case 9125570: // MFA6 (Post boss lore spawn)
			case 9135398: // MFB4 (Post boss lore spawn)
			case 9135406: // MFB5 (Filth Must Flow spawn)
				return ef_LoreType_Trigger;
			// Both Black Signal lores have 1 min despawn timers
			case 8499259:  // Hyper-Infected Citizen drop (Kaiden BS #3), will despawn if not engaged but can be healtanked for a while
			case 8508040:  // Behemoth of the Devouring Plague drop (The Wall BS #4) in KD
			// Bestiary lore seems to have 5 min despawn timers
			case 9240080:  // Shared by almost all known monster drop or spawned bestiary lore
			case 9241297:  // Spectres 11 drop, in anima form in KD
				return ef_LoreType_Drop;
			case 8397678: // Probably Niflheim
			case 8397708: // Probably Niflheim
			case 8437788: // Unknown (KD?)
			case 8437793: // Unknown (KD?)
			case 8508014: // Unknown (KD?)
			case 8508217: // Unknown (KD?)
			case 8587691: // Scrappy's death spawn?
				// Cultist lore in The Prisoner (i6)?
				// One or more IDs might be related to the full sets of event lore missing entirely
				// - Christmas (2 in Niflheim)
				// - Scrappy (the spawn near kurt when it dies)
				// - Riders (one or several (4, 8?) numbers? Expect this to be the standard drop ID)
				return ef_LoreType_Unknown;
			default:
				return ef_LoreType_None;
		}
	}

	private static function ExpandedDetection(dynel:Dynel):Boolean {
		// Check the dynel's lore ID, it may not have a proper entry in the string table (Polaris drone clause)
		// Won't detect inactive event lore though (Shrouded Lore would slip through both tests most of the time)
		if (dynel.GetStat(e_Stats_LoreId, 2) != 0) { return true; }
		// Have the localization system provide language dependent strings to compare
		// Using exact comparison, should be slightly faster and eliminate almost all false positives
		// May require occasional scans of the string db to catch additions of things like "Shrouded Lore"
		var testStr:String = LDBFormat.LDBGetText(50200, 7128026); // Format string for common placed lore
		return LDBFormat.Translate(dynel.GetName()) == testStr;
	}

	/// Notification and message formatting

	private function SendLoreNotifications(loreType:Number, categorizationId:Number, dynel:Dynel) {
		var messageStrings:Array = GetMessageStrings(loreType, dynel.GetStat(e_Stats_LoreId, 2), dynel, categorizationId);
		var detailStrings:Array = GetDetailStrings(loreType, dynel);
		DispatchMessages(messageStrings, loreType, detailStrings, categorizationId);
	}

	// Index:
	// 0: Fifo message
	// 1: System chat message
	// 2: Mail report
	// 3: Log encoding
	private function GetMessageStrings(loreType:Number, loreId:Number, dynel:Dynel, categorizationId:Number):Array {
		var loreName:String = AttemptIdentification(loreId, loreType, categorizationId);
		var messageStrings:Array = new Array();
		switch (loreType) {
			case ef_LoreType_Placed:
				messageStrings.push("Lore (" + loreName + ") nearby");
				messageStrings.push("Common lore nearby (" + loreName + ")");
				break;
			case ef_LoreType_Trigger:
				messageStrings.push("Lore (" + loreName + ") has appeared");
				messageStrings.push("Triggered lore nearby (" + loreName + ")");
				break;
			case ef_LoreType_Drop:
				messageStrings.push("Lore (" + loreName + ") dropped");
				messageStrings.push("Dropped lore nearby (" + loreName + ")");
				break;
			case ef_LoreType_Despawn:
				messageStrings.push("Lore (" + loreName + ") despawned");
				messageStrings.push("Lore despawned or out of range (" + loreName + ")");
				break;
			case ef_LoreType_Unknown:
				messageStrings.push("Lore (" + loreName + ") needs cataloguing");
				messageStrings.push("Unknown lore detected (" + loreName + ")");
				break;
			default:
				// It should be impossible for the game data to trigger this state
				// This message probably indicates a logical failure in the mod
				messageStrings.push("Error, lore type defaulted: " + loreType);
				messageStrings.push("Error, lore type defaulted: " + loreType);
				break;
		}
		messageStrings.push("Category: " + loreType + " (" + loreName + ")"); // Report string
		if (DumpToLog && dynel != undefined) {
			var pos:Vector3 = dynel.GetPosition(0);
			var posStr:String = "[" + Math.round(pos.x) + "," + Math.round(pos.z) + "," + Math.round(pos.y) + "]";
			messageStrings.push("C:" + loreType + ";ID:" + loreId + ";PF:" + dynel.GetPlayfieldID() + ";" + posStr);
		}
		return messageStrings;
	}

	// Jackpot!! Connects dynels to LoreNode entries and the rest of the Lore interface:
	// m_Name: Empty for our node, but the parent will contain the topic
	// m_Type: LoreNodes aren't just lore, they also do achivements, mounts, teleports... (this will be 2, not so useful)
	// m_Locked: Has this node been picked up yet?
	// m_Parent/m_Children: Navigate the lore tree
	// Lore.IsVisible(id): Unsure, still doesn't seem to be related to unlocked state
	// Lore.GetTagViewpoint(id): 0 is Buzzing, 1 is Black Signal (both are m_Children for a single topic)
	private static function AttemptIdentification(loreId:Number, loreType:Number, categorizationId:Number):String {
		if (loreId != 0) {
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
					// Consider setting up a report here, with LoreID as tag
					// Low probability of it actually occuring, but knowing sooner rather than later might be nice
					catCode = " ?#";
					TraceMsgS("Lore has unknown voice: " + loreSource);
					break;
			}
			var parentNode:LoreNode = loreNode.m_Parent;
			var priorSiblings:Number = 1; // Most people number based on type and from a base of 1
			for (var i:Number = 0; i < parentNode.m_Children.length; ++i) {
				var childId:Number = parentNode.m_Children[i].m_Id;
				if (childId == loreId) {
					return parentNode.m_Name + catCode + priorSiblings;
				}
				if (Lore.GetTagViewpoint(childId) == loreSource) {
					++priorSiblings;
				}
			}
			TraceMsgS("Unknown topic or entry #, malformed lore ID: " + loreId);
			return "Invalid lore ID";
		}
		// Deal with any that are missing data
		switch (loreType) {
			case ef_LoreType_Placed:
				// All the unidentified common lore I ran into matched up with event/seasonal lore
				// Though not all the event/seasonal lore exists in this disabled state
				// For lore in accessible locations (ie, not event instances):
				// - Samhain lores seem to be mostly absent (double checked in light of Polaris drone... really seems to be absent)
				// - Other event lores seem to be mostly present
				// (There are, of course, exceptions)
				return "Inactive " + (categorizationId == c_ShroudedLoreCategory ? "shrouded lore" : "event lore");
			default:
				// Lore drops occasionally fail to completely load before they're detected, but usually succeed on second detection
				// The only reason to see this now is if the automatic redetection system failed
				return "Incomplete data, rescan failed";
		}
	}

	// This info is ommitted from FIFO messages
	// Unknown lore always requests some info for identification purposes
	private function GetDetailStrings(loreType:Number, dynel:Dynel):Array {
		var details:Number = Config.GetValue("Details");
		var detailStrings:Array = new Array();

		if (loreType == ef_LoreType_Unknown || (details & ef_Details_Location) == ef_Details_Location) {
			// Not entirely clear on what the "attractor" parameter is for
			// Current hypothesis is that it's related to focusing on different parts of a dynel ie: hands may have different coordinates from face
			// Leaving it at 0 causes results to match world coordinates reported through other means (shift F9, topbars)
			// Y is being listed last because it's the vertical component, and most concern themselves with map coordinates (x,z)
			var pos:Vector3 = dynel.GetPosition(0);
			detailStrings.push(LDBFormat.LDBGetText("Playfieldnames", dynel.GetPlayfieldID()) + " (" + Math.round(pos.x) + ", " + Math.round(pos.z) + ", " + Math.round(pos.y) + ")");
		}
		if (loreType == ef_LoreType_Unknown || (details & ef_Details_FormatString) == ef_Details_FormatString) {
			var formatStr:String = dynel.GetName();
			// Strip off (seemingly) unimportant info and reformat to something more meaningful in this context
			var ids:Array = formatStr.substring(formatStr.indexOf('id="')).split(' ', 2);
			for (var i:Number = 0; i < ids.length; ++i) {
				var str = ids[i];
				ids[i] = str.substring(str.indexOf('"') + 1, str.length - 1);
			}
			detailStrings.push("Category ID: " + ids[0] + " Supergroup: " + ids[1]);
		}
		if ((details & ef_Details_DynelId) == ef_Details_DynelId) {
			detailStrings.push("Dynel ID: " + dynel.GetID().toString());
		}
		if ((details & ef_Details_StatDump) == ef_Details_StatDump) {
			// Fishing expedition, trying to find anything potentially useful
			detailStrings.push("Stat Dump: Mode " + DetailStatMode);
			var start:Number = (DetailStatRange - 1) * 1000000;
			var end:Number = DetailStatRange * 1000000;
			for (var statID:Number = start; statID < end; ++statID) {
				var val = dynel.GetStat(statID, DetailStatMode);
				if (val != 0) { // I think this only returns numbers, might be interesting to be proven wrong
					detailStrings.push("Stat: #" + statID + " Value: " + val);
				}
			}
		}
		return detailStrings;
	}

	private function DispatchMessages(messageStrings:Array, loreType:Number, detailStrings:Array, categorizationId:Number):Void {
		if ((Config.GetValue("FifoLevel") & loreType) == loreType) {
			Chat.SignalShowFIFOMessage.Emit(messageStrings[0], 0);
			}
		if ((Config.GetValue("ChatLevel") & loreType) == loreType) {
			ChatMsg(messageStrings[1], false, (Config.GetValue("Details") & ef_Details_Timestamp) == ef_Details_Timestamp);
			for (var i:Number = 0; i < detailStrings.length; ++i) {
				ChatMsg(detailStrings[i], true);
			}
		}
		if (loreType == ef_LoreType_Unknown) { // Auto report handles own enabled state
			var report:String = messageStrings[2];
			if (detailStrings.length > 0) {	report += "\n" + detailStrings.join("\n"); }
			ReportManager.AddReport({ id: categorizationId, text: report });
		}
		if (DumpToLog && messageStrings.length > 3) {
			LogMsg(messageStrings[3]);
			// Relevant details are already embedded
		}
	}

	/// Variables
	private static var e_DynelType_Object:Number = 51320; // All known lore shares this dynel type with a wide variety of other props
	private static var e_Stats_LoreId:Number = 2000560; // Most lore dynels seem to store the LoreId at this stat index, those that don't are either not fully loaded, or event related
	private static var c_ShroudedLoreCategory:Number = 7993128; // Keep ending up with special cases for this particular one

	// When doing a stat dump, use/change these parameters to determine the range of the stats to dump
	// It will dump the Nth million stat ids, with the mode parameter provided
	// Tradeoff between the length of time locked up, and the number of tests needed
	private var DumpToLog:Boolean;
	private var DetailStatRange:Number;
	private var DetailStatMode:Number;

	private var TrackedLore:Object;

	// When compiling reports for the automated report system consider the following options for IDs
	// Categorization ID: This one is currently being used to report on unknown lore groups (Range estimated to be [7...10] million)
	// Lore ID: If a particular lore needs to be flagged for some reason, this is a reasonable choice if available (Range estimated to be [400...1000])
	// Dynel ID: Not ideal, range is all over the place, doesn't uniquely identify a specific entry
	// Playfield ID and location: Good for non-drop lores (and not terrible for them as the drop locations are usually predictible), formatting as an id might be a bit tricky
	private var ReportManager:AutoReport;
}
