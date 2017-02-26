// Copyright 2017, Earthfiredrake (Peloprata)
// Released under the terms of the MIT License
// https://github.com/Earthfiredrake/TSW-LoreHound
// Based off of the Preferences class of El Torqiro's ModUtils library:
//   https://github.com/eltorqiro/TSW-Utils
//   Copyright 2015, eltorqiro
//   Usage under the terms of the MIT License

import com.GameInterface.DistributedValue;
import com.Utils.Archive;
import com.Utils.Signal;

// WARNING: Recursive or cyclical data layout is verboten.
//   A config setting holding a reference to a direct ancestor will cause infinite recursion during serialization.

class com.LoreHound.lib.Config {

	public var SignalValueChanged:Signal;// (settingName:String, newValue, oldValue):Void

	private var m_ArchiveName:String;
	private var m_Settings:Object;

	public function Config(archiveName:String) {
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

	private function DVCallback(dv:DistributedValue):Void {
		SignalValueChanged.Emit(dv.GetName(), dv.GetValue(), m_Settings[dv.GetName()].oldValue);
		m_Settings[dv.GetName()].oldValue = dv.GetValue();
	}

	public function GetValue(key:String) {
		if (m_Settings[key] == undefined) { return; }
		return m_Settings[key].value;		
	}

	public function GetDefault(key:String) {
		if (m_Settings[key] == undefined) { return; }
		return m_Settings[key].defaultValue;
	}

	public function SetValue(key:String,value) {
		if (m_Settings[key] == undefined) { return; }
		var equalityCheckTypes:Object = {boolean:true, number:true, string:true};
		var oldVal = GetValue(key);
		if (!equalityCheckTypes[typeof value] || oldVal != value) {
			m_Settings[key].value = value;
			SignalValueChanged.Emit(key, value, oldVal);
		}
		return value;
	}

	private function ToArchive():Archive {
		var archive:Archive = new Archive();
		archive.AddEntry("ArchiveType", "Config");
		// Tag this archive as a Config object;
		for (var key:String in m_Settings) {
			archive.AddEntry(key, Package(GetValue(key)));
		}
		return archive;
	}

	private function Package(value:Object) {
		if (value instanceof Config) { return value.ToArchive(); }
		if (value instanceof Archive) { return value; }
		if (value instanceof Array || value instanceof Object) {
			var wrapper:Archive = new Archive();
			var values:Archive = new Archive();
			wrapper.AddEntry("ArchiveType", value instanceof Array ? "Array" : "Object");
			for (var key:String in value) {
				wrapper.AddEntry("keys", key);
				values.AddEntry(key, Package(value[key]));
			}
			wrapper.AddEntry("values", values);
			return wrapper;
		}
		return value; // Basic type
	}

	private function FromArchive(archive:Archive):Config {
		if (archive == undefined || !(archive instanceof Archive)) {
			return this;
		}
		for (var key:String in m_Settings) {
			var element:Object = archive.FindEntry(key,null);
			if ((element == null)) {
				continue;
			}
			SetValue(key, Unpack(element, key));			
		}
		return this;
	}
	
	private function Unpack(element:Object, key:String) {		
		if (element instanceof Archive) {
			var type:String = element.FindEntry("ArchiveType");
			switch (type) {
				case "Config":
					return m_Settings[key].value.FromArchive(element);
				case "Array": 
				case "Object": // Serialized unspecified type
					var value = type == "Array" ? new Array() : new Object();
					var keys:Array = element.FindEntryArray("keys");
					var values:Archive = element.FindEntry("values");
					for (var i in keys) {
						value[keys[i]] = Unpack(values.FindEntry(keys[i]));
					}
					return value;
				default: // Unaddorned archive
					return element;
			}
		}
		return element; // Basic type
	}

	public function LoadConfig():Void {
		if (m_ArchiveName != undefined) {			
			FromArchive(DistributedValue.GetDValue(m_ArchiveName));			
		}
	}

	public function SaveConfig():Void {
		if (m_ArchiveName != undefined) {
			DistributedValue.SetDValue(m_ArchiveName, ToArchive());
		}
	}

}