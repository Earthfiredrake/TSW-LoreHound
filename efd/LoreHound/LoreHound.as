﻿// Copyright 2017-2018, Earthfiredrake
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

import efd.LoreHound.lib.DebugUtils;
import efd.LoreHound.lib.LocaleManager;
import efd.LoreHound.lib.Mod;
import efd.LoreHound.lib.sys.ConfigManager;
import efd.LoreHound.lib.sys.config.ConfigWrapper;
import efd.LoreHound.lib.sys.config.Versioning;
import efd.LoreHound.lib.sys.ModIcon;
import efd.LoreHound.lib.sys.VTIOHelper;

import efd.LoreHound.LoreData;

class efd.LoreHound.LoreHound extends Mod {
/// Initialization
	// Function wrapper eliminates compile-constant requirements, permits more flexibility in filling it out
	private function GetModInfo():Object {
		return {
			// Dev/debug settings at top so commenting out leaves no hanging ','
			// Debug : true,
			Name : "LoreHound",
			Version : "1.4.0",
			Subsystems : {
				Config : {
					Init : ConfigManager.Create,
					InitObj : {
						MinUpgradableVersion : "1.0.0",
						LibUpgrades : [{mod : "1.3.2", lib : "1.0.0"}]
					}
				},
				Icon : {
					Init : ModIcon.Create,
					InitObj : {
						GetFrame : GetIconFrame,
						LeftMouseInfo : IconMouse_ToggleConfigWindow,
						RightMouseInfo : IconMouse_ToggleUserEnabled,
						ExtraTooltipInfo : IconTooltip
					}
				},
				LinkVTIO : {
					Init : VTIOHelper.Create,
					InitObj : {
						ConfigDV : "efdShowLoreHoundConfigWindow" // ConfigWindowVarName is not yet properly initialized
					}
				}
			}
		};
	}

	public function LoreHound(hostMovie:MovieClip) {
		super(GetModInfo(), hostMovie);
		// Ingame debug menu registers variables that are initialized here, but not those initialized at class scope
		// - Perhaps flash does static evaluation and decides to collapse constant variables?
		// - Regardless of the why, this will let me tweak these at runtime
		DetailStatRange = 1; // Start with the first million
		DetailStatMode = 2; // Defaulting to mode 2 based on repeated comments in game source that it is somehow "full"
		SystemsLoaded.CategoryIndex = false;

		TrackedLore = new Object();
		WaypointSystem = _root.waypoints;
		WaypointInterface.SignalPlayfieldChanged.Connect(ClearTracking, this);

		InitializeConfig();

		IndexFile = LoadXmlAsynch("CategoryIndex", Delegate.create(this, CategoryIndexLoaded));
	}

/// Settings
	// TODO: Some reports of settings being lost, reverting to defaults (v1.2.2). Investigate further for possible causes

	// Category flags for extended information
	private static var ef_Details_None:Number = 0;
	public static var ef_Details_Location:Number = 1 << 0; // Playfield name and coordinate vector
	public static var ef_Details_CategoryIDs:Number = 1 << 1; // String table ID# (indexing table 50200) and LoreID#
	public static var ef_Details_DynelId:Number = 1 << 2;
	public static var ef_Details_Timestamp:Number = 1 << 3;
	private static var ef_Details_All:Number = (1 << 4) - 1;
	private static var ef_Details_Default:Number = ef_Details_Location | ef_Details_Timestamp;

