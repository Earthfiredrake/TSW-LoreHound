// Copyright 2017, Earthfiredrake (Peloprata)
// Released under the terms of the MIT License
// https://github.com/Earthfiredrake/TSW-LoreHound

import com.GameInterface.DistributedValue;
import com.GameInterface.Game.Character; // To prevent self mailing
import com.GameInterface.Tradepost;

import efd.LoreHound.lib.ConfigWrapper;
import efd.LoreHound.lib.LocaleManager;
import efd.LoreHound.lib.Mod;

// Automated error/information reporting framework
// Accepts arbitrary report items, as long as they have an:
//   Accessible and comparable "id" attribute, to reduce duplicate reporting
//   Accessible "text" attribute, providing the message to be dispatched
// Compiles a list of unique(by ID) report items, testing both those in the queue, and those previously sent
// When the user enters the bank interface it will attempt to send those reports automaticly by ingame mail
// Queued reports, and a list of report IDs sent are stored as a Config object, and can be persisted by the mod if desired.

class efd.LoreHound.lib.AutoReport {
	private function AutoReport() { } // Static class, don't really need more than one/mod

	public static function Initialize(modName:String, modVer:String, devCharName:String):ConfigWrapper {
		MailHeader = modName + ": Automated report (" + modVer + ")";
		Recipient = devCharName;
		MailTrigger = DistributedValue.Create("tradepost_window");

		Config = new ConfigWrapper();
		Config.NewSetting("Enabled", false); // For privacy reasons, this system should be opt-in
	 	Config.NewSetting("QueuedReports", new Array());
		Config.NewSetting("PriorReports", new Array());
		Config.SignalValueChanged.Connect(ConfigChanged); // Unaffected by load-time triggers, no need to defer
		return Config;
	}

	private static function ConfigChanged(setting:String, newValue, oldValue):Void {
		switch (setting) {
			case "Enabled":
				IsEnabled = undefined; // Update enabled state without changing mod state
				break;
			default: break;
		}
	}

	public static function AddReport(report:Object):Boolean {
		if (!IsModActive) { TraceMsg("Inactive mod is queuing reports!"); }
		if (!IsEnabled) {
			// Don't build up queue while system is disabled
			return false;
		}
		// Verify that the report will fit in a mail
		// Otherwise a single oversized report at the head of the queue could block it up eternally
		if (!(MailHeader.length + report.text.length < MaxMailLength)) {
			TraceMsg("Report was too long to fit in mail and has been discarded.");
			return false;
		}
		// Ensure that report ids are only sent once
		var contains = function (array:Array, comparator:Function):Boolean {
			for (var i:Number = 0; i < array.length; ++i) {
				if (comparator(array[i])) { return true; }
			}
			return false;
		};
		var queue:Array = Config.GetValue("QueuedReports");
		if (contains(Config.GetValue("PriorReports"), function (id):Boolean { return id == report.id; }) ||
			contains(queue, function (pending):Boolean { return pending.id == report.id; })) {
				TraceMsg("Report ID #" + report.id + " is already pending or sent.");
				return false;
		}
		queue.push(report);
		Config.NotifyChange("QueuedReports");
		ChatMsg(LocaleManager.GetString("AutoReport", "ReportQueued"));
		return true;
	}

	// To reduce config file size, clean out any pending or sent reports that are no longer required
	public static function CleanupReports(removalPredicate:Function):Void {
		var cleanArray:Array = new Array();
		var sourceArray:Array = Config.GetValue("PriorReports");
		for (var i:Number = 0; i < sourceArray.length; ++i) {
			if (!removalPredicate(sourceArray[i])) {
				cleanArray.push(sourceArray[i]);
			}
		}
		Config.SetValue("PriorReports", cleanArray);
		TraceMsg("Sent report cleanup removed " + (sourceArray.length - cleanArray.length) + " records, " + cleanArray.length + " records remain.");
		cleanArray = new Array();
		sourceArray = Config.GetValue("QueuedReports");
		for (var i:Number = 0; i < sourceArray.length; ++i) {
			if (!removalPredicate(sourceArray[i].id)) {
				cleanArray.push(sourceArray[i]);
			}
		}
		Config.SetValue("QueuedReports", cleanArray);
		TraceMsg("Queued report cleanup removed " + (sourceArray.length - cleanArray.length) + " records, " + cleanArray.length + " records remain.");
	}

