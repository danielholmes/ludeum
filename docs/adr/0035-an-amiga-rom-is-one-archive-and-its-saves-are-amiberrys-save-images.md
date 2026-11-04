# An Amiga ROM is one archive, and its saves are Amiberry's save images

Amends the glossary's Disc, whose floppy sets were each Disc a ROM of its own, and adds to [0024](0024-ludeum-installs-duckstation-and-says-where-it-keeps-things.md), [0027](0027-ludeum-installs-mesence-with-a-folder-per-platform.md), [0028](0028-ludeum-installs-ares-and-says-where-it-keeps-things.md) and [0032](0032-ludeum-installs-pcsx2-and-says-where-it-keeps-things.md) a fifth Emulator Ludeum installs.

I want to play Amiga floppy games, and the Amiga had no ROM handling. The research, and what was run to check it, is [amiga-emulator.md](../research/amiga-emulator.md). I chose Amiberry over vAmiga, giving up vAmiga's run-ahead, as it opens every form these games come in, emulates every Amiga model and can be told on its command line exactly which disks to use. WHDLoad's `.lha` and CD32 are for later: only floppies for now.

Two things shape this, both tried on Amiberry 8.5.0.

**A game saves to its disk.** There's no cartridge battery or memory card: a game writes to its floppy, or asks for one to format. Amiberry opens a loose `.adf` read-write and writes straight into it, so a ROM would change as it's played, and Rename, Dropbox and a later dump comparison would all be working on a file that's no longer the dump. But a disk in an archive is read-only, and what's written goes to a **save image**: `<disk>_save.adf` in a folder of Amiberry's, an extended ADF read over the disk. A boot sector writing to a test disk in a `.7z` changed only the save image, and read the write back after a restart, with the archive byte for byte the same.

Amiberry only makes a save image when its write protection is turned off in its menu; with none, the game finds its disk write-protected. An empty one is just a header and zeros, the same every time, so Ludeum can make it first.

**Its disks can stay in one file.** Given `Game.7z/Disk 1.adf`, Amiberry opens that disk, names its save image after the disk, and swaps between any such paths. So a set of disks needs no folder or playlist, which Amiberry couldn't read anyway.

So:

- **An Amiga ROM is one `.7z`**, always: Compacted, holding its one disk, or every Disc of its Version under their own names, in order by their `(Disk N)`. Add ROM takes one disk, each of a set's disks, an archive of them, or an archive of each, as TOSEC keeps them, and packs them. It doesn't look for a Version among them: `(Disk 1 of 3)[t +85 HLM]` and `[a](Disk 1 of 3)` are other Versions, with Disk 1s of their own.
- **A loose disk is read as a ROM but can't be Played.** Put there by hand, it waits in the Review queue to be Compacted, like any Compactable Platform's, and Play says why it's refused.
- **A Play lists the archive, gives each disk an empty save image if it has none, and launches.** The save images are in `Emulators/Amiberry/Saved Disks/<ROM name>/` in the Data folder: the Amiga's Game saves. Each is 2 MB, nearly all zeros, however little is saved. There's nothing Ludeum shows or backs up about them yet. A Rename moves the folder, and refuses if one has the new name. Deleting a ROM leaves it, as with every Emulator's Game saves.
- **The first two disks go in the two drives and all of them in the Disk Swapper.** Many games look in the second drive and don't ask. One that wants another is given it from Amiberry's menu (F12). They're set as configuration (`-s floppy0=`, `-s diskimage0=`), not `-0` and `-diskswapper=`, whose list would need quoting and has its commas guessed at.
- **A disk's path over 255 bytes is refused.** Amiberry opens one up to 255, archive and all, and past that leaves the drive empty and says nothing. Names aren't the trouble: tried at every length around it, with and without TOSEC's tags. On this Mac the ROM folder's path is 65 of them, so a ROM's name and its disk's have 186 between them; HeroQuest II's take 153. A ROM over it is refused at Play, which says to Rename it with fewer of its tags.
- **Every Standing setting is for the one launch**, so no settings file is kept in step: the environment's `AMIBERRY_HOME_DIR`, Amiberry's only way to move its folders on a Mac, where its portable mode is off, is `Emulators/Amiberry/` in the Data folder, with its Kickstarts, Save states, Configurations, controllers and screenshots under it; `-o amiberry_config=` puts its settings there too, and `-o saveimage_dir=` the ROM's save images. It starts on an A500 (`--model A500`), and goes straight to the game (`-G`). Only its window position and which ROMs it found stay in `~/Library/Application Support/Amiberry/amiberry.ini`.
- **Ludeum installs Amiberry**, the pinned `Amiberry-8.5.0-macOS-universal.dmg` checked against its SHA-256, mounted unseen, its app copied to `Emulators/Amiberry.app` and its version checked from its `Info.plist`, without running it. Any other version is a wrong build to install again. Play is refused while any Amiberry is open, as it writes its settings when it quits.
- **Play isn't refused without a Kickstart.** Amiberry falls back to AROS, its free stand-in for one, which both of my example games boot on. A Kickstart goes in `Emulators/Amiberry/ROMs` in the Data folder, and every Play rescans it (`--rescan-roms`), as the list of what's there is otherwise only made once.

## Considered Options

- **vAmiga**, the most accurate, a native Mac app with run-ahead: rejected for now. It opens no `.zip`, `.ipf` or `.lha` and its one way to be told what to do at launch is a RetroShell command per argument. Run-ahead, which led every earlier choice of Emulator, matters less for a game on a floppy, but it's what would make me look again.
- **FS-UAE**: rejected. Last released September 2025, and last pushed the same month. Its floppy overlays are what Amiberry's save images are.
- **Loose disks in a subfolder with a playlist**, as a GameCube ROM of several Discs: rejected. Amiberry reads no `.m3u` (only its libretro core does), Ludeum would have to read it for it, and a loose disk is written over.
- **A `.7z` per disk in a subfolder**: rejected. Compact, Rename and Delete all work on one file already.
- **Writing saves into the loose disks, as Amiberry would like**: rejected, for what it does to the ROM. It's the simplest, and the file is small; but a Game save would go wherever the ROM went, Keep only one Version and a replaced dump included.
- **Copying each disk out of the ROM folder at Play and writing there**: rejected. It's what a save image already is, with more to go wrong.
- **Making a Kickstart a requirement**, as PCSX2's BIOS is: rejected. PCSX2 can't boot without one and Amiberry can, and a game that won't run on AROS says so by not running.
- **A per-game Amiga model**, for AGA games that need an A1200: not yet. Every Play is an A500, and a game for a later Amiga won't run until a Game has that as an Emulator setting.

## Consequences

- Amiberry's Save states, made from its menu (F12), are kept in the Data folder but neither listed nor Played from in Ludeum.
- The A500 is slow to start: HeroQuest II's screen was still grey 25 seconds in.
- 7-Zip is needed to Play an Amiga Game, not only to pack one.
- A save image is found by the name of its disk inside the archive, so an archive packed again by hand with other names leaves its saves behind.
