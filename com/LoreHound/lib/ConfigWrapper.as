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
// Supports basic types and limited composite types (nested ConfigWrapper, Array, and generic Objects)

class com.LoreHound.lib.ConfigWrapper {

	public var SignalValueChanged:Signal; // (settingName:String, newValue, oldValue):Void

 	// The distributed value archive saved into the game settings which contains this config setting
	// Child config wrappers should leave this undefined if they are intended to be saved in the same archive
	// If there is a secondary archive to be used,
	private var m_ArchiveName:String;
	private var m_Settings:Object;
	private var m_DirtyFlag:Boolean = false;
	private var m_IsLoaded:Boolean = false;

	private var m_Archived:Archive;

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
			// In theory a nested independent archive could be saved by itself, without touching the main archive
			// but most usages will just save the main and expect it to save everything.
			// Suppose this could be expanded into a tri-state so it could skip down to the relevant sections on save.
			if (setting instanceof ConfigWrapper && setting.IsDirty) { return true; }
		}
		return false;
	}
	// Allows for higher levels to suggest that config should be saved
	// - Automated detection doesn't pick up on internal changes to objects/arrays, needs manual notification
	public function set IsDirty(value:Boolean) {
		m_DirtyFlag = value;
	}

	// ArchiveName is distributed value to be saved to for top level config wrappers
	// Leave archiveName undefined for nested config wrappers (unless they are saved seperately)
	public function ConfigWrapper(archiveName:String, trace:Boolean) {
		SignalValueChanged = new Signal();
		m_ArchiveName = archiveName;
		m_Settings = new Object();
		m_DebugTrace = trace;
	}

	// Adds a setting to this config archive
	// - Archives are all or nothing affairs, it's not recommended to try and cherry pick keys as needed
	// - If a module needs to add additional settings it should either:
	//   - Provide a subconfig wrapper, if the settings are specific to the mod
	//   - Provide its own archive, if it's a static module that can share the settings between uses
	public function NewSetting(key:String, defaultValue):Void {
		if (key == "ArchiveType") { TraceMsg("ArchiveType is a reserved setting name."); return; } // Reserved
		if (m_IsLoaded) { TraceMsg("Settings added after loading saved values (requires reload)."); }
		m_Settings[key] = {
			value: CloneValue(defaultValue),
			defaultValue: defaultValue
		};
		// Dirty flag not required
		// Worst case: An unsaved default setting is changed by an upgrade
	}

	public function GetValue(key:String) {
		if (m_Settings[key] == undefined) { TraceMsg("Setting '" + key + "' is undefined."); return; }
		return m_Settings[key].value;
	}

	// Note: Not a clone, allows direct edits to default objects
	//       Use ResetValue in preference when resetting values
	public function GetDefault(key:String) {
		if (m_Settings[key] == undefined) { TraceMsg("Setting '" + key + "' is undefined."); return; }
		return m_Settings[key].defaultValue;
	}

	public function SetValue(key:String,value) {
		if (m_Settings[key] == undefined) { TraceMsg("Setting '" + key + "' is undefined."); return; }
		var oldVal = GetValue(key);
		if (oldVal != value) { // Should compare value types properly, reference types will change if they're different objects.
			m_Settings[key].value = value;
			IsDirty = true;
			SignalValueChanged.Emit(key, value, oldVal);
		}
		return value;
	}

	public function ResetValue(key:String):Void {
		SetValue(key, CloneValue(GetDefault(key)));
	}

	public function ResetArchive():Void {
		for (var key:String in m_Settings) {
			ResetValue(key);
		}
	}

	// Allows defaults to be distinct from values for reference types
	private function CloneValue(value) {
		if (value instanceof ConfigWrapper) {
			var clone = new ConfigWrapper(value.m_ArchiveName, value.m_DebugTrace);
			for (var key:String in value.m_Settings) {
				clone.NewSetting(key, CloneValue(value.GetDefault(key)));
			}
			return clone;
		}
		if (value instanceof Array) {
			var clone = new Array();
			for (var i:Number; i < value.length; ++i) {
				clone[i] = CloneValue(value[i]);
			}
			return clone;
		}
		if (value instanceof Object) {
			var clone = new Object();
			for (var key:String in value) {
				clone[key] = CloneValue(value[key]);
			}
			return clone;
		}
		// Basic type
		return value;
	}

	private function ToArchive():Archive {
		var archive:Archive = new Archive();
		archive.AddEntry("ArchiveType", "Config");
		for (var key:String in m_Settings) {
			var pack = Package(GetValue(key));
			if (pack != undefined) { // pack may be undefined if dealing with a nested independent archive
				archive.AddEntry(key, pack);
			}
		}
		IsDirty = false;
		return archive;
	}

	private static function Package(value:Object) {
		if (value instanceof ConfigWrapper) { return value.m_ArchiveName != undefined ? value.SaveConfig() : value.ToArchive(); }
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
			TraceMsg("Archive '" + m_ArchiveName + "' could not be found. (New install?)");
			return this;
		}
		for (var key:String in m_Settings) {
			var element:Object = archive.FindEntry(key,null);
			if ((element == null)) {
				var value = GetValue(key);
				if (value instanceof ConfigWrapper && value.m_ArchiveName != undefined) {
					// Nested config saved as independent archive
					value.LoadConfig();
				} else {
					TraceMsg("Setting '" + key + "' could not be found in archive. (New setting?)");
				}
				continue;
			}
			SetValue(key, Unpack(element, key));
		}
		m_IsLoaded = true;
		IsDirty = false;
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
			m_Archived = ToArchive();
			DistributedValue.SetDValue(m_ArchiveName, m_Archived);
		}
	}

}
