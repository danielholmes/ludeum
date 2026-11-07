# Windows Games are Played in 86Box, from a game disk over one Windows base

Takes the place of [0040](0040-windows-games-are-played-in-wine-from-a-clone-of-the-roms-prepared-game.md), adds to [0038](0038-emulators-are-whole-apps-ludeum-installs-not-cores.md)'s model a seventh Emulator Ludeum installs, and answers [0035](0035-an-amiga-rom-is-one-archive-and-its-saves-are-amiberrys-save-images.md)'s problem again: a game that writes to the thing it was loaded from.

I want to play Windows games of about 1995 to 2000. Wine ran Z and Age of Empires, but only after hand work that differed from game to game, and that is what I want to get away from as more games come in. Real Windows 98 SE in an emulated PC ran games from their own installers with none of it. The research, with what was run and the exact recipes, is [windows-9x-in-86box.md](../research/windows-9x-in-86box.md).

**Windows does the compatibility work.** Age of Empires' own installer, which fails under Wine, ran on both 86Box and DOSBox-X, and it played with its CD music, which Wine has no way to play. Z ran unpatched, with the menu picture Wine left black. Red Alert 2 ran from its files in The First Decade, whose installer wants XP. What a game needs now is ordinary Windows knowledge (DirectX, a settings tool, which file starts it), not patches.

**86Box over DOSBox-X.** They felt close on Age of Empires, but DOSBox-X's Apple Silicon build has only its slow CPU mode for Windows 9x, and needed its speed tuning by hand: 80,000 cycles a millisecond pegged a core and broke up the audio at 1024×768, and 70,000 was clean but slowed Z. 86Box's recompiler held a 450 MHz Pentium II through Age of Empires and Red Alert 2 at full speed with nothing tuned. DOSBox-X stays an acceptable fallback if that changes.

**One Windows, and a file of differences per game.** 86Box reads VHD differencing disks: a read-only parent, and a file holding only what's been written over it. Age of Empires' is 271 MB over a 541 MB base, and the base's checksum didn't change through install, play, save and reload. So games don't share a disk that one bad install can break, nothing has to be resized as games arrive, and Windows isn't stored again for each game.

So:

