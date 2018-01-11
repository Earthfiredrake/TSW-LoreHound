// Copyright 2017, Earthfiredrake (Peloprata)
// Released under the terms of the MIT License
// https://github.com/Earthfiredrake/TSW-LoreHound

import flash.geom.Point;

import gfx.utils.Delegate;

import com.GameInterface.Dynels;
import com.GameInterface.Game.Character;
import com.GameInterface.Game.Dynel;
import com.GameInterface.Lore;
import com.GameInterface.LoreNode;
import com.GameInterface.MathLib.Vector3;
import com.GameInterface.VicinitySystem;
import com.GameInterface.Waypoint;
import com.GameInterface.WaypointInterface;
import GUI.Waypoints.CustomWaypoint;
import com.Utils.Archive; // DEPRECATED(v1.1.0.alpha): Required for bugfix that corrects forgetting AutoReport settings
import com.Utils.ID32;
import com.Utils.LDBFormat;

import efd.LoreHound.lib.AutoReport;
import efd.LoreHound.lib.ConfigWrapper;
import efd.LoreHound.lib.LocaleManager;
import efd.LoreHound.lib.Mod;

import efd.LoreHound.LoreData;

class efd.LoreHound.LoreHound extends Mod {
	private var ModInfo:Object = {
		// Dev/debug settings at top so commenting out leaves no hanging ','
		// Trace : true,
		Name : "LoreHound",
		Version : "1.3.2",
		Type : e_ModType_Reactive,
		MinUpgradableVersion : "1.0.0",
		IconData : { GetFrame : GetIconFrame,
					 ExtraTooltipInfo : IconTooltip }
	};

	// Category flags for extended information
	private static var ef_Details_None:Number = 0;
	public static var ef_Details_Location:Number = 1 << 0; // Playfield name and coordinate vector
	public static var ef_Details_FormatString:Number = 1 << 1; // Trimmed contents of format string, to avoid automatic evaluation
	public static var ef_Details_DynelId:Number = 1 << 2;
	public static var ef_Details_Timestamp:Number = 1 << 3;
	private static var ef_Details_StatDump:Number = 1 << 4; // Repeatedly calls Dynel.GetStat() (limited by the constant below), recording any stat which is not 0 or undefined
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
		DetailStatRange = 1; // Start with the first million
		DetailStatMode = 2; // Defaulting to mode 2 based on repeated comments in game source that it is somehow "full"
		SystemsLoaded.CategoryIndex = false;

		TrackedLore = new Object();
		WaypointSystem = _root.waypoints;
		WaypointInterface.SignalPlayfieldChanged.Connect(ClearTracking, this);

		var arConfig:ConfigWrapper = AutoReport.Initialize(ModName, Version, DevName);

		InitializeConfig(arConfig);

		IndexFile = LoadXmlAsynch("CategoryIndex", Delegate.create(this, CategoryIndexLoaded));

