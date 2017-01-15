# TSW-LoreHound
Notifications for random lore drops in The Secret World, even if they're not visible.

## Overview
Detects and notifies when a lore pickup is within ~20m of the player, even if it is not visible to the player. While this is intended to be used to help players who already have the lore (so can't see it), call out when an rng lore drops, it may inadvertently reveal the existence of other lore as well (see onfiguration section for details).

At the moment I cannot precisely identify which lore element the pickup would unlock. The current attempt at categorization is largely guesswork, based off of what is likely a tangental identifying feature, and may not properly categorize every detected pickup. It is also unable to tell if a lore pickup is visible or not, and will make notifications for plainly obvious lore items (which is at least useful for debugging).

## Installation
Any packaged releases can be installed by copying the contents into [Game Directory]\Data\Gui\Flash\Customized, and restarting the client. 

## Default Configuration
By default, this mod reports via System chat on lore which drops on monster kills (both rng and 100% drops), or is unknown and not properly categorized. It also logs unknown lore entries to the ClientLog.txt file. It should not notify about lore which has a fixed placement in the game world. Support for FIFO messages is also currently not enabled by default.

The entire mod's activities can be toggled with `/setoption ReleaseTheLoreHound [true|false]`, which persists as a character configuration option. There is no gui or other persistent configuration at the moment. Note: It does not currently appreciate swapping to an alt, and will require a `/reloadui` to resume working.

## Advanced Configuration
For debugging and testing purposes there are additional options available through the debug window (ctrl+shift+F2). These values are not currently retained, and will reset to defaults when the UI reloads (when first starting the game and on `/reloadui`)

m_FifoMessageLore, m_ChatMessageLore and m_LogMessageLore can be changed to enable/disable notifications on the various categories (a bitflag set represented by the various ef_LoreType values) from the related output system.

m_DebugDetails can be set to dump some extra information about the lore pickup detected. Lore in an unknown category always reports this information, as it is needed to help with the categorization.

m_DebugVerify permits the mod to do additional tests on things it believes are not lore pickups, in an effort to detect any false negatives. It is enabled by default on current alpha builds.

## Testing and Further Developments
For testing purposes, please note if you see any lores which are miscategorized, go unreported when they shouldn't, or are mentioned as as Unknown. While the mod is intended to be used by characters who have much of the lore, those who can still see the lore drops will provide more complete debugging.

Currently the mod should work with any version of the client, but this is untested. Notification text is mostly in English (parts may be localized due to internal processing by the game). Should there be sufficient interest (and capable volunteers), providing translations of the messages should be relatively trivial.

Ideally I would like to add at least the following features, though some may prove impossible to provide:
+ Persistant configuration settings for notifications
+ Full identification of lore (Topic & Entry #)
+ Ignore visible lore pickups
+ Notification only for RNG based drops
+ Automated error reporting (via in game mail)

Defect reports, suggestions, and contributions are welcome. They can be sent to Peloprata (by pm or mail) in game, or submitted through the project github page.

## Build Requirements
Building from source requires a copy of the TSW API (included in the game directory under \Data\Gui\Flash\Customized\Sources) to be included in the library search paths for the flash compiler of your preference. (Existing project files are configured for Flash Pro CS5.5)

## License and Attribution
Copyright (c) 2017 Earthfiredrake
Software and source released under the MIT License.

TSW and the related API are products of Funcom