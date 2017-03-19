// Copyright 2017, Earthfiredrake (Peloprata)
// Released under the terms of the MIT License
// https://github.com/Earthfiredrake/TSW-LoreHound

import gfx.utils.Delegate;

import com.GameInterface.DistributedValue;
import com.GameInterface.Game.Character;
import com.GameInterface.Tradepost;
import com.GameInterface.Utils;
import com.Utils.Signal;

import efd.LoreHound.lib.ConfigWrapper;
import efd.LoreHound.lib.Mod;

// Automated error/information reporting framework
// Accepts arbitrary report items, as long as they have an:
//   Accessible and comparable "id" attribute, to reduce duplicate reporting
//   Accessible "text" attribute, providing the message to be dispatched
// Compiles a list of unique(by ID) report items, testing both those in the queue, and those previously sent
// When the user enters the bank interface it will attempt to send those reports automaticly by ingame mail
// Queued reports, and a list of report IDs sent are stored as a Config object, and can be persisted by the mod if desired.

class efd.LoreHound.lib.AutoReport {

	private var m_Config:ConfigWrapper;

	public function get IsEnabled():Boolean {
		// This is only internal state
		return m_Config.GetValue("Enabled") && Character.GetClientCharacter().GetName() != m_Recipient;
	}
	public function set IsEnabled(modEnabled:Boolean) {
		// These include mod enabled states
		if (modEnabled != undefined) { IsModActive = modEnabled; }
		if (IsModActive && IsEnabled) {
			m_MailTrigger.SignalChanged.Connect(TriggerReports, this);
			Tradepost.SignalMailResult.Connect(VerifyReceipt, this);
		} else {
			m_MailTrigger.SignalChanged.Disconnect(TriggerReports, this);
			Tradepost.SignalMailResult.Disconnect(VerifyReceipt, this);
		}
	}
	public function get HasReportsPending():Boolean {
		// Does not care about mod state, only internal state
		return IsEnabled && m_Config.GetValue("QueuedReports").length > 0;
	}

	// Mailing information
    private var m_ModName:String;
	private var m_ModVersion:String;
	private var m_Recipient:String;

	private var m_ReportsSent:Number = 0; // Counts the number of reports sent in the last mail
	private var m_MailTrigger:DistributedValue;

	private static var c_MaxRetries = 5;
	private static var c_RetryDelay = 10;
	private static var c_MaxMailLength = 3000;

	public function AutoReport(modName:String, modVer:String, devCharName:String) {
		m_ModName = modName;
		m_ModVersion = modVer;
		m_Recipient = devCharName;

		m_Config = new ConfigWrapper();
		m_Config.NewSetting("Enabled", false); // For privacy reasons, this system should be opt-in
	 	m_Config.NewSetting("QueuedReports", new Array());
		m_Config.NewSetting("PriorReports", new Array());
		m_Config.SignalValueChanged.Connect(ConfigChanged, this);

		m_MailTrigger = DistributedValue.Create("tradepost_window");
	}

	public function GetConfigWrapper():ConfigWrapper {
		return m_Config;
	}

	private function ConfigChanged(setting:String, newValue, oldValue):Void {
		switch (setting) {
			case "Enabled":
				IsEnabled = undefined; // Update enabled state without changing mod state
				break;
			default: break;
		}
	}

	public function AddReport(report:Object):Boolean {
		if (!IsModActive) { TraceMsg("Inactive mod is queuing reports!"); }
		if (!IsEnabled) {
			// Don't build up queue while system is disabled
			return false;
		}
		// Ensure that report ids are only sent once
		var contains = function (array:Array, comparator:Function):Boolean {
			for (var i:Number = 0; i < array.length; ++i) {
				if (comparator(array[i])) { return true; }
			}
			return false;
		}
		var queue:Array = m_Config.GetValue("QueuedReports");
		if (contains(m_Config.GetValue("PriorReports"), function (id):Boolean { return id == report.id; }) ||
			contains(queue, function (pending):Boolean { return pending.id == report.id; })) {
				TraceMsg("Report ID #" + report.id + " is already pending or sent.");
				return false;
		}
		queue.push(report);
		m_Config.NotifyChange("QueuedReports");
		ChatMsg("A report has been generated and will be sent when you are next at the bank.");
		return true;
	}

	private function TriggerReports(dv:DistributedValue):Void {
		if (dv.GetValue()) {
			// Only try to send when the bank is opened
			SendReport(0);
		}
	}

	private function SendReport(attempt:Number):Void {
		var queue:Array = m_Config.GetValue("QueuedReports");
		if (queue.length > 0) {
			// Compose the automated report message, splitting it if it would exceed our max mail length
			var msg:String = m_ModName + ": Automated report (" + m_ModVersion + ")";
			while (m_ReportsSent < queue.length && (msg.length + queue[m_ReportsSent].text.length) < c_MaxMailLength) {
				msg += "\n" + queue[m_ReportsSent++].text;
			}

			// WARNING: The third parameter in this function is the pax to include in the mail. This must ALWAYS be 0.
			//   While a FiFo message is displayed by sending mail, it is easy to overlook and does not tell you who the recipient was.
			if (!Tradepost.SendMail(m_Recipient, msg, 0)) {
				// Failed to send, will delay and retry up to max attempts
				m_ReportsSent = 0;
				if (attempt < c_MaxRetries) {
					setTimeout(Delegate.create(this, SendReport), c_RetryDelay, attempt + 1);
				} else {
					ChatMsg("One or more reports failed to send and will remain queued.");
				}
			}
		}
	}

	private function VerifyReceipt(success:Boolean, error:String):Void {
		// We only care about our own messages, not about other mail
		// Assuming that this is triggered immediately after the send
		// Problematic if there could be multiple mails in transit
		if (m_ReportsSent > 0) {
			if (success) {
				// Record and clear sent reports
				var queue:Array = m_Config.GetValue("QueuedReports");
				var sent:Array = m_Config.GetValue("PriorReports");
				for (var i:Number = 0; i < m_ReportsSent; ++i) {
					sent.push(queue[i].id);
				}
				queue.splice(0, m_ReportsSent);
				m_ReportsSent = 0;
				m_Config.NotifyChange("QueuedReports");
				m_Config.NotifyChange("PriorReports");
				// Continue sending reports as needed
				if (queue.length > 0) {
					// Delay to avoid triggering flow restrictions
					setTimeout(Delegate.create(this, SendReport), c_RetryDelay, 0);
				} else {
					ChatMsg("All queued reports have been sent. Thank you for your assistance.");
				}
			} else {
				// Reset index, and keep remaining reports to retry later
				m_ReportsSent = 0;
				ChatMsg("One or more reports could not be delivered and will remain queued. (Reason: " + error + ")");
			}
		}
	}

	private function ChatMsg(msg:String, suppressLeader:Boolean):Void {
		if (!suppressLeader) {
			Mod.ChatMsgS("AutoReport - " + msg, suppressLeader);
		} else { Mod.ChatMsgS(msg, suppressLeader); }
	}

	private function TraceMsg(msg:String, suppressLeader:Boolean):Void {
		if (!suppressLeader) {
			Mod.TraceMsgS("AutoReport - " + msg, suppressLeader);
		} else { Mod.TraceMsgS(msg, suppressLeader); }
	}

	private var IsModActive:Boolean;
}
