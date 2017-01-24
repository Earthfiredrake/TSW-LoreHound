import com.GameInterface.DistributedValue;
import com.Utils.Archive;
import com.Utils.Signal;

class com.LoreHound.lib.Config {
	
	public var SignalValueChanged:Signal;
	
	private var m_DistributedSettings:Object;
	private var m_ArchiveName:String;
	private var m_Settings:Object;
	
	public function Settings(archiveName:String) {
		SignalValueChanged = new Signal();
		m_ArchiveName = archiveName;
		m_Settings = new Object();
	}
	
	public function NewSetting(key:String, defaultValue):Void {
		m_Settings[key] = {
			value: defaultValue,
			defaultValue: defaultValue
		};
	}
	
	public function NewDistributedSetting(key:String):Void {
		m_DistributedSettings[key] = {
			
		}
	}
	
	public function GetValue(key:String) {
		if (prefs[key] == undefined) {
			return;
		}
		return prefs[key].value;
	}
	
	public function GetDefault(key:String) {
		if (prefs[key] == undefined) {
			return;
		}
		return prefs[key].defaultValue;
	}
	
	public function SetValue(key:String, value) {		
		if (m_Settings[key] == undefined) {
			// Setting is not defined
			return;
		}
		var equalityCheckTypes:Object = { boolean: true, number: true, string: true };
		var oldVal = m_Settings[key].value;
		if (equalityCheckTypes[typeof(value)] && oldVal == value) return value;
		m_Settings[key].value = value;
		SignalValueChanged.Emit(key, value, oldVal);
		return value;
	}
	
	public function FromArchive(archive:Archive) {
		if (archive == undefined || !(archive instanceof Archive)) return;
		for (var key:String in m_Settings) {
			var value = archive.FindEntry(key, null);
			if (value == null) continue;
			
			m_Settings[key].value = value;
		}
	}
	
	public function ToArchive(): Archive {
		var archive:Archive = new Archive();
		for (var key:String in m_Settings) {
			var value:Object = m_Settings[key];
			archive.AddEntry(key, value);
		}
		return archive;
	}

}
