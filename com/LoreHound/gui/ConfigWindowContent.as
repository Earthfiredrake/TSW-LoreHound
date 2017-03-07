import com.Components.WindowComponentContent;

import com.LoreHound.LoreHound;

class com.LoreHound.gui.ConfigWindowContent extends WindowComponentContent {

	// Checkboxes
	private var m_CBModEnabled:MovieClip;
	private var m_CBIgnoreLore:MovieClip;
	private var m_CBErrorReports:MovieClip;

	private var m_CBDetailLocation:MovieClip;
	private var m_CBDetailCategory:MovieClip;
	private var m_CBDetailInstance:MovieClip;

	// Lore Groups
	private var m_CommonLoreGroup:MovieClip;
	private var m_TriggeredLoreGroup:MovieClip;
	private var m_DropLoreGroup:MovieClip;
	private var m_SpecialLoreGroup:MovieClip;
	private var m_UnknownLoreGroup:MovieClip;

	public function ConfigWindowContent() {
		super();
	}

	private function configUI():Void {
		super.configUI();
		m_CBModEnabled.disableFocus = true;
		m_CBIgnoreLore.disableFocus = true;
		m_CBErrorReports.disableFocus = true;
		m_CBDetailLocation.disableFocus = true;
		m_CBDetailCategory.disableFocus = true;
		m_CBDetailInstance.disableFocus = true;
		m_CommonLoreGroup.SetType(LoreHound.ef_LoreType_Common);
		m_TriggeredLoreGroup.SetType(LoreHound.ef_LoreType_Triggered);
		m_DropLoreGroup.SetType(LoreHound.ef_LoreType_Drop);
		m_SpecialLoreGroup.SetType(LoreHound.ef_LoreType_Special);
		m_UnknownLoreGroup.SetType(LoreHound.ef_LoreType_Unknown);
	}
}
