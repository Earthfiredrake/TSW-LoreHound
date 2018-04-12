# TSW-LoreHound

Proximity detection for lore in Secret World Legends, including non-visible pickups. <br/>
Legacy (TSW) compatible.

## Overview

Detects and identifies lore pickups when they enter or spawn within ~25m of the player. Notifications can be sent to chat (System channel), pop-up (FIFO) text, and/or as HUD (not map) waypoints. Clicking on the icon will bring up the settings menu where the behaviour can be customized further (see below for details).

Lore pickups have been roughly categorized into four groups:
+ Placed: Basic placed lore. Usually available for pickup with no extra work
+ Triggered: Requires a particular condition to spawn or be visible
  + May or may not be detected before that condition is met
+ Dropped: Largely, but not exclusively, bestiary lore from mobs
  + Most despawn after a short period, with an option to track and notify of this
    + Bestiary lore has a 5min timeout.
	+ KD rare spawn drops have a 1min timeout.
+ Uncategorized: Something new that needs to be assigned a category, chat details provide the required information if you'd like to let me know about it
+ Related Items: While not lore themselves, are directly related to acquiring certain lore
  + Mostly scarabs

## Links

**Forum Topic**: https://forums.funcom.com/t/lorehound-lore-proximity-alerts/2217 <br/>
**Download**: https://www.curseforge.com/swlegends/tswl-mods/lorehound <br/>
**Source Repository**: https://github.com/Earthfiredrake/TSW-LoreHound <br/>

## Installation

The packaged release should be unzipped (including the internal folder) into the listed folder:
<br/>SWL: [SWL Directory]\Data\Gui\Custom\Flash
<br/>TSW: [TSW Directory]\Data\Gui\Customized\Flash

If Modules.xml or any *Prefs.xml files are being changed (such as when first installing) the client should be fully closed and restarted to install the mod. Otherwise, it's possible to do a hotpatch with '/reloadui' after updating the .swf and any other supporting files.

Settings may change slightly between versions, and an attempt has been made to provide as unsurprising behaviour as possible when upgrading from recent versions. To reduce the amount of legacy upgrade code the lowest upgradeable version may change. Currently versions prior to v1.0.0 will have their settings reset to defaults if not upgraded in stages.

v0.1.1-alpha did not support the versioning system, and should be fully uninstalled prior to upgrading. Remove the existing mod entirely and login to the game to clear any existing settings before installing a more recent version.

## Configuration

**Category Settings**:
Each lore category (above) has its own notification options. Notifications can be limited to only those lores you do not yet have, or set to include the ones you've already picked up (useful if doing a lore run or to provide callouts of drops for other people). By default two categories have alerts for lore you've already picked up. Drops, which need it to properly notify of despawns, and uncategorized lore, which provide information that can then be added to future versions of the mod.

**Despawn Tracking**:
The drop category has an additional option to provide despawn tracking. This requires that alerts for claimed lore be enabled, attempting to mismatch the settings will toggle the other as needed. This feature will cause dropped lore provide additional alerts when the lore despawns or you move too far away from it to continue tracking. It does not affect the waypoint, which only requires alerts for claimed lore to persist until the lore despawns. Additionally, while tracking lore the icon will have an exclamation mark on it and the tooltip will list all currently tracked lore.

**Chat Details**:
When an alert is output to system chat, these options set some of the formatting and additional information provided. Uncategorized lore reports will override these settings to ensure that required information is available. With the exception of the timestamp, these details are unavailable for despawn notifications.
+ Timestamp: Adds the time of detection without having to timestamp all of the System channel (revealing many mysteriously blank lines that it otherwise ignores)
+ Location: Zone name and coordinate vector for the lore
  + Swizzled to better match map coordinates; [x,z,y], as y is the vertical axis for the game engine
+ Category IDs: IDs used by the filtering systems; First used as a heuristic for basic categorization, second identifies the lore entry
+ Instance IDs: Identifier values for the particular object in the world
  + Occasionally useful if a single lore seems to be getting spammed to determine that they are actually multiple objects

**Additional Options**:
+ Enable Mod: Turns off the mod, can be quickly done by right clicking the icon
+ Topbar Integration: Lock the mod icon to the default topbar or a topbar mod that supports the VTIO registration system (such as Meeehr's topbar or ModFolder). Disable to revert the mod to a free floating icon that can be placed elsewhere on the screen
+ Extended Testing: This option has two effects. It will activate some additional testing in an effort to detect lore that has no data entry at all. It will also permit the mod to raise alerts for lore that it cannot fully identify, including various lore triggers or inactive event lore. As it cannot be identified, it will not be properly named and cannot be checked against collected lore for filtering purposes
+ Log Cartographer Data: Detected lore notifications are logged in "ClientLog.txt" file, in a format which can be easily extracted for use by my Cartographer mod
+ Waypoint Colour: The colour (6 digit RGB hex notation) to use on onscreen waypoints

My mod framework also includes some standardized supporting features, the more useful of which include:
+ Icon position and scale can be adjusted by using the default GUI unlock mode
+ '/setoption efdLoreHoundResetConfig true' will quickly reset all options to default settings
+ '/setoption emfListMods true' lists all installed framework mods, with version and author info, in System chat

Settings are saved account wide and will be shared across characters. Some settings have recently been removed or merged, see the change log for details.

## Known Issues & FAQ

The following issues are known to exist in the most recent release:
+ There may be five uncategorized lore IDs somewhere in the game
  + One is believed to be event related and unavailable at the moment
+ Sometimes has strange behaviour when zoning into instances with nearby lore, either failing to detect them or issuing alerts that should be disabled
+ The waypoint colour customization interface is a bit kludgey

Where are the waypoints on my map? <br/>
I have not found any way for an in-game mod to interact with or overlay the map UI or the waypoint files. While this mod can help you locate things once you're close, a waypoint pack such as Lassie's may be a helpful supplement. You may also be interested in my prototype Cartographer map mod, which will eventually have support for direct updates from a future version of LoreHound, if I can ever iron out the bugs.

Can I adjust the detection range? <br/>
No. The API for the proximity detection system I am using does not give me access to that feature. Similarly the despawn tracking range is outside of my control (and slightly random). Once detected, the range at which onscreen waypoints disappear could be customized, but the current range seems to be good enough that the extra work for customization isn't warranted.

Can it tell me where lore X is? <br/>
Not really. LoreHound does not actually contain a database of lore locations or names, it generates the notifications on the fly based on the detected object. If looking for the location of a specific lore, I suggest using a community info site, such as TSWDB or Crygaia wiki.

LoreHound says a lore dropped, where is it? <br/>
It's likely you already have it. The default settings include detection of already claimed lore drops to facilitate callouts and despawn tracking, which can easilly be disabled if not useful.

A guide says there's a lore here, where is it? <br/>
The game has a number of different methods to disguise triggered lore and keep it from rendering. Some of these prevent the mod from detecting the lore at all, others leave the lore in a detectable but non-identifiable state. These are filtered out unless the settings are changed to display them.

Why is so much of it disabled by default? <br/>
It isn't anymore (v1.3.3), but for the record: The original intent of LoreHound was to provide a system to detect invisible lore drops, specifically from the rider Samhain event in TSW. I tried to avoid spamming notifications or spoiling lore locations for those who would rather hunt them down personally. While popular demand and my own use have led to the mod becoming more flexible, the default settings have only recently been changed to reflect the more common usage.

Defect reports, suggestions, and contributions are always welcome. The forum post is the ideal place to leave a message, but I also track the CurseForge comments and GitHub's issue tracker. For little things or quick troubleshooting flag me down in discord (@Peloprata on the official server's #modding channel) or look for me in game (often lurking in #Sanctuary).

## Change Log

**Version 1.4.0**
+ Settings changes
  + Auto report system has been removed, recently added content is similar enough to existing ones that the feature doesn't justify the upkeep at this time
  + Inactive (offseason) event lore setting has been merged with the Extra Testing setting
  + Drop despawn tracking is now more explicitly linked to alerts for already collected drop lore
  + Colour customization now takes effect immediately
  + Change to Modules.xml & LoginPrefs.xml (standardization of DV names)
+ Improved identification of triggered lores
+ Onscreen markers no longer truncate long names and mostly keep them onscreen
+ Data updated to include SAF content
+ Shrouded Lore (if it ever comes back) now properly categorized as triggered
+ Various backend improvements and library bug fixes

**Version 1.3.3**
+ Classification improvements
  + KD: More initially invisible lore now in the triggered category
  + Light in black places: "Related Items" now includes a candlestick in a basement (but not Prof. Plum)
    + Various other items were considered but didn't make the cut (almost unmissable, or just plain spammy), if you're curious they're still in there, just commented out
  + Better late than never, detects the lore in Niflheim (I wouldn't want to go sniffing around those Krampii either)
    + Uncategorized lore fixed to provide notifications in the future (auto-reports continue to be largely untested, to the slight relief of the postman)
  + The uncategorized lore count drops to 5
+ Interface and other changes
  + Improved topbar integration, supporting default topbar as well as VTIO compatible mods
    + Enabled on fresh installs, updating will use existing behaviour to pick a value (icons should be where you left them)
	+ Default topbar location should be just to the right of the middle of the screen
    + Workaround for bug with ModFolder when doing /reloadui
    + Fixed a layout issue affecting Meeehr and Viper topbars
  + Default settings have been changed to better reflect common usage (I do eventually listen to criticism)
	+ Will now get lots of notifications for all types of uncollected lore by default
	+ This affects fresh installs, upgrades will retain existing settings
  + Strings.xml has had a minor format change
    + Any text customization will need to be copied to the new file (the old format no longer works)

**Version 1.3.0**
+ New category "Related Items" for non-lore pickups and objects related to unlocking lore; currently has entries for:
  + Pieces of Joe: Will be detected only if they are currently spawned
  + Demonic Crystals
  + Dead Scarabs: Including colour identification
+ Fixed the bug with icon not staying with UI edit mode overlay
+ Settings can now be manually reset (/setoption efdLoreHoundResetConfig true)
+ Lore re-categorization:
  + Mobs drops in dungeons have been recategorized as Drop lore (instead of Triggered)
  + Several entries in KD have been recategorized as Triggered (instead of Placed), due to requiring actions/missions to appear
+ Log output has been slightly reformatted and a basic python script has been included to quickly parse relevant entries
  + Usage requires a suitable python interpreter to be installed, and will dump the data into a LoreHound.txt file in the LoreHound directory

**Version 1.2.4**
+ By request: Waypoint colour may now be customized to something less like a sabotage mission marker
  + Default changed from 0xF6D600 to the slightly oranger 0xFFAA00
  + Colour changes will not affect currently displayed waypoints
+ Previously undocumented feature to dump detections to ClientLog.txt has been given proper config option
  + Format of data has changed for convenient transfer of data to Cartographer
  + Does not require onscreen notification to work, but does filter on other criteria
+ Various minor framework patches

**Version 1.2.2**
+ Waypoints now refresh immediately to reflect change in preferences, or when lore is claimed
+ Fixes GUI Edit Mode regression bug, icon can once again be moved and resized
+ Some lore which previously fell into the "Placed" category is now being reclassified as "Triggered". This requires manual confirmation, so it a work in progress, and currently consists of:
  + Padurii #3

**Version 1.2.0**
+ Expanded options for tracking known/unkown lore
+ Expanded options for waypoint notifications
+ Unifies lore tracking and waypoints, should no longer forget to provide despawn notifications

**Version 1.1.0**
+ Setting migration from versions prior to v1.0.0 no longer supported
+ Onscreen flags at detected lore locations!
  + It's a rather ugly hack at the moment, the occasional ak'ab may request hugs
+ Tooltip now provides listing of tracked lore and pending reports
+ Fixed a bug with auto report setting corruption that was causing the system to fail
  + During the update a chat message will be issued if you were affected, and that setting will be reset

**Version 1.0.0**
+ An actual release version!
+ Options menu no longer possessed by a gaki, you can now esc from it
+ Can timestamp detections without having to timestamp all of System chat
  + Timestamps on System chat are annoying, displays a bunch of blank lines that would otherwise be ignored
+ Despawn tracking can now be disabled independently of lore drop detection
+ Shrouded lore deemed not special enough to have a category all to itself, has been recategorized as Placed Lore
+ XML file for primary categorization, the most basic data updates no longer require a flash compiler
  + Spoiler warning: Comments describing the magic numbers may ruin some surprises
+ Teach the hound a new language, or just customize what he says
  + XML file for text (strings) has been added, with some support for localization (actual localization not included)
  + Includes format strings for almost all alerts. If you don't like my colour selection or want the mod name in FIFO alerts, that can be customized too.
+ The mod does require both xml files to run, if it cannot find them it will disable itself.
  + It would still *work* without either of the files, but a missing index file severely limits detection, and the strings file is required to display alert messages.
+ Install process has recovered from amnesia, remembers to save default settings after fresh install without being prompted.
+ Unknown lore id count: 7 (still)

**Version 0.6.0-beta**
+ Now even lazier, does less work wherever possible
  + Setting for "new content" will re-enable some of these tests, but should not be needed until new content arrives. May be useful if a particular piece of lore does not seem to be detected at all.
+ No longer goes berserk around certain players, and has been told to stop sniffing German corpses
  + False positives in the detection system have been stomped
+ No longer baffled by the drone in Polaris and can spot lore #4 there
+ Various other code cleanup and back-end changes
+ Unknown lore id count: 7

**Version 0.5.0-beta**
+ New responses to lore pickups that don't connect to anything (formerly "Unable to identify")
  + Partially initialized drops will be poked until they shape up
  + Disabled event lore flagged as such
+ Told to ignore inactive event lore (new option: default ignores)
+ Icon no longer super-glued to screen without topbar mod, works with GUI edit mode
  + Refuses to hide, but can be made into a very small puppy
+ Now more vocal, notification on icon when tracking lore drops or when a debug report is ready
  + Topbars cause shrinkage, but it's still there
+ Unknown lore id count: 10

**Version 0.4.0-beta**
+ First open beta release
+ Learned a new trick, now identifies lore with topic and entry #
+ Suborned the postal service into serving as an automated bug report system (opt-in)
+ Settings GUI added w/ Topbar integration, disillusioning debug menu of its supposed popularity
+ Unknown lore id count: 15

**Version 0.1.1-alpha**
+ Proof of concept
+ Grumpy dog has unfriendly info format and no GUI access to settings
+ Unknown lore id count:  26

## Future Work
Aside from ongoing code tweaks, bug fixes and data maintenance, this one is near complete. A few extra features I've been considering:
+ Interop protocol so that LoreHound can pass detection data to other mods (ie: Cartographer)
+ Localization is an option if somebody's willing to volunteer translations

A concept for identifying people in need of Abandoned lore didn't work out when tested

## License and Attribution
Copyright (c) 2017-2018 Earthfiredrake<br/>
Software and source released under the MIT License

Uses the TSW-AddonUtils library and graphical elements from the UI_Tweaks mod<br/>
Both copyright (c) 2015 eltorqiro and used under the terms of the MIT License<br/>
https://github.com/eltorqiro/TSW-Utils <br/>
https://github.com/eltorqiro/TSW-UITweaks

TSW, SWL, the related APIs, and most graphics elements are copyright (c) 2012 Funcom GmBH<br/>
Used under the terms of the Funcom UI License<br/>

LoreHound icon developed from game graphics (sourced from TSWDB) and http://www.iconninja.com/basset-hound-dog-head-icon-843075

Special Thanks to:<br/>
The TSW modding community for neglecting to properly secure important intel in their faction vaults<br/>
Vomher for brainstorming the magic numbers
