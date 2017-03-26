# TSW-LoreHound
Notifications for lore drops in The Secret World, even if they're not visible.

## Overview
Can detect and attempt to identify lore pickups when they enter a ~20m radius around the player. Lore pickups have been roughly categorized into 5 groups.
+ Standard: Basic placed pickups, usually always available.
+ Triggered: Mostly found in dungeons after boss fights, requires an event to spawn but doesn't despawn.
+ Timed Drop: Mostly bestiary lore, either drops from monsters or is triggered and will time out after a short period of time (~5min for Bestiary lore, significantly faster for some others). It will track these and also notify you when they despawn, or you end up out of range of the tracker.
+ Unusual Lore: Particularly odd lore detections, currently has the Shrouded Lore from End of Days in it (and a couple of other ones that need a bit more work done on them).
+ Uncategorized: Something that I haven't run across yet, so haven't been able to place in a group.

Notifications for each group can be output to either the System Chat, or as FIFO alerts. By default it will ignore categorized and identified lore which the character has not yet picked up. It will also ignore lore believed to be linked to an inactive event. There is also an option to send in reports of uncategorized lore semi-automatically (sends the next time the bank is opened).

## Installation
Any packaged releases can be installed by copying the contents into [Game Directory]\Data\Gui\Flash\Customized, and restarting the client.
If upgrading from v0.1.1.alpha, a clean reinstall is recommended. Remove the existing mod entirely and login to the game to clear any existing settings before installing a more recent version.

## Changelog
Version next
+ Options menu no longer possessed by a gaki, you can now esc from it
+ Can timestamp detections without having to timestamp all of System chat
+ Despawn tracking can now be disabled independently of lore drop detection
+ Shrouded lore deemed not special enough to have a category all to itself, has been moved to Placed Lore
+ XML file for primary categorization, the most basic updates no longer require a flash compiler
  + Spoiler warning: Descriptive comments may ruin some surprises
+ Install process has recovered from amnesia, no longer forgets to save settings
+ Unknown lore id count: 7 (still)

Version 0.6.0-beta
+ Now even lazier, does less work wherever possible
  + Setting for "new content" will re-enable some of these tests, but should not be needed unitl new content arrives. May be useful if a particular piece of lore does not seem to be detected at all.
+ No longer goes berserk around certain players, and has been told to stop sniffing German corpses
  + False positives in the detection system have been stomped
+ No longer baffled by the drone in Polaris and can spot lore #4 there
+ Various other code cleanup and backend changes
+ Unknown lore id count: 7

Version 0.5.0-beta
+ New responses to lore pickups that don't connect to anything (formerly "Unable to identify")
  + Partially intialized drops will be poked until they shape up
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
+ There are 7 uncategorized lores believed to be in the game
+ Misses lore pickups within the detection range when zoning into a new map
  + "Fixing" this causes cascading strange behaviours as it starts detecting things halfway through loading the map. While these can, mostly, be corrected, I'm not convinced it's worth the time.

## Testing and Further Developments
This is a prerelease version of the mod, for testing purposes. Some things may not be working as intended, or require further work. If you notice a problem with this mod, or with how it interacts with other mods, please let me know.

As this approaches an official release version, there's a few more changes I'm looking at making:
+ Depreciated features of the config system that have been retained to permit smooth upgrades from older versions may start to be removed. Likely starting with the version to follow v1.0.0.
+ Support for localization or message customization is being investigated.

A feature for helping with The Abandoned lore has been found to be unworkable. Lore.IsLockedForChar either does not work as advertised, or requires GM permissions.

Defect reports, suggestions, and contributions are welcome. They can be sent to Peloprata (by pm or mail) in game, or submitted via the project page or official forum post.

Project Page: https://github.com/Earthfiredrake/TSW-LoreHound

Forum Post: https://forums.thesecretworld.com/showthread.php?98459-Mod-LoreHound&p=2031487#post2031487

## Build Requirements
Building from source requires a copy of the TSW API and of the Scaleform CLIK API. Existing project files are configured for Flash Pro CS5.5.

## License and Attribution
Copyright (c) 2017 Earthfiredrake

Software and source released under the MIT License

Uses the TSW-AddonUtils library and graphical elements from the UI_Tweaks mod

Both copyright (c) 2015 eltorqiro and used under the terms of the MIT License

https://github.com/eltorqiro/TSW-Utils

https://github.com/eltorqiro/TSW-UITweaks

TSW, the related API, and most graphics elements are copyright (c) 2012 Funcom GmBH

LoreHound icon developed from game graphics (sourced from TSWDB) and  http://www.iconninja.com/basset-hound-dog-head-icon-843075

Special Thanks to:
The TSW modder community for neglecting to secure various tutorials, code and other commentary in their faction vault
Vomher for help identifying some magic numbers
