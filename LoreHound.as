// Copyright 2017, Earthfiredrake (Peloprata)
// Released under the terms of the MIT License

import com.GameInterface.Chat;
import com.GameInterface.Game.Dynel;
import com.GameInterface.Log;
import com.GameInterface.MathLib.Vector3;
import com.GameInterface.Utils;
import com.GameInterface.VicinitySystem;
import com.Utils.ID32;
import com.Utils.LDBFormat;

// Category flags for represented lore types
var ef_LoreType_None:Number = 0;
var ef_LoreType_Common:Number = 1 << 0; // Most lore with fixed locations
var ef_LoreType_Drop:Number = 1 << 1; // Lore which drops from monsters
var ef_LoreType_Special:Number = 1 << 2; // Unusual lore, often triggered
var ef_LoreType_Unknown:Number = 1 << 3; // Newly detected lore, will need to be catalogued
var ef_LoreType_All:Number = (1 << 4) - 1;

// Sets which notifications are used for which lore types
var m_FifoMessageLore:Number = ef_LoreType_None; // Popup FiFo messages onscreen
var m_ChatMessageLore:Number = ef_LoreType_Drop | ef_LoreType_Unknown; // System chat messages
var m_LogMessageLore:Number = ef_LoreType_Unknown; // ClientLog.txt output (Tagged: Scaleform.LoreHound)

// Category flags for extended debug information
var ef_DebugDetails_None:Number = 0;
var ef_DebugDetails_FormatString:Number = 1 << 0; // Trimmed contents of format string, to avoid automatic evaluation
var ef_DebugDetails_Location:Number = 1 << 1; // Playfield ID and coordinate vector
var ef_DebugDetails_StatDump:Number = 1 << 2; // Repeatedly calls Dynel.GetStat() (limited by the constant below), recording any stat which is not 0 or undefined.
var ef_DebugDetails_All:Number = (1 << 3) -1;

// Number of stat IDs to test [0,N) when doing a StatDump (this can cause significant performance hitches, particularly with large ranges)
// This number is high enough to catch all of the values discovered with a test of various static lores (of the first million statIDs)
// Unfortunately none seem to be useful, would like to test further with drop lores
var c_DebugDetails_StatCount:Number = 1110; 

// Debugging settings
var m_DebugDetails:Number = ef_DebugDetails_None; // Dump extended info to chat or log output
var m_DebugVerify:Boolean = true; // Do additional tests to detect inaccurate early discards

function onLoad():Void {
	VicinitySystem.SignalDynelEnterVicinity.Connect(LoreSniffer, this);
}

// Notes on Dynels:
//   GetName() - Actually a remoteformat xml tag, for the LDB localization system
//   GetID() - The type seems to be constant for all lore, each placed lore seems to consistently maintain a unique instance, but dropped lore may select one at random
//   GetPlayfieldID() - Unsure how to convert this to a playfield name, Playfield data objects lack a source
//   GetPosition() - World coordinates
//   GetDistanceToPlayer() - ~20m when approaching lore, drops may trigger much closer
//   IsRendered() - Seems to only consider occlusion and clipping, not consistent on lore already claimed
//   GetStat() - Unknown if any of these are useful, the mode parameter does not seem to change the value/lack of one, a scan of the first million stats provided:
//     #12 - Unknown, consistently 7456524 across current data sample
//     #23 and #112 - Copies of the format string ID #, matching values used in ClassifyID
//     #1050 - Unknown, usually 6, though other numbers have been observed
//     #1102 - Copy of the Dynel instance identifier (dynelId.m_Instance)
//     While the function definition suggests a relationship with the Stat enum
//       the only matching value is 1050, mapping to "CarsGroup", whatever that is
//   Unfortunately, there does not seem to be any existing connection between the Dynel data, and the Lore entries,
//     if additional features making use of that relationship are desired, it may require a hardcoded mapping of instance ids
//     (a script comparing lore coordinates could merge instance ids with an existing list of lore locations)

function LoreSniffer(dynelID:ID32):Void {
	var dynel:Dynel;
	var dynelName:String;
	
	var loreType:Number = ef_LoreType_None;
	// All known lore shares this dynel type with a wide variety of other props
	if (dynelID.m_Type == 51320) { 
		dynel = Dynel.GetDynel(dynelID);
		dynelName = dynel.GetName();
		loreType = ClassifyID(dynelName);
		if (loreType == ef_LoreType_Unknown && !CheckLocalizedName(dynelName)) {
			loreType = ef_LoreType_None;
		}
	} else if (m_DebugVerify) {
		// Do what we can to ensure we aren't missing any with our early filter
		dynel = Dynel.GetDynel(dynelID);
		dynelName = dynel.GetName();
		if (CheckLocalizedName(dynelName)) {
			loreType = ef_LoreType_Unknown;
		}
	}
	
	if (loreType != ef_LoreType_None) {
		SendLoreNotifications(loreType, dynel);	
	}
}