	private static function TriggerReports(dv:DistributedValue):Void {
		if (dv.GetValue()) {
			// Only try to send when the bank is opened
			SendReport(0);
		}
	}

	private static function SendReport(attempt:Number):Void {
		var queue:Array = Config.GetValue("QueuedReports");
		if (queue.length > 0) {
			// Compose the automated report message, splitting it if it would exceed our max mail length
			var msg:String = MailHeader;
			while (ReportsSent < queue.length && (msg.length + queue[ReportsSent].text.length) < MaxMailLength) {
				msg += "\n" + queue[ReportsSent++].text;
			}

			// Request delivery confirmation
			Tradepost.SignalMailResult.Connect(VerifyReceipt);
			// WARNING: The third parameter in this function is the pax to include in the mail. This must ALWAYS be 0
			//   While a FiFo message is displayed by sending mail, it is easy to overlook and does not tell you who the recipient was
			if (!Tradepost.SendMail(Recipient, msg, 0)) {
				// Failed to send, will delay and retry up to max attempts
				ReportsSent = 0;
				if (attempt < MaxRetries) {
					setTimeout(SendReport, RetryDelay, attempt + 1);
				} else {
					ChatMsg(LocaleManager.GetString("AutoReport", "FailSend"));
				}
			}
		}
	}

	private static function VerifyReceipt(success:Boolean, error:String):Void {
		// We only care about our own messages, not about other mail
		// Assuming that this is triggered immediately after the send
		// Problematic if there could be multiple mails in transit
		if (ReportsSent > 0) {
			// Detach this handler
			Tradepost.SignalMailResult.Disconnect(VerifyReceipt);
			if (success) {
				// Record and clear sent reports
				var queue:Array = Config.GetValue("QueuedReports");
				var sent:Array = Config.GetValue("PriorReprots");
				for (var i:Number = 0; i < ReportsSent; ++i) {
					sent.push(queue[i].id);
				}
				queue.splice(0, ReportsSent);
				ReportsSent = 0;
				Config.NotifyChange("QueuedReports");
				Config.NotifyChange("PriorReports");
				// Continue sending reports as needed
				if (queue.length > 0) {
					// Delay to avoid triggering flow restrictions
					setTimeout(SendReport, RetryDelay, 0);
				} else {
					ChatMsg(LocaleManager.GetString("AutoReport", "Submitted"));
				}
			} else {
				// Reset index, and keep remaining reports to retry later
				ReportsSent = 0;
				ChatMsg(LocaleManager.GetString("AutoReport", "FailDeliver"));
				ChatMsg(LocaleManager.FormatString("AutoReport", "ErrorDesc", error), { noPrefix : true });
			}
		}
	}

	private static function ChatMsg(msg:String, options:Object):Void {
		if (options == undefined) { options = new Object(); }
		options.system = "AutoReport";
		Mod.ChatMsg(msg, options);
	}

	private static function TraceMsg(msg:String, options:Object):Void {
		if (options == undefined) { options = new Object(); }
		options.system = "AutoReport";
		Mod.TraceMsg(msg, options);
	}

	public static function get IsEnabled():Boolean {
		// This is only internal state
		return Config.GetValue("Enabled") && Character.GetClientCharacter().GetName() != Recipient;
	}

	public static function set IsEnabled(modEnabled:Boolean):Void {
		// These include mod enabled states
		if (modEnabled != undefined) { IsModActive = modEnabled; }
		if (IsModActive && IsEnabled) {
			MailTrigger.SignalChanged.Connect(TriggerReports);
		} else {
			MailTrigger.SignalChanged.Disconnect(TriggerReports);
		}
	}

	public static function get NumReportsPending():Number {
		// Does not care about mod state, only internal state
		return IsEnabled ? Config.GetValue("QueuedReports").length : 0;
	}

	private static var IsModActive:Boolean;
	private static var Config:ConfigWrapper;

	// Mailing information
	private static var MailHeader:String;
	private static var Recipient:String;

	private static var ReportsSent:Number = 0; // Counts the number of reports sent in the last mail
	private static var MailTrigger:DistributedValue;

	private static var MaxRetries = 5;
	private static var RetryDelay = 10;
	private static var MaxMailLength = 3000;
}
