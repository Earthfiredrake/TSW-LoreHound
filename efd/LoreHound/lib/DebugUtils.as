// Copyright 2018, Earthfiredrake
// Released under the terms of the MIT License
// https://github.com/Earthfiredrake/SWL-FrameworkMod

// Provides basic debugging tools
//   LogMsg: Outputs a string to the ClientLog.txt file
//           Searching for "Scaleform.[ModName]" will find relevant entries
//           All other functions mirror to the log by default
//           Direct access avoids spamming system chat (formatted data dumps, etc.)
//           Note: Log file clears on startup, be sure to recover any logged data beforehand
//   TraceMsg: Output only if debug flag is set
//             ModName yellow, labeled Trace
//   DevMsg: Output if debug flag is set, or for mod dev's character in release builds
//           ModName orange, labeled Alert
//   ErrorMsg: Output always
//             ModName red, labeled ERROR
//   Functions all take (msg:string, options:object) parameter pairs, where options can contain the following fields:
//     sysName:String - Overrides the SystemName field for this particular message
//     noHeader:Boolean - System chat formatting ; Replaces the identifying header with a short indent;
//     noLog:Boolean - Suppress output to the Log file
//     fatal:Boolean - ErrorMsg only; Signals other systems that a mod disabling error has occured, so they can attempt to mitigate the collateral
//         Generally by disabling most functionality in the hope that a mod that isn't doing anything won't crash the game

// Mod baseclass will handle the static init and other systems are encouraged to create their own local copies so that the message sources are more identifiable
// For quick debugging, static function wrappers around Mod's instance can be accessed by appending "S" to the function

import gfx.utils.Delegate;

import com.GameInterface.DistributedValue;
import com.GameInterface.Game.Character;
import com.GameInterface.Log;
import com.GameInterface.Utils;
import com.Utils.Signal;

// Mod namespace qualified imports and class definition are #included from locally overriden file
#include "DebugUtils.lcl.as"
/// Basic interface
	// If not using framework, first instance should be generated using StaticInit()
	public function DebugUtils(sysName:String) {
		SystemName = sysName || ""; // If you named your system "false" my sympathy is limited
	}

	public function ErrorMsg(message:String, options:Object):Void {
		var isFatal:String = options.fatal ? "FATAL " : "";
		PostMsg(isFatal + "ERROR", message, ErrorColour, options);
		if (options.fatal) { SignalFatalError.Emit(); }
	}

	public function DevMsg(message:String, options:Object): Void {
		if (DebugMode || IsDev) { PostMsg("Alert", message, AlertColour, options); }
	}

	public function TraceMsg(message:String, options:Object):Void {
		if (DebugMode) { PostMsg("Trace", message, TraceColour, options); }
	}

	public function LogMsg(message:String, options:Object):Void {
		if (options.noLog) { return; }
		var sysName = options.sysName || SystemName;
		Log.Error(ModName, (sysName ? sysName + ": " : "") + message);
	}

	public static var ErrorMsgS:Function;
	public static var DevMsgS:Function;
	public static var TraceMsgS:Function;
	public static var LogMsgS:Function;

	public static var DebugMode:Boolean; // Visible so mod specific debug tools can check it

	public static var SignalFatalError:Signal; // No parameters

/// Implementation details
	// Static init called by Mod constructor, provides first instance for free, further instances should use normal construtor
	public static function StaticInit(modName:String, devName:String, dvPrefix:String, debug:Boolean):DebugUtils {
		ModName = modName;
		IsDev = Character.GetClientCharacter().GetName() == devName;
		SignalFatalError = new Signal();

		GlobalDebugDV = DistributedValue.Create("emfDebugMode");
		GlobalDebugDV.SignalChanged.Connect(SetDebugMode);
		LocalDebugDV = DistributedValue.Create(dvPrefix + modName + "DebugMode");
		LocalDebugDV.SignalChanged.Connect(SetDebugMode);
		var localDebug:Boolean = LocalDebugDV.GetValue();
		var globalDebug:Boolean = GlobalDebugDV.GetValue();
		DebugMode = localDebug != undefined ? localDebug : globalDebug != undefined ? globalDebug : debug;

		// Create Mod's instance and setup the static wrappers
		var dbu:DebugUtils = new DebugUtils();
		ErrorMsgS = Delegate.create(dbu, dbu.ErrorMsg);
		DevMsgS = Delegate.create(dbu, dbu.DevMsg);
		TraceMsgS = Delegate.create(dbu, dbu.TraceMsg);
		LogMsgS = Delegate.create(dbu, dbu.LogMsg);

		return dbu;
	}

	private function PostMsg(desc:String, message:String, colour:String, options:Object):Void {
		LogMsg(desc + " {" + message + "}", options);
		if (!options.noHeader) {
			var sysName:String = options.sysName || SystemName;
			if (sysName) { sysName += " "; }
			message = "<font color='" + colour + "'>" + ModName + "</font>: " + desc + " - " + sysName + message;
		}
		else { message = "    " + message; }
		Utils.PrintChatText(message);
	}

	private static function SetDebugMode(dv:DistributedValue):Void { DebugMode = dv.GetValue(); }

	private static var ModName:String;
	private static var IsDev:Boolean;
	private var SystemName:String;

	// See Mod for DV names and descriptions
	private static var GlobalDebugDV:DistributedValue;
	private static var LocalDebugDV:DistributedValue;

	private static var ErrorColour:String = "#EE0000";
	private static var AlertColour:String = "#FF5000";
	private static var TraceColour:String = "#FFB555";
}