function ClassifyID(formatStr:String):Number {
	// Extract the format string ID number from the xml tag
	var formatStrID:String = formatStr.substring(formatStr.indexOf('id="') + 4);
	formatStrID = formatStrID.substring(0, formatStrID.indexOf('"'));
	
	// Here be the magic numbers (probably planted by the Dragon)
	switch (formatStrID) {
		case "7128026":
			return ef_LoreType_Common;
		case "9240080":
			return ef_LoreType_Drop;
		case "7647988": // HF6 (possibly related to the demonic crystal? investigate further)
		case "7993128": // Shrouded Lore (End of Days)
		case "9135398": // Two one-off lores found in MFB
		case "9135406":
			return ef_LoreType_Special;
		default:
			return ef_LoreType_Unknown;
	}
}

function CheckLocalizedName(formatStr:String):Boolean {
	// Have the localization system provide a language dependent string to compare with
	// In English this ends up being "Lore", hopefully it is similarly generic and likely to match in other languages
	var testStr:String = LDBFormat.LDBGetText(50200, 7128026);
	
	return LDBFormat.Translate(formatStr).indexOf(testStr) != -1;
}

function SendLoreNotifications(loreType:Number, dynel:Dynel) {
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
		case ef_LoreType_Drop:
			fifoMessage = "A lore dropped!";
			chatMessage = "Dropped lore nearby (" + formatStr + " [" + dynelID.m_Instance + "])";
			logMessage = "Dropped lore (" + formatStr + " [" + dynelID + "])";
			break;
		case ef_LoreType_Special:
			fifoMessage = "Lore nearby.";
			chatMessage = "Unusal lore nearby (" + formatStr + " [" + dynelID.m_Instance + "])";
			logMessage = "Special lore (" + formatStr + " [" + dynelID + "])";
			break;
		case ef_LoreType_Unknown:
			fifoMessage = "Unknown lore; Please tell Peloprata.";
			chatMessage = "Unknown lore detected, please tell Peloprata (" + formatStr + " [" + dynelID + "])";
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
	var debugDetails:Array = new Array();
	if (loreType == ef_LoreType_Unknown || (m_DebugDetails & ef_DebugDetails_FormatString) == ef_DebugDetails_FormatString) {
		debugDetails.push("Identity details: " + formatStr.substring(14, formatStr.indexOf('>') - 1 ));
	}
	if (loreType == ef_LoreType_Unknown || (m_DebugDetails & ef_DebugDetails_Location) == ef_DebugDetails_Location) {
		// Not entirely clear on what the "attractor" parameter is for, but leaving it at 0 lines up with world coordinates reported through other means (shift F9, topbars)
		// In world coordinates, Y is vertical and, as the least relevant coordinate, it is therefore listed last.
		var pos:Vector3 = dynel.GetPosition(0);
		debugDetails.push("Playfield: " + dynel.GetPlayfieldID() + " Coordinates: [" + Math.round(pos.x) + ", " + Math.round(pos.z) + ", " + Math.round(pos.y) + "]");
	}	
	if ((m_DebugDetails & ef_DebugDetails_StatDump) == ef_DebugDetails_StatDump) {
		debugDetails.push("Stat Dump:"); // Fishing expedition, trying to find anything potentially useful
		for (var statID:Number = 0; statID < c_DebugDetails_StatCount; ++statID) {			
			var val = dynel.GetStat(statID, 0);
			if (val != undefined && val != 0) {
				debugDetails.push("Stat: #" + statID + " Value: " + val);
			}		
		}
	}
	
	// Dispatch notifications
	if ((m_FifoMessageLore & loreType) == loreType) {
		Chat.SignalShowFIFOMessage.Emit(fifoMessage, 0);
		}
	if ((m_ChatMessageLore & loreType) == loreType) {
		Utils.PrintChatText("<font color='#00FFFF'>LoreHound</font>: " + chatMessage);
		for (var i:Number = 0; i < debugDetails.length; ++i) {
			Utils.PrintChatText(debugDetails[i]);
		}
	}		
	if ((m_LogMessageLore & loreType) == loreType) {
		Log.Error("LoreHound", logMessage);
		for (var i:Number = 0; i < debugDetails.length; ++i) {
			Log.Error("LoreHound", debugDetails[i]);
		}
	}
}