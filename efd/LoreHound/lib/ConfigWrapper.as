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

import efd.LoreHound.lib.Mod;

// WARNING: Recursive or cyclical data layout is verboten.
//   A config setting holding a reference to a direct ancestor will cause infinite recursion during serialization.
// The setting name "ArchiveType" is reserved for internal use
// Supports basic types and limited composite types (nested ConfigWrapper, Array, Point, and generic Object)

class efd.LoreHound.lib.ConfigWrapper {
	// ArchiveName is distributed value to be saved to for top level config wrappers
	// Leave archiveName undefined for nested config wrappers (unless they are saved seperately)
	public function ConfigWrapper(archiveName:String) {
		ArchiveName = archiveName;
		Settings = new Object();
		SignalValueChanged = new Signal();
		SignalConfigLoaded = new Signal();
	}

	// Adds a setting to this config archive
	// - Archives are all or nothing affairs, it's not recommended to try and cherry pick keys as needed
	// - If a module needs to add additional settings it should either:
	//   - Provide a subconfig wrapper, if the settings are specific to the mod
	//   - Provide its own archive, if it's a static module that can share the settings between uses
	public function NewSetting(key:String, defaultValue):Void {
		if (key == "ArchiveType") { TraceMsg("'" + key + "' is a reserved setting name."); return; } // Reserved
		if (Settings[key] != undefined) { TraceMsg("Setting '" + key + "' redefined, existing definition will be overwritten."); }
		if (IsLoaded) { TraceMsg("Setting '" + key + "' added after loading archive will have default values."); }
		Settings[key] = {
			value: CloneValue(defaultValue),
			defaultValue: defaultValue
		};
		// Dirty flag not required
		// Worst case: An unsaved default setting is changed by an upgrade
	}

	public function DeleteSetting(key:String):Void {
		delete Settings[key];
	}

	// Get a reference to the setting (value, defaultValue) tuple object
	// Useful if a subcomponent needs to view but not change a small number of settings
	// Hooking up ValueChanged event requires at least temporary access to Config object
	public function GetSetting(key:String) {
		if (Settings[key] == undefined) { TraceMsg("Setting '" + key + "' is undefined."); return; }
		return Settings[key];
	}

	// If changes are made to a returned reference the caller is responsible for setting the dirty flag and firing the value changed signal
	public function GetValue(key:String) { return GetSetting(key).value; }

	// Not a clone, allows direct edits to default object
	// Use ResetValue in preference when resetting values
	public function GetDefault(key:String) { return GetSetting(key).defaultValue; }

	public function SetValue(key:String, value) {
		var oldVal = GetValue(key);
		if (oldVal != value) {
			// Points cause frequent redundant saves and are easy enough to compare
			if (value instanceof Point && oldVal.equals(value)) { return oldVal; }
			Settings[key].value = value;
			DirtyFlag = true;
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
		for (var key:String in Settings) {
			ResetValue(key);
		}
	}

	// Notify the config wrapper of changes made to the internals of composite object settings
	public function NotifyChange(key:String):Void {
		DirtyFlag = true;
		SignalValueChanged.Emit(key, GetValue(key)); // oldValue cannot be provided
	}

	// Allows defaults to be distinct from values for reference types
	// TODO: Very uncertain if Archives can be cloned at all, consider removing support for them below
	private static function CloneValue(value) {
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
		if (archive == undefined) { archive = DistributedValue.GetDValue(ArchiveName); }
		FromArchive(archive);
	}

	public function SaveConfig():Archive {
		if (IsDirty) {
			UpdateCachedArchive();
			if (ArchiveName != undefined) { DistributedValue.SetDValue(ArchiveName, CurrentArchive); }
		}
		return CurrentArchive;
	}

	// Reloads from cached archive, resets to last saved values, rather than default
	public function Reload():Void {
		if (!IsLoaded) { TraceMsg("Config never loaded, cannot reload."); return; }
		LoadConfig(CurrentArchive);
	}

	// Updates the cached CurrentArchive if dirty
	private function UpdateCachedArchive():Void {
		delete CurrentArchive;
		CurrentArchive = new Archive();
		CurrentArchive.AddEntry("ArchiveType", "Config");
		for (var key:String in Settings) {
			var value = GetValue(key);
			var pack = Package(value);
			if (!(value instanceof ConfigWrapper && value.ArchiveName != undefined)) {
				// Only add the pack if it's not an independent archive
				CurrentArchive.AddEntry(key, pack);
			}
		}
		DirtyFlag = false;
	}

	private static function Package(value:Object) {
		if (value instanceof ConfigWrapper) { return value.SaveConfig(); }
		if (value instanceof Archive) { return value; }
		if (value instanceof Point) { return value; }
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
			for (var key:String in Settings) {
				var element:Object = archive.FindEntry(key,null);
				if (element == null) {
					var value = GetValue(key);
					if (value instanceof ConfigWrapper && value.ArchiveName != undefined) {
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
		CurrentArchive = archive;
		DirtyFlag = false;
		return this;
	}

	private function Unpack(element:Object, key:String) {
		if (element instanceof Archive) {
			var type:String = element.FindEntry("ArchiveType", null);
			if (type == null) {
				// Basic archive
				return element;
			}
			switch (type) {
				case "Config":
					// Have to use the existing config, as it has the field names defined
					return GetValue(key).FromArchive(element);
				case "Point": // Depreciated storage method, retained for backwards compatibility
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
					TraceMsg("Setting '" + key + "' was saved with a type not supported by this version. Default values will be used.");
					return null;
			}
		}
		return element; // Basic type
	}

	private function TraceMsg(msg:String, supressLeader:Boolean) {
		if (!supressLeader) {
			Mod.TraceMsgS("Config - " + msg, supressLeader);
		} else { Mod.TraceMsgS(msg, supressLeader); }
	}

	// TODO: IsLoaded will be false if nothing was loaded, which may result in multiple ConfigLoaded(true) signals
	public function get IsLoaded():Boolean { return CurrentArchive != undefined; }

	// Checks if this, or any nested Config settings object, is dirty
	public function get IsDirty():Boolean {
		if (DirtyFlag == true) { return true; }
		for (var key:String in Settings) {
			var setting = GetValue(key);
			// In theory a nested independent archive could be saved by itself, without touching the main archive
			// but most usages will just save the main and expect it to save everything.
			// Could be expanded into a tri-state so it could skip down to the relevant sections on save.
			if (setting instanceof ConfigWrapper && setting.IsDirty) { return true; }
		}
		return false;
	}

	// TODO: SignalConfigLoaded doesn't trigger for subconfig groups on first install
	public var SignalValueChanged:Signal; // (settingName:String, newValue, oldValue):Void // Note: oldValue may not always be available
	public var SignalConfigLoaded:Signal; // (initialLoad:Boolean):Void // Parameter is true when the config is loaded for the very first time

 	// The distributed value archive saved into the game settings which contains this config setting
	// Usually only has a value for the root of the config tree
	// Most options should be saved to the same archive, leaving this undefined in child nodes
	// If a secondary archive is in use, providing a value will allow both archives to be unified in a single config wrapper
	// Alternatively a config wrapper may elect to forgo the names, and offload the actual archive load/save through parameters
	// Parameters take precidence over names
	private var ArchiveName:String;
	private var Settings:Object;

	// A cache of the last loaded/saved archive
	private var CurrentArchive:Archive;
	private var DirtyFlag:Boolean = false;
}
