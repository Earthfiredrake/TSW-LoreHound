// Copyright 2017, Earthfiredrake (Peloprata)
// Released under the terms of the MIT License

import com.GameInterface.DistributedValue;
import com.GameInterface.Game.Character;
import com.GameInterface.Tradepost;
import com.GameInterface.Utils;

// Automated error/information reporting framework
// Accepts arbitrary report items, as long as they have an:
//   Accessible and comparable "m_ID" attribute, to reduce duplicate reporting
//   Accessible toString() method, to convert the data into a valid output
// Compiles a list of unique(by ID) report items
// when the user enters the bank interface it will attempt to send those reports automaticly by ingame mail

// To avoid multiple mods fighting each other over mail times, make this static and shared?
//   This concept may result in versioning issues however.

class com.LoreHound.lib.AutoReport {
				
    private var m_ModName:String;				
	private var m_ModVersion:String;
	private var m_Recipient:String;				
				
	private var m_ReportQueue:Array = new Array();
	private var m_ReportSplitIndex:Number = 0;	
	private var m_MailTrigger:DistributedValue;
	
	private var c_MaxAttempts = 5;
	private var c_MaxMailLength = 3000;

	// modName will be used as part of the identifying header for mailed reports
	// devCharName is the ingame nickname of the character to whom the mail should be sent
	public function AutoReport(modName:String, modVer:String, devCharName:String) {
		m_ModName = modName;
		m_Recipient = devCharName;
		// Sending mail requires the bank window be open, so we hook to that as our trigger
		m_MailTrigger = DistributedValue.Create("tradepost_window");
		m_MailTrigger.SignalChanged.Connect(TriggerReports, this);
		// To ensure the data is retained, we verify that the mail is recieved
		Tradepost.SignalMailResult.Connect(VerifyReceipt, this);
	}
	
	public function AddReport(report:Object):Boolean {
		if (Character.GetClientCharacter().GetName() == m_Recipient) {
			// Unable to send mail to self, so prevent building up a report queue
			return false;
		}
		for (var i:Number = 0; i < m_ReportQueue.length; ++i) {
			// Ensure that report ids are unique (to avoid redundant info)
			if (m_ReportQueue[i].m_ID == report.m_ID) {
				return false;
			}
		}
		m_ReportQueue.push(report);
		Utils.PrintChatText("<font color='#00FFFF'>" + m_ModName + "</font>: An automated report has been generated, and will be sent when next you are at the bank.");
		return true;
	}
	
	private function TriggerReports(dv:DistributedValue):Void {
		if (dv.GetValue() && Character.GetClientCharacter().GetName() != m_Recipient) {
			// Only try to send when the bank is opened, and only if it wouldn't be to self
			SendReport(0);
		}
	}
	
	private function SendReport(attempt:Number):Void {
		if (m_ReportQueue.length > 0) {
			var msg:String = m_ModName + ": Automated report (" + m_ModVersion + ")";
			while (m_ReportSplitIndex < m_ReportQueue.length && (msg.length + m_ReportQueue[m_ReportSplitIndex].toString().length) < c_MaxMailLength) {
				msg += "\n" + m_ReportQueue[m_ReportSplitIndex++].toString();
			}
			
			// WARNING: The third parameter in this function is the pax to include in the mail. This must ALWAYS be 0.
			//   While a FiFo message is displayed by sending mail, it is easy to overlook and does not tell you who the recipient was.
			if (!Tradepost.SendMail(m_Recipient, msg, 0)) {
				// Failed to send, will retry with 10ms delay
				m_ReportSplitIndex = 0;
				if (attempt < c_MaxAttempts) {
					setTimeout(SendReport, 10, attempt+1);
				} else {
					Utils.PrintChatText("<font color='#00FFFF'>" + m_ModName + "</font>: One or more automated reports failed to send and will be retried later.");
				}
			}
		}
	}
	
	private function VerifyReceipt(success:Boolean, error:String):Void {
		if (success) {
			// Clear sent reports
			m_ReportQueue.splice(0, m_ReportSplitIndex);
			m_ReportSplitIndex = 0;
			// Continue sending reports as needed
			if (m_ReportQueue.length > 0) {
				// 10ms delay to avoid flow control systems
				setTimeout(SendReport, 10, 0);
			} else {
				Utils.PrintChatText("<font color='#00FFFF'>" + m_ModName + "</font>: All queued reports have been sent. Thank you for your assistance.");
			}
		} else {
			// Reset index, but keep remaining array to retry later
			m_ReportSplitIndex = 0;
			Utils.PrintChatText("<font color='#00FFFF'>" + m_ModName + "</font>: One or more automated reports could not be delivered, and will be retried later. (Reason: " + error + ")");
		}
	}

}
