﻿// Copyright 2017, Earthfiredrake (Peloprata)
// Released under the terms of the MIT License
// https://github.com/Earthfiredrake/TSW-LoreHound

import com.GameInterface.Game.Dynel;
import com.GameInterface.Lore;
import com.GameInterface.LoreNode;
import com.Utils.ID32;

// Helper data structure for detected lore dynel information

class efd.LoreHound.LoreData {
	// Category flags for identifiable lore types
	public static var ef_LoreType_None:Number = 0;
	public static var ef_LoreType_Placed:Number = 1 << 0; // Most lore with fixed locations
	public static var ef_LoreType_Trigger:Number = 1 << 1; // Lore with triggered spawn conditions, seems to stay spawned once triggered (often after dungeon bosses)
	public static var ef_LoreType_Drop:Number = 1 << 2; // Lore which drops from monsters, or otherwise spawns with a time limit
	public static var ef_LoreType_Despawn:Number = 1 << 3; // Special type for generating despawn messages (will be output as Drop lore)
	public static var ef_LoreType_Uncategorized:Number = 1 << 4; // Newly detected lore, will need to be catalogued
	public static var ef_LoreType_All:Number = (1 << 5) - 1;

	public function LoreData(dynel:Dynel, formatStrID:Number, type:Number) {
		// The dynel will be invalid when the lore tracking callbacks are disabled
		// Caches useful values prior to this
		DynelInst = dynel;
		DynelID = dynel.GetID();
		CategorizationID = formatStrID;
		Type = type;
	}

	// Extracts the format string ID from the xml localization formatting tag
	// Provides limited ability to detect different lore behaviours based on multiple instances of localization strings
	public static function GetFormatStrID(dynel:Dynel):Number {
		var dynelName:String = dynel.GetName();
		var formatStrId:String = dynelName.substring(dynelName.indexOf('id="') + 4);
		return Number(formatStrId.substring(0, formatStrId.indexOf('"')));
	}

	public function get LoreID():Number {
		if (!LoreIDCache) {
			LoreIDCache = DynelInst.GetStat(e_Stats_LoreId, 2);
		}
		return LoreIDCache;
	}

	public function get IsInactiveEventLore():Boolean {
		return (Type == ef_LoreType_Placed && LoreID == 0);
	}

	public function get IsKnown():Boolean {
		return !Lore.IsLocked(LoreID);
	}

	public function get Topic():String {
		return Lore.GetDataNodeById(LoreID).m_Parent.m_Name;
	}

	public function get Source():Number {
		// 0 == Buzzing; 1 == Black Signal
		return Lore.GetTagViewpoint(LoreID);
	}

	public function get Index():Number {
		var source:Number = Source;
		var siblings:Array = Lore.GetDataNodeById(LoreID).m_Parent.m_Children;
		var index:Number = 1; // Lore entries start count at 1
		for (var i:Number = 0; i < siblings.length; ++i) {
			var sibling:Number = siblings[i].m_Id;
			if (LoreID == sibling) { return index; }
			if (Lore.GetTagViewpoint(sibling) == source) {
				++index;
			}
		}
	}

	// Variables
	private static var e_Stats_LoreId:Number = 2000560; // Most lore dynels seem to store the LoreId at this stat index, those that don't are either not fully loaded, or event related

	public var DynelInst:Dynel;
	public var DynelID:ID32;
	public var CategorizationID:Number;
	public var Type:Number;

	private var LoreIDCache:Number;
}