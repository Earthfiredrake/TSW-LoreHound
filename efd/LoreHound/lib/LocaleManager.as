// Copyright 2017, Earthfiredrake (Peloprata)
// Released under the terms of the MIT License
// https://github.com/Earthfiredrake/TSW-LoreHound

import com.Utils.Format;
import com.Utils.LDBFormat;
import com.Utils.Signal;

import efd.LoreHound.lib.Mod;

// Loads an xml file and extracts a set of indexed strings for use by the mod
// Strings will be localized if possible, or default to English if translations are undefined
// Tags must be unique within a category, categories should not be defined multiple times
// Format specification:
//   <Category name="categoryKey">
//     <String tag="stringKey" [rdb="id=# category=#"|en="English|Default"|fr="French"|de="German"] />
//   </Category>
// Any combination of localization attributes is permited though usually they will either be:
//   rdb: The string is sourced from the game resource database for the user's language (may also include an "en" fallback, but likely will not)
//     This option will take precidence, unless it fails to load
//   en+[fr/de]: Localization support is dependent on the mod developer, or end user customization, though "en" should be provided as a default

// Can also be used on individual string tags by other loaders to parse localized strings,
//   without adding them to the internal lookup table
// In this usage, the category tag is omitted, and the name and tag attribute of the String xml tag are ignored

// Also provides some formatting utilities for strings and simplified lookups for common UI elements
class efd.LoreHound.lib.LocaleManager {
	private function LocaleManager() { } // Static class for ease of access and singleton nature

	public static function Initialize(fileName:String, testLocale:String):Void {
		CurrentLocale = testLocale != undefined ? testLocale : LDBFormat.GetCurrentLanguageCode();

		SignalStringsLoaded = new Signal();

		StringFile = Mod.LoadXmlAsynch(fileName, StringsLoaded);
	}

	public static function GetString(category:String, tag:String):String { return StringDict[category][tag]; }

	// Translate a prepared text field containing its own GUI tag value
	public static function ApplyLabel(label:TextField):Void { label.text = GetString("GUI", label.text); }

	// Printf style function, passes the retrieved string and arbitrary parameters to the game's format utility
	//   Uses Boost::Format syntax, with exceptions on parameter mismatch disabled
	public static function FormatString(category:String, tag:String):String {
		var fmtString:String = GetString(category, tag);
		arguments.splice(0, 2, fmtString);
		return Format.Printf.apply(undefined, arguments);
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
					category[entry.attributes.tag] = GetLocaleString(entry);
				}
				StringDict[categoryXML.attributes.name] = category;
			}
		} else {
			// Bypass localization entirely
			Mod.ErrorMsg("Could not load localized strings", { system : "Localization" });
		}
		delete StringFile;
		SignalStringsLoaded.Emit(success);
	}

	// Load the localized string if available, or default to English
	// English being the most likely to be both available and understood
	public static function GetLocaleString(xml:XMLNode):String {
		var localeStr:String;
		if (xml.attributes.rdb != undefined) {
			localeStr = LDBFormat.Translate("<localized " + xml.attributes.rdb + " />");
		}
		if (localeStr == undefined) { localeStr = xml.attributes[CurrentLocale]; }
		return localeStr != undefined ? localeStr : xml.attributes.en;
	}

	private static var StringFile:XML;
	public static var SignalStringsLoaded:Signal; // (success:Boolean):Void

	private static var CurrentLocale:String;  // de, en, fr
	private static var StringDict:Object;
}
