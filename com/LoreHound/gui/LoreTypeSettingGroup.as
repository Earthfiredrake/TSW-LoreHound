import gfx.core.UIComponent;

import com.LoreHound.LoreHound;

class com.LoreHound.gui.LoreTypeSettingGroup extends UIComponent {

	private var m_GroupTitle:TextField;
	private var m_CBFifoEnabled:MovieClip;
	private var m_CBChatEnabled:MovieClip;

	private var m_Type:Number;

	private function LoreTypeSettingGroup() {
		super();
	}

	private function configUI():Void {
		super.configUI();
		m_CBFifoEnabled.disableFocus = true;
		m_CBChatEnabled.disableFocus = true;
	}

	public function SetType(loreType:Number):Void {
		m_Type = loreType;
		switch(loreType) {
		case LoreHound.ef_LoreType_Common:
			m_GroupTitle.text = "Standard Lore";
			break;
		case LoreHound.ef_LoreType_Triggered:
			m_GroupTitle.text = "Triggered Lore";
			break;
		case LoreHound.ef_LoreType_Drop:
			m_GroupTitle.text = "Timed Drop Lore";
			break;
		case LoreHound.ef_LoreType_Special:
			m_GroupTitle.text = "Unusual Lore";
			break;
		case LoreHound.ef_LoreType_Unknown:
			m_GroupTitle.text = "Uncategorized Lore";
			break;
		}
	}

}
