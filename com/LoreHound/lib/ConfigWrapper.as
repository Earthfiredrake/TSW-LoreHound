// Copyright 2017, Earthfiredrake (Peloprata)
// Released under the terms of the MIT License
// https://github.com/Earthfiredrake/TSW-LoreHound
// Based off of the Preferences class of El Torqiro's ModUtils library:
//   https://github.com/eltorqiro/TSW-Utils
//   Copyright 2015, eltorqiro
//   Usage under the terms of the MIT License

import com.GameInterface.DistributedValue;
import com.GameInterface.Utils;
import com.Utils.Archive;
import com.Utils.Signal;

// WARNING: Recursive or cyclical data layout is verboten.
//   A config setting holding a reference to a direct ancestor will cause infinite recursion during serialization.
// The setting name "ArchiveType" is reserved for internal use

class com.LoreHound.lib.ConfigWrapper {

	public var SignalValueChanged:Signal; // (settingName:String, newValue, oldValue):Void

 	// The distributed value archive which this (top level) config should save to
	// Nested archives cannot be saved directly, and use the name specified at the parent level, should leave this undefined
	private var m_ArchiveName:String;
	private var m_Settings:Object;
	private var m_DirtyFlag:Boolean = false;

	public var m_DebugTrace:Boolean = false;
	private function TraceMsg(message:String):Void {
		if (m_DebugTrace) {
			Utils.PrintChatText("<font color='#00FFFF'>ConfigWrapper</font>: Trace - " + message);
		}
	}

	// Checks if this, or any nested Config settings object, is dirty
	public function get IsDirty():Boolean {
		if (m_DirtyFlag == true) { return true; }
		for (var key:String in m_Settings) {
			var setting = GetValue(key);
			if (setting instanceof ConfigWrapper && setting.IsDirty) { return true; }
		}
		return false;
	}
	// Allows for higher levels to suggest that config should be saved
	// - Automated detection doesn't pick up on internal changes to objects/arrays, needs manual notification
	public function set IsDirty(value:Boolean) {
		TraceMsg("Setting dirty flag to: " + value);
		m_DirtyFlag = value;
	}

	public function ConfigWrapper(archiveName:String, trace:Boolean) {
		SignalValueChanged = new Signal();
		m_ArchiveName = archiveName;
		m_Settings = new Object();
		m_DebugTrace = trace;
		TraceMsg("Wrapper created for archive: " + archiveName);
	}

	public function NewSetting(key:String, defaultValue):Void {
		if (key == "ArchiveType") { return; } // Reserved
		m_Settings[key] = {
			value: defaultValue,
			defaultValue: defaultValue
		};
		TraceMsg("Setting added: " + key);
		// Dirty flag not required
		// Worst case: An unsaved default setting is changed by an upgrade
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
			TraceMsg("Setting changed: " + key);
			m_Settings[key].value = value;
			IsDirty = true;
			SignalValueChanged.Emit(key, value, oldVal);
		}
		return value;
	}

	private function ToArchive():Archive {
		TraceMsg("Creating archive from config");
		var archive:Archive = new Archive();
		archive.AddEntry("ArchiveType", "Config");
		for (var key:String in m_Settings) {
			TraceMsg("Packaging setting: " + key);
			archive.AddEntry(key, Package(GetValue(key)));
		}
		m_DirtyFlag = false;
		return archive;
	}

	private static function Package(value:Object) {
		if (value instanceof ConfigWrapper) { return value.ToArchive(); }
		if (value instanceof Archive) { return value; }
		if (value instanceof Array || value instanceof Object) {
			var wrapper:Archive = new Archive();
			var values:Archive = new Archive();
			wrapper.AddEntry("ArchiveType", value instanceof Array ? "Array" : "Object");
			for (var key:String in value) {
				wrapper.AddEntry("Keys", key);
				values.AddEntry(key, Package(value[key]));
			}
			wrapper.AddEntry("Values", values);
			return wrapper;
		}
		return value; // Basic type
	}

	private function FromArchive(archive:Archive):ConfigWrapper {
		if (archive == undefined || !(archive instanceof Archive)) {
			return this;
		}
		for (var key:String in m_Settings) {
			var element:Object = archive.FindEntry(key,null);
			if ((element == null)) {
				TraceMsg("Settting not found in existing archive: " + key);
				continue;
			}
			TraceMsg("Unpacking setting from archive: " + key);
			SetValue(key, Unpack(element, key));
		}
		m_DirtyFlag = false;
		return this;
	}

	private function Unpack(element:Object, key:String) {
		if (element instanceof Archive) {
			var type:String = element.FindEntry("ArchiveType");
			switch (type) {
				case "Config":
					// Have to use the existing config, as it has the defined fields
					return m_Settings[key].value.FromArchive(element);
				case "Array":
				case "Object": // Serialized unspecified type
					var value = type == "Array" ? new Array() : new Object();
					var keys:Array = element.FindEntryArray("Keys");
					var values:Archive = element.FindEntry("Values");
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
			TraceMsg("Loading archive: " + m_ArchiveName);
			FromArchive(DistributedValue.GetDValue(m_ArchiveName));
		}
	}

	public function SaveConfig():Void {
		if (m_ArchiveName != undefined && IsDirty) {
			TraceMsg("Saving archive: " + m_ArchiveName);
			DistributedValue.SetDValue(m_ArchiveName, ToArchive());
		}
	}

}
