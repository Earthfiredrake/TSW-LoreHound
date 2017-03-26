// Copyright 2017, Earthfiredrake (Peloprata)
// Released under the terms of the MIT License
// https://github.com/Earthfiredrake/TSW-LoreHound

import com.Utils.LDBFormat;
import com.Utils.Signal;

import efd.LoreHound.lib.Mod;

// Loads an xml file and extracts a set of indexed strings for use by the mod
// Strings will be localized if possible, or default to English if translations are undefined
// See Strings.xml for a sample of the expected data format
// Tags must be unique within a category, categories should not be defined multiple times

class efd.LoreHound.lib.LocaleManager {

	// Static class for ease of access
	private function LocaleManager() { }

	public static function Initialize(fileName:String, testLocale:String) {
		CurrentLocale = testLocale != undefined ? testLocale : LDBFormat.GetCurrentLanguageCode();

		SignalStringsLoaded = new Signal();

		StringFile = new XML();
		StringFile.ignoreWhite = true;
		StringFile.onLoad = StringsLoaded;
		StringFile.load(fileName);
	}

	public static function GetString(category:String, tag:String):String {
		return StringDict[category][tag];
	}

	// Translate a prepared text field containing its GUI tag value
	public static function ApplyLabel(label:TextField):Void {
		label.text = GetString("GUI", label.text);
	}

	private static function StringsLoaded(success:Boolean):Void {
		if (success) {
			StringDict = new Object();
			var xmlRoot:XMLNode = StringFile.firstChild;
			for (var i:Number = 0; i < xmlRoot.childNodes.length; ++i) {
				var categoryXML:XMLNode = xmlRoot.childNodes[i];
				var category:Object = new Object;
				for (var j:Number = 0; j < categoryXML.childNodes.length; ++j) {
					var entry:XMLNode = categoryXML.childNodes[j];
					var localeStr:String = entry.attributes[CurrentLocale];
					// Load the localized string if available, or default to English
					// English being the most likely to be both available and understood
					category[entry.attributes.tag] = localeStr != undefined ? localeStr : entry.attributes.en;
				}
				StringDict[categoryXML.attributes.name] = category;
			}
			delete StringFile;
			SignalStringsLoaded.Emit();
		} else {
			TraceMsg("Failed to load text resources");
		}
	}

	private static function TraceMsg(msg:String, suppressLeader:Boolean):Void {
		if (!suppressLeader) {
			Mod.TraceMsgS("Localization - " + msg, suppressLeader);
		} else { Mod.TraceMsgS(msg, suppressLeader); }
	}

	public static var SignalStringsLoaded:Signal;

	private static var CurrentLocale:String;  // de, en, fr
	private static var StringFile:XML;
	private static var StringDict:Object;
}
