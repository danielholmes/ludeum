# Windows Games are Played in Wine, from a clone of the ROM's prepared game

Adds a seventh Emulator Ludeum installs to [0038](0038-emulators-are-whole-apps-ludeum-installs-not-cores.md)'s model, and meets [0035](0035-an-amiga-rom-is-one-archive-and-its-saves-are-amiberrys-save-images.md)'s problem again: a game that writes to the thing it was loaded from.

I want to play Windows 9x games, Z and Age of Empires to begin with, and Windows had no ROM handling. Both were got working by hand on 2026-11-05, each as an app of its own; the research, with what was run, is [wine-as-windows-emulator.md](../research/wine-as-windows-emulator.md). My first thought was to keep such an app as the ROM and have Play open it. Three findings turned that into this.

**Most of such an app isn't the game.** Z's was 1.5 GB: 891 MB of Wine, the same for every game; 317 MB of a Wine prefix's `windows` folder, which Wine builds again in about 20 seconds; and 361 MB of game. Age of Empires ran on Z's Wine unchanged, with 175 MB of its own. What is the game is its folder and a few kilobytes saying how to start it.

**Getting a game to the point where it Plays is hand work, and differs in kind from game to game.** Z needed its patched exe unpacked and given an import so cnc-ddraw loads first. Age of Empires needed 89 of its files given back their long names, a stand-in for its disc check, and the disc's video codec and fonts. Its own installer fails under Wine. None of that can be Ludeum's; what can be is starting a game that has been prepared, the same way every time.

**A game writes into its own folder and into the registry**: Z's saves sit beside its exe and its options under `HKEY_LOCAL_MACHINE`, Age of Empires' saves in its `SAVEGAME` folder and its options under `HKEY_CURRENT_USER`. Wine has nothing like Amiberry's save images to keep those apart. But an APFS clone is nearly free: Z's game folder cloned in 0.13 seconds for under 1 MB, and writes to the clone left the original's checksum unchanged. Tried with Age of Empires from a clone: a game saved and loaded back, and afterwards the clone differed from the original by the one save file.

So:

