// Copyright 2017, Earthfiredrake (Peloprata)
// Released under the terms of the MIT License
// https://github.com/Earthfiredrake/TSW-LoreHound

import flash.geom.Point; // DEPRECIATED(v0.5.0): Required for update routine from previous release

import gfx.utils.Delegate;

import com.GameInterface.DistributedValue; // DEPRECIATED(v0.8.0): Renaming settings archive
import com.GameInterface.Dynels;
import com.GameInterface.Game.Dynel;
import com.GameInterface.Lore;
import com.GameInterface.LoreNode;
import com.GameInterface.MathLib.Vector3;
import com.GameInterface.VicinitySystem;
import com.GameInterface.WaypointInterface; // Playfield change notifications
import com.Utils.Archive; // DEPRECIATED(v0.8.0): Renaming settings archive
import com.Utils.ID32;
import com.Utils.LDBFormat;

import efd.LoreHound.lib.AutoReport;
import efd.LoreHound.lib.ConfigWrapper;
import efd.LoreHound.lib.LocaleManager;
import efd.LoreHound.lib.Mod;

class efd.LoreHound.LoreHound extends Mod {
	private static var ModInfo:Object = {
		// Debug settings at top so that commenting out leaves no hanging ','
		// Trace : true,
		Name : "LoreHound",
		Version : "1.0.0",
		ArchiveName : "LoreHoundConfig" // DEPRECIATED(v0.8.0): Renaming settings archive
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
		DumpToLog = false;
		DetailStatRange = 1; // Start with the first million
		DetailStatMode = 2; // Defaulting to mode 2 based on repeated comments in game source that it is somehow "full"
		SystemsLoaded.CategoryIndex = false;

		TrackedLore = new Object();
		WaypointInterface.SignalPlayfieldChanged.Connect(ClearTracking, this);

		var arConfig:ConfigWrapper = AutoReport.Initialize(ModName, Version, DevName);

		InitializeConfig(arConfig);
		LoadLoreCategories();

		Icon.UpdateState = function(stateFlag:Number, enable:Boolean) {
			if (stateFlag != undefined) {
				switch (enable) {
					case true: { this.StateFlags |= stateFlag; break; }
					case false: { this.StateFlags &= ~stateFlag; break; }
					case undefined: { this.StateFlags ^= stateFlag; break; }
				}
			}
			if (Config.GetValue("Enabled")) { // If game disables mod, it isn't visible at all, so only user disables matter
				if ((this.StateFlags & LoreHound.ef_IconState_Alert) == LoreHound.ef_IconState_Alert) { this.gotoAndStop("alerted"); return; }
				if ((this.StateFlags & LoreHound.ef_IconState_Report) == LoreHound.ef_IconState_Report) { this.gotoAndStop("reporting"); return; }
				this.gotoAndStop("active");
			} else { this.gotoAndStop("inactive"); }
		};

		TraceMsg("Initialized");
	}

	// DEPRECIATED(v0.8.0): Used to tweak ArchiveName in config wrapper for attempted upgrade without adding to the library interface
	// A hack to circumvent private visibility at compile time
	private static function ForceDirectSet(target:Object, property:String, value):Void { target[property] = value; }

	private function InitializeConfig(arConfig:ConfigWrapper):Void {
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

		arConfig.SignalValueChanged.Connect(AutoReportConfigChanged, this);
		Config.NewSetting("AutoReport", arConfig);

		// DEPRECIATED(v0.8.0): Archive name upgrade
		// Attempt to determine whether we're a fresh install, pre-upgrade or post-upgrade
		var oldArchive:Archive = DistributedValue.GetDValue("LoreHoundConfig");
		if (oldArchive.FindEntry("Installed", undefined) == undefined) {
			// Old archive did not include an installed setting
			// Either we have a fresh install, or it's properly cleared after the upgrade
			// In both cases we should load from the new archive
			ForceDirectSet(Config, "ArchiveName", undefined);
		}
	}

