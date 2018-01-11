# TSW-LoreHound
Proximity detection for lore in Secret World Legends, including non-visible pickups.
Legacy (TSW) compatible.

## Overview
Will detect and attempt to identify lore pickups when they enter or spawn within ~25m of the player. Lore pickups have been roughly categorized into four groups.
+ Placed: Basic placed lore. Usually always available but also includes most event lore and a few that require extra work to reveal
  + Am attempting to recategorize the conditional spawning ones, so if you encounter any that don't appear by default let me know
  + Lore for inactive events will not be fully identified and is excluded from notifications by default. Once the event is running, the missing data is available and detection works normally
  + Some event lore appears to have been removed from the game entirely rather than just disabled so cannot be detected at all outside of the event
+ Triggered: Requires a particular condition to spawn or be visible but doesn't despawn (as far as I know)
  + Commonly in instances that don't permit MUs, such as dungeons or replayable mission areas
  + Also a lot in some areas of KD
+ Dropped: Mostly bestiary lore drops from monsters and triggered spawns. Will time out after a short period of time.
  + A tracking option can inform you when these despawn, as long as you stay in the vicinity (somewhere between ~75-100m).
    + Bestiary lore has a 5min timeout.
	+ KD rare spawn drops have a 1min timeout.
+ Uncategorized: Something that I haven't run across yet, so haven't been able to place in a group.
  + Opting into the automated report option permits the collection of required information to be mailed to me when you open the bank, saving you the trouble. (Automated reports remain untested in SWL.)
+ Related Items: Items which, while not lore themselves, are directly related to acquiring certain lore

Each category can independently have notifications output to either chat (System channel), as pop-up (FIFO) alerts, or with HUD (not map) waypoints. Default settings provide a wide range of notifications for most lore, including already known drop and uncategorized lore, but these can be customized extensively by clicking the icon. When sending a notification through the chat, a set of additional details can be displayed. Those marked with a '*' will always be displayed with Uncategorized lore and are used to identify it in the index.
+ Timestamp: Puts a timestamp on detections, so you can know when the drop was without having to timestamp all of the System channel (revealing many mysteriously blank lines that it otherwise ignores).
+ Location*: Map name and coordinate vector for the lore
  + The vector has been swizzled into [x,z,y] format, where y is the vertical coordinate
+ Category IDs*: Identifying information that is used to confirm and categorize detected objects.
  + Officially these have no relevance to the lore's behaviour; unofficially it's too conveniently coincidental.
+ Instance IDs: Identifier values for the particular pickup object in the world.
  + Occasionally useful if a single lore seems to be getting spammed to determine that they are actually multiple objects.