- **86Box is the Emulator for Windows** (IGDB's PC (Microsoft Windows)), installed by Ludeum at one pinned release, `86Box-macOS-x86_64+arm64-b9001.zip` (v6.0) with its v6.0 ROM set, each checked against its SHA-256, in `Emulators/` in the Ludeum folder.
- **The machine is one, fixed:** an ASUS P3B-F (`p3bf`) with a Pentium II (Deschutes), 256 MB, a Voodoo3 3500 (`voodoo3_3500_agp`, NTSC BIOS, 4 render threads), a Sound Blaster 16 PnP, a 32 GB disk and 86Box's own DVD drive (`86dvd`), since a CD-only drive refuses an image larger than a CD. The board and cards are fixed because Windows installs drivers for them; a Standing setting, written before each Play.
- **The Windows base is prepared by hand, once, outside Ludeum, and chosen.** It can't be shipped, and Setup needs a person. Choose Base… on 86Box's row of the Emulators table takes the prepared archive (the VHD, with the machine's BIOS settings so a new game doesn't stop at a CMOS prompt), and Ludeum brings it under its control: copied into the Data folder, read-only. The row shows it, with a button to show it in Finder. How to prepare one is in [windows-base.md](../agents/windows-base.md). Play is refused until there's a base.
- **A base is never changed or replaced once a game disk stands on it,** as that disk would no longer read true. Choosing another is refused while any game disk exists.
- **A Windows ROM is its disc:** a subfolder of the Windows ROM folder, named for the ROM, holding its disc image or images (`.iso`, or a cue sheet with its tracks). It's never written to. It's taken as a Disc Platform's ROM is, and Matched by hand, as no checksum database covers these. A game that comes as files and no disc is made into an ISO by hand first.
- **A game disk is a ROM's own differencing VHD, `<ROM name>.vhd`, beside the base in `Emulators/86Box/Game Disks/` in the Data folder,** so it syncs. They must stay in the one folder: a game disk names its parent by a full path and by a bare file name, and 86Box refuses one that finds neither, so the folder can move but they can't be parted. The base's file name is therefore fixed.
- **The game disk is the Game save.** It holds the installed game and everything it writes, so saves need no handling of their own and are backed up with it. Deleting one loses the install and the saves together, and says so. A Rename moves it; deleting a ROM leaves it, as with every Emulator's Game saves.
- **The first Play makes the game disk** (86Box does, given a file that doesn't exist and a parent), boots to the Windows desktop with Disc 1 in the drive, and the game is installed in Windows. Later Plays boot the same disk to the desktop. Each game has its own Windows, so a shortcut in its StartUp folder is how it starts itself, if I want that; Ludeum doesn't reach inside.
- **A Play's other files stay out of the Data folder and are rewritten each time:** 86Box takes a folder per machine (`-P`), with its `86box.cfg` and BIOS settings, kept per ROM in the Ludeum folder. The mouse is released with ⌘⌥. Other Discs are changed from 86Box's Media menu.
- **Windows Games Play side by side, each ROM in one 86Box at a time.** Unlike the other Emulators Ludeum installs, whose one set of settings files it writes before every Play, nothing a Play of 86Box writes is shared between ROMs (its global settings go in the machine folder too, `-O`), and the base is only read. So Play is refused only while an 86Box is playing that ROM already, as a game disk can be in use by only one machine; Ludeum tells which by the `-P` on each open 86Box's command line, and counts one it can't read as playing anything. Rename and deleting a game disk wait only on the ROM's own 86Box; choosing a base and installing 86Box still wait on every one.
- **CPU speed is an Emulator setting, per Game**, starting at 450 MHz, the fastest Pentium II 86Box has. Lowering it costs nothing to reinstall, and a game that holds 100% at a lower speed has clean audio where one at 90% doesn't.
- **The display fills the screen with 86Box's resizable window and forced 4:3** (`vid_resize = 1`, `force_43 = 1`) and the Mac's own full screen. Its fullscreen command leaves a fixed-size picture small in the middle.

## Considered Options

- **Wine ([0040](0040-windows-games-are-played-in-wine-from-a-clone-of-the-roms-prepared-game.md))**: built, and taken out the same day. It works, but every game is its own piece of hand work, and it leans on Rosetta 2, which ends after macOS 27.
- **DOSBox-X**: rejected for now, and acceptable if things change. It's the lighter one to set up, with no BIOS files or boot floppy, but it needs per-game tuning and has the less headroom here.
- **Parallels or another VM with current Windows on Arm**: rejected. Fast, but old games meet modern Windows's own problems, and a VM of that size doesn't fit a Game save per Game.
- **QEMU in UTM**: rejected. UTM says it has no 3D for Windows, and there's a reported failure booting Windows 98 SE on Apple Silicon.
- **Windows XP as the base**: rejected. It would ask more of a machine already near its limit, some 9x games don't run on it, and the games that truly need it want more than 86Box can give.
- **All Windows games on one shared disk**: rejected. It saves little on this Mac, one bad install could break every game, and it has to be sized up front and never shrinks.
- **A plain copy of the base per game**: rejected. An APFS clone is free here but not in Dropbox or the Backups, where every game would carry Windows again.
- **A wizard that drives Windows Setup**: rejected. Setup stops for a person whatever the answer file says, and only I use this.

## Consequences

- **The limit is about 2000.** Z, Age of Empires, Tiberian Sun and Red Alert 2 are solid. Renegade (2002) runs at 800×600 but lags in action with its audio breaking up, crashed once, and its emulated CPU was the limit, with the render threads far from theirs, so nothing is left to turn up. Later games need something else, probably outside this model.
- **DOS Games aren't this.** A small DOS game would wait on Windows and may run too fast, so they stay DOSBox's ([#53](https://github.com/danielholmes/ludeum/issues/53)), Platform 13 apart from Platform 6.
- Two machines at once each keep a core busy with their recompiler, besides the Voodoo's render threads, so either may drop below full speed, and its audio break up, where it held alone.
- A Play boots Windows before anything else, and I shut Windows down myself. Quitting 86Box without doing so risks a ScanDisk at the next boot.
- The game disk changes on every Play, as Windows writes as it starts, so Dropbox syncs some of it each time. How much hasn't been measured, nor has a base or game disk that Dropbox keeps online only.
- A game disk can't be looked into from the Mac as a ROM can, and a copy of a game's files from a CD image arrives read-only until `attrib -r` clears it.
- Ludeum has nothing to say about which file starts a game or what it needs first (`RA2.EXE`, not `GAME.EXE`; Renegade's `WWCONFIG.EXE`). That's knowledge for the Game's notes.
