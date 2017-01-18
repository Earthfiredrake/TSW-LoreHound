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

import com.GameInterface.DistributedValue;
import com.GameInterface.Game.Character;
import com.GameInterface.Tradepost;
import com.LoreHound.ReportData;

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
var m_MailMessageLore:Number = ef_LoreType_Unknown; // Lore to package as an automatic bug report

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
var m_DebugAutomatedReports:Boolean; // If Unknown lore items (or other identifiable errors) are detected, automatically sends a report when the AH is next accessed
var m_DebugDetails:Number = ef_DebugDetails_None; // Dump extended info to chat or log output
var m_DebugVerify:Boolean = true; // Do additional tests to detect inaccurate early discards

// Automated error report system
var m_ReportQueue:Array = new Array();
var m_ReportSplitIndex:Number = 0; // There is a character limit for the mail system, if too many reports are queued this is the restart index for subsequent messages
var m_MailTrigger:DistributedValue;
var c_MailRecipient:String = "Peloprata";

function onLoad():Void {
	// Lore detection signal
	VicinitySystem.SignalDynelEnterVicinity.Connect(LoreSniffer, this);
		
	// Automatic error reporting
	// Can't send mail to ourselves, so no point in trying
	m_DebugAutomatedReports = Character.GetClientCharacter().GetName() != c_MailRecipient;
	if (m_DebugAutomatedReports) {
		// Sending mail requires that the tradepost window be open, so the automated reports must be queued until that occurs, and then sent.	
		m_MailTrigger = DistributedValue.Create("tradepost_window");
		m_MailTrigger.SignalChanged.Connect(SendErrorReport, this);	
		// We also want to verify that the mail was successfully sent before discarding the report
		Tradepost.SignalMailResult.Connect(VerifyMail, this);
	}
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
	if ((m_MailMessageLore & loreType) == loreType) {
		// To reduce spam, ensure that dynelIDs are unique (a particular pickup should only be reported on once)
		var exists:Boolean = false;
		for (var i:Number = 0; i < m_ReportQueue.length; ++i) {
			if(m_ReportQueue[i].m_ID == dynelID.m_Instance) {
				exists = true;
				break;
			}
		}
		if (!exists) {
			m_ReportQueue.push(new ReportData(dynelID.m_Instance, "Category: " + loreType + "(" + LDBFormat.Translate(formatStr) + " [" + dynelID.m_Instance + "]", debugDetails));
			Utils.PrintChatText("<font color='#00FFFF'>LoreHound</font>: An automated report on detected lore has been compiled, and will be sent the next time you access the bank.");
		}
	}
}

function ReadyToSendMail(dv:DistributedValue):Void {
	if (m_DebugAutomatedReports && dv.GetValue()) {
		SendErrorReport(0);
	}
}

function SendErrorReport(attempt:Number):Void {
    if (m_ReportQueue.length > 0) {	
		// Compose the message from the queue, ensuring it is not longer than the character limit on mail (I believe that it's 3000 chars)
		var msg:String = "LoreHound: Automated report";
		while (m_ReportSplitIndex < m_ReportQueue.length && (msg.length + m_ReportQueue[m_ReportSplitIndex].m_Text.length) < 3000) {
			msg += "\n" + m_ReportQueue[m_ReportSplitIndex++].m_Text;
		}
		
		// WARNING: The third parameter in this function is the pax to include in the mail. This must ALWAYS be 0.
		//   While a FiFo message is displayed by sending mail, it is easy to overlook and does not tell you who the recipient was.
		if (!Tradepost.SendMail(c_MailRecipient, msg, 0)) {
			// If it could not be sent, retry 5 times with a small delay in between
			m_ReportSplitIndex = 0;			
			if (attempt < 5) {
				setTimeout(SendErrorReport, 10, attempt+1);
			} else {				
				Utils.PrintChatText("<font color='#00FFFF'>LoreHound</font>: One or more automated reports failed to send and will be retried later.");
			}
		}
	}
}

function VerifyMail(success:Boolean, error:String):Void {
	if (success) {
		// Clear any sent reports from the array, and reset the index
		m_ReportQueue.splice(0, m_ReportSplitIndex);
		m_ReportSplitIndex = 0;
		// Continue to send reports as needed
		if (m_ReportQueue.length > 0) {
			// 10ms delay here to avoid flow control cancelling our mail
			setTimeout(SendErrorReport, 10, 0);			
		} else {
			// TEST: This should only print after all have succeeded, and only once.
			Utils.PrintChatText("<font color='#00FFFF'>LoreHound</font>: All queued reports have been sent. Thank you for your assistance.");			
		}
	} else {
		// Failed, reset the index without clearing the array, it will retry the next time ReadyToSendMail is triggered.
		m_ReportSplitIndex = 0;
		Utils.PrintChatText("<font color='#00FFFF'>LoreHound</font>: One or more automated reports failed to be delivered and will be retried later. (Reason: " + error + ")");
	}	
}