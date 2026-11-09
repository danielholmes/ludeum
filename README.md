# Ludeum

A macOS game journal and launcher. Keep a record of every game you play, on any platform: what you thought of it, when you played it, and what you want to play next. Then launch your ROMs straight from the journal in the best standalone emulator for each platform.

> Status: a personal project, v0.1. Expect rough edges.

## Capabilities

- **Journal any game** on any IGDB platform (retro consoles, PC, Xbox, and more), with ratings from 0.0 to 10.0, a rating history, playthroughs marked finished or dropped (with who played along and which copy you played), and a highlight note at the top of a game's page for a tip or where you got to. Expansions and DLC are games too, linked to their base game.
- **Plan and look back** with Backlog, Up next and Want to buy, a What to play next screen, Top-rated, Year in review, lists of your own, and themes, franchises, series and companies pinned to the sidebar.
- **Face-off** checks your ratings against each other: pick the better of two games at a time, and Ludeum points out ratings your picks disagree with.
- **Copies**: record every copy you have or once had, physical or digital, with its regions and where and when you got it. ROMs count as copies too. A bundle (C&C: The First Decade, Super Mario All-Stars) is recorded once, with its own copies, and each game in it shows them.
- **ROM folders**: Ludeum keeps a folder of ROMs for each platform. It identifies them by checksum (via Hasheous) and name, and anything it isn't sure about goes into a Review queue. A file put in a ROM folder by hand waits there too, as a Stray file, to be added as a ROM or given back to the missing ROM it was renamed from. Add ROM brings in a ROM from anywhere, and Rename gives it its No-Intro (or Redump) name.
- **Archive and Compact**: pack ROMs you aren't playing into `.7z` to save room, and unpack them again in the background when you want to play. Cartridge ROMs can be compacted into an archive their emulator opens directly, so they still play.
- **Metadata and covers** from IGDB, using box art and screenshots from the [LaunchBox Games Database](https://gamesdb.launchbox-app.com).
- **One-click play** in the right emulator, with per-game emulator settings such as run-ahead and the Game Boy model.
- **Attachments**: keep manuals, maps and other files with a game, in a folder per game, and open them in the app your Mac uses for them.
- **Backups** of the journal, taken routinely and before any big change, and Storage Stats to see where the space goes.

## Requirements to build

- macOS 15 or later
- Xcode 26 or later (Swift 6.2)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- IGDB API credentials (a free Twitch developer application)
- Optional: a [Hasheous](https://hasheous.org) API key

## Build and run

```sh
git clone https://github.com/danielholmes/ludeum.git
cd ludeum
scripts/run.sh
```

`scripts/run.sh` generates the Xcode project, builds the Debug configuration, and opens the app; `scripts/build.sh` does the same without opening it. To work in Xcode instead:

```sh
xcodegen
open Ludeum.xcodeproj
```

Run the tests with `swift test`.

**Signing.** The app is ad-hoc signed by default, so it builds anywhere. With ad-hoc signing, macOS asks for Keychain access again after each rebuild. To sign with a stable identity, copy `App/Config/Local.xcconfig.example` to `App/Config/Local.xcconfig` and set your Personal Team ID. You can find the ID in Xcode ▸ Settings ▸ Accounts, or with `security find-identity -v -p codesigning`.

**IGDB credentials.** `scripts/setup-igdb.sh` walks you through creating a Twitch application and tests the credentials against IGDB. Enter the Client ID and Client Secret, plus your Hasheous key if you have one, in Ludeum ▸ Settings (⌘,).

## Where Ludeum keeps things

Ludeum keeps everything in `~/Library/Application Support/Ludeum/`: the journal, the emulators it installs (under `Emulators/`), and a `Data` folder holding what must survive losing your Mac (the ROM folders, attachments, backups, and what DuckStation saves: its save states, memory cards and BIOS files under `Data/Emulators/DuckStation/`). Ludeum won't start until the `Data` folder exists. Ludeum never creates it, so a missing link can't be silently replaced by an empty folder. Create it yourself, or link it to a synced folder so it's kept safe:

```sh
ln -s ~/Dropbox/games/Ludeum ~/Library/Application\ Support/Ludeum/Data
```

Each platform's ROMs go in `Data/ROMs/<Platform>/`, for example `Data/ROMs/SNES/`. The cache lives in `~/Library/Caches/Ludeum/` and can always be rebuilt.

## Requirements to play ROMs

Ludeum doesn't include any games, BIOS files or emulators. Supply your own legally obtained ROMs and BIOS files, and set up BIOS, controllers and video in each emulator. Ludeum keeps those settings, and sets each game's own settings for that Play only.

Install the emulator for each platform you want to play. Ludeum checks each emulator's version at launch and won't play in one older than the version below. Ludeum ▸ Emulators… shows what it found. DuckStation, MesenCE, ares, PCSX2, Amiberry, Ymir, 86Box and DOSBox Staging are the exception: Ludeum installs its own copy of each from there, at exactly the version below, into its own folder, so nothing it keeps is shared with any other copy on your Mac. Their settings are still yours to make in each, during a Play, apart from where they keep things and a few Ludeum fixes for every game. MesenCE 2.2.1 needs SDL2 (`brew install sdl2`). PCSX2's release is built for Intel, so it needs Rosetta 2, and a PlayStation 2 BIOS in the Data folder's `Emulators/PCSX2/BIOS` before it can play. Amiberry plays on its bundled AROS until there's a Kickstart in the Data folder's `Emulators/Amiberry/ROMs`, which some games need. An Amiga game saves to its disk, so an Amiga ROM is kept in a `.7z` that's never written to, with what the game saves in `Emulators/Amiberry/Saved Disks`. Ymir needs a Saturn BIOS in the Data folder's `Emulators/Ymir/BIOS` before it can play, and can't be started from a save state, so its states load with its own keys once a game is running. A disc that lists the Virtua Gun is played with the mouse: left click to shoot, right click to reload.

| Platform | Emulator | Version |
| --- | --- | --- |
| NES / Famicom, SNES / Super Famicom, Game Boy, Game Boy Color, Game Boy Advance, Master System, Game Gear, PC Engine CD | [MesenCE](https://github.com/nesdev-org/MesenCE), installed by Ludeum | 2.2.1 |
| PlayStation | [DuckStation](https://www.duckstation.org), installed by Ludeum | build 12442 |
| PlayStation 2 | [PCSX2](https://pcsx2.net), installed by Ludeum | 2.9.152 |
| PlayStation Portable | [PPSSPP](https://www.ppsspp.org) | 1.20.4 |
| Nintendo 64, Mega Drive / Genesis, Sega CD | [ares](https://ares-emu.net), installed by Ludeum | v148 |
| GameCube, Wii | [Dolphin](https://dolphin-emu.org) | 2609 |
| Nintendo DS | [melonDS](https://melonds.kuribo64.net) | 1.1 |
| Saturn | [Ymir](https://github.com/ymir-emu/Ymir), installed by Ludeum | 0.4.1 |
| Xbox | [xemu](https://xemu.app) | 0.8.136 |
| Amiga | [Amiberry](https://amiberry.com), installed by Ludeum | 8.5.0 |
| Windows | [86Box](https://86box.net), installed by Ludeum | 6.0 |
| DOS | [DOSBox Staging](https://www.dosbox-staging.org), installed by Ludeum | 0.83.0 |

Windows games of about 1995 to 2000 play on real Windows 98 SE in 86Box. Supply your own Windows, prepare a base from it once ([how](docs/agents/windows-base.md)), and choose it in Ludeum ▸ Emulators…. A Windows game's ROM is its disc, which is never written to; its first Play boots Windows with the disc in the drive, and you install it there. The installed game and its saves are its game disk, in the Data folder's `Emulators/86Box/Game Disks`, beside the base.

A DOS game's ROM is a folder of its drives, `Data/ROMs/DOS/<name>/` with `C/`, the game's files, and `CD/`, its disc images; Add ROM lays one out from a game's folder, its discs, or both. It's never written to: what the game writes, its saves and a CD game's install, goes to its Game save in the Data folder's `Emulators/DOSBox Staging/Game Saves`. Choose the program it starts with in its DOSBox Staging settings on Game detail, or Play goes to a DOS prompt; a game that needs other settings (CPU cycles, a sound card) gets them in its own settings file, which the same place opens. MIDI music plays through the SoundFont Ludeum installs with DOSBox Staging.

PS Vita and MSX2 have ROM folders, but no emulator plays them yet. You can journal games on any other platform (Xbox 360, PlayStation 3, and so on), but Ludeum can't launch them.

Ludeum also uses these command-line tools, and warns at launch if one is missing:

- [7-Zip](https://www.7-zip.org) (`brew install sevenzip`) to Archive, Unarchive and Compact ROMs, to list what's inside an archived one, and to Play an Amiga game.
- [Zstandard](https://facebook.github.io/zstd/) (`brew install zstd`) to show the screenshots of DuckStation save states.
- [xdvdfs](https://github.com/antangelo/xdvdfs) (`cargo install xdvdfs-cli`), only if you have xemu. xemu boots only an XISO, so Play refuses a full Redump Xbox image; make an XISO from it with `xdvdfs pack`.

Cartridge ROMs (and DS) can be kept in a `.7z`, or a `.zip` for N64 and Mega Drive, since their emulators open those directly; the Review queue lists loose ones and compacts them for you. A ROM packed in a format its emulator can't open (for example a `.7z` disc image) shows as archived. Unarchive it in Game detail (PS1, PS2, PSP, Vita, GameCube, Wii, Xbox, Sega CD, Saturn and PC Engine CD) or extract it in its ROM folder to make it playable.

On the disc platforms (PS1, Sega CD, Saturn and PC Engine CD), each ROM is a subfolder named after it. A multi-disc game's subfolder holds its discs and an `.m3u` playlist that loads them. Add ROM writes the playlist; a folder put in by hand without one, then Added from the Review queue, can't be played until it has one. Saturn is the exception: Ymir reads no playlist, so a multi-disc game opens at Disc 1, and its disc is changed in Ymir.

## License

[MIT](LICENSE)
