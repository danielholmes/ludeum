# Ludeum

A macOS game journal and launcher. Keep a record of every game you play, on any platform: what you thought of it, when you played it, and what you want to play next. Then launch your ROMs straight from the journal in the best standalone emulator for each platform.

> Status: a personal project, v0.1. Expect rough edges.

## Capabilities

- **Journal any game** on any IGDB platform (retro consoles, PC, Xbox, and more), with ratings from 0.0 to 10.0, a rating history, and playthroughs marked finished or dropped.
- **Plan and look back** with a Play Next list, Top Rated, and a Year in Review.
- **ROM folders**: point Ludeum at a folder of ROMs for each platform. It identifies them by checksum (via Hasheous) and name, and anything it isn't sure about goes into a review queue.
- **Metadata and covers** from IGDB, using box art first.
- **One-click play** in the right emulator, with per-game emulator settings such as the Game Boy model.

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

## Requirements to play ROMs

Ludeum doesn't include any games, BIOS files or emulators. Supply your own legally obtained ROMs and BIOS files, and set up BIOS, controllers and video in each emulator. Ludeum copies those settings and applies each game's settings on top.

Install the emulator for each platform you want to play:

| Platform | Emulator |
| --- | --- |
| NES / Famicom, SNES / Super Famicom, Game Boy, Game Boy Color, Game Boy Advance, Master System, Game Gear, PC Engine, PC Engine CD | [Mesen](https://www.mesen.ca) |
| PlayStation | [DuckStation](https://www.duckstation.org) |
| PlayStation Portable | [PPSSPP](https://www.ppsspp.org) |
| Nintendo 64, Mega Drive / Genesis, Sega CD | [ares](https://ares-emu.net) |
| GameCube, Wii | [Dolphin](https://dolphin-emu.org) |
| Nintendo DS | [melonDS](https://melonds.kuribo64.net) |
| Saturn | [Ymir](https://github.com/StrikerX3/Ymir) |

You can journal games on any other platform (PC, Xbox, and so on), but Ludeum can't launch them.

Cartridge ROMs (and DS) can be kept in a `.7z`, or a `.zip` for N64 and Mega Drive, since their emulators open those directly; the Review queue lists loose ones and compacts them for you. A ROM packed in a format its emulator can't open (for example a `.7z` disc image) shows as archived. Unarchive it in Game detail (PS2, PSP) or extract it in its ROM folder to make it playable.

## License

[MIT](LICENSE)