	private function InitializeConfig():Void {
		// Notification types
		Config.NewSetting("FifoLevel", LoreData.ef_LoreType_None); // DEPRECATED(v1.2.0.alpha) : Renamed
		Config.NewSetting("ChatLevel", LoreData.ef_LoreType_Drop | LoreData.ef_LoreType_Uncategorized); // DEPRECATED(v1.2.0.alpha) : Renamed

		// Renaming and expanding options for v1.2
		Config.NewSetting("FifoAlerts",LoreData.ef_LoreType_Spawned); // FIFO onscreen alerts
		Config.NewSetting("ChatAlerts", LoreData.ef_LoreType_Spawned); // System chat alerts
		Config.NewSetting("WaypointAlerts", LoreData.ef_LoreType_Spawned); // Display onscreen waypoints for lore
		Config.NewSetting("AlertForCollected", LoreData.ef_LoreType_Drop | LoreData.ef_LoreType_Uncategorized); // Alert the player for lore they already have
		Config.NewSetting("AlertForUncollected", LoreData.ef_LoreType_Spawned); // Alert the player for lore they haven't picked up yet

		Config.NewSetting("IgnoreUnclaimedLore", true); // DEPRECATED(v1.2.0.alpha) : Renamed and expanded
		Config.NewSetting("TrackDespawns", true); // Track timed lore comb drops, and notify when they despawn
		Config.NewSetting("ShowWaypoints", true); // DEPRECATED(v1.2.0.alpha) : Renamed and expanded
		Config.NewSetting("CheckNewContent", false); // DEPRECATED(v1.1.0.alpha): Renamed
		Config.NewSetting("ExtraTesting", false); // Additional testing to detect lore that slips through or is uninformative (inactive event lore, malformed strings, new IDs)
		Config.NewSetting("CartographerLogDump", false); // Dumps detected lore to the log file in a format which can easilly be extracted for Cartographer waypoint files
		Config.NewSetting("WaypointColour", 0xFFAA00); // Colour of onscreen waypoints

		// Extended information, regardless of this setting:
		// - Is always ommitted from Fifo notifications, to minimize spam
		// - Some fields are always included when detecting uncategorized lore, to help identify it
		Config.NewSetting("Details", ef_Details_Default);
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
				if (!(newValue & LoreData.ef_LoreType_Drop)) { Config.SetValue("TrackDespawns", false); }
				// Fallthrough intentional
			case "AlertForUncollected":
				// Spawn waypoints for detected lore that now meets the filter criteria
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
			case "TrackDespawns":
				if (newValue) { Config.SetFlagValue("AlertForCollected", LoreData.ef_LoreType_Drop, true); }
				Icon.Refresh();
				break;
			case "ExtraTesting":
				for (var key:String in TrackedLore) {
					var lore:LoreData = TrackedLore[key];
					if (!lore.IsDataComplete &&
						Config.GetValue("WaypointAlerts") & Config.GetValue("AlertForUncollected") & lore.Type) { // Use of binary & intentional
						if (newValue) {
							CreateWaypoint(lore.DynelInst, AttemptIdentification(lore));
						} else {
							// TODO: Remove waypoints here if attempting to reduce the on-update overhead
						}
					}
				}
				break;
			case "WaypointColour":
				for (var key:String in TrackedLore) {
					var existing:Waypoint = WaypointSystem.m_CurrentPFInterface.m_Waypoints[key];
					if (existing) {
						existing.m_Color = newValue;
						WaypointSystem.SlotWaypointColorChanged(TrackedLore[key].DynelID);
					}
				}
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
			UpdateLoadProgress("CategoryIndex");
		} else {
			// Loading is asynchronous, not localized
			// Currently localization appears to load first, but I won't count on it
			// There's also the possibility that it also failed to load
			// Could check SystemsLoaded, but seems excessive for what should be a disabled state
			Debug.ErrorMsg("Failed to load category index", { fatal : true });
		}
	}

	private function UpdateMod(newVersion:String, oldVersion:String):Void {
		// Version specific updates
		//   Some upgrades may reflect unreleased builds, for consistency on develop branch
		if (Versioning.CompareVersions("1.1.0.alpha", oldVersion) > 0) {
			// Renaming setting due to recent events
			Config.SetValue("ExtraTesting", Config.GetValue("CheckNewContent"));
		}
		if (Versioning.CompareVersions("1.2.0.alpha", oldVersion) > 0) {
			// Rename *level settings to *alert
			Config.SetValue("FifoAlerts", Config.GetValue("FifoLevel"));
			Config.SetValue("ChatAlerts", Config.GetValue("ChatLevel"));
			// Copy waypoint settings to new per-category setting
			var existingAlerts = Config.GetValue("FifoLevel") | Config.GetValue("ChatLevel");
			Config.SetValue("WaypointAlerts", (Config.GetValue("ShowWaypoints") ? existingAlerts : LoreData.ef_LoreType_None));
			// Copy unclaimed lore to per-category setting (no existing setting for claimed lore)
			Config.SetValue("AlertForUncollected", (Config.GetValue("IgnoreUnclaimedLore") ? LoreData.ef_LoreType_Uncategorized : LoreData.ef_LoreType_Spawned));
		}
		if (Versioning.CompareVersions("1.4.0.beta", oldVersion) > 0) {
			// Despawn tracking now mandates uncollected alerts for drop lore
			if (!(Config.GetValue("AlertForCollected") & LoreData.ef_LoreType_Drop)) { Config.SetValue("TrackDespawns", false); }
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
		HostClip.onEnterFrame = Delegate.create(this, FrameUpdate);
		VicinitySystem.SignalDynelEnterVicinity.Connect(LoreSniffer, this);
		Dynels.DynelGone.Connect(LoreDespawned, this);
	}

	private function Deactivate():Void {
		// For most local teleports the mod will be re-enabled before the despawn notification is sent
		//   Oddly the despawn notification will be sent even if we deregister the dynel stat observer manually
		// When changing zones, despawn and detection notices are both sent during the deactivated period
		// Detection notices between the deactivate-activate pair often provide the correct LoreId,
		//   but fail to link to an actual lore or player object
		Dynels.DynelGone.Disconnect(LoreDespawned, this);
		VicinitySystem.SignalDynelEnterVicinity.Disconnect(LoreSniffer, this);
		delete HostClip.onEnterFrame;
	}

	private function FrameUpdate():Void {
		UpdateLoreData();
		UpdateWaypoints();
	}

	private function GetIconFrame():String {
		if (Enabled) { // If game disables mod, icon isn't visible at all, so only user disables matter
			// Only show alerted flag if both tracking despawns and alerting for drop lore
			if (Config.GetValue("TrackDespawns") &&
				((Config.GetValue("AlertForCollected") | Config.GetValue("AlertForUncollected")) & LoreData.ef_LoreType_Drop)) {
				for (var id:String in TrackedLore) {
					if (TrackedLore[id].Type == LoreData.ef_LoreType_Drop) { return "alerted"; }
				}
			}
			return "active";
		} else { return "inactive"; }
	}

	private function IconTooltip():String {
		if (!Config.GetValue("TrackDespawns")) { return undefined; }
		var strings:Array = new Array();
		for (var id:String in TrackedLore) {
			if (TrackedLore[id].Type == LoreData.ef_LoreType_Drop) {
				if (strings.length == 0) { strings.push(LocaleManager.GetString("GUI", "TooltipTracking")); }
				strings.push("  " + AttemptIdentification(TrackedLore[id]));
			}
		}
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
	//           It mnay not be assigned for triggered lore that is placed invisibly...
	//           Unless a trigger is found that can proc on this value changing, it won't be particularly useful with lore detection
	//           Further testing suggests it might be related to the model id
	//           Can be used to determine colour of Dead Scarabs and spawn state of Bits of Joe
	//     #23 and #112 - Copies of the format string ID #, matching values used in ClassifyID
	//     #1050 - Unknown, usually 6 on lore, though other numbers have been observed (1 on scarabs)
	//             Of interest: Marquard's Mansion #3 starts as 1, but then changes to 6 when triggered
	//             Some inactive event lore detections are reporting 5
	//             _global Stat enum CarsGroup? What does this mean?
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
	//     Testing of Dynel.SignalStatChanged indicated that it did not fire for the sample lore dynel :(

	/// Lore detection and sorting
	private function LoreSniffer(dynelId:ID32):Void {
		if (dynelId.m_Type != _global.Enums.TypeID.e_Type_GC_SimpleDynel) { return; } // Dynel is not of supertype associated with lore combs
		if (TrackedLore[dynelId.toString()]) { return; }

		var dynel:Dynel = Dynel.GetDynel(dynelId);
		var categorizationId:Number = LoreData.GetFormatStrID(dynel);

		// Categorize the detected item
		var loreType:Number = ClassifyID(categorizationId, dynel.GetStat(e_Stats_LoreId, 2));
		if (loreType == LoreData.ef_LoreType_None) {
			if (Config.GetValue("ExtraTesting") && ExpandedDetection(dynel)) { loreType = LoreData.ef_LoreType_Uncategorized; } // It's so new it hasn't been added to the index list yet
			else { return; } // Dynel is not lore
		}

		var lore:LoreData = new LoreData(dynel, categorizationId, loreType, CategoryIndex[categorizationId].loreID);

		TrackedLore[dynelId.toString()] = lore;
		// Registers despawn callback for lore tracking systems (spam reduction, waypoint cleanup and despawn notifications)
		// _global.enums.Property.e_ObjScreenPos seems like it would be more useful, but returns the same value :(
		// Can't tell if it actually updates the value on a regular basis... as lore doesn't move
		Dynels.RegisterProperty(dynelId.m_Type, dynelId.m_Instance, _global.enums.Property.e_ObjPos);

		FilterAndNotify(lore);
	}

	// Callback for timeout delegate if loreId is uninitialized
	private function FilterAndNotify(lore:LoreData):Void {
		if (FilterLore(lore)) { SendLoreNotifications(lore); }
		Icon.Refresh();
	}

	private function FilterLore(lore:LoreData):Boolean {
		// Only process special items that are currently spawned
		if (lore.Type == LoreData.ef_LoreType_SpecialItem && !lore.DynelInst.GetStat(12, 2)) { return false; }

		// Filters lore based on user notification settings
		if (!lore.IsDataComplete && !Config.GetValue("ExtraTesting")) { return false; }
		// TODO: If having lore popping up in error when changing zones is still an issue
		//       Consider doing a test here to see if the player data is properly loaded
		if (!(lore.Type & Config.GetValue(lore.IsKnown ? "AlertForCollected" : "AlertForUncollected"))) { return false; }

		// Verify that at least one notification is needed
		return (lore.Type & (Config.GetValue("FifoAlerts") | Config.GetValue("ChatAlerts") | Config.GetValue("WaypointAlerts"))) ||
			    Config.GetValue("CartographerLogDump");
	}

/// Lore proximity tracking

	// Updates lore data for those dynels which loaded with incomplete data
	private function UpdateLoreData():Void {
		for (var id:String in TrackedLore) {
			var lore:LoreData = TrackedLore[id];
			if (!lore.IsDataComplete && lore.RefreshLoreID()) {
				lore.Type = ClassifyID(lore.CategorizationID, lore.LoreID);
				FilterAndNotify(lore);
			}
		}
	}

	// Triggers when the lore dynel is removed from the client, either because it has despawned or the player has moved too far away
	// With no dynel to query, all required info has to be known values or cached
	private function LoreDespawned(type:Number, instance:Number):Void {
		var despawnedId:String = new ID32(type, instance).toString();
		var lore:LoreData = TrackedLore[despawnedId];
		if (lore) { // Ensure the despawned dynel was tracked by this mod
			lore.Type |= LoreData.ef_LoreType_Despawn; // Set the despawn flag

			RemoveWaypoint(lore.DynelID);
			// Despawn notifications
			if ((lore.Type & LoreData.ef_LoreType_Drop) && Config.GetValue("TrackDespawns")) {
				if (FilterLore(lore)) { // Despawn notifications are subject to same filters as regular ones
					var messageStrings:Array = GetMessageStrings(lore);
					DispatchMessages(messageStrings, lore); // No details or raw format string
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
		var category:Number = indexEntry.excluding[loreId] || indexEntry.type;
		return category || LoreData.ef_LoreType_None;
	}

	private static function ExpandedDetection(dynel:Dynel):Boolean {
		// Check the dynel's lore ID, it may not have a proper entry in the string table (Polaris drone clause)
		// Won't detect inactive event lore though (Shrouded Lore would slip through both tests most of the time)
		// May detect other achievement related things (subject to super filters)
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
	// 0: Unaddorned lore name (for waypoints)
	// 1: Fifo message
	// 2: System chat message
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
					Debug.DevMsg("Lore type defaulted: " + lore.Type);
					return;
			}
		}
		messageStrings.push(loreName); // For waypoints
		messageStrings.push(LocaleManager.FormatString("LoreHound", typeString + "Fifo", loreName));
		messageStrings.push(LocaleManager.FormatString("LoreHound", typeString + "Chat", loreName));
		if (!(lore.Type & LoreData.ef_LoreType_Despawn) && Config.GetValue("CartographerLogDump")) {
			// No dynel data on despawn, and initial detection should have left a log record
			var dynel:Dynel = lore.DynelInst;
			var pos:Vector3 = dynel.GetPosition(0);
			var posStr:String = 'x="'+ Math.round(pos.x) + '" y="' + Math.round(pos.z) + '" z="' + Math.round(pos.y) + '"';
			messageStrings.push('<Lore loreID="' + lore.LoreID +  '" zone="' + dynel.GetPlayfieldID() + '" ' + posStr + ' /> <!-- ' + loreName + '(' + typeString + ') -->');
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
						DebugUtils.DevMsgS("Scarab colour filter failure!");
						return LDBFormat.Translate(lore.DynelInst.GetName());
				}
				return LocaleManager.FormatString("LoreHound", scarabColour, LDBFormat.Translate(lore.DynelInst.GetName()));
			}
			return LDBFormat.Translate(lore.DynelInst.GetName());
		}

		if (lore.IsDataComplete) {
			var topic:String = lore.Topic;
			var index:Number = lore.Index;
			if (!(topic && index)) {
				DebugUtils.DevMsgS("Unknown topic or entry #, malformed lore ID: " + lore.LoreID);
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
					DebugUtils.DevMsgS("Lore has unknown source: " + lore.Source);
					break;
			}
			return LocaleManager.FormatString("LoreHound", "LoreName", topic, catCode, index);
		}

		// Inactive event lore, and some triggered lore, won't have a valid ID when detected
		// We can partially ID some, but most is going to be "??"
		if (lore.IsShroudedLore) { return LocaleManager.GetString("LoreHound", "InactiveShrouded"); }
		return LocaleManager.GetString("LoreHound", "InactiveLore");
	}

	// This info is ommitted from FIFO messages
	// Uncategorized lore always requests some info for identification purposes
	private function GetDetailStrings(lore:LoreData):Array {
		var detailStrings:Array = new Array();
		var details:Number = Config.GetValue("Details");
		if (lore.Type == LoreData.ef_LoreType_Uncategorized) { details |= ef_Details_Location | ef_Details_CategoryIDs; }

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
		if (details & ef_Details_CategoryIDs) {
			detailStrings.push(LocaleManager.FormatString("LoreHound", "CategoryInfo", lore.CategorizationID.toString(), lore.LoreID));
		}
		if (details & ef_Details_DynelId) {
			detailStrings.push(LocaleManager.FormatString("LoreHound", "InstanceInfo", dynel.GetID().toString()));
		}
		return detailStrings;
	}

	private function DispatchMessages(messageStrings:Array, lore:LoreData, detailStrings:Array):Void {
		if (Config.GetValue("FifoAlerts") & lore.Type) { FifoMsg(messageStrings[1]); }
		if (Config.GetValue("ChatAlerts") & lore.Type) {
			ChatMsg(messageStrings[2], { forceTimestamp : (Config.GetValue("Details") & ef_Details_Timestamp) });
			for (var i:Number = 0; i < detailStrings.length; ++i) {
				ChatMsg(detailStrings[i], { noPrefix : true });
			}
		}
		if (lore.Type & LoreData.ef_LoreType_Despawn) { return; } // Early return, following message types don't apply for despawns
		if (Config.GetValue("WaypointAlerts") & lore.Type) { CreateWaypoint(lore.DynelInst, messageStrings[0]); }
		if (Config.GetValue("CartographerLogDump")) { Debug.LogMsg(messageStrings[3]); }
	}

	/// Waypoint rendering
	private function CreateWaypoint(dynel:Dynel, loreName:String):Void {
		var dynelID:ID32 = dynel.GetID();
		var existing:Waypoint = WaypointSystem.m_CurrentPFInterface.m_Waypoints[dynelID.toString()];
		if (existing) {
			// Waypoint already exists likely from an incomplete detection that's being updated
			existing.m_Label = loreName;
			WaypointSystem.SlotWaypointRenamed(dynelID);
			return;
		}
		var waypoint:Waypoint = new Waypoint();
		waypoint.m_Id = dynelID;
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
				waypoint.m_Waypoint.m_Color = Config.GetValue("WaypointColour");
				waypoint.m_Waypoint.m_ScreenPositionX = scrPos.x;
				waypoint.m_Waypoint.m_ScreenPositionY = scrPos.y;
				waypoint.m_Waypoint.m_DistanceToCam = dynel.GetCameraDistance(0);

				// Improve name display so that it doesn't trim long names and is readable while waypoint off the sides of the screen
				// Will still end up being cut off when near, but not over, the edges of the screen
				waypoint["i_NameText"].autoSize = "center";
				switch (waypoint.m_Direction) {
					case "left" : {
						waypoint["i_NameText"]._x = 0;
						break;
					}
					case "right" : {
						waypoint["i_NameText"]._x = -waypoint["i_NameText"].textWidth;
						break;
					}
				}

				waypoint.Update(Stage.visibleRect.width);
			}
		}
	}

	/// Variables
	private static var e_Stats_LoreId:Number = 2000560; // Most lore dynels seem to store the LoreId at this stat index, those that don't are either not fully loaded, or event related

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