- **Wine is the Emulator for Windows** (IGDB's PC (Microsoft Windows)), installed by Ludeum at one pinned release in `Emulators/Wine/` in the Ludeum folder: Sikarugir's `WS12WineSikarugir10.0_6.tar.xz`, the build both games Play on, with the libraries it doesn't carry copied into its `lib/` from Sikarugir's `Template-1.0.11.tar.xz`, each download checked against its SHA-256. Install keeps the modification time of its `share/wine/wine.inf`, as Wine updates every prefix that remembers another. Ludeum runs its `bin/wine` directly; nothing of it is an app I open. One pin serves every Windows ROM, and raising it means trying each of them again.
- **A Windows ROM is a prepared game, not a disc.** It's a subfolder of the Windows ROM folder, named for the ROM, holding:
  - **its launch file**, `launch.json`, the file a Play opens: the exe and the folder it starts in, the DLL overrides, the locale, the registry file to import, the drives to make (letter, kind, label), the files to lay into the prefix's `windows` folder, and the registry keys that are the game's own;
  - **`Game/`**, the game's folder as it has to be to run, with cnc-ddraw and its `ddraw.ini` beside the exe where the game draws with DirectDraw;
  - **`Prefix/`**, what the launch file lays into the prefix (Age of Empires' codec, fonts and registry file);
  - **`Disc/`**, the disc image it was prepared from, and anything that did the preparing. A Play never reads it.
- **Preparing a game is done by hand, outside Ludeum.** Add ROM takes the prepared subfolder as it is and Matches it by hand, as no checksum of a folder is in any database.
- **A Play never runs the ROM.** Each ROM has a prefix of its own in `Emulators/Wine Prefixes/<ROM name>/` in the Ludeum folder, outside the Data folder, made when it's missing or was made by another pin, from the launch file. A Play clones `Game/` into it afresh, lays the ROM's Game save over the clone, imports the saved registry keys, and starts the exe with everything else as environment for the one launch (`WINEPREFIX`, `WINEDLLOVERRIDES`, `WINEDEBUG`, `LC_ALL`), so Wine has no settings file to keep in step, as with Amiberry.
- **A Windows Game's Game save is what the game wrote**: every file in the clone that is new or differs from the ROM's, and an export of the registry keys the launch file names. It's kept in `Emulators/Wine/Saves/<ROM name>/` in the Data folder, gathered once the game and its `wineserver` have ended (Wine writes the registry as it exits), and at the next Play if Ludeum wasn't there to see it end. Nothing about a game has to be known but its registry keys, and those have to be named: the rest of the registry changes on every run for Wine's own reasons. The ROM is byte for byte what was Added, so Rename, Archive and Dropbox work on a folder that doesn't change, and Deleting a ROM leaves its Game save, as with every Emulator's.
- **A Windows ROM is Archived and Unarchived as a PS2 one is**: the whole subfolder into a `.7z` and back. That's where keeping the disc image costs nothing to Play around: Age of Empires' is 657 MB beside a 175 MB game.
- **No Save states and no Resume state.** Wine can't snapshot a running program, so Play has the one way to start.
- **Play is refused while that ROM's Wine is still running**, and while Wine is missing or not the pinned build, each with its reason, as for the other Emulators.

## Considered Options

- **The whole app as the ROM, and Play opens it**: rejected. It puts 1.2 GB of Wine and rebuildable prefix into Dropbox for every game, each app pins its own Wine for good, and the game's saves are inside the ROM.
- **Play runs the ROM's folder in place**: rejected, for what 0035 rejected it for. The ROM would change as it's played, and its saves would go wherever it went, Keep only one Version included.
- **The launch file lists the game's save files, and only those are kept**: rejected. Each game's save paths would have to be worked out, and anything not listed would be lost; the clone makes the whole difference cheap to find. It keeps a few files that aren't saves (cnc-ddraw rewrites its `ddraw.ini`, Age of Empires its `scenario.inf`), which costs nothing.
- **Gcenx's `wine-stable-11.0_1`**, the package WineHQ's download page names, as the pin: rejected. It's one download with its libraries in it, and Age of Empires Played, saved and loaded on it. But Z dies as it starts, the v1.5 exe as its patch ships it as well as mine, while the original 1998 exe starts. Its old releases don't stay listed either.
- **A pin per ROM**: rejected for now. Wine's own FAQ expects regressions between versions, and going from Wine 10 to 11 lost one game of two, so it's the safer shape; but each release kept is about 900 MB and there are two games.
- **The disc image as the ROM, prepared by Ludeum at Add ROM**: rejected. Neither game's preparation is something a program could have been told in advance.
- **The disc image as a second ROM, as an Attachment, or left outside Ludeum**: rejected. A second ROM is two Copies of one disc and trips Duplicate Versions; an Attachment is never a copy of the Game; and left outside, the Data folder holds a game with nothing to prepare it from again.
- **One prefix for every game**: rejected. Age of Empires needs a drive, a codec and fonts of its own in it, and Wine's documentation leans to one each.
- **Ludeum fetching cnc-ddraw at a pin of its own**: rejected. Its releases publish no checksums, its settings are per game, and a ROM that carries its own still runs when a release is gone.
- **CrossOver's source, Apple's Game Porting Toolkit, Whisky**: rejected. The first is source with no build, the second is licensed for developing and evaluating games and adds nothing a DirectDraw game uses, and the third is archived.
- **Playing the disc's CD audio through a `winmm` wrapper**: not yet. Wine on macOS plays no CD audio, and Age of Empires falls back to its MIDI files.

## Consequences

- **Rosetta 2 is Wine's horizon.** Every usable build is x86_64, and Apple keeps Rosetta whole only through macOS 27. Whether a Windows game counts among the "older, unmaintained games" it serves after that, Apple hasn't said. macOS 28 is when to look again.
- A Windows ROM has to be on this Mac to be Played, as the clone reads all of it. One that Dropbox keeps online only is downloaded first.
- `Z95.app` and `Age of Empires.app` in `~/Applications` are taken apart into ROMs by hand, once, and then deleted.
- What I fixed per game stays the ROM's business and its flaws stay too: Age of Empires' Windows text boxes are drawn at half the size of their frames, as cnc-ddraw scales the picture and not the controls on it.
- A game that saves in My Documents would write into my real `~/Documents`, which Wine links a prefix's user folders to. Neither game does, and nothing here handles one that does.
- DOS (#53) asks for the same shape, a folder and a file saying what to run, and can take this one. A Mac game that still runs has no Emulator at all; neither is decided here.
- The glossary changes when this is built: Emulator and Data folder gain Wine, ROM folder a Windows ROM's subfolder, Game save a Windows Game's, and Archive the Windows ROM.

## Still to settle before this is built

- **Saving and loading in Z** hasn't been tried, nor has either game been Played from a Game save laid over a fresh clone.
- **Cloning a ROM that Dropbox keeps online only** hasn't been tried.
- **The source of Sikarugir's changes to Wine 10.0** wasn't found, and `10.0_6` is no longer in its list of current engines, though the download is still there.
