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

## Known Issues
+ If not using a topbar replacement, the icon cannot be moved or hidden
  + In the player account settings file, the IconPosition record in the LoreHoundConfig archive can be manually changed while the game is not running to change this location.
  + Setting both x and y values to -32 should position the icon completely off the screen
+ Drop lores may not have the topic and entry # immediately available.
  + Stepping away (more than 20m) and reapproaching the lore should cause it to be properly identified
+ German users may see a number of false positive detections, due to wide use of "Wissen" in names
  + Disabling the unknown lore category will remove the spam (as well as any accurate detections)

## Testing and Further Developments
This is a prerelease version of the mod, for testing purposes. Some things may not be working as intended, or require further work. If you notice a problem with this mod, or with how it interacts with other mods, please let me know.

Defect reports, suggestions, and contributions are welcome. They can be sent to Peloprata (by pm or mail) in game, or submitted via the project page or official forum post.

Project Page: https://github.com/Earthfiredrake/TSW-LoreHound

Forum Post: https://forums.thesecretworld.com/showthread.php?98459-Mod-LoreHound&p=2031487#post2031487

## Build Requirements
Building from source requires a copy of the TSW API and of the Scaleform CLIK API. (Existing project files are configured for Flash Pro CS5.5)

## License and Attribution
Copyright (c) 2017 Earthfiredrake

Software and source released under the MIT License

TSW, the related API, and most graphics elements are products of Funcom
LoreHound icon developed from game graphics (sourced from TSWDB) and http://www.iconninja.com/basset-hound-dog-head-icon-843075

Special Thanks to Vomher for help identifying some magic numbers