		TraceMsg("Initialized");
	}

	// TODO: Some reports of settings being lost, reverting to defaults (v1.2.2). Investigate further for possible causes

	private function InitializeConfig(arConfig:ConfigWrapper):Void {
		// Notification types
		Config.NewSetting("FifoLevel", LoreData.ef_LoreType_None); // DEPRECATED(v1.2.0.alpha) : Renamed
		Config.NewSetting("ChatLevel", LoreData.ef_LoreType_Drop | LoreData.ef_LoreType_Uncategorized); // DEPRECATED(v1.2.0.alpha) : Renamed

		// Renaming and expanding options for v1.2
		Config.NewSetting("FifoAlerts", LoreData.ef_LoreType_None); // FIFO onscreen alerts
		Config.NewSetting("ChatAlerts", LoreData.ef_LoreType_All ^ LoreData.ef_LoreType_Despawn); // System chat alerts
		Config.NewSetting("WaypointAlerts", LoreData.ef_LoreType_All ^ LoreData.ef_LoreType_Despawn); // Display onscreen waypoints for lore
		Config.NewSetting("AlertForCollected", LoreData.ef_LoreType_Drop | LoreData.ef_LoreType_Uncategorized); // Alert the player for lore they already have
		Config.NewSetting("AlertForUncollected", LoreData.ef_LoreType_All ^ LoreData.ef_LoreType_Despawn); // Alert the player for lore they haven't picked up yet

		Config.NewSetting("IgnoreUnclaimedLore", true); // DEPRECATED(v1.2.0.alpha) : Renamed and expanded
		Config.NewSetting("IgnoreOffSeasonLore", true); // Ignore event lore if the event isn't running
		Config.NewSetting("TrackDespawns", true); // Track timed lore comb drops, and notify when they despawn
		Config.NewSetting("ShowWaypoints", true); // DEPRECATED(v1.2.0.alpha) : Renamed and expanded
		Config.NewSetting("CheckNewContent", false); // DEPRECATED(v1.1.0.alpha): Renamed
		Config.NewSetting("ExtraTesting", false); // Does extra tests to detect lore that isn't on the index list at all yet (ie: new content!)
		Config.NewSetting("CartographerLogDump", false); // Dumps detected lore to the log file in a format which can easilly be extracted for Cartographer waypoint files
		Config.NewSetting("WaypointColour", 0xFFAA00); // Colour of onscreen waypoints

		// Extended information, regardless of this setting:
		// - Is always ommitted from Fifo notifications, to minimize spam
		// - Some fields are always included when detecting uncategorized lore, to help identify it
		Config.NewSetting("Details", ef_Details_Location | ef_Details_Timestamp);

		arConfig.SignalValueChanged.Connect(AutoReportConfigChanged, this);
		Config.NewSetting("AutoReport", arConfig);
	}

	private function AutoReportConfigChanged(setting:String, newValue, oldValue):Void {
		switch(setting) {
			case "Enabled":
			case "QueuedReports":
				Icon.Refresh();
				break;
			default: break;
		}
	}

	/// Mod framework extensions and overrides
	private function ConfigChanged(setting:String, newValue, oldValue):Void {
		switch(setting) {
			case "WaypointAlerts":
				if (newValue) {
					var addedTypes:Number = newValue & ~oldValue;
					var removedTypes:Number = oldValue & ~newValue;
					for (var key:String in TrackedLore) {
						var lore:LoreData = TrackedLore[key];
						if (addedTypes & lore.Type) { CreateWaypoint(lore.DynelInst, AttemptIdentification(lore)); }
						if (removedTypes & lore.Type) { RemoveWaypoint(lore.DynelID); }
					}
				} else { ClearWaypoints(); }
				break;
			case "AlertForCollected":
			case "AlertForUncollected":
				var addedTypes:Number = newValue & ~oldValue;
				// var removedTypes:Number = oldValue & ~newValue;
				for (var key:String in TrackedLore) {
					var lore:LoreData = TrackedLore[key];
					if (lore.IsKnown == (setting == "AlertForCollected")
						&& Config.GetValue("WaypointAlerts") & lore.Type) {
							if (addedTypes & lore.Type) { CreateWaypoint(lore.DynelInst, AttemptIdentification(lore)); }
							// if (removedTypes & lore.Type) { RemoveWaypoint(lore.DynelID); }
							// Waypoints to remove should automatically do so during the next refresh cycle
					}
				}
				break;
			case "WaypointColour":
				// TODO: This is spamming the screen with stray waypoints whenever it changes
				// Possibly because it's not having time to clear the existing waypoint before a new one registers overtop
				//ClearWaypoints();
				//for (var key:String in TrackedLore) {
					//var lore:LoreData = TrackedLore[key];
					// if (Config.GetValue("WaypointAlerts") & lore.Type) { CreateWaypoint(lore.DynelInst, AttemptIdentification(lore)); }
				//}
				break;
			default:
				super.ConfigChanged(setting, newValue, oldValue);
				break;
		}
	}

	private function CategoryIndexLoaded(success:Boolean):Void {
		if (success) {
			CategoryIndex = new Array();
			var xmlRoot:XMLNode = IndexFile.firstChild;
			for (var i:Number = 0; i < xmlRoot.childNodes.length; ++i) {
				var categoryXML:XMLNode = xmlRoot.childNodes[i];
				var category:Number = LoreData["ef_LoreType_" + categoryXML.attributes.name];
				for (var j:Number = 0; j < categoryXML.childNodes.length; ++j) {
					var dynelXML:XMLNode = categoryXML.childNodes[j];
					var indexEntry:Object = {type : category, loreID : dynelXML.attributes.loreID, excluding : new Array()};
					for (var k:Number = 0; k < dynelXML.childNodes.length; ++k) {
						var exclusionXML:XMLNode = dynelXML.childNodes[k];
						indexEntry.excluding[exclusionXML.attributes.loreID] = LoreData["ef_LoreType_" + exclusionXML.attributes.category];
					}
					CategoryIndex[dynelXML.attributes.value] = indexEntry;
				}
			}
			delete IndexFile;
			TraceMsg("Lore category data loaded");
			SystemsLoaded.CategoryIndex = true;
			CheckLoadComplete();
		} else {
			// Loading is asynchronous, not localized
			// Currently localization appears to load first, but I won't count on it
			// There's also the possibility that it also failed to load
			// Could check SystemsLoaded, but seems excessive for what should be a disabled state
			ErrorMsg("Failed to load category index");
			ErrorMsg("Mod cannot be enabled", { noPrefix : true });
			Config.SetValue("Enabled", false);
		}
	}

	private function IsCategorizedLore(categoryId:Number):Boolean {
		var category:Number = ClassifyID(categoryId);
		return category != LoreData.ef_LoreType_Uncategorized && category != LoreData.ef_LoreType_None;
	}

	private function UpdateMod(newVersion:String, oldVersion:String):Void {
		// Minimize settings clutter by purging auto-report records of newly categorized IDs
		AutoReport.CleanupReports(IsCategorizedLore);

		// Version specific updates
		//   Some upgrades may reflect unreleased builds, for consistency on develop branch
		if (CompareVersions("1.1.0.alpha", oldVersion) > 0) {
			// Renaming setting due to recent events
			Config.SetValue("ExtraTesting", Config.GetValue("CheckNewContent"));
			// May have lost the config settings for the auto report system :(
			if (Config.GetValue("AutoReport") instanceof Archive) {
				Config.SetValue("AutoReport", Config.GetDefault("AutoReport"));
				ChatMsg(LocaleManager.GetString("Patch", "AutoReportRepair"));
			}
		}
		if (CompareVersions("1.2.0.alpha", oldVersion) > 0) {
			// Rename *level settings to *alert
			Config.SetValue("FifoAlerts", Config.GetValue("FifoLevel"));
			Config.SetValue("ChatAlerts", Config.GetValue("ChatLevel"));
			// Copy waypoint settings to new per-category setting
			var existingAlerts = Config.GetValue("FifoLevel") | Config.GetValue("ChatLevel");
			Config.SetValue("WaypointAlerts", (Config.GetValue("ShowWaypoints") ? existingAlerts : LoreData.ef_LoreType_None));
			// Copy unclaimed lore to per-category setting (no existing setting for claimed lore)
			Config.SetValue("AlertForUncollected", (Config.GetValue("IgnoreUnclaimedLore") ? LoreData.ef_LoreType_Uncategorized : LoreData.ef_LoreType_All - LoreData.ef_LoreType_Despawn));
		}
	}

	private function LoadComplete():Void {
		super.LoadComplete();
		Config.DeleteSetting("CheckNewContent"); // DEPRECATED(v1.1.0.alpha): Renamed
		Config.DeleteSetting("FifoLevel"); // DEPRECATED(v1.2.0.alpha) : Renamed
		Config.DeleteSetting("ChatLevel"); // DEPRECATED(v1.2.0.alpha) : Renamed
		Config.DeleteSetting("ShowWaypoints"); // DEPRECATED(v1.2.0.alpha) : Renamed
		Config.DeleteSetting("IgnoreUnclaimedLore"); // DEPRECATED(v1.2.0.alpha) : Renamed
	}

	private function Activate():Void {
		AutoReport.IsEnabled = true; // Only updates this component's view of the mod state
		HostMovie.onEnterFrame = Delegate.create(this, UpdateWaypoints);
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
		delete HostMovie.onEnterFrame;
		AutoReport.IsEnabled = false; // Only updates this component's view of the mod state
	}

	private function GetIconFrame():String {
		if (Config.GetValue("Enabled")) { // If game disables mod, icon isn't visible at all, so only user disables matter
			if (Config.GetValue("TrackDespawns")) {
				for (var id:String in TrackedLore) {
					if (TrackedLore[id].Type == LoreData.ef_LoreType_Drop) { return "alerted"; }
				}
			}
			if (AutoReport.NumReportsPending > 0) {	return "reporting";	}
			return "active";
		} else { return "inactive"; }
	}

	private function IconTooltip():String {
		var strings:Array = new Array();
		if (Config.GetValue("TrackDespawns")) {
			for (var id:String in TrackedLore) {
				if (TrackedLore[id].Type == LoreData.ef_LoreType_Drop) {
					if (strings.length == 0) { strings.push(LocaleManager.GetString("GUI", "TooltipTracking")); }
					strings.push("  " + AttemptIdentification(TrackedLore[id]));
				}
			}
		}
		if (AutoReport.NumReportsPending > 0) { strings.push(LocaleManager.FormatString("GUI", "TooltipReports", AutoReport.NumReportsPending)); }
		return strings.length > 0 ? strings.join('\n') : undefined;
	}

	// Override to add timestamps
	//   forceTimestamp property added to options
	private function _ChatMsg(message:String, options:Object):Void {
		var timestamp:String = "";
		if (options.forceTimestamp) {
			var time:Date = new Date();
			timestamp = LocaleManager.FormatString("LoreHound", "TimestampInfo", time.getHours(), time.getMinutes());
		}
		// Currently there is no allowance for attaching yet more additional parameters
		super._ChatMsg(message, options, timestamp);
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
	//   GetID() - The ID type seems to be constant (51320) for all lore, but is shared with a wide variety of other props (simple dynels)
	//       Other types:
	//         50000 - used by all creatures (players, pets, npcs, monsters, etc.)
	//         51321 - destructibles (according to global enums)
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
	//     #12 - Consistently 7456524 across most lore dynels (including black signal)
	//           It is not assigned for triggered lore that is placed invisibly...
	//           Unless a trigger is found that can proc on this value changing, it won't be particularly useful with lore detection
	//           Further testing suggests it might be related to the model id
	//           Can be used to determine colour of Dead Scarabs and spawn state of Bits of Joe
	//     #23 and #112 - Copies of the format string ID #, matching values used in ClassifyID
	//     #1050 - Unknown, usually 6 on lore, though other numbers have been observed (1 on scarabs)
	//     #1102 - Copy of the Dynel instance identifier (dynelId.m_Instance)
	//     #1374 - OverrideCursor, used for categorizing the Reticule interaction prompt (See CrosshairController)
	//             New for SWL, Scarabs have value of 26, a couple lore samples have a value of 45, a bit of joe was 35
	//     #2000560 - Exists on a massive majority of the lore recently observed:
	//                - Missing from all Shrouded Lore and other inactive event lore (lore for active events has this value)
	//                - Sometimes fails to load before a dropped lore triggers the detection, a few quick retries is usually enough time for it to load
	//              - Tag # matching db entries labled "Lore#.Tag#", outside of api access but still very useful info (Thanks Vomher)
	//              - ID number for the lore entry in the journal!
	//              - Seems to be tied to "Lore"Nodes in general, as it also appears on Champ mobs, with their achivement ID
	//     Character and monster dynels have many more values specified, and further analysis is progressing as I find the need
	//     The function seems to be related to the enum _global.Stat, but most of the indices that actually come up are unspecified
	//       - The only matching value is 1050, mapping to "CarsGroup", whatever that is.
	//       - There are a number of other values in the 2 million range, though none matching 560
	//     Unlisted values and missing IDs return 0
	//     Testing unclaimed lore with alts did not demonstrate any notable differences in the reported stats

	/// Lore detection and sorting
	private function LoreSniffer(dynelId:ID32):Void {
		if (dynelId.m_Type != _global.Enums.TypeID.e_Type_GC_SimpleDynel) { return; } // Dynel is not of supertype associated with lore combs
		if (TrackedLore[dynelId.toString()]) { return; }

		var dynel:Dynel = Dynel.GetDynel(dynelId);
		var categorizationId:Number = LoreData.GetFormatStrID(dynel);

		// Categorize the detected item
		var loreType:Number = ClassifyID(categorizationId);
		if (loreType == LoreData.ef_LoreType_None) {
			if (Config.GetValue("ExtraTesting") && ExpandedDetection(dynel)) { loreType = LoreData.ef_LoreType_Uncategorized; } // It's so new it hasn't been added to the index list yet
			else { return; } // Dynel is not lore
		}

		ProcessAndNotify(new LoreData(dynel, categorizationId, loreType, CategoryIndex[categorizationId].loreID), 0);
	}

	// Callback for timeout delegate if loreId is uninitialized
	private function ProcessAndNotify(lore:LoreData, repeat:Number):Void {
		if (TryConfirmLoreID(lore, repeat) && FilterLore(lore)) {
			SendLoreNotifications(lore);
		}
		var dynelId:ID32 = lore.DynelID;
		TrackedLore[dynelId.toString()] = lore;
		// Registers despawn callback for lore tracking systems (spam reduction, waypoint cleanup and despawn notifications)
		// _global.enums.Property.e_ObjScreenPos seems like it would be more useful, and returns the same value :(
		// Can't tell if it actually updates the value on a regular basis... as lore doesn't move
		Dynels.RegisterProperty(dynelId.m_Type, dynelId.m_Instance, _global.enums.Property.e_ObjPos);
		Icon.Refresh();
	}

	private function TryConfirmLoreID(lore:LoreData, repeat:Number):Boolean {
		// Passthrough on valid lore ID, placed event lore, or if several retries all fail
		if (lore.LoreID) {
			// Reclassify based on ID#, in case it's a lore that detects as the wrong type
			lore.Type = ClassifyID(lore.CategorizationID, lore.LoreID);
			return true;
		} else if (lore.Type == LoreData.ef_LoreType_Placed ||
			repeat > 5) { return true; }
		setTimeout(Delegate.create(this, ProcessAndNotify), 1, lore, repeat + 1);
		return false;
	}

	private function FilterLore(lore:LoreData):Boolean {
		// Only process special items that are currently spawned
		if (lore.Type == LoreData.ef_LoreType_SpecialItem &&
			!lore.DynelInst.GetStat(12, 2)) {
			return false;
		}

		// Filters lore based on user notification settings
		if (lore.LoreID == 0) {
			if (lore.Type == LoreData.ef_LoreType_Placed) { // Most likely inactive event lore
				if (Config.GetValue("IgnoreOffSeasonLore")) { return false; }
			} else { // Persisting partial initialization
				TraceMsg("LoreID not available, limiting analysis");
			}
		} else { // Tests require a valid LoreID
			if (lore.IsKnown) {
				if (!(lore.Type & Config.GetValue("AlertForCollected"))) { return false; }
			} else {
				if (!(lore.Type & Config.GetValue("AlertForUncollected"))) { return false; }
			}
		}
		// Pass conditions
		if ((Config.GetValue("FifoAlerts") & lore.Type) ||
			(Config.GetValue("ChatAlerts") & lore.Type) ||
			(Config.GetValue("WaypointAlerts") & lore.Type) ||
			(lore.Type == LoreData.ef_LoreType_Uncategorized && AutoReport.IsEnabled) ||
			Config.GetValue("CartographerLogDump")){ return true; }

		// No notifications are to be made
		return false;
	}

	/// Lore proximity tracking

	// Triggers when the lore dynel is removed from the client, either because it has despawned or the player has moved too far away
	// With no dynel to query, all required info has to be known values or cached
	private function LoreDespawned(type:Number, instance:Number):Void {
		var despawnedId:String = new ID32(type, instance).toString();
		var lore:LoreData = TrackedLore[despawnedId];
		if (lore) { // Ensure the despawned dynel was tracked by this mod
			lore.Type |= LoreData.ef_LoreType_Despawn; // Set the despawn flag

			if (Config.GetValue("WaypointAlerts") & lore.Type) { RemoveWaypoint(lore.DynelID); }
			// Despawn notifications
			if ((lore.Type & LoreData.ef_LoreType_Drop) && Config.GetValue("TrackDespawns")) {
				if (FilterLore(lore)) { // Despawn notifications are subject to same filters as regular ones
					var messageStrings:Array = GetMessageStrings(lore);
					DispatchMessages(messageStrings, lore); // No details or raw categorizationID
				}
			}
			delete TrackedLore[despawnedId];
			Icon.Refresh();
		}
	}

	private function ClearTracking():Void {
		// Don't need to clear waypoints, playfield change resets waypoint interface
		delete TrackedLore;
		TrackedLore = new Object();
		Icon.Refresh();
	}

	/// Lore identification
	// Much of the primary categorization info is now contained in the xml data file
	private function ClassifyID(categorizationId:Number, loreId:Number):Number {
		var indexEntry:Object = CategoryIndex[categorizationId];
		var category:Number = indexEntry.excluding[loreId] ?
			indexEntry.excluding[loreId] :
			indexEntry.type;
		return category ? category : LoreData.ef_LoreType_None;
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
	private function SendLoreNotifications(lore:LoreData):Void {
		var messageStrings:Array = GetMessageStrings(lore);
		var detailStrings:Array = GetDetailStrings(lore);
		DispatchMessages(messageStrings, lore, detailStrings);
	}

	// Index:
	// 0: Fifo message
	// 1: System chat message
	// 2: Mail report
	// 3: Log encoding
	private function GetMessageStrings(lore:LoreData):Array {
		var loreName:String = AttemptIdentification(lore);
		var messageStrings:Array = new Array();
		var typeString:String;
		if (lore.Type & LoreData.ef_LoreType_Despawn) {
			typeString = "Despawn";
		} else {
			switch (lore.Type) {
				case LoreData.ef_LoreType_Placed:
					typeString = "Placed";
					break;
				case LoreData.ef_LoreType_Trigger:
					typeString = "Trigger";
					break;
				case LoreData.ef_LoreType_Drop:
					typeString = "Drop";
					break;
				case LoreData.ef_LoreType_Uncategorized:
					typeString = "Uncategorized";
					break;
				case LoreData.ef_LoreType_SpecialItem:
					typeString = "SpecialItem";
					break;
				default:
					// It should be impossible for the game data to trigger this state
					// This message probably indicates a logical failure in the mod
					TraceMsg("Error, lore type defaulted: " + lore.Type);
					return;
			}
		}
		messageStrings.push(loreName); // For waypoints
		messageStrings.push(LocaleManager.FormatString("LoreHound", typeString + "Fifo", loreName));
		messageStrings.push(LocaleManager.FormatString("LoreHound", typeString + "Chat", loreName));
		if (!(lore.Type & LoreData.ef_LoreType_Despawn)) {
		// No Dynel data on despawn, and initial detection should have left a log record
			if (lore.Type == LoreData.ef_LoreType_Uncategorized) {
				var reportStrings:Array = new Array();
				// TODO: Strip customization/localization from debug systems
				//   loreName still uses custom strings
				reportStrings.push("Category: " + lore.Type + " (" + loreName + ")"); // Report string
				var dynel:Dynel = lore.DynelInst;
				var pos:Vector3 = dynel.GetPosition(0);
				reportStrings.push(LDBFormat.LDBGetText("Playfieldnames", dynel.GetPlayfieldID()) + " (" + Math.round(pos.x) + "," + Math.round(pos.z) + "," + Math.round(pos.y) + ")");
				reportStrings.push("Category ID: " + lore.CategorizationID);
				messageStrings.push(reportStrings.join('\n'));
			}
			if (Config.GetValue("CartographerLogDump")) {
				var dynel:Dynel = lore.DynelInst;
				var pos:Vector3 = dynel.GetPosition(0);
				var posStr:String = 'x="'+ Math.round(pos.x) + '" y="' + Math.round(pos.z) + '" z="' + Math.round(pos.y) + '"';
				messageStrings.push('<!-- ' + AttemptIdentification(lore) + ' --> <Lore zone="' + dynel.GetPlayfieldID() + '" ' + posStr + ' loreID="' + lore.LoreID + '" />');
			}
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
	private static function AttemptIdentification(lore:LoreData):String {
		if (lore.Type == LoreData.ef_LoreType_SpecialItem) {
			// Special items contain the lore ID (for filtering purposes), but should use the default dynel name for reporting purposes
			// Some have additional logic to further differentiate them
			if (lore.CategorizationID == 9240620) { // Dead Scarab
				var scarabColour:String;
				switch (lore.DynelInst.GetStat(12, 2)) {
					case 9240634: scarabColour = "ScarabColourBlack"; break;
					case 9240632: scarabColour = "ScarabColourGreen"; break;
					case 9240636: scarabColour = "ScarabColourRed"; break;
					default:
						TraceMsg("Scarab colour filter failure!");
						return LDBFormat.Translate(lore.DynelInst.GetName());
				}
				return LocaleManager.FormatString("LoreHound", scarabColour, LDBFormat.Translate(lore.DynelInst.GetName()));
			}
			return LDBFormat.Translate(lore.DynelInst.GetName());
		}

		if (lore.LoreID) {
			var topic:String = lore.Topic;
			var index:Number = lore.Index;
			if (!(topic && index)) {
				TraceMsg("Unknown topic or entry #, malformed lore ID: " + lore.LoreID);
				return LocaleManager.GetString("LoreHound", "InvalidLoreID");
			}
			var catCode:String;
			switch (lore.Source) {
				case 0: // Buzzing
					catCode = LocaleManager.GetString("LoreHound", "BuzzingSource");
					break;
				case 1: // Black Signal
					catCode = LocaleManager.GetString("LoreHound", "BlackSignalSource");
					break;
				default: // Unknown source
					// Consider setting up a report here, with LoreID as tag
					// Low probability of it actually occuring, but knowing sooner rather than later might be nice
					catCode = LocaleManager.GetString("LoreHound", "UnknownSource");
					TraceMsg("Lore has unknown source: " + lore.Source);
					break;
			}
			return LocaleManager.FormatString("LoreHound", "LoreName", topic, catCode, index);
		}

		// Deal with missing IDs
		switch (lore.Type) {
			case LoreData.ef_LoreType_Placed:
				// All the unidentified common lore I ran into matched up with event/seasonal lore
				// Though not all the event/seasonal lore exists in this disabled state
				// For lore in accessible locations (ie, not event instances):
				// - Samhain lores seem to be mostly absent (double checked in light of Polaris drone... really seems to be absent)
				// - Other event lores seem to be mostly present
				// (There are, of course, exceptions)
				return LocaleManager.GetString("LoreHound", lore.CategorizationID == c_ShroudedLoreCategory ? "InactiveShrouded" : "InactiveEvent");
			default:
				// Lore drops occasionally fail to completely load before they're detected, but usually succeed on second detection
				// The only reason to see this now is if the automatic redetection system failed
				return LocaleManager.GetString("LoreHound", "IncompleteDynel");
		}
	}

	// This info is ommitted from FIFO messages
	// Uncategorized lore always requests some info for identification purposes
	private function GetDetailStrings(lore:LoreData):Array {
		var details:Number = Config.GetValue("Details");
		if (lore.Type == LoreData.ef_LoreType_Uncategorized) {
			details |= ef_Details_Location | ef_Details_FormatString;
		}
		var detailStrings:Array = new Array();

		var dynel:Dynel = lore.DynelInst;
		if (details & ef_Details_Location) {
			// Not entirely clear on what the "attractor" parameter is for
			// Current hypothesis is that it's related to focusing on different parts of a dynel ie: hands may have different coordinates from face
			// Leaving it at 0 causes results to match world coordinates reported through other means (shift F9, topbars)
			// Y is being listed last because it's the vertical component, and most concern themselves with map coordinates (x,z)
			var pos:Vector3 = dynel.GetPosition(0);
			var playfield:String = LDBFormat.LDBGetText("Playfieldnames", dynel.GetPlayfieldID());
			detailStrings.push(LocaleManager.FormatString("LoreHound", "PositionInfo", playfield, Math.round(pos.x), Math.round(pos.y), Math.round(pos.z)));
		}
		if (details & ef_Details_FormatString) {
			var formatStr:String = dynel.GetName();
			// Strip off (seemingly) unimportant info and reformat to something more meaningful in this context
			var ids:Array = formatStr.substring(formatStr.indexOf('id="')).split(' ', 2);
			for (var i:Number = 0; i < ids.length; ++i) {
				var str = ids[i];
				ids[i] = str.substring(str.indexOf('"') + 1, str.length - 1);
			}
			detailStrings.push(LocaleManager.FormatString("LoreHound", "CategoryInfo", ids[0], ids[1]));
		}
		if (details & ef_Details_DynelId) {
			detailStrings.push(LocaleManager.FormatString("LoreHound", "InstanceInfo", dynel.GetID().toString()));
		}
		if (details & ef_Details_StatDump) {
			// Fishing expedition, trying to find anything potentially useful
			// Dev/debug only, does not need localization
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

	private function DispatchMessages(messageStrings:Array, lore:LoreData, detailStrings:Array):Void {
		if ((Config.GetValue("WaypointAlerts") & lore.Type) && !(lore.Type & LoreData.ef_LoreType_Despawn)) {
			CreateWaypoint(lore.DynelInst, messageStrings[0]);
		}
		if (Config.GetValue("FifoAlerts") & lore.Type) {
			FifoMsg(messageStrings[1]);
		}
		if (Config.GetValue("ChatAlerts") & lore.Type) {
			ChatMsg(messageStrings[2], { forceTimestamp : (Config.GetValue("Details") & ef_Details_Timestamp) });
			for (var i:Number = 0; i < detailStrings.length; ++i) {
				ChatMsg(detailStrings[i], { noPrefix : true });
			}
		}
		if (lore.Type == LoreData.ef_LoreType_Uncategorized) { // Auto report handles own enabled state
			// When compiling reports for the automated report system consider the following options for IDs
			// Categorization ID: This one is currently being used to report on uncategorized lore groups (Range estimated to be [7...10] million)
			// Lore ID: If a particular lore needs to be flagged for some reason, this is a reasonable choice if available (Range estimated to be [400...1000])
			// Dynel ID: Not ideal, range is all over the place, doesn't uniquely identify a specific entry
			// Playfield ID and location: Good for non-drop lores (and not terrible for them as the drop locations are usually predictible), formatting as an id might be a bit tricky
			AutoReport.AddReport({ id: lore.CategorizationID, text: messageStrings[3] });
			// Relevant details are already embedded
		}
		if (Config.GetValue("CartographerLogDump") && messageStrings.length > 3) {
			// Situations where a log dump was not possible (despawns) would also not generate a report
			// If generated report will always be in index 3, and log dump will always be in the last slot (either 3 or 4)
			LogMsg(messageStrings[messageStrings.length - 1]);
			// Relevant details are already embedded
		}
	}

	/// Waypoint rendering
	private function CreateWaypoint(dynel:Dynel, loreName:String):Void {
		var waypoint:Waypoint = new Waypoint();
		waypoint.m_Id = dynel.GetID();
		waypoint.m_WaypointType = _global.Enums.WaypointType.e_RMWPScannerBlip;
		waypoint.m_WaypointState = _global.Enums.QuestWaypointState.e_WPStateActive;
		waypoint.m_Label = loreName;
		waypoint.m_IsScreenWaypoint = true;
		waypoint.m_IsStackingWaypoint = true;
		waypoint.m_Radius = 0;
		waypoint.m_Color = Config.GetValue("WaypointColour");
		waypoint.m_WorldPosition = dynel.GetPosition(0);
		var scrPos:Point = dynel.GetScreenPosition();
		waypoint.m_ScreenPositionX = scrPos.x;
		waypoint.m_ScreenPositionY = scrPos.y;
		waypoint.m_CollisionOffsetX = 0;
		waypoint.m_CollisionOffsetY = 0;
		waypoint.m_DistanceToCam = dynel.GetCameraDistance(0);
		waypoint.m_MinViewDistance = 0;
		waypoint.m_MaxViewDistance = c_MaxWaypointRange;

		WaypointSystem.m_CurrentPFInterface.m_Waypoints[waypoint.m_Id.toString()] = waypoint;
		WaypointSystem.m_CurrentPFInterface.SignalWaypointAdded.Emit(waypoint.m_Id);
	}

	private function RemoveWaypoint(dynelID:ID32):Void {
		var key:String = dynelID.toString();
		if (WaypointSystem.m_CurrentPFInterface.m_Waypoints[key]) {
			delete WaypointSystem.m_CurrentPFInterface.m_Waypoints[key];
			WaypointSystem.m_CurrentPFInterface.SignalWaypointRemoved.Emit(dynelID);
		}
	}

	private function ClearWaypoints():Void {
		for (var key:String in TrackedLore) { RemoveWaypoint(TrackedLore[key].DyenlID); }
	}

	// Ugly, but I don't really see any alternative to doing a per/frame update
	private function UpdateWaypoints():Void {
		for (var key:String in TrackedLore) {
			var lore:LoreData = TrackedLore[key];
			if (Config.GetValue("WaypointAlerts") & lore.Type) {
				if (!FilterLore(lore)) {
					// If not notifying for a particular lore, clear the waypoint if any
					// Clears waypoint when picking up lore or when settings change
					// TODO: Lore.SignalTagAdded as an "on pickup" event to simplify some of this, setting changes would have to be handled elsewhere
					RemoveWaypoint(lore.DynelID);
					continue;
				}
				// The waypoints that are added to the PFInterface are constantly stomped by the C++ side.
				// So I'm updating the data held by the rendered copy, and then forcing it to redo the layout before it gets stomped again.
				// As long as the mod updates after the main interface, this should work.
				// To do this properly, I'd have to implement my own waypoint system, which just isn't worth it yet.
				var dynel:Dynel = lore.DynelInst;
				var scrPos:Point = dynel.GetScreenPosition();
				var waypoint:CustomWaypoint = WaypointSystem.m_RenderedWaypoints[key];
				waypoint.m_Waypoint.m_ScreenPositionX = scrPos.x;
				waypoint.m_Waypoint.m_ScreenPositionY = scrPos.y;
				waypoint.m_Waypoint.m_DistanceToCam = dynel.GetCameraDistance(0);

				waypoint.Update(Stage.visibleRect.width);
				waypoint = undefined;
			}
		}
	}

	/// Variables
	private static var e_Stats_LoreId:Number = 2000560; // Most lore dynels seem to store the LoreId at this stat index, those that don't are either not fully loaded, or event related
	private static var c_ShroudedLoreCategory:Number = 7993128; // Keep ending up with special cases for this particular one

	private static var c_MaxWaypointRange:Number = 50; // Maximum display range for waypoints, in metres

	// When doing a stat dump, use/change these parameters to determine the range of the stats to dump
	// It will dump the Nth million stat ids, with the mode parameter provided
	// Tradeoff between the length of time locked up, and the number of tests needed
	private var DetailStatRange:Number;
	private var DetailStatMode:Number;

	private var IndexFile:XML;

	private var CategoryIndex:Array;
	private var TrackedLore:Object;
	private var WaypointSystem:Object;
}
