// Copyright 2018, Earthfiredrake
// Released under the terms of the MIT License
// https://github.com/Earthfiredrake/SWL-LoreHound

// Provides some minor debug tools
//   LogMsg: Outputs a string to the ClientLog.txt file
//           The string "Scaleform.[ModName]" can be used to find relevant entries
//           Most direct uses are for exporting data dumps, Trace and Error messages will be copied to the log
//   TraceMsg: If debug mode is enabled sends a message to System chat and the client log
//             Mod name will be yellow instead of default blue
//   ErrorMsg: Always outputs the message to System chat and the client log
//             Mod name will be red instad of default blue
//   Msg functions take an optional object parameter which accepts the following fields:
//     mlCont:Boolean - Replaces the identifying prefix with a short indent;
//         for followup information or splitting long messsages, like this
//     sysName:String - Overrides the SystemName field for this particular message
//         Mostly used to add a system name to the static "S" versions
//         LogMsg can take this as an optional second parameter
//     fatal:Boolean - ErrorMsg only; Signals other systems that a mod disabling error has occured, so they can attempt to mitigate the collateral
//         Generally by disabling most functionality in the hope that a mod that isn't doing anything won't crash the game

// Mod baseclass will handle the static init and other systems are encouraged to create their own local copies so that the message sources are more identifiable
// For quick debugging, static function wrappers around Mod's instance can be accessed by appending "S" to the function

import gfx.utils.Delegate;

import com.GameInterface.DistributedValue;
import com.GameInterface.Log;
import com.GameInterface.Utils;
import com.Utils.Signal;

class efd.LoreHound.lib.DebugUtils {
	
/// Basic interface
	public function DebugUtils(sysName:String) {
		SystemName = sysName || ""; // If you named your system "false" my sympathy is limited
	}
	
	public function ErrorMsg(message:String, options:Object):Void {
		var isFatal:String = options.fatal ? "FATAL " : "";
		PostMsg(message + "!", options, isFatal + "ERROR", ErrorColour);
		if (options.fatal) { SignalFatalError.Emit(message); }
	}
	
	public function TraceMsg(message:String, options:Object):Void {
		if (DebugMode) { PostMsg(message, options, "Trace", TraceColour); }
	}

	public function LogMsg(message:String, sysName:String):Void {
		sysName = sysName || SystemName;
		Log.Error(ModName, (sysName ? sysName + ": " : "") + message);
	}
	
	public static var ErrorMsgS:Function;
	public static var TraceMsgS:Function;
	public static var LogMsgS:Function;
	
	public static var DebugMode:Boolean; // Visible so mod specific debug tools can check it
	
	public static var SignalFatalError:Signal;	// (error:String), not entirely sure what can be done with it though
	
/// Implementation details
	// Static init called by Mod constructor
	public static function StaticInit(modName:String, dvPrefix:String, debug:Boolean):DebugUtils {
		ModName = modName;
		SignalFatalError = new Signal();
		
		GlobalDebugDV = DistributedValue.Create("emfDebugMode");
		GlobalDebugDV.SignalChanged.Connect(SetDebugMode);
		LocalDebugDV = DistributedValue.Create(dvPrefix + modName + "DebugMode");
		LocalDebugDV.SignalChanged.Connect(SetDebugMode);
		DebugMode = GlobalDebugDV.GetValue() || LocalDebugDV.GetValue() || debug;
		
		// Create Mod's instance and setup the static wrappers
		var dbu:DebugUtils = new DebugUtils();
		ErrorMsgS = Delegate.create(dbu, dbu.ErrorMsg);
		TraceMsgS = Delegate.create(dbu, dbu.TraceMsg);
		LogMsgS = Delegate.create(dbu, dbu.LogMsg);
		return dbu;
	}

	private function PostMsg(message:String, options:Object, desc:String, colour:String):Void {
		var sysName:String = options.sysName || SystemName;
		LogMsg(desc + " {" + message + "}", sysName);
		if (!options.mlCont) { message = "<font color='" + colour + "'>" + ModName + "</font>: " + desc + " - " + sysName + message; }
		else { message = "    " + message; }
		Utils.PrintChatText(message);
	}
	
	private static function SetDebugMode(dv:DistributedValue):Void { DebugMode = dv.GetValue(); }
	
	private static var ModName:String;
	private var SystemName:String;
	
	// See Mod for DV names and descriptions
	private static var GlobalDebugDV:DistributedValue;
	private static var LocalDebugDV:DistributedValue;
	
	private static var ErrorColour:String = "#EE0000";
	private static var TraceColour:String = "#FFB555";
}
