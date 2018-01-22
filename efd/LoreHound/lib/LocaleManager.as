// Copyright 2017-2018, Earthfiredrake
// Released under the terms of the MIT License
// https://github.com/Earthfiredrake/TSW-LoreHound

import com.Utils.Format;
import com.Utils.LDBFormat;
import com.Utils.Signal;

import efd.LoreHound.lib.Mod;

// Provides string localization features, consisting of two major components:
//   Parses xml files containing categorized strings (ie: Strings.xml) and stores the localized strings in a globally available lookup table
//   Parses and evaluates string formatted xml tags for subsystem data loaders, for localized data provision

// Format specification:
//   <CategoryKey>
//     <StringKey fmtSrc [fmt="true"]>
//       <Param fmtSrc />
//     </StringKey>
//   </CategoryKey>
//   Where:
//     CategoryKey and StringKey are lookup keys (generally making unique pairs)
//       Categories may be re-opened and extended after initial definition, but re-defined StringKeys will replace the originals
//     fmtSrc -> (cat="CategoryKey" str="StringKey") | rbd="id=# category=#" | (en="english/default" [fr="french"][de="german"])

//   Multiple fmtSrcs are permitted, but they will be evaluated in order of precidence, and will ignore any results after finding a valid source
//     str: Sourced from the string file, and must be already loaded, mostly used when other mod data repeatedly uses generic string segments
//     rdb: Sourced from the game resource database for the user's language
//     en+[fr/de]: Localization support is dependent on the mod developer, or end user customization. "en" will be used by default if actual locale is unavailable

//   The fmt attribute is used for binding constant params to a formatted string, usually when referencing a str or wrapping an rdb reference
//     Sufficient params should be provided to cover all replacements in the base string (or expect to see "undefined" output)
//     Params are passed in the order specified by the file, with the first one binding to %1%
//     Params are ignored if fmt is not specified, and no runtime data binding is provided at the moment (if partial formatting is needed %n% -> %m% replacement should work)
//     Params can also have the fmt tag applied, which may be useful if attempting to merge multiple strings

// Can also be used on individual string tags by other loaders to parse localized strings, without adding them to the lookup table
// In this usage, the category tag is omitted, and the name of the "StringKey" xml tag is ignored

// Also provides some formatting utilities for strings and simplified lookups for common UI elements

class efd.LoreHound.lib.LocaleManager {
	private function LocaleManager() { } // Static class for ease of access and singleton nature

	public static function Initialize(testLocale:String):Void {
		StringDict = new Object();
		SignalStringsLoaded = new Signal();
		CurrentLocale = testLocale != undefined ? testLocale : LDBFormat.GetCurrentLanguageCode();
	}

	public static function LoadStringFile(fileName:String):Void {
		if (StringFile == undefined) {
			StringFile = Mod.LoadXmlAsynch(fileName, StringsLoaded);
		} else {
			Mod.ErrorMsg("Already loading string file, wait for SignalStringsLoaded before starting subsequent files");
		}
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
		if (success) { AddStrings(StringFile.firstChild); }
		else {
			// Bypass localization for obvious reasons
			Mod.ErrorMsg("Could not load localized strings", { system : "Localization" });
		}
		delete StringFile;
		SignalStringsLoaded.Emit(success);
	}

	// Parse an xml node to the string lookup table
	// Used if mod data files can extend the string table
	public static function AddStrings(xml:XMLNode):Void {
		for (var i:Number = 0; i < xml.childNodes.length; ++i) {
			var categoryXML:XMLNode = xml.childNodes[i];
			var category:Object = (StringDict[categoryXML.nodeName] == undefined) ? (StringDict[categoryXML.nodeName] = new Object()) : StringDict[categoryXML.nodeName];
			for (var j:Number = 0; j < categoryXML.childNodes.length; ++j) {
				var entry:XMLNode = categoryXML.childNodes[j];
				category[entry.nodeName] = GetLocaleString(entry);
			}
		}
	}

	// Load the localized string if available, or default to English
	// English being the most likely to be both available and understood
	public static function GetLocaleString(xml:XMLNode):String {
		var localeStr:String;
		if (xml.attributes.str != undefined) {
			localeStr = GetString(xml.attributes.cat, xml.attributes.str);
		}
		if (localeStr == undefined && xml.attributes.rdb != undefined) {
			localeStr = LDBFormat.Translate("<localized " + xml.attributes.rdb + " />");
		}
		if (localeStr == undefined) {
			localeStr = xml.attributes[CurrentLocale] != undefined ?  xml.attributes[CurrentLocale] : xml.attributes.en;
		}
		return (xml.attributes.fmt) ? ApplyFormat(localeStr, xml) : localeStr;
	}

	private static function ApplyFormat(str:String, xml:XMLNode):String {
		var args:Array = new Array(str);
		for (var i:Number = 0; i < xml.childNodes.length; ++i) {
			var child:XMLNode = xml.childNodes[i];
			if (child.nodeName == "Param") {
				args[i+1] = GetLocaleString(child);
			}
		}
		return Format.Printf.apply(undefined, args);
	}

	private static var StringFile:XML;
	public static var SignalStringsLoaded:Signal; // (success:Boolean):Void

	private static var CurrentLocale:String;  // de, en, fr
	private static var StringDict:Object;
}