	private function AutoReportConfigChanged(setting:String, newValue, oldValue):Void {
		switch(setting) {
			case "Enabled":
			case "QueuedReports":
				Icon.UpdateState(ef_IconState_Report, AutoReport.HasReportsPending);
				break;
			default: break;
		}
	}

	/// Mod framework extensions and overrides
	private function ConfigChanged(setting:String, newValue, oldValue):Void {
		switch(setting) {
			case "TrackDespawns":
				if (!newValue) { ClearTracking(); }
				break;
			default:
				super.ConfigChanged(setting, newValue, oldValue);
				break;
		}
	}

	private function LoadLoreCategories():Void {
		IndexFile = new XML();
		IndexFile.ignoreWhite = true;
		var capture:LoreHound = this;
		IndexFile.onLoad = Delegate.create(this, CategoryIndexLoaded);
		IndexFile.load("LoreHound/CategoryIndex.xml");
	}

	private function CategoryIndexLoaded(success:Boolean):Void {
		if (success) {
			CategoryIndex = new Array();
			var xmlRoot:XMLNode = IndexFile.firstChild;
			for (var i:Number = 0; i < xmlRoot.childNodes.length; ++i) {
				var categoryXML:XMLNode = xmlRoot.childNodes[i];
				var category:Number = LoreHound["ef_LoreType_" + categoryXML.attributes.name];
				for (var j:Number = 0; j < categoryXML.childNodes.length; ++j) {
					CategoryIndex[categoryXML.childNodes[j].attributes.value] = category;
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
		return category != ef_LoreType_Unknown && category != ef_LoreType_None;
	}

	private function LoadComplete():Void {
		super.LoadComplete();
		Config.DeleteSetting("SendReports"); // DEPRECIATED(v0.6.0): Setting removed
	}

	private function DoUpdate(newVersion:String, oldVersion:String):Void {
		// Minimize settings clutter by purging auto-report records of newly categorized IDs
		AutoReport.CleanupReports(IsCategorizedLore);

		// Version specific updates
		//   v0.1.x-alpha did not have the version tag, and so can't be detected
		//   Some referenced versions refer to internal builds rather than release versions
		if (oldVersion == "v0.4.0.beta") {
			TraceMsg("Update for v0.4.0");
			// Point support added to ConfigWrapper, and position settings were updated accordingly
			// Also the last version to have the "v" embedded in the version string
			var oldPoint = Config.GetValue("ConfigWindowPosition");
			Config.SetValue("ConfigWindowPosition", new Point(oldPoint.x, oldPoint.y));
			oldPoint = Config.GetValue("IconPosition");
			Config.SetValue("IconPosition", new Point(oldPoint.x, oldPoint.y));
		}
		if (CompareVersions("0.5.0.beta", oldVersion) >= 0) {
			TraceMsg("Update for v0.5.0");
			// Points now saved using built in support from Archive
			//   Should not require additional update code
			// Enabled state of autoreport system is now internal to that config group
			if (Config.GetValue("SendReports")) {
				Config.GetValue("AutoReport").SetValue("Enabled", true);
			}
		}
		if (CompareVersions("0.6.5.alpha", oldVersion) >=0) {
			TraceMsg("Update for v0.6.5");
			// Removed "Unusual" lore category, value now occupied by "Despawn" special flag
			Config.SetFlagValue("FifoLevel", ef_LoreType_Despawn, false);
			Config.SetFlagValue("ChatLevel", ef_LoreType_Despawn, false);
		}
		if (CompareVersions("0.7.0.alpha", oldVersion) >=0) {
			TraceMsg("Update for v0.7.0");
			// Attempting to rename settings archive
			// Loaded the old settings from the original archive
			// Direct the save to the new archive and clear the old one
			ForceDirectSet(Config, "ArchiveName", undefined);
			DistributedValue.SetDValue("LoreHoundConfig", new Archive());
		}
	}

	private function Activate():Void {
		AutoReport.IsEnabled = true; // Only updates this component's view of the mod state
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
		AutoReport.IsEnabled = false; // Only updates this component's view of the mod state
	}

	private function TopbarRegistered():Void {
		// Topbar icon does not copy custom state variable, so needs explicit refresh
		Icon.UpdateState(ef_IconState_Report, AutoReport.HasReportsPending);
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
	private function LoreSniffer(dynelId:ID32):Void {
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
			(loreType != ef_LoreType_Unknown || !AutoReport.IsEnabled) && !DumpToLog) {
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
		if (loreId != undefined) { // Ensure the despawned dynel was tracked by this mod
			// Conform to the player's choice of notification on unclaimed lore, should they have left it unclaimed
			if (loreId == 0 || !(Lore.IsLocked(loreId) && Config.GetValue("IgnoreUnclaimedLore"))) {
				var messageStrings:Array = GetMessageStrings(ef_LoreType_Despawn, loreId);
				DispatchMessages(messageStrings, ef_LoreType_Drop); // No details or raw categorizationID
			}
			delete TrackedLore[despawnedId];
			for (var key:String in TrackedLore) {
				return; // There's still at least one lore being tracked, don't clear the icon
			}
			Icon.UpdateState(ef_IconState_Alert, false);
		}
	}

	private function ClearTracking():Void {
		for (var key:String in TrackedLore) {
			var id:Array = key.split(":");
			// Probably don't *have* to unregister, the dynel is most likely about to be destroyed anyway
			// This is more for cleaning up my end of things
			Dynels.UnregisterProperty(id[0], id[1], _global.enums.Property.e_ObjPos);
		}
		delete TrackedLore;
		TrackedLore = new Object();
		Icon.UpdateState(ef_IconState_Alert, false);
	}

	/// Lore identification
	// Much of the primary categorization info is now contained in the xml data file
	private function ClassifyID(categorizationId:Number):Number {
		var category:Number = CategoryIndex[categorizationId];
		return category ? category : ef_LoreType_None;
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

	private function SendLoreNotifications(loreType:Number, categorizationId:Number, dynel:Dynel):Void {
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
		var typeString:String;
		switch (loreType) {
			case ef_LoreType_Placed:
				typeString = "Placed";
				break;
			case ef_LoreType_Trigger:
				typeString = "Trigger";
				break;
			case ef_LoreType_Drop:
				typeString = "Drop";
				break;
			case ef_LoreType_Despawn:
				typeString = "Despawn";
				break;
			case ef_LoreType_Unknown:
				typeString = "Unknown";
				break;
			default:
				// It should be impossible for the game data to trigger this state
				// This message probably indicates a logical failure in the mod
				TraceMsg("Error, lore type defaulted: " + loreType);
				return;
		}
		messageStrings.push(LocaleManager.FormatString("LoreHound", typeString + "Fifo", loreName));
		messageStrings.push(LocaleManager.FormatString("LoreHound", typeString + "Chat", loreName));
		if (loreType == ef_LoreType_Unknown) {
			var reportStrings:Array = new Array();
			reportStrings.push("Category: " + loreType + " (" + loreName + ")"); // Report string
			var pos:Vector3 = dynel.GetPosition(0);
			reportStrings.push(LDBFormat.LDBGetText("Playfieldnames", dynel.GetPlayfieldID()) + " (" + Math.round(pos.x) + "," + Math.round(pos.z) + "," + Math.round(pos.y) + ")");
			reportStrings.push("Category ID: " + categorizationId);
			messageStrings.push(reportStrings.join('\n'));
		}
		if (DumpToLog && dynel != undefined) { // No Dynel on despawns
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
					catCode = LocaleManager.GetString("LoreHound", "BuzzingSource");
					break;
				case 1: // Black Signal
					catCode = LocaleManager.GetString("LoreHound", "BlackSignalSource");
					break;
				default: // Unknown source
					// Consider setting up a report here, with LoreID as tag
					// Low probability of it actually occuring, but knowing sooner rather than later might be nice
					catCode = LocaleManager.GetString("LoreHound", "UnknownSource");
					TraceMsg("Lore has unknown source: " + loreSource);
					break;
			}
			var parentNode:LoreNode = loreNode.m_Parent;
			var entryNumber:Number = 1; // Most people number based on type and from a base of 1
			for (var i:Number = 0; i < parentNode.m_Children.length; ++i) {
				var childId:Number = parentNode.m_Children[i].m_Id;
				if (childId == loreId) {
					return LocaleManager.FormatString("LoreHound", "LoreName", parentNode.m_Name, catCode, entryNumber);
				}
				if (Lore.GetTagViewpoint(childId) == loreSource) {
					++entryNumber;
				}
			}
			TraceMsg("Unknown topic or entry #, malformed lore ID: " + loreId);
			return LocaleManager.GetString("LoreHound", "InvalidLoreID");
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
				return LocaleManager.GetString("LoreHound", categorizationId == c_ShroudedLoreCategory ? "InactiveShrouded" : "InactiveEvent");
			default:
				// Lore drops occasionally fail to completely load before they're detected, but usually succeed on second detection
				// The only reason to see this now is if the automatic redetection system failed
				return LocaleManager.GetString("LoreHound", "IncompleteDynel");
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
			var playfield:String = LDBFormat.LDBGetText("Playfieldnames", dynel.GetPlayfieldID());
			detailStrings.push(LocaleManager.FormatString("LoreHound", "PositionInfo", playfield, Math.round(pos.x), Math.round(pos.y), Math.round(pos.z)));
		}
		if (loreType == ef_LoreType_Unknown || (details & ef_Details_FormatString) == ef_Details_FormatString) {
			var formatStr:String = dynel.GetName();
			// Strip off (seemingly) unimportant info and reformat to something more meaningful in this context
			var ids:Array = formatStr.substring(formatStr.indexOf('id="')).split(' ', 2);
			for (var i:Number = 0; i < ids.length; ++i) {
				var str = ids[i];
				ids[i] = str.substring(str.indexOf('"') + 1, str.length - 1);
			}
			detailStrings.push(LocaleManager.FormatString("LoreHound", "CategoryInfo", ids[0], ids[1]));
		}
		if ((details & ef_Details_DynelId) == ef_Details_DynelId) {
			detailStrings.push(LocaleManager.FormatString("LoreHound", "InstanceInfo", dynel.GetID().toString()));
		}
		if ((details & ef_Details_StatDump) == ef_Details_StatDump) {
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

	private function DispatchMessages(messageStrings:Array, loreType:Number, detailStrings:Array, categorizationId:Number):Void {
		if ((Config.GetValue("FifoLevel") & loreType) == loreType) {
			FifoMsg(messageStrings[0]);
		}
		if ((Config.GetValue("ChatLevel") & loreType) == loreType) {
			ChatMsg(messageStrings[1], { forceTimestamp : (Config.GetValue("Details") & ef_Details_Timestamp) == ef_Details_Timestamp });
			for (var i:Number = 0; i < detailStrings.length; ++i) {
				ChatMsg(detailStrings[i], { noPrefix : true });
			}
		}
		if (loreType == ef_LoreType_Unknown) { // Auto report handles own enabled state
			// When compiling reports for the automated report system consider the following options for IDs
			// Categorization ID: This one is currently being used to report on unknown lore groups (Range estimated to be [7...10] million)
			// Lore ID: If a particular lore needs to be flagged for some reason, this is a reasonable choice if available (Range estimated to be [400...1000])
			// Dynel ID: Not ideal, range is all over the place, doesn't uniquely identify a specific entry
			// Playfield ID and location: Good for non-drop lores (and not terrible for them as the drop locations are usually predictible), formatting as an id might be a bit tricky
			AutoReport.AddReport({ id: categorizationId, text: messageStrings[2] });
			// Relevant details are already embedded
		}
		if (DumpToLog && messageStrings.length > 2) {
			// Situations where a log dump was not possible (despawns) would also not generate a report
			// If generated report will always be in index 2, and log dump will always be in the last slot (either 2 or 3)
			LogMsg(messageStrings[messageStrings.length - 1]);
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

	private var IndexFile:XML;

	private var CategoryIndex:Array;
	private var TrackedLore:Object;
}
