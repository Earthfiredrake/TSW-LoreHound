// Copyright 2017, Earthfiredrake (Peloprata)
// Released under the terms of the MIT License

class com.LoreHound.ReportData {
	public var m_ID:Number;
	private var m_Text:String;
	
	public function ReportData(id:Number, subject:String, details:Array) {
		m_ID = id;
		m_Text = subject;
		if (details.length > 0) {
			m_Text += "\n" + details.join("\n");
		}
	}
	
	public function toString():String {
		return m_Text;
	}
}