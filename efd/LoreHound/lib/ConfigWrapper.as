// Copyright 2017, Earthfiredrake (Peloprata)
// Released under the terms of the MIT License
// https://github.com/Earthfiredrake/TSW-LoreHound
// Based off of the Preferences class of El Torqiro's ModUtils library:
//   https://github.com/eltorqiro/TSW-Utils
//   Copyright 2015, eltorqiro
//   Usage under the terms of the MIT License

import flash.geom.Point;

import com.GameInterface.DistributedValue;
import com.GameInterface.Utils;
import com.Utils.Archive;
import com.Utils.Signal;

// WARNING: Recursive or cyclical data layout is verboten.
//   A config setting holding a reference to a direct ancestor will cause infinite recursion during serialization.
// The setting name "ArchiveType" is reserved for internal use
// Supports basic types and limited composite types (nested ConfigWrapper, Array, Point, and generic Object)

class efd.LoreHound.lib.ConfigWrapper {

	// TODO: SignalConfigLoaded doesn't trigger for subconfig groups on first install
	public var SignalValueChanged:Signal; // (settingName:String, newValue, oldValue):Void
	public var SignalConfigLoaded:Signal; // (initialLoad:Boolean):Void // Parameter is true when the config is loaded for the very first time

 	// The distributed value archive saved into the game settings which contains this config setting
	// Usually only has a value for the root of the config tree
	// Most options should be saved to the same archive, leaving this undefined in child nodes
	// If a secondary archive is in use, providing a value will allow both archives to be unified in a single config wrapper
	// Alternatively a config wrapper may elect to forgo the names, and offload the actual archive load/save through parameters
	// Parameters take precidence over names
	private var m_ArchiveName:String;
	private var m_Settings:Object;

	// A cache of the last loaded/saved archive, will see if it lets us get away with this
	private var m_CurrentArchive:Archive;
	private var m_DirtyFlag:Boolean = false;

	// TODO: IsLoaded will be false if nothing was loaded, which may result in multiple ConfigLoaded(true) signals
	public function get IsLoaded():Boolean { return m_CurrentArchive != undefined; }

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
			// Could be expanded into a tri-state so it could skip down to the relevant sections on save.
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
		m_ArchiveName = archiveName;
		m_Settings = new Object();
		m_DebugTrace = trace;
		SignalValueChanged = new Signal();
		SignalConfigLoaded = new Signal();
	}

	// Adds a setting to this config archive
	// - Archives are all or nothing affairs, it's not recommended to try and cherry pick keys as needed
	// - If a module needs to add additional settings it should either:
	//   - Provide a subconfig wrapper, if the settings are specific to the mod
	//   - Provide its own archive, if it's a static module that can share the settings between uses
	public function NewSetting(key:String, defaultValue):Void {
		if (key == "ArchiveType") { TraceMsg(key + " is a reserved setting name."); return; } // Reserved
		if (IsLoaded) { TraceMsg("Settings added after loading archive will have default values."); }
		m_Settings[key] = {
			value: CloneValue(defaultValue),
			defaultValue: defaultValue
		};
		// Dirty flag not required
		// Worst case: An unsaved default setting is changed by an upgrade
	}

	// If changes are made to a returned reference the caller is responsible for setting the dirty flag and firing the value changed signal
	public function GetValue(key:String) {
		if (m_Settings[key] == undefined) { TraceMsg("Setting '" + key + "' is undefined."); return; }
		return m_Settings[key].value;
	}

	// Not a clone, allows direct edits to default object
	// Use ResetValue in preference when resetting values
	public function GetDefault(key:String) {
		if (m_Settings[key] == undefined) { TraceMsg("Setting '" + key + "' is undefined."); return; }
		return m_Settings[key].defaultValue;
	}

	public function SetValue(key:String, value) {
		if (m_Settings[key] == undefined) { TraceMsg("Setting '" + key + "' is undefined."); return; }
		var oldVal = GetValue(key);
		if (oldVal != value) {
			// Points cause frequent redundant saves and are easy enough to compare
			if (value instanceof Point && oldVal.equals(value)) { return oldVal; }
			m_Settings[key].value = value;
			IsDirty = true;
			SignalValueChanged.Emit(key, value, oldVal);
		}
		return value;
	}

	// Leave state undefined to toggle a flag
	public function SetFlagValue(key:String, flag:Number, state:Boolean) {
		var flags = GetValue(key);
		switch (state) {
			case true: { flags |= flag; break; }
			case false: { flags &= ~flag; break; }
			case undefined: { flags ^= flag; break; }
		}
		SetValue(key, flags);
	}

	public function ResetValue(key:String):Void {
		var defValue = GetDefault(key);
		if (defValue instanceof ConfigWrapper) { GetValue(key).ResetAll(); }
		else { SetValue(key, CloneValue(defValue)); }
	}

	public function ResetAll():Void {
		for (var key:String in m_Settings) {
			ResetValue(key);
		}
	}

	// Allows defaults to be distinct from values for reference types
	// TODO: Very uncertain if Archives can be cloned at all, consider removing support for them below
	private function CloneValue(value) {
		if (value instanceof ConfigWrapper) {
			// No need to clone a ConfigWrapper
			// The slightly faster reset call isn't worth two extra copies of all the defaults
			return value;
		}
		if (value instanceof Point) {
			return value.clone();
		}
		if (value instanceof Array) {
			var clone = new Array();
			for (var i:Number; i < value.length; ++i) {
				clone[i] = CloneValue(value[i]);
			}
			return clone;
		}
		if (value instanceof Object) {
			// Avoid feeding this things that really shouldn't be cloned
			var clone = new Object();
			for (var key:String in value) {
				clone[key] = CloneValue(value[key]);
			}
			return clone;
		}
		// Basic type
		return value;
	}

	public function LoadConfig(archive:Archive):Void {
		if (archive == undefined) { archive = DistributedValue.GetDValue(m_ArchiveName); }
		FromArchive(archive);
	}

	public function SaveConfig():Archive {
		if (IsDirty) {
			UpdateCachedArchive();
			if (m_ArchiveName != undefined) { DistributedValue.SetDValue(m_ArchiveName, m_CurrentArchive); }
		}
		return m_CurrentArchive;
	}

	// Updates the cached m_CurrentArchive if dirty
	private function UpdateCachedArchive():Void {
		delete m_CurrentArchive;
		m_CurrentArchive = new Archive();
		m_CurrentArchive.AddEntry("ArchiveType", "Config");
		for (var key:String in m_Settings) {
			var value = GetValue(key);
			var pack = Package(value);
			if (!(value instanceof ConfigWrapper && value.m_ArchiveName != undefined)) {
				// Only add the pack if it's not an independent archive
				m_CurrentArchive.AddEntry(key, pack);
			}
		}
		IsDirty = false;
	}

	private static function Package(value:Object) {
		if (value instanceof ConfigWrapper) { return value.SaveConfig(); }
		if (value instanceof Archive) { return value; }
		if (value instanceof Point) {
			var wrapper:Archive = new Archive();
			wrapper.AddEntry("ArchiveType", "Point");
			wrapper.AddEntry("X", value.x);
			wrapper.AddEntry("Y", value.y);
			return wrapper;
		}
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
		if (archive != undefined) {
			for (var key:String in m_Settings) {
				var element:Object = archive.FindEntry(key,null);
				if (element == null) {
					var value = GetValue(key);
					if (value instanceof ConfigWrapper && value.m_ArchiveName != undefined) {
						// Nested config saved as independent archive
						value.LoadConfig();
					} else {
						TraceMsg("Setting '" + key + "' could not be found in archive. (New setting?)");
					}
					continue;
				}
				var savedValue = Unpack(element, key);
				if (savedValue != null) {
					SetValue(key, savedValue);
				}
			}
		}
		SignalConfigLoaded.Emit(!IsLoaded);
		m_CurrentArchive = archive;
		IsDirty = false;
		return this;
	}

	private function Unpack(element:Object, key:String) {
		if (element instanceof Archive) {
			var type:String = element.FindEntry("ArchiveType");
			if (type == undefined) {
				// Basic archive
				return element;
			}
			switch (type) {
				case "Config":
					// Have to use the existing config, as it has the field names defined
					return m_Settings[key].value.FromArchive(element);
				case "Point":
					return new Point(element.FindEntry("X"), element.FindEntry("Y"));
				case "Array":
				case "Object": // Serialized unspecified type
					var value = type == "Array" ? new Array() : new Object();
					var keys:Array = element.FindEntryArray("Keys");
					var values:Archive = element.FindEntry("Values");
					for (var i in keys) {
						value[keys[i]] = Unpack(values.FindEntry(keys[i]));
					}
					return value;
				default:
				// Archive type is not supported
				// (Caused by reversion when a setting has had its type changed
				//  A bit late to be working this out though)
					return null;
			}
		}
		return element; // Basic type
	}

}
