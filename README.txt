VISUAL MEDIA CONTROL FOR FIFINE D6
==================================

Version 1.0.0

Visual Media Control shows artwork from the active Windows media session and
adds Play / Pause, Previous, Next, and title controls to the FIFINE D6 Stream
Controller Deck.

The plugin was built and tested for the FIFINE D6 on Windows 10/11. Other
StreamDock-compatible devices may work, but are not tested or supported yet.

Installation
------------
1. Close FIFINE Control Deck completely, including its notification-area icon.
2. Right-click Install-For-FIFINE.ps1 and choose Run with PowerShell, or run:

   powershell -ExecutionPolicy Bypass -File .\Install-For-FIFINE.ps1

3. Start FIFINE Control Deck.
4. Find Visual Media Control in the action list.
5. Drag Artwork Play / Pause onto a key, or use the four grid actions below.

2x2 artwork grid
----------------
Place the grid actions in this exact arrangement:

   Top Left       Top Right
   Bottom Left    Bottom Right

Each grid key can be Artwork only, Play / Pause, Previous track, Next track,
or Title. The Bezel gap setting compensates for the physical space between D6
keys and is synchronized across all four grid actions.

Customization
-------------
- Solid or gradient icons and text
- Icon and text size, opacity, shadow, outline, and alignment controls
- Optional icon backdrop with configurable edge blur
- Per-key custom transparent PNG icons (288x288 recommended, 2 MB maximum)
- Automatic fitting for long titles and artist names

Compatibility
-------------
The active media application must publish metadata through Windows Global
System Media Transport Controls. Spotify, Chrome/Edge with YouTube, VLC, and
many other players normally do this. Artwork availability depends on the app.

Uninstallation
--------------
Close FIFINE Control Deck completely and run:

   powershell -ExecutionPolicy Bypass -File .\Uninstall-From-FIFINE.ps1

Project page
------------
https://github.com/marehori/visual-media-control

New versions and my other plugins:
https://github.com/marehori

by marehori
