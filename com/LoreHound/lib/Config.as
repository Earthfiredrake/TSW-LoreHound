import com.GameInterface.DistributedValue;
import com.Utils.Archive;
import com.Utils.Signal;

class com.LoreHound.lib.Config {
	
	public var SignalValueChanged:Signal;
	
	private var m_ArchiveName:String;
	private var m_Settings:Object;
	
	private var e_ArchivedSetting:Number = 1; // Saves into the archive
	private var e_DistributedSetting:Number = 2; // Distributed variable, persistance determined elsewhere
	
	public function Config(archiveName:String) {
		SignalValueChanged = new Signal();
		m_ArchiveName = archiveName;
		m_Settings = new Object();
	}
	
	public function NewSetting(key:String, defaultValue, type:Number = e_ArchivedSetting):Void {
		switch (type) {
			case e_ArchivedSetting:
				m_Settings[key] = {
					type: e_ArchivedSetting,
					value: defaultValue,
					defaultValue: defaultValue
				};
				break;
			case e_DistributedSetting:
				var dv:DistributedValue = DistributedValue.Create(key);
				dv.SignalChanged.Connect(DVCallback, this);
				m_Settings[key] = {					
					type: e_DistributedSetting,
					distVal: dv,
					defaultValue: defaultValue,
					oldValue: dv.GetValue()					
				};								
				break;
			default:
			// Bad type value
		}
	}	
	
	private function DVCallback(dv:DistributedValue):Void {
		SignalValueChanged.Emit(dv.GetName(), dv.GetValue(), m_Settings[dv.GetName()].oldValue);
		m_Settings[dv.GetName()].oldValue = dv.GetValue();
	}
	
	public function GetValue(key:String) {
		if (m_Settings[key] == undefined) {
			return;
		}
		switch (m_Settings[key].type) {
			case e_ArchivedSetting:
				return m_Settings[key].value;
			case e_DistributedSetting:
				return m_Settings[key].distVal.GetValue();
			default:
			// Bad type value
		}
	}
	
	public function GetDefault(key:String) {
		if (m_Settings[key] == undefined) {
			return;
		}
		return m_Settings[key].defaultValue;
	}
	
	public function SetValue(key:String, value) {		
		if (m_Settings[key] == undefined) {
			// Setting is not defined
			return;
		}
		var equalityCheckTypes:Object = { boolean: true, number: true, string: true };
		var oldVal = GetValue(key);
		if (equalityCheckTypes[typeof(value)] && oldVal == value) return value;
		switch (m_Settings[key].type) {
			case e_ArchivedSetting:
				m_Settings[key].value = value;
				SignalValueChanged.Emit(key, value, oldVal);
				break;
			case e_DistributedSetting:
				m_Settings[key].distVal.SetValue(value);
				// Distributed value hook will handle our self notification
				break;
			default:
			// Bad type value
		}
		return value;
	}

	public function ToArchive(): Archive {
		var archive:Archive = new Archive();
		archive.AddEntry("ArchiveType", "Config"); // Tag this archive as a Config object
		for (var key:String in m_Settings) {
			if (m_Settings[key].type == e_ArchivedSetting) {				
				var value:Object = GetValue(key);
				// TODO: Account for specific types
				if (value instanceof Config) {
					archive.AddEntry(key, value.ToArchive());
				} else if (value instanceof Archive) {
					archive.AddEntry(key, value);
				} else if (value instanceof Array || value instanceof Object) {
					var wrapper:Archive = new Archive();					
					var values:Archive = new Archive();
					wrapper.AddEntry("ArchiveType", (value instanceof Array) ? "Array" : "Object");					
					
					for (var i:String in value) {
						wrapper.AddEntry("keys", i);
						values.AddEntry(i, value[i]);
					}
					
					wrapper.AddEntry("values", values);
					archive.AddEntry(key, wrapper);
				} else { // Basic type
					archive.AddEntry(key, value);
				}
			}
		}
		return archive;
	}
	
	public function FromArchive(archive:Archive) {
		if (archive == undefined || !(archive instanceof Archive)) return;
		for (var key:String in m_Settings) {
			if (m_Settings[key].type == e_ArchivedSetting) {				
				var element:Object = archive.FindEntry(key, null);
				if (element == null) continue;
				var value;
				
				if (element instanceof Archive) {
					var type:String = element.FindEntry("ArchiveType");
					switch (type) {
						case "Config":
							m_Settings[key].value.FromArchive(element);
							continue;
						case "Array": // An array														
						case "Object": // Serialized entry of unspecified type
							value = type == "Array" ? new Array() : new Object();

							var keys:Array = element.FindEntryArray("keys");
							var values:Archive = element.FindEntry("values");
							for (var i in keys) {
								value[keys[i]] = values.FindEntry(keys[i]);
							}
							break;
						default: // An unaddorned archive
							value = element;
							break
					}
				} else {
					// A basic type
					value = element;					
				}
				SetValue(key, value);
			}
		}
	}

}
