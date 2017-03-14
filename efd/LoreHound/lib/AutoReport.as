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

// Automated error/information reporting framework
// Accepts arbitrary report items, as long as they have an:
//   Accessible and comparable "id" attribute, to reduce duplicate reporting
//   Accessible "text" attribute, providing the message to be dispatched
// Compiles a list of unique(by ID) report items, testing both those in the queue, and those previously sent
// When the user enters the bank interface it will attempt to send those reports automaticly by ingame mail
// Queued reports, and a list of report IDs sent are stored as a Config object, and can be persisted by the mod if desired.

class efd.LoreHound.lib.AutoReport {

	private var m_Enabled:Boolean = false;
	private var m_Config:ConfigWrapper;

	public function get IsEnabled():Boolean { return m_Enabled; }
	public function set IsEnabled(value:Boolean) {
		if (Character.GetClientCharacter().GetName() == m_Recipient) {
			// Can't send mail to ourselves, system should remain disabled
			value = false;
		}
		if (value != m_Enabled) {
			if (value) {
				m_MailTrigger.SignalChanged.Connect(TriggerReports, this);
				Tradepost.SignalMailResult.Connect(VerifyReceipt, this);
			} else {
				m_MailTrigger.SignalChanged.Disconnect(TriggerReports, this);
				Tradepost.SignalMailResult.Disconnect(VerifyReceipt, this);
			}
			m_Enabled = value;
		}
	}

	public function get HasReportsPending():Boolean { return m_Config.GetValue("QueuedReports").length > 0; }
	public var SignalReportsSent:Signal;

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
	 	m_Config.NewSetting("QueuedReports", new Array());
		m_Config.NewSetting("PriorReports", new Array());

		SignalReportsSent = new Signal();
		m_MailTrigger = DistributedValue.Create("tradepost_window");
		IsEnabled = true;
	}

	public function GetConfigWrapper():ConfigWrapper {
		return m_Config;
	}

	public function AddReport(report:Object):Boolean {
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
				return false;
		}
		queue.push(report);
		m_Config.IsDirty = true;
		Utils.PrintChatText("<font color='#00FFFF'>" + m_ModName + "</font>: An automated report has been generated, and will be sent when next you are at the bank.");
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
					Utils.PrintChatText("<font color='#00FFFF'>" + m_ModName + "</font>: One or more automated reports failed to send and will remain queued.");
				}
			}
		}
	}

	private function VerifyReceipt(success:Boolean, error:String):Void {
		// We only care about our own messages, not about other mail
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
				m_Config.IsDirty = true;
				// Continue sending reports as needed
				if (queue.length > 0) {
					// Delay to avoid triggering flow restrictions
					setTimeout(Delegate.create(this, SendReport), c_RetryDelay, 0);
				} else {
					Utils.PrintChatText("<font color='#00FFFF'>" + m_ModName + "</font>: All queued reports have been sent. Thank you for your assistance.");
					SignalReportsSent.Emit();
				}
			} else {
				// Reset index, and keep remaining reports to retry later
				m_ReportsSent = 0;
				Utils.PrintChatText("<font color='#00FFFF'>" + m_ModName + "</font>: One or more automated reports could not be delivered and will remain queued. (Reason: " + error + ")");
			}
		}
	}

}
