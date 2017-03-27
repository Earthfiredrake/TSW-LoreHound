# TSW-LoreHound
Notifications for lore drops in The Secret World, even if they're not visible.

## Overview
Will detect and attempt to identify lore pickups when they enter or spawn within a ~20m radius around the player. Lore pickups have been roughly categorized into four groups.
+ Placed: Basic placed lore. Usually always available but also includes most event lore and a few that require extra work to reveal.
  + Lore for inactive events will not be fully identified and is excluded from detections by default. I'm hopeful that it will work with no changes when the related event is running.
  + Some event lore appears to have been removed from the game entirely rather than just disabled, and cannot be detected at all.
+ Triggered: Requires a particular condition to spawn but doesn't despawn (as far as I know).
  + Commonly in instances that don't permit MUs, such as dungeons or replayable mission instances.
+ Dropped: Mostly bestiary lore drops from monsters and triggered spawns. Will time out after a short period of time.
  + A tracking option can inform you when these despawn, as long as you stay in the vicinity (unsure on exact range, though it's significantly larger than the initial detection radius).
    + Bestiary lore has a 5min timeout.
	+ KD rare spawn drops have a 1min timeout.
+ Uncategorized: Something that I haven't run across yet, so haven't been able to place in a group.
  + Opting into the automated report option permits the collection of required information to be mailed to me when you open the bank, saving you the trouble.

Each group can independently have notifications output to either chat (System channel), or as FIFO alerts. By default, if it is able to precisely identify a lore that the character has not picked up, it will ignore it. When sending a notification through the chat, a set of additional details can be displayed. Those marked with a '*' will always be displayed with Uncategorized lore and are used to identify it in the index.
+ Timestamp: Puts a timestamp on detections, so you can know when the drop was without having to timestamp all of the System channel (revealing the mysteriously blank lines that it otherwise hides).
+ Location*: Map name and coordinate vector for the lore
  + The vector has been swizzled into [x,z,y] format, where y is the vertical coordinate
+ Category IDs*: Identifying information that is used to confirm and categorize detected objects.
  + Officially these have no relevance to the lore's behaviour; unofficially it's too conveniently coincidental.
+ Instance IDs: Identifier values for the particular pickup object in the world.
  + Questionably useful, but staying in for the moment.

To improve efficiency and reduce false-positives, it only checks against the existing list of known/suspected lore. If it fails to detect something that it should, particularly if the developers have added new content, the "New Game Content" option will activate additional testing on objects that would otherwise be ignored.

All settings are saved account wide and will be shared across all characters. If you'd rather have different settings for each character, renaming the file "LoginPrefs.xml" to "CharPrefs.xml" when installing/upgrading the mod should work without any problems. A clean install of the mod is recommended if doing this. It will not be able to transfer existing settings anyway.

## Installation
Any packaged releases can be installed by copying the contents into [Game Directory]\Data\Gui\Customized\Flash and restarting the client.

The update system *should* carry forward settings from v0.4.0-beta onwards. However, v1.0.x will be the last release to support upgrades from the v0.x pre-release line. Starting with v1.1.0 directly upgrading from versions prior to v1.0.0 may result in settings being lost, reset, or potentially invalid.

If upgrading from v0.1.1-alpha, a clean reinstall is recommended. Remove the existing mod entirely and login to the game to clear any existing settings before installing a more recent version.

## Change Log
Version next
+ Options menu no longer possessed by a gaki, you can now esc from it
+ Can timestamp detections without having to timestamp all of System chat
+ Despawn tracking can now be disabled independently of lore drop detection
+ Shrouded lore deemed not special enough to have a category all to itself, has been recategorized as Placed Lore
+ XML file for primary categorization, the most basic data updates no longer require a flash compiler
  + Spoiler warning: Descriptive comments may ruin some surprises
+ Teach the hound a new language, or just customize what he says
  + XML file for text (strings) has been added, with some support for localization (actual localization not included)
  + Includes format strings for almost all alerts. If you don't like my colour selection or want the mod name in FIFO alerts, that can be customized too.
+ The mod does require both xml files to run, if it cannot find them it will disable itself.
  + It would still *work* without either of the files, a missing index file severely limits detection, and the strings file is required to display alert messages.
+ Install process has recovered from amnesia, no longer forgets to save default settings after fresh install.
+ Unknown lore id count: 7 (still)

Version 0.6.0-beta
+ Now even lazier, does less work wherever possible
  + Setting for "new content" will re-enable some of these tests, but should not be needed until new content arrives. May be useful if a particular piece of lore does not seem to be detected at all.
+ No longer goes berserk around certain players, and has been told to stop sniffing German corpses
  + False positives in the detection system have been stomped
+ No longer baffled by the drone in Polaris and can spot lore #4 there
+ Various other code cleanup and backend changes
+ Unknown lore id count: 7

Version 0.5.0-beta
+ New responses to lore pickups that don't connect to anything (formerly "Unable to identify")
  + Partially initialized drops will be poked until they shape up
  + Disabled event lore flagged as such
+ Told to ignore inactive event lore (new option: default ignores)
+ Icon no longer superglued to screen without topbar mod, works with GUI edit mode
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

## Known Issues
The following issues are known to exist in the most recent release:
+ There appear to be seven uncategorized lore IDs somewhere in the game
  + Three of these are believed to be event related and unavailable at the moment
+ Misses lore pickups already within the detection range when zoning into a new map
  + "Fixing" this causes cascading strange behaviours as it detects things halfway through loading the map. While these can, mostly, be corrected, I'm not convinced it's worth the time.
+ Long label customizations are truncated by the GUI
  + If I get any translations, I'll likely have to expand the space to fit them

## Testing and Further Developments
Features are mostly locked down for the v1.0.0 release. Some things that may be in subsequent releases:
+ Actual localization would be nice, but I'm not going to rely on Google and my limited knowledge of French to be at all accurate. Somebody else will have to provide me with translations.
+ Depreciated features of the config system retained to permit smooth upgrades from pre-release versions will be removed starting with v1.1.0.
+ A second project is in the preliminary stages of development, and may have some integration possibilities with this one.
+ Maintenance updates will be made as needed to fix bugs or add updates to the data files.

A feature for helping with The Abandoned lore was found to be unworkable. Lore.IsLockedForChar either does not work as advertised, or requires GM permissions.

There have been several significant changes since the previous version, and only limited testing. Defect reports, suggestions, and contributions are welcome. They can be sent to Peloprata in game (by mail or pm), or submitted via the project page (Issues) or official forum post.

Source Repository: https://github.com/Earthfiredrake/TSW-LoreHound

Forum Post: https://forums.thesecretworld.com/showthread.php?98459-Mod-LoreHound&p=2031487#post2031487

## Building from Source
Requires copies of the TSW and Scaleform CLIK APIs. Existing project files are configured for Flash Pro CS5.5.

Master/Head is the most recent packaged release. Develop/Head is usually a commit or two behind my current test build. As much as possible I try to avoid regressions or unbuildable commits but new features may be incomplete and unstable and there may be additional debug code that will be removed or disabled prior to release.

Once built, 'LoreHound.swf' and the contents of 'config' should be copied to the directory 'LoreHound' in the game's mod directory. '/reloadui' is sufficient to force the game to load an updated swf or mod data file, but changes to the game config files (LoginPrefs.xml and Modules.xml) will require a restart of the client.

## License and Attribution
Copyright (c) 2017 Earthfiredrake<br/>
Software and source released under the MIT License

Uses the TSW-AddonUtils library and graphical elements from the UI_Tweaks mod<br/>
Both copyright (c) 2015 eltorqiro and used under the terms of the MIT License<br/>
https://github.com/eltorqiro/TSW-Utils <br/>
https://github.com/eltorqiro/TSW-UITweaks

TSW, the related API, and most graphics elements are copyright (c) 2012 Funcom GmBH<br/>
Used under the terms of the Funcom UI License<br/>

LoreHound icon developed from game graphics (sourced from TSWDB) and http://www.iconninja.com/basset-hound-dog-head-icon-843075

Special Thanks to:<br/>
The TSW modding community for neglecting to properly secure important intel in their faction vaults<br/>
Vomher for brainstorming the magic numbers
