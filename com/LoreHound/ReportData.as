class com.LoreHound.ReportData {
	public var m_ID:Number;
	public var m_Text:String;
	
	public function ReportData(id:Number, subject:String, details:Array) {
		m_ID = id;
		m_Text = subject;
		if (details.length > 0) {
			m_Text += "\n" + details.join("\n");
		}
	}
}