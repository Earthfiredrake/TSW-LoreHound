// Copyright 2017-2018, Earthfiredrake
// Released under the terms of the MIT License
// https://github.com/Earthfiredrake/SWL-FrameworkMod

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
//     fmtSrc -> (cat="CategoryKey" str="StringKey") | rdb="category=# id=#" | (en="english/default" [fr="french"][de="german"])

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

import com.Utils.Format;
import com.Utils.LDBFormat;
import com.Utils.Signal;

// Mod namespace qualified imports and class definition are #included from locally overriden file
#include "LocaleManager.lcl.as"
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
			DebugUtils.ErrorMsgS("Loading in progress, wait for SignalStringsLoaded before starting subsequent files", { sysName: "Localization" });
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
			DebugUtils.ErrorMsgS("Could not load localized strings", { sysName : "Localization" });
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

// Many categories seem to have extra outdated English files (with occasionally interesting|frightening ideas in them)
// I mostly guessed based on the first English language file I could find, some details might be inaccurate
// File size is a useful heuristic for finding the most current files,
//   if there are three larger than others in a category, they are usually the most up to date (German, French, then English)
// There's a few other languages in some files, and a few aren't localized at all
// Asterixed ones I consider to be most useful (names of things, and a few other generic fields)
// [x] is the index file description of the category
// Don't know if can access alternate language files with the game API
//   normal calls get the one for the user's language setting
// Uncertain whether all of the categories, particularly the unused ones, are accessible
// Known RDB string categories (or best guesses):
//   100: Big list of misc stuff... could be almost anything in here
//   105: Login and Account messages
//   120: "Cannot do x" messages (four of them)
//   130: Various notifications, many of them more descriptive failure messages
//   140: Clothing or equipment slot names?
//  *150: Days of the week (0 and 7 are both "Sunday", 5986953 is "Today")
//  *151: Months (zero indexed)
//   160: Chat command responses (/stuck, /petition, /help, etc.)
//   161: Combat (log?) messages
//   162: Annoyingly capitalized attack modifiers (for FIFO?)
//   170: A single parameterized string ("x is y")
//   250: Unused player categorizations?
//   253: Difficulty grades? (Grades 1..10, Lieutenant and Boss)
//   254: Faction names and mottos (from char creation)
//   270: Anima well names
//   280: Misplaced playfield name? (use 52000 instead)
//   300: Generic mission messages
//   520: Travel confirmations (on zoneID, for every zone, instead of templating them)
//   600: Damage types (from back when that was a thing)
//   601: Attack result modifiers (Glance/Miss)
//   602: Old attack result modifiers (Block/Pen)
//   603: Genders
//   604: Targetting categories? (self, team, hostile etc.)
//   607: Unknown... variable/function names of some sort?
//   610: "Has Mission Item"? (not localized)
//   615: Character stat strings (for item tooltips)
//   616: Random collection of statistic titles (perhaps from AO?)
//   627: GM abilities (enum names?)
//   629: AH/Exchange/Mail strings
//   630: Titles for bar fights (from AoC?)
//  *634: Character stat strings (for character sheet)
//   635: Tooltips for above
//   802: PvP game modes (for SH and ED)
//   900: Cabal structure names
//   901: Cabal rank names
//   950: Graphics driver notifications
//   10002: /help strings for chat commands
//   10010: Item types
//   10012: Ethnicities (Appears to be abandoned, most files have "Ethnicity1" and "Ethnicity2" (translated))
//   10013: Activity Finder strings
//   10016: "Use" action names?
//   10017: Loading screen hints
//   10027: Control binding names
//   10028: Currencies (Fun fact: Egyptian Pounds and Romanian Leu? Even more exotic currencies?)
//   10029: Crafting (Upgrade/Fusion) interface (Fun fact: used to be called Transcription)
//   10033: Ability window boilerplate (weapon and category names, gimick help descriptions, also descriptions of old decks and new character classes)
//   10034: Weapon types
//   10035: TSW skill window strings
//   10036: Friend window headers and menu options
//   10050: Very out of date tutorial text
//   10058: Spoilers! Various story texts... seems to be a mix of computer terminals, found notes and phone texts
//   10059: Video playback status messages
//   10060: Achievement/Lore window boilerplate
//   10062: TSW scenario console strings
//   10063: Museum strings (exhibit descriptions, upgrade prompts, player achievements)
//   13000: Installer text
//   14000: Patcher text
//   14250: Character rename prompts
//   14500: Old launcher text?
//   15000: Title and login screen strings
//   20000: Assorted system messages?
//   20032: A short list of colours (Includes grey twice; doesn't have black, so won't work for Scarab colours unless I change it)
//   30000: Weapon types (again) and other oddities (Tokens, "I Evaded Melee"?)
//   40000: "[Placeholder]" and "[MissionName]"... no idea (partially localized)
//   50000: [nc_stockphrases] Spoilers! Subtitles for mission intros, scripted shouts, phonecalls (fun fact: Demotion messages?)
//   50001: [nc_questions] Spoilers! Conversation topics and computer terminal inputs
//   50002: [nc_text] Spoilers! Conversation and computer terminal responses
//   50003: [nc_trade] Contains only "default"
//   50013: [showsubtitle] "Entering/Leaving Arena", "gas can will ignite in:", "Explosion in", PvP Flagging messages, and a bunch of numbers
//   50014: [showfifomessage] FIFO message strings
//   50015: [sayinchat] Umm... no idea... some of it's slightly amusing
//   50016: [showheadtext] A single test/debug value
//   50212: [showsubtitlefromserver] Debug/trace messages
//   50018: [showfifomessagefromserver] FIFO message strings
//   50021: [createwaypoint] PvP anima well names, and some related to DW? Not sure it's used
//   50022: [setstringvariable] Level restriction and environmental damage messages?
//   50023: [playorskip] A short list of early cutscenes?
//   50025: [localized] Mostly FIFO? messages related to missions and area names
//   50026: [startobjectaction] Castbar text for object interactions
//   50070: [animbcc] Animation (emote?) names
//   50071: More emote names
//   50072: Emote chat messages
//  *50200: [item] Names for interactive world dynels and inventory items
//   50201: [item] General item descriptions (for tooltips)
//   50202: [special] Unusual item ability descriptions
//   50203: [special] More descriptions
//   50210: [special] A muddle, some is ability, passive or buff names, also a bunch of clothing in here
//   50211: [special] Descriptions for 50210 (maybe the simple ones that don't provide calculated stats?)
//   50212: Detailed descriptions for 50210 (with the replacement fields for calculated stats)
//   50214: Debug buff descriptions
//  *50220: [feat] Ability and passive names
//   50221: [feat] Old names and some tooltips from the old skill/ability windows?
//  *50300: [main_quest_templates] Mission names. There's some extra decoration (zone and type mostly) on them, but it gets stripped before display, don't know if it can be used or not.
//   50301: [quest_tempates] Mostly mission tier names
//   50302: [quest_tempates] Spoilers! Mission tier descriptions (used in journal)
//   50303: [quest_tempates] Mostly unwritten task solved text and generic mission reports
//   50304: [quest_goal_tempates] Spoilers! Sidebar mission objectives
//   50305: Some of it looks to be hardcoded unicode values (\u####) or just unknown characters, possibly encrypted consistency across files suggests it's not corruption
//   50306: [quest_mission_types] Truth in advertising (doesn't seem to have the Area bounty mission type though)
//   50307: Spoilers! Mission descriptions (used in journal)
//   50308: Some of them are mission names, some of them look like rejects, not a complete set
//   50309: Spoilers! Mission descriptions (appear to be based on 50308)
//   50310: Spoilers! Templar mission reports
//   50311: Spoilers! Illuminati mission reports
//   50312: Spoilers! Dragon mission reports
//   50313: Mission unlock requirements
//   50316: Spoilers! Dragon mission reports (post Tokyo variants)
//  *51000: [npc_template] Names for NPCs, pets, monsters
//  *52000: [regions] Names for playfields (by playfield ID)
//   52001: Server names (Fun fact: the full list includes several of the 17)
//   53000: [feat_specialized_trees] Not sure, it's got some weapon tree mentions in there and a lot of filler
//   54000: [breedenum] Names of creature types, seems to be in GetStat[89] for monster dynels
//   55000: [simpledynels] Internal names for non-interactive dynel objects?
//   55200: [stackinglines] Unsure, seems to be some debuffs
//   55700: Spoilers! Lore texts (also achievement, pet, and sprint descriptions, emotes, tutorial messages... stuff that ends up under Lore.as)
//  *55701: Lore and Achievement categories, player titles (roughly names for 55700)
//  *55800: [clothing_tree_node] Clothing (and weapon skin) names
//   55801: [clothing_tree_node] Clothing aquisition source strings
//   55802: [clothing_tree_node] Clothing colours (could steal scarab colours from here...)
//   55901: [agent_agents] Spoilers! Agent names
//   55902: [agent_agents] Spoilers! Agent bios
//   55903: [agent_traits] Agent trait names
//   55904: [agent_traits_category] Agent trait category names
//   55905: [agent_traits] Agent trait effect descriptions
//   55906: [agent_archetypes] Broad agent categories
//   55907: [agent_rarity] Rarity names again
//   55908: [agent_agents] Spoilers! Success comments
//   55909: [agent_agents] Spoilers! Failure comments
//   55910: [agent_agents] Agent occupations
//   55911: [agent_missions] Mission names
//   55912: [agent_missions] Spoilers! Mission briefings
//   55914: [agent_bonuses] Mission reward descriptions?
//   55915: [agent_successlevels] Three tiers of success ("Complete", "Success", "Outstanding Results")
//   55916: [agent_missions] Spoilers! Mission success debriefings
//   55917: [agent_missions] Spoilers! Mission failure debriefings
//   55918: [agent_agents] Agent genders
//   55919: [agent_agents] Agent species
//   55920: [agent_agents] Agent ages
//   55921: [agent_mission_difficulties] Mission difficulty strings
//   56000: Cabal activity log strings