Additional Options
+ "Topbar Integration": Enable to lock the mod icon to the default topbar or a topbar mod that supports the VTIO registration system (such as Meeehr's topbar or ModFolder). Disable to revert the mod to a free floating icon that can be placed elsewhere on the screen.
+ "Extended Testing": To improve efficiency and reduce false-positives, it only checks against the existing list of known/suspected lore. This option will activate additional testing on objects that would otherwise be ignored, for use if it fails to detect something that it should have.
+ "Log Cartographer Data": Detected lore notifications are logged in "ClientLog.txt" file, in a format which can be easily extracted for use by my Cartographer mod.
+ "Waypoint Colour": The colour (6 digit RGB Hex notation) to use on onscreen waypoints.

Settings are saved account wide and will be shared across characters. If you'd prefer unique settings for each character, renaming "LoginPrefs.xml" to "CharPrefs.xml" when installing/upgrading the mod should work without any problems. A clean install of the mod is recommended if doing this for the first time, as it will be unable to transfer existing settings anyway.

## Installation
The packaged release should be unzipped (including the internal LoreHound folder) into the appropriate folder:
<br/>TSW: [TSW Directory]\Data\Gui\Customized\Flash.
<br/>SWL: [SWL Directory]\Data\Gui\Custom\Flash.

The safest method for upgrading (required for installing) is to have the client closed and delete any existing .bxml files in the LoreHound directory. Hotpatching (using /reloadui) works as long as neither Modules.xml or LoginPrefs.xml (stable since v1.0.0, but I may forget to update this) have changed.

An internal update system *should* carry forward settings from a limited range of previous versions (currently back to v1.0.0) Attempting to upgrade an earlier version will reset all settings to defaults, unless upgrades are staged to each in between major version.

If updating v0.1.1-alpha a clean reinstall is recommended. Remove the existing mod entirely and login to the game to clear any existing settings before installing a more recent version.

## Change Log
Version 1.3.3
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

Version 1.3.0
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

Version 1.2.4
+ By request: Waypoint colour may now be customized to something less like a sabotage mission marker
  + Default changed from 0xF6D600 to the slightly oranger 0xFFAA00
  + Colour changes will not affect currently displayed waypoints
+ Previously undocumented feature to dump detections to ClientLog.txt has been given proper config option
  + Format of data has changed for convenient transfer of data to Cartographer
  + Does not require onscreen notification to work, but does filter on other criteria
+ Various minor framework patches

Version 1.2.2
+ Waypoints now refresh immediately to reflect change in preferences, or when lore is claimed
+ Fixes GUI Edit Mode regression bug, icon can once again be moved and resized
+ Some lore which previously fell into the "Placed" category is now being reclassified as "Triggered". This requires manual confirmation, so it a work in progress, and currently consists of:
  + Padurii #3

Version 1.2.0
+ Expanded options for tracking known/unkown lore
+ Expanded options for waypoint notifications
+ Unifies lore tracking and waypoints, should no longer forget to provide despawn notifications

Version 1.1.0
+ Setting migration from versions prior to v1.0.0 no longer supported
+ Onscreen flags at detected lore locations!
  + It's a rather ugly hack at the moment, the occasional ak'ab may request hugs
+ Tooltip now provides listing of tracked lore and pending reports
+ Fixed a bug with auto report setting corruption that was causing the system to fail
  + During the update a chat message will be issued if you were affected, and that setting will be reset

Version 1.0.0
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

Version 0.6.0-beta
+ Now even lazier, does less work wherever possible
  + Setting for "new content" will re-enable some of these tests, but should not be needed until new content arrives. May be useful if a particular piece of lore does not seem to be detected at all.
+ No longer goes berserk around certain players, and has been told to stop sniffing German corpses
  + False positives in the detection system have been stomped
+ No longer baffled by the drone in Polaris and can spot lore #4 there
+ Various other code cleanup and back-end changes
+ Unknown lore id count: 7

Version 0.5.0-beta
+ New responses to lore pickups that don't connect to anything (formerly "Unable to identify")
  + Partially initialized drops will be poked until they shape up
  + Disabled event lore flagged as such
+ Told to ignore inactive event lore (new option: default ignores)
+ Icon no longer super-glued to screen without topbar mod, works with GUI edit mode
  + Refuses to hide, but can be made into a very small puppy
+ Now more vocal, notification on icon when tracking lore drops or when a debug report is ready
  + Topbars cause shrinkage, but it's still there
+ Unknown lore id count: 10

Version 0.4.0-beta
+ First open beta release
+ Learned a new trick, now identifies lore with topic and entry #
+ Suborned the postal service into serving as an automated bug report system (opt-in)
+ Settings GUI added w/ Topbar integration, disillusioning debug menu of its supposed popularity
+ Unknown lore id count: 15

Version 0.1.1-alpha
+ Proof of concept
+ Grumpy dog has unfriendly info format and no GUI access to settings
+ Unknown lore id count:  26

## Known Issues & FAQ
The following issues are known to exist in the most recent release:
+ There appear to be five uncategorized lore IDs somewhere in the game
  + One is believed to be event related and unavailable at the moment
+ Sometimes has strange behaviour when zoning into instances with nearby lore, either failing to detect them or issuing alerts that should be disabled.
+ Text field labels are truncated to fixed sizes
  + Lore topics may cause waypoint labels to be truncated, hiding the #
  + Custom or translated settings menu text may have size issues, if you want to provide translations I can tweak the label sizes to compensate
+ The waypoint colour customization interface is a bit kludgey

Where are the waypoints on my map? <br/>
I have not found any way for an in-game mod to interact with or overlay the map UI or the waypoint files. While this mod can help you locate things once you're close, a waypoint pack such as Lassie's may be a helpful supplement. I am currently working on a supplementary map mod, Cartographer, which will eventually have support for direct updates from a future version of LoreHound.

Can I adjust the detection range? <br/>
No. The API for the proximity detection system I am using does not give me access to that feature. Similarly the despawn tracking range is outside of my control (and slightly random). Once detected, the range at which onscreen waypoints disappear could be customized, but does not seem to be that important to people.

Can it tell me where lore X is? <br/>
Not really. LoreHound does not actually contain a database of lore locations or names, it generates the notifications on the fly based on the detected object. If looking for the location of a specific lore, I suggest using a community info site, such as TSWDB or Crygaia wiki.

Why is so much of it disabled by default? <br/>
It isn't anymore (v1.3.3), but for the record: The original intent of LoreHound was to provide a system to detect invisible lore drops, specifically from the rider Samhain event in TSW. I tried to avoid spamming notifications or spoiling lore locations for those who would rather hunt them down personally. While popular demand and my own use have led to the mod becoming more flexible, the default settings have only recently been changed to reflect the way most people use this mod.

## Testing and Further Developments
This continues to be something of a work in progress, though I'm mostly satisfied that it achieves the objectives. I am considering:
+ Some form of whitelisting to further filter the accepted values:
  + The *easy* version would be one that simply works on loreIDs after initial filtering, as a global white list.
  + More complicated systems (intelligent per-category whitelists, random drops only, etc.) would require additional information to be saved about each lore entry.
+ Localization would be nice, but I'm not going to rely on Google and my limited knowledge of French to be at all accurate. Somebody else will have to provide me with translations, if there is sufficient interest.
+ Possible runtime linkage with Cartographer once it gets far enough into development.
+ Some lore is detected in one type, while it behaves as something different, there is an ongoing effort to correct this for two major reasons:
  + Consistency of alerts with behaviour
  + Preventing drop lore from spamming Cartographer with large numbers of location waypoints
    + While simply preventing duplicates by loreID is possible, a large number of existing lore entries with multiple (fixed) spawn points suggests that such a solution is not flexible enough

A feature for helping with The Abandoned lore was found to be unworkable. Lore.IsLockedForChar either does not work as advertised, or requires GM permissions.

Defect reports, suggestions, and contributions are always welcome. Message Peloprata in #modding on the SWL discord, or in-game by mail or pm, or leave a message on the Curse or GitHub page. I am infrequently in TSW at this point, so mail there is likely to go unread.

Curse Mirror: https://www.curseforge.com/swlegends/tswl-mods/lorehound

Source Repository: https://github.com/Earthfiredrake/TSW-LoreHound

## Building from Source
Requires copies of the TSW and Scaleform CLIK APIs. Existing project files are configured for Flash Pro CS5.5.

Master/Head is the most recent packaged release. Develop/Head is usually slightly behind my current local test build. As much as possible I try to avoid regressions or unbuildable commits but new features may be incomplete and unstable and there may be additional debug code that will be removed or disabled prior to release.

Once built, 'LoreHound.swf' and the contents of 'config' should be copied to the directory 'LoreHound' in the game's mod directory. '/reloadui' is sufficient to force the game to load an updated swf or mod data file, but changes to the game config files (LoginPrefs.xml and Modules.xml) will require a restart of the client and possible deletion of .bxml caches from the mod directory. If the LogParser.py tool is required, it should be copied to the install directory as well.

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
