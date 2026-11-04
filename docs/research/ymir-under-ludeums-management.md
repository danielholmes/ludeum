# Ymir under Ludeum's management

Researched 2026-11-04 for issue #86. The question: can Ludeum manage Ymir as ADR 0024 manages DuckStation, 0027 MesenCE, 0028 ares, 0032 PCSX2 and 0035 Amiberry (install a pinned build, keep it apart from any other copy, write Standing settings that put its Save states and Game saves in the Data folder, refuse Play while it runs, list and Play from Save states in Game detail, show a Game's Game saves)? Where does Ymir keep its Save states and backup RAM, what does it name them by, what loses one, and can OpenEmu's Saturn saves be brought across? It lays out the facts and the options. Apart from the pin, which Daniel decided on 2026-11-04 (§11), it doesn't make the decision.

Sources:

- **Ymir source** at tag `v0.4.1`, commit `d49c0868cf9998d279394498ad0cd0efbd102ccb` (2026-10-18). Links like `T/apps/ymir-sdl3/src/main.cpp#L26-L41` mean `https://github.com/ymir-emu/Ymir/blob/d49c0868cf9998d279394498ad0cd0efbd102ccb/apps/ymir-sdl3/src/main.cpp#L26-L41`.
- **Ymir `v0.3.3`**, commit `54fead6a0001d3e4b6741a8d095ee8342266c3dc` (2026-06-22), for what's on this Mac and the state and settings versions only.
- **Ymir `main`** at `0d7f58b9c0de34ed8a37739d1524916f1b3704ba` (2026-11-01), diffed against `v0.4.1` on the files cited here (§11).
- **The GitHub REST API** for releases, assets, digests and repo metadata, last re-checked as this was finished: nothing newer than `v0.4.1` but the moving `latest-nightly`.
- **The release assets** `ymir-macos-arm64-v0.4.1.zip` and `ymir-macos-arm64-v0.3.3.zip`, downloaded into the session scratchpad, checked against the API's digests and unpacked. **Neither was ever run.**
- **This Mac**, read without changing or launching anything: `/Applications/ymir.app`, `~/Library/Application Support/StrikerX3/Ymir/`, the Ludeum folder, its journal (read-only) and the Data folder (`~/Dropbox/games/Ludeum/`). No ROM's contents were read.
- **Ludeum's code** on `main` at commit `466e232`.

The repository is now **`ymir-emu/Ymir`**. `StrikerX3/Ymir` redirects there; the code still says `StrikerX3` where it names the organisation for the default data folder, and the bundle ID is still `io.github.strikerx3.ymir` (§1, §8). The README's link in this repo points at the old name.

Anything not checked against one of these sources is marked **unverified**. Nothing here has been checked by running Ymir, so behaviour read from source is what the code says, not what was seen.

## Answer

**Mostly yes, and the data side is the simplest yet: one flag gives Ymir a whole profile folder, every folder can be overridden by an absolute path, and saves are keyed by the disc, not the file's name. But nothing can start a Play from a Save state, and there's no Resume state.** Eight facts shape the design:

1. **`-p <folder>` sets the whole profile for that launch**, with no first-run dialog, and nothing goes in or beside the bundle. It holds `Ymir.toml`, and `General.PathOverrides` in that file moves each folder to an absolute path (§1, §2).
2. **No flag, setting or file starts a Save state.** The only start options are the disc, the profile, fullscreen, paused, fast-forward and debug tracing. States are loaded into their slots when a disc loads, and a state is only applied by a hotkey or menu item (§3).
3. **There's no automatic or on-exit state.** A Resume (ADR 0034) has nothing to read. The rewind buffer is memory only (§3).
4. **Save states are keyed by a hash of the disc's first sectors**, in `savestates/<hash>/<slot>.savestate`, with a `meta.txt` beside them giving the disc's Title and Product Number. So they follow a ROM through Rename, Unarchive and a `.chd` conversion, and Ludeum can match a folder to a Game by reading `meta.txt` rather than computing the hash (§3, §5).
5. **Backup RAM has a per-Game switch.** `System.InternalBackupRAMPerGame` gives each disc its own 32 KiB `backup/games/bup-int-<Title> [<Product>].bin`, named from the disc's header. With it off, every Game shares one image. Either way a save inside is listable from a small block format, but a save's name is whatever the game chose (`HOUSEOFDEAD`), so a shared image can't be split by Game (§4).
6. **Backup RAM is a memory-mapped file**, written by the OS rather than by Ymir, and this Data folder is under `~/Library/CloudStorage/Dropbox`. Whether Dropbox sees and syncs those writes is **unverified**, and it's the riskiest unknown. And Ymir **formats an internal image whose size or header is wrong**, so a damaged one is wiped rather than refused (§6).
7. **The release is ad-hoc signed, not notarised**, so Install needs the same no-quarantine step as DuckStation and MesenCE. It's a self-contained arm64 app with a plain Info.plist version, so the version check needs no launch (§8).
8. **Ymir opens no `.m3u`, `.7z` or `.zip`.** A playlist on the command line loads nothing, silently, and Ludeum's Saturn ROM folder reads `.m3u` as ready and has a test expecting it. All five Saturn ROMs here are Archived `.7z` and single-disc, so nothing hits this today, but none can be Played until Unarchived (§5).

The rest:

- **It has never played anything on this Mac**: one launch of a minute on 2026-10-06, no BIOS, no disc, no states, an empty backup RAM. Nothing needs moving over (§12).
- **A BIOS is required**, none is in Ymir's folder, and two are in OpenEmu's folders (§9).
- **OpenEmu's saves**: House of the Dead's `.bkr` files are already Ymir's format and should load as they are. Its `.bcr` is blank. The `.smpc` files can't be read and hold only a clock. **The six Virtua Cop files the issue lists weren't found anywhere searched** (§13).
- **Refuse Play while it's open** is the right rule: there's no single-instance guard, and it rewrites its whole settings file on exit (§7).

## 0. Which repository

- **`ymir-emu/Ymir`**, GPL-3.0 (API `license.spdx_id`), default branch `main`. `gh api repos/StrikerX3/Ymir` answers with `ymir-emu/Ymir`.
- **Release tags**: 18 stable and prerelease versions `v0.1.0` to `v0.4.1`, plus the moving `latest-nightly`. A stray tag `latest` sits at `f1569eab` (2025-07-20) with no release.

## 1. Data root, portable mode and command line

### Where the profile is

The order, `T/apps/ymir-sdl3/src/app/app.cpp#L342-L435`:

1. `-p <path>`: that path, used as given.
2. `-u`: the user profile.
3. A `Ymir.toml` in the "portable" folder.
4. A `Ymir.toml` in the executable's folder.
5. A `Ymir.toml` in the user profile.
6. Otherwise a dialog asks Installed, Portable or Cancel.

- **The user profile** is `SDL_GetPrefPath("StrikerX3", "Ymir")` (`T/apps/ymir-sdl3/src/app/profile.cpp#L29-L34`, `T/apps/ymir-sdl3/CMakeLists.txt#L641-L642`), which on this Mac is `~/Library/Application Support/StrikerX3/Ymir/`.
- **Portable on macOS is `Contents/MacOS`**: `GetPortableProfilePath` returns the executable's folder there, as "SDL_GetCurrentDirectory() returns "/" for some reason" (`profile.cpp#L36-L46`). So a marker means a `Ymir.toml` inside the bundle, and all of Ymir's writes beside it, which breaks the seal of its ad-hoc signature.
- **`-p` skips the dialog**, and a folder with no `Ymir.toml` is fine: `Settings::Load` takes defaults and remembers the path (`T/apps/ymir-sdl3/src/app/settings.cpp#L1191-L1197`), and the profile's folders are created at startup (`app.cpp#L448-L454`). So `-p Emulators/Ymir` keeps the bundle sealed, and needs nothing beside it but that flag.
- **Only `-p` is per-launch.** A launch without it, such as Open from the Emulators sheet, finds the user profile instead, so every way Ludeum starts it would need the flag.

### What's in a profile

`T/apps/ymir-sdl3/src/app/profile.cpp#L12-L23`:

| Folder | Holds | Override key |
|---|---|---|
| `roms/ipl/` | BIOS images | `IPLROMImages` |
| `roms/cdb/` | CD block ROMs (only for low-level CD emulation) | `CDBlockROMImages` |
| `roms/cart/` | ROM cartridges | `ROMCartImages` |
| `backup/` | per-Game backup RAM, in `games/` | `BackupMemory` |
| `backup/exported/` | files exported from the Backup Memory window | `ExportedBackups` |
| `state/` | shared backup RAM, SMPC data, window and GUI state, recent discs, update cache, debugger state | `PersistentState` |
| `savestates/` | Save states | `SaveStates` |
| `dumps/` | debugger memory dumps | `Dumps` |
| `screenshots/` | screenshots | `Screenshots` |

And `Ymir.toml` and an optional `gamecontrollerdb.txt` at the root, which can't be moved except by moving the root.

### Command line

All of it, `T/apps/ymir-sdl3/src/main.cpp#L26-L43`: `-d`/`--disc <path>` (also the one positional argument), `-p`/`--profile <path>`, `-u`/`--user`, `-h`/`--help`, `-f`/`--fullscreen`, `-P`/`--paused`, `-F`/`--fast-forward`, `-D`/`--debug`, `-E`/`--exceptions`. The set is the same at `v0.3.3` and at `main`.

- **There is no `--version`.** An unknown option is a parse failure, which shows a fatal error dialog (`main.cpp#L59-L65`). Ludeum's spec says `--version` opens Ymir's window; by the source it would show that dialog. Either way, it's not something to run (§8).
- **There's no way to choose a Save state, a slot or a setting** on the command line: "TODO: allow overriding configuration from CommandLineOptions" (`app.cpp#L437`).

## 2. Settings: `Ymir.toml`

- **TOML**, through toml++, sorted, with paths as single-quoted literal strings. `ConfigVersion` is 6 at `v0.4.1` and `main`, 5 at `v0.3.3` (`settings.cpp#L26-L44`). This Mac's file, written by v0.3.3, is version 5.
- **A missing file is defaults. A partial one is defaults plus what's there**: `Load` resets to defaults, then each key overrides only if present and of the right type (`settings.cpp#L1205`, `#L662-L673`).
- **But a missing `ConfigVersion` reads as 0**, and some sections are read by version: from 3 for controller binds, 4 for gamepad settings, 5 for others (`#L1207-L1211`, `#L1515`, `#L1597`, `#L1640`). So a file Ludeum seeds should say `ConfigVersion = 6`.
- **An older version is converted on a best-effort basis; a newer one is refused**: `Load` returns an error, Ymir runs on defaults with its path unset, and on exit `Save` writes `Ymir.toml` in the current directory rather than over the file (`#L1213-L1215`, `#L1724-L1727`). A file that doesn't parse goes the same way (`#L1199-L1202`).
- **Written whole, not atomically.** `Save` builds a new table from what's in memory and opens the file with `ios::trunc` (`#L2118`), so a key Ymir doesn't know is dropped, and a crash mid-write leaves a truncated file. It saves 250 ms after any change (`#L2128-L2142`), **at every disc load when auto-detect region is on** (`T/apps/ymir-sdl3/src/app/services/disc_service.cpp#L143-L146`), and on exit (`app.cpp#L442-L446`). So anything Ludeum writes while Ymir runs is lost.
- **Read once**, at startup.

### Keys a Standing settings write would touch

- `[General.PathOverrides]` `IPLROMImages`, `CDBlockROMImages`, `ROMCartImages`, `BackupMemory`, `ExportedBackups`, `PersistentState`, `SaveStates`, `Dumps`, `Screenshots` (`#L1253-L1266`, `#L1895-L1904`). Empty means the profile's own folder. **Each is used exactly as written**, not resolved against the profile (`profile.cpp#L94-L104`), so they need to be absolute. Each is created at startup if missing (`profile.cpp#L78-L92`).
- `[General] CheckForUpdates` (default `false`), `IncludeNightlyBuilds`, `RememberLastLoadedDisc` (default `false`), `StartPaused`, `PreloadDiscImagesToRAM`.
- `[System] InternalBackupRAMPerGame` (default `false`) and `InternalBackupRAMImagePath`, resolved against `PersistentState` unless absolute (`#L1294-L1295`).
- `[System.IPL] Override`, `Path`, `Variant`; `[Cartridge] Type`, `AutoLoadGameCarts`, `[Cartridge.BackupRAM] ImagePath`, `Capacity`.
- `[Input.Port1] PeripheralType` (§10).

### Update checks

- **It only tells you.** The checker fetches release information and shows a window with a link (`T/apps/ymir-sdl3/src/app/services/update_checker_service.cpp#L40-L110`, `T/apps/ymir-sdl3/src/app/ui/windows/update_window.cpp`). Nothing in it replaces the bundle.
- **A new profile opens an onboarding window** asking about update checks, until `state/updates/.onboarded`, an empty file, exists (`app.cpp#L548-L552`, `T/apps/ymir-sdl3/src/app/ui/windows/update_onboarding_window.cpp#L55-L62`). So Ludeum could make that file with the rest, or it'd appear at the first Play.

### A quirk in saved paths

An empty path is saved through `std::filesystem::proximate`, as the way from that key's folder to the current directory (`settings.cpp#L2872-L2874`). So this Mac's file has `[CDBlock] ROMPath = '../../../../../../../..'` and `[Cartridge.BackupRAM] ImagePath = '../../../../../../..'`, which read back as real paths, not empty ones.

That's harmless for `ROMPath` and `IPL.Path`, which are used only with their `Override` on. It isn't for a backup RAM cartridge: `InsertCartridgeFromSettings` takes its default name only when `ImagePath` is empty (`T/apps/ymir-sdl3/src/app/events/emu_event_factory.cpp#L457-L463`), so once saved, a `Type = 'BackupRAM'` looks at that directory instead. Setting `Type` to `BackupRAM` would want `ImagePath` set absolutely with it. Reproducing this is **unverified**.

## 3. Save states

- **Where**: `<SaveStates>/<disc hash>/`, the hash as 32 hex digits (`T/apps/ymir-sdl3/src/app/services/save_state_service.cpp#L140-L141`).
- **Named by slot**: `<n>.savestate` for slots 0–9 (shown as 1–10), and `<n>-1.savestate` for the state it replaced, kept for Undo (`#L178-L180`, `#L251-L252`; `kSlots = 10`, `save_state_service.hpp#L20`). When saved over, the previous becomes `-1`, so exactly one previous is kept. That's DuckStation's `.bak` and PCSX2's `.backup`.
- **`meta.txt` beside them**, a text file naming the disc: `IPL ROM hash`, `Title`, `Product Number`, `Version`, `Release date`, `Disc` (usually `CD-1/1`, `T/libs/ymir-core/include/ymir/media/saturn_header.hpp#L64`) and `Compatible area codes` (`#L259-L314`). It's written every time a disc loads unless it's under a day old, **so every disc Ymir has opened has a folder, with or without states**. With no disc the hash is all zeros and every field is empty, as this Mac's is.
- **When each was saved** is the file's modified time; Ymir reads it the same way (`#L156-L160`).
- **Format**: a cereal `PortableBinaryOutputArchive` of the whole machine, version tagged, with four-byte markers between sections (`T/apps/ymir-sdl3/src/serdes/cereal_savestate.hpp#L1785-L1860`). Not compressed on disk. Size on disk is **unverified** with none to look at.
- **No screenshot.** The `SaveState` struct has none (`T/libs/ymir-core/include/ymir/savestate/savestate.hpp#L18-L60`), and the menu shows slot and time. Game detail could list them as it does ares's, by slot and time without a picture.
- **Written in place, not atomically**: `std::ofstream` straight onto the final name (`#L243-L245`). A crash mid-write loses that slot's state; `-1` was written just after it, from the slot's previous.

### Versions

The version constant goes up about once a release, and **every older version still loads**. A state is refused only when it's newer than the build (`cereal_savestate.hpp#L1792-L1795`), and the reader carries branches back to version 1.

| Tag | Date | State version | `ConfigVersion` |
|---|---|---|---|
| v0.3.0 | 2026-04-24 | 12 | |
| v0.3.2, **v0.3.3** | 2026-06-21 to 2026-06-22 | 13 | 5 |
| 0.4.0-dev | | 14, 15, 16 | |
| v0.4.0, **v0.4.1** | 2026-10-17 to 2026-10-18 | 17 | 6 |
| `main` | 2026-11-01 | 17 | 6 |

So a bump keeps every state going forward, unlike ares (ADR 0028) and PCSX2, and going back to an older build loses them to that build. That older states do then run correctly is **unverified**: the reader accepts them, and it's a best-effort conversion.

### What refuses a state when loading

`T/apps/ymir-sdl3/src/app/events/emu_event_factory.cpp#L676-L815`:

- **The disc's hash must match**, or nothing happens but a log line (`#L697-L700`, and `T/libs/ymir-core/src/ymir/sys/saturn.cpp#L434`).
- **The BIOS must match too.** A state records its BIOS's hash; on a mismatch Ymir looks through the BIOS folder for that one, loads it if found, and refuses if not (`#L709-L724`). So removing a BIOS from the folder, or a `System.IPL` change that leaves it out, strands every state made with it.
- The same goes for a CD block ROM, only if low-level CD emulation was on, and loading such a state turns that setting on and saves it (`#L799-L805`).

### Starting from one

- **Nothing does.** At startup and at each disc load, `LoadSaveStates` reads all ten slots' files, and their previous ones, into memory (`save_state_service.cpp#L137-L186`, `app.cpp#L521`, `#L3536`). A state is then applied only by the Load State hotkey or menu (`Ctrl+1`–`Ctrl+0`, or `F3` for the selected slot, which starts at slot 1 each launch and isn't saved: `save_state_service.hpp#L146`).
- **So "Play from a state" needs one of:**
  - Leave it out of Ludeum. Game detail lists and deletes states, and Play opens the disc for the player to press a key.
  - **Copy the chosen state to `0.savestate`** before launching, so `F3` applies it. That overwrites slot 1, which would have to be kept somewhere, and the player still has to press `F3`.
  - Send the key from Ludeum, which needs Accessibility permission and timing against the boot.
  - Have a `--load-state` option added upstream. `main`'s source has none, and upstream's issues weren't searched. **Upstream's `CONTRIBUTING.md` refuses any work that had AI assistance at any point** (commit `73d320b7`, 2026-10-25), so a patch from a session like this one can't be sent, and a request would be Daniel's own to make and write.
  - Carry a patched build. The GPL allows it, but Ludeum would then build and sign Ymir itself, rather than install a release.
- **Which of these is acceptable is the biggest open question here.** ADR 0028, 0032 and 0027 all had a way, and #55 asks for one.

### Resume

**No state is made automatically.** No autosave or on-exit save exists in `save_state_service.cpp` or `app.cpp`, and the rewind buffer (`General.EnableRewindBuffer`, off by default) lives in memory only. ADR 0034's line that Ymir "keeps none Ludeum reads" stands.

## 4. Game saves: backup RAM

### The format

`T/libs/ymir-core/src/ymir/sys/backup_ram.cpp`:

- **A Saturn's internal backup RAM is 32 KiB in 64-byte blocks. A cartridge is 512 KiB, 1, 2 or 4 MiB**, in 512-byte blocks, or 1,024 for 4 MiB (`#L14-L28`). The file is exactly that size, or twice it when "interleaved" (`FF xx FF xx…`, as a real one is wired), which Ymir detects (`#L54-L71`, `#L580-L589`).
- **Block 0 is `BackUpRam Format` repeated, block 1 is zeros**, and blocks from 2 hold saves (`#L12`, `#L591-L606`).
- **A save starts at any block whose first byte has its top bit set and next three are zero** (`#L544-L555`): name at `+0x04` (11 bytes), language at `+0x0F`, comment at `+0x10` (10 bytes), date at `+0x1A` (big-endian minutes since 1980-01-01), size at `+0x1E` (`#L624-L634`, `T/libs/ymir-core/include/ymir/sys/backup_ram_defs.hpp#L30-L35`).
- So **Ludeum can list what's in an image in a few dozen lines, with no extra dependency**. This note's checker did it in Python, and its dates agree with the `.smpc` beside the file (§13).

### Shared or per Game

- **Shared by default**: `<PersistentState>/bup-int.bin`, or `InternalBackupRAMImagePath` (`T/apps/ymir-sdl3/src/app/shared_context.cpp#L72-L76`). It's the same as the console: every Game's saves in one image.
- **Per Game with `InternalBackupRAMPerGame`**: `<BackupMemory>/games/bup-int-<Title> [<Product>].bin` (`#L59-L71`, `#L28-L57`), reloaded when a disc loads or ejects (`disc_service.cpp#L150-L152`, `app.cpp#L3570`). Title and Product come from the disc's header, each with `:|<>/\*?` and any non-ASCII character replaced by `_`. With no Product Number it's the file's name, so that case wouldn't follow a Rename.
- **A shared image can't be split by Game.** A save's name is the game's own (`HOUSEOFDEAD`), with nothing to tie it to a serial or a title, so Ludeum could only show a shared image as a whole. That's unlike PCSX2's folder cards.
- **A per-Game image can.** It holds that Game's saves, as the glossary wants.
- **What per-Game gives up**: a game that reads another game's save can't see it (Shining Force III's scenarios, by reputation: **unverified**), and a multi-disc game whose discs have different Product Numbers would have one image per disc. Multi-disc headers are **unverified**, with none here.
- **Ymir has a Backup Memory window** for moving saves between images, and for export and import as `.bup` or `.ymbup` (`T/apps/ymir-sdl3/src/app/ui/views/backup_memory_view.cpp#L202-L203`), which could split a shared image by hand.

### Cartridges

- **None by default**: `[Cartridge] Type = 'None'`, so a Game with no database entry saves only to internal RAM (`settings.cpp#L1157`).
- **`[Cartridge] AutoLoadGameCarts`** (default on) inserts what the Game's database entry asks for at disc load (`disc_service.cpp#L173-L179`, `T/apps/ymir-sdl3/src/app/services/rom_service.cpp#L292-L358`). Where that's backup RAM, as for Dezaemon 2 and Sega Ages Galaxy Force II (`T/libs/ymir-core/src/ymir/db/game_db.cpp#L61-L62`), it's a per-Game `<BackupMemory>/games/bup-ext-32M-<Title> [<Product>].bin`.
- **A shared cartridge** with `Type = 'BackupRAM'` is `<PersistentState>/bup-ext-<n>M.bin` by default (§2's quirk applies).

### SMPC data and the clock

- **The console's settings** (language, and whether it's been set) go in `<PersistentState>/smpc-<region>.bin` since v0.4.0, one for each region of BIOS: `smpc-us_eu.bin`, `smpc-jp.bin`, `smpc-asia.bin`, `smpc-other.bin`, or `smpc-none.bin` with no BIOS info (`shared_context.cpp#L85-L99`, `CHANGELOG.md`). An old `smpc.bin` is copied to the new name (`app.cpp#L1899-L1905`).
- **25 bytes**: version 1, three reserved, four of SMEM, the "set" flag, an 8-byte clock offset and an 8-byte timestamp (`T/apps/ymir-sdl3/src/app/services/persistence_service.cpp#L27-L53`, `#L91-L102`). Saved 250 ms after it changes. Losing it means the BIOS asks for language and date again.
- **`[System.RTC] Mode`** defaults to `Host`, the Mac's clock.

## 5. Through Archive, Compact and Rename

### The hash

`T/libs/ymir-core/src/ymir/media/filesystem.cpp#L59-L101`: XXH3 128 over the **2,048 bytes of user data** of sectors 150–165 (the header, IP.BIN) and of each volume descriptor from sector 166 to its terminator.

- **It doesn't depend on the file's name, path or form.** A sector's user data is the same in `.cue`/`.bin`, `.chd` and `.iso` of one dump. So Save states follow a ROM through Rename, Archive and Unarchive, and a `.chd` conversion. Not run, so **unverified** in practice.
- **Another dump** of the same disc gets the same hash if those sectors match, which they normally will. **Another Version or region** has a different header, so it's a different set of states, which is right.
- **Ludeum computing it** would need XXH3-128 in Swift (not in the standard library) and the sectors read from a cue sheet's `.bin`, or a CHD, or through 7-Zip. **Reading `meta.txt` is the cheap alternative**: match on Product Number against what Ludeum knows of the ROM, or on the folder's title. That needs a Saturn Serial in the journal, which isn't read today (`Serials.platforms` is PlayStation and PlayStation 2, `Sources/LudeumCore/Serials.swift`). The Product Number is at `0x20` of the disc's first sector, ten characters, and the title at `0x60` (`T/libs/ymir-core/src/ymir/media/saturn_header.cpp#L24`, `#L67`).
- **`meta.txt`'s limit**: one Product Number can cover several revisions, as `Version` shows, and it appears only after a disc has been opened.

### Rename (ADR 0012)

Nothing moves. States are by hash, per-Game backup RAM by the header, so Ludeum has nothing to do, unlike MesenCE, ares and Amiberry. The only name-keyed case is a disc with no Product Number (§4). Ymir's `recent_discs.txt` holds absolute paths, and a stale one is just a dead menu entry.

### Formats Ymir opens

`T/libs/ymir-core/src/ymir/media/loader/loader.cpp#L11-L32`: **`.chd`, `.cue`, `.mds`, `.ccd`, `.iso`**. Its Info.plist also claims `.bin`, `.img` and `.mdf`, which get to the right loader only through their sheets.

Ludeum's Saturn ROM folder reads `m3u`, `chd`, `cue`, `iso` and `bin` as ready (`Sources/LudeumCore/Import/ROMPlatform.swift` line 136), with `archiving: .intoFolder` and no `compactExtension`.

| Form | Ludeum: ready? | Ymir |
|---|---|---|
| `.cue` with `.bin` | yes | opens |
| `.chd` | yes | opens |
| `.iso` | yes | opens (the loader requires the extension: `loader_iso.cpp#L28-L32`) |
| `.bin` alone | yes | **no**: `iso::Load` refuses the extension, and it's not a cue sheet |
| `.m3u` | yes | **no**: no loader reads it |
| `.7z`, `.zip` | Archived | **no** |
| `.ccd`, `.mds` | no | opens |

### A multi-disc Play

- **No playlist support**: "m3u" and "playlist" appear nowhere in the app's or the media library's source.
- **What a Play would do today**: Ludeum gives Ymir the `.m3u` (`Tests/LudeumCoreTests/PlayTests.swift` lines 81–99 expect it). At startup, `LoadDiscImage(path, false)` is told not to show errors (`app.cpp#L479`, `disc_service.cpp#L65`), so Ymir opens to its BIOS screen **with no disc and no message**. No Saturn ROM here is multi-disc, so this hasn't been seen.
- **Changing Disc in Ymir** is File ▸ Load disc (`Ctrl+O`), the recent discs list, or a dropped file. Each loads that disc's states and, per-Game, its backup RAM.
- **An option that's already there**: ADR 0026's Disc start, which already opens a chosen Disc's file on other Emulators, passing the Disc's `.cue` rather than the playlist.

### This Mac's ROMs

Five in `ROMs/Saturn/`, all **Archived `.7z`**, none multi-disc, all matched to a Game, none with an MD5 or Serials in the journal: G. Darius (USA), House of the Dead, The (USA), Saturn Bomberman (Europe), Virtua Cop (USA) (DW0030), Virtua Cop 2 (USA) (DW0743). 278–450 MB each. What's inside each wasn't listed, so its form is **unverified**. None can be Played until Unarchived, as is true today.

## 6. What else loses one

- **Backup RAM is memory-mapped, with no explicit flush.** `MemoryMapFile` maps the file writable through `mio` (`backup_ram.cpp#L713-L728`), a game's writes go straight into that memory, and there's no sync call in `backup_ram.cpp`, `backup_ram.hpp` or `app.cpp`. `mio` was not read (a submodule, not fetched), so whether it syncs on unmapping is **unverified**.
  - **Against a crash of Ymir**, dirty pages of a mapped file normally survive in the kernel, and are written out later. That's general macOS behaviour, not checked here.
  - **Against Dropbox**, this is the real question. The Data folder is `~/Dropbox` → `~/Library/CloudStorage/Dropbox`, a File Provider location, and whether a mapped file's writes update its modified time promptly and get synced, particularly while it's still mapped, is **unverified**. PCSX2's cards are written with `fwrite` (see its note); how Ludeum's other Emulators write wasn't checked here. It wants a rehearsal: a real save, then checking the file's bytes, its date and Dropbox's copy, both while Ymir runs and after it quits.
- **A wrong-sized or invalid internal image gets formatted, not refused.** Internal backup RAM loads through `CreateFrom` (`T/libs/ymir-core/src/ymir/sys/memory.cpp#L42-L44`), which **resizes the file and formats it** when its size isn't valid or its header doesn't check out (`backup_ram.cpp#L107-L114`, `#L135-L144`). So anything else at that path, or an image truncated or half-synced, is wiped at the next launch, with no message. A shared or per-Game image alike. `LoadFrom`, used for a cartridge picked in Ymir, refuses instead (`#L68-L71`).
- **A Dropbox online-only file stalls startup**: Ymir reads all 20 possible state files for a disc on the main thread before showing a frame (§3), scans every 512 KiB file in the BIOS folder, and maps the disc image itself (`MemoryMappedBinaryReader`, `loader_iso.cpp#L97`) unless `PreloadDiscImagesToRAM` is on. The folders would want marking available offline, as ADR 0024 does.
- **A different BIOS** strands states (§3).
- **Non-atomic writes**: states, `Ymir.toml` and SMPC data are all truncated and rewritten in place (§2, §3, §4).
- **`meta.txt` is rewritten when over a day old**, which is harmless but means a folder's modified time isn't its last save.
- **A second copy of the profile**: only `-p` keeps Ymir in Ludeum's folder, so an Open without it writes to the user profile, and its states and saves are in another place. It's not lost, but it's not seen.

## 7. Single instance

- **There's no guard.** Nothing in the app takes a lock or looks for another instance (grepped for the usual names at `v0.4.1`). Ludeum launches with `createsNewApplicationInstance = true` (`App/Sources/GameDetailParts.swift` line 498), and the spec says a second window opens.
- **Two would clash**: each has the settings in memory and writes `Ymir.toml` whole at exit, and both would map one backup RAM image.
- **So "refuse Play while any Ymir is open"** is the same cheap rule as DuckStation, MesenCE, ares and PCSX2. It's also needed for Delete, and for anything else that touches a mapped image.
- **While the other copy exists**: `/Applications/ymir.app` has the same bundle ID, so a check by bundle ID sees either copy, and `NSWorkspace.urlForApplication(withBundleIdentifier:)` could return either. Managed Emulators already use an explicit path (`isLudeums`, `App/Sources/EmulatorVersionChecks.swift`).

## 8. Install

### Releases

- **Stable tags are versioned and keep their assets**, with a `digest` per asset; everything back to `v0.1.0` is still listed, 19 releases in all.
- **`v0.4.1`**: published 2026-10-18T20:39:38Z, target tag at `d49c0868`. `ymir-macos-arm64-v0.4.1.zip`, 8,696,991 bytes, **`sha256:070a234b7460608ae22f08ab5914c8edac3a5efaf364590d2dde18ff460627a7`**. The download matched. There's also an x86-64 zip, not needed.
- **`latest-nightly` can't be pinned.** It's one release on one moving tag: each night's workflow force-moves the tag (`.github/workflows/nightly-release.yaml` line 88), **deletes the existing release** (line 102) and creates a new one (line 116). The cron is 03:45 UTC when there's a commit in the last day. Older nightlies aren't kept: the asset this Mac's Ymir recorded on 2026-10-06, `latest-nightly/ymir-macos-arm64-v0.4.0-dev_92000a51.zip`, now answers 404. So a digest would be good only until the next night's build. The API shows it as `0.4.2-dev_0d7f58b9` today. The asset's name has its commit in it, but building that commit is the only way to get it back.

### The zip

- It holds `ymir-sdl3.app` (20 MB) and, beside it, `README.md`, `CHANGELOG.md`, `TROUBLESHOOTING.md`, `gamecontrollerdb.txt` and `licenses/`.
- **The app**: `Contents/MacOS/ymir-sdl3` (Mach-O, thin arm64), `Contents/Resources/ymir.icns`, `Info.plist`. Links only system frameworks and libraries (`otool -L`), so **nothing from Homebrew**, unlike MesenCE's SDL2.
- **`Info.plist`**: `CFBundleIdentifier` `io.github.strikerx3.ymir`, `CFBundleExecutable` `ymir-sdl3`, `CFBundleName` `Ymir`, `CFBundleShortVersionString` and `CFBundleVersion` both `0.4.1`, `LSMinimumSystemVersion` 13.0 (the README and changelog say 12).
- **Ad-hoc signed, not notarised**: `codesign -dv` says `Signature=adhoc`, no team (`.github/workflows/build.yaml` line 560 is `codesign --force --deep --sign -`), `codesign --verify --deep --strict` passes, `spctl` says `rejected`, and there's no stapled ticket. The README tells macOS users to allow it by hand. So Install needs what DuckStation's does: `ditto` to unpack, and `xattr -dr com.apple.quarantine` (`Sources/LudeumCore/DuckStationInstall.swift` lines 186, 203). A copy changed inside would no longer verify, so nothing should be written into `Contents`.
- **`gamecontrollerdb.txt` isn't found where the zip puts it.** Ymir looks in `Contents/MacOS` (its "portable" folder) and at the profile's root (`T/apps/ymir-sdl3/src/app/services/rom_service.cpp#L36-L37`), so beside the app it isn't read unless that folder is the profile. With `-p Emulators/Ymir` and the app in `Emulators/Ymir/`, it is. It's 2,291 lines of SDL's community mappings; what SDL knows without it is **unverified**.

### The version check

- **`Info.plist`'s version is real**, set from the build's version (`T/apps/ymir-sdl3/CMakeLists.txt#L517`, `#L521`), so today's `EmulatorVersionSpec(expected: "0.3.3", source: .appVersion)` stays the right shape, with no launch. It would become exact, as for ares and PCSX2, with any other being "Wrong build: install again".
- **There's no marker of Ludeum's copy** in a `-p` model, so it can't be told from another by anything but its path, which `isLudeums` already uses, and its version.

### This Mac

`/Applications/ymir.app` is the v0.3.3 release renamed: its executable has the same SHA-256 as the release's (`30e8cc3d…e927`), same bundle ID, ad-hoc, still `com.apple.quarantine` from Chrome. macOS 26.5, arm64. No `Emulators/Ymir` exists in the Ludeum folder, and no `Emulators/Ymir` in the Data folder.

## 9. BIOS and cartridges

- **Required.** Without one the Saturn runs a do-nothing program (`T/libs/ymir-core/src/ymir/sys/null_program.hpp`), and Ymir opens its Welcome window (`app.cpp#L504-L506`). No fallback is included, unlike Amiberry's AROS. So Play could be refused until one's there, as PCSX2's is (ADR 0032).
- **Where**: the `IPLROMImages` folder, scanned recursively at startup for files of exactly 512 KiB, identified by hash against a database of known images (`T/apps/ymir-sdl3/src/app/rom_manager.cpp#L14-L46`, `T/libs/ymir-core/src/ymir/db/ipl_db.cpp#L9-L28`).
- **Chosen automatically** by the disc's region, among images the database knows: exact region, then a region-free patched one, then another (`rom_service.cpp#L127-L180`). **An image it doesn't know is skipped** unless `[System.IPL] Override` and `Path` name it (`#L116-L125`, `#L165-L167`).
- **On this Mac**: Ymir's `roms/ipl/` is empty. **`mpr-17933.bin` and `sega_101.bin`** (524,288 bytes each, by name the US/EU and Japanese BIOSes, as Mednafen's convention has them) are in `~/Library/Application Support/OpenEmu/BIOS/` and in `~/Dropbox/games/OpenEmu/Application Support/BIOS/`. MD5s `3240872c70984b6cbfda1586cab68dbe` and `85ec9ca47d8f6807718151cbcca8b964`. That Ymir's database knows these two exact images is **unverified**, as it holds XXH128 hashes with a seed, not computed here. Its list does have a Saturn 1.00a and 1.01a for US/EU and a 1.01 for Japan.
- **Which BIOS**: with both, if it knows them, a USA disc gets the first and a Japan one the second, automatically. Each has its own SMPC file (§4), and states are tied to the one they were made with (§3).
- **CD block ROM**: only for `[CDBlock] UseLLE`, off by default. Not needed.
- **Cartridges**: `AutoLoadGameCarts` (default on) inserts DRAM carts for the 31 listed games, and backup RAM for those above, with no file needed. **Only KoF '95 and Ultraman need a file**, a ROM cart image in `ROMCartImages`, and without it a dialog says so (`game_db.cpp#L20-L22`, `rom_service.cpp#L313-L340`). No line in the database names any of this Mac's five Saturn games (a grep on their titles; the database is keyed by Product Number, with titles in comments).

## 10. Per-Game settings and controls

- **Ymir has none of its own**, no per-game file or layer. A per-disc behaviour comes only from its game database's compiled-in fixes, and backup RAM and cartridges (§4, §9). So ADR 0029's shape has nothing to apply to, and Ludeum's "melonDS and Ymir have no per-Game settings" holds, for now.
- **Controls are global, in `Ymir.toml`**: `[Input.Port1]`, `[Input.Port2]`, with `PeripheralType` per port and binds for each peripheral. So they travel with the profile and aren't in the Data folder unless the profile is. `[Hotkeys]` likewise.
- **A light gun is the one thing a Game would want different.** House of the Dead, Virtua Cop and Virtua Cop 2 are all light-gun games, and `PeripheralType` is `ControlPad` by default, with no switch per Game. A Disc's header lists `G` for Virtua Gun (`saturn_header.cpp#L53`), but nothing acts on it: `compatPeripherals` is used nowhere else in the app or the core's sources. Whether that needs anything from Ludeum, or a by-hand change in Ymir each time, is a question for the design session. Ymir's Virtua Gun graduated to a stable feature in v0.4.0 (§11).
- **This Mac's `Ymir.toml`** was written during a single minute's launch on 2026-10-06, so its binds are Ymir's defaults, by the look of it (not diffed), and nothing needs carrying across. A new profile gets the same defaults, apart from any differences between v0.3.3's and v0.4.1's.

## 11. The pin

**Decided by Daniel on 2026-11-04: the most recent release, stable `v0.4.1`** (§8).

What changed from v0.3.3 that bears on this, from `CHANGELOG.md` at the tag:

- **State version 13 → 17, `ConfigVersion` 5 → 6.** Forward-compatible (§2, §3), and there are no v0.3.3 states on this Mac anyway.
- **SMPC data per BIOS region** (§4).
- **Virtua Gun graduated to stable, and many fixes to it** ("many cases of games not recognizing Virtua Gun inputs or missing shots", shot offset and reload detection, #787). Three of the five Saturn ROMs here are gun games.
- **A native Metal backend**, hardware-accelerated rendering not yet covering it on macOS by the notes, which name Direct3D 12 only.
- **Unpause on disc load** is a new option, on by default. Its settings key is misspelt when read (`UnpauseOnDiscLoadd`, `settings.cpp#L1240`, written as `UnpauseOnDiscLoad` at `#L1889`), so the setting doesn't persist, and it stays on.
- **Backup RAM fixes**: a crash loading a cartridge at the default path, and importing saves from other emulators' cartridges no longer refused on language.
- **Many CD, CUE and CHD fixes**, and a filesystem read rewritten from a disc to a CD reader interface. The hash's sectors are the same, with the volume descriptor now always at address 166 rather than `session start + 166` (a diff of `filesystem.cpp`), so single-session discs should hash alike. Moot here without a v0.3.3 state.

**`main` since `v0.4.1`**, 97 commits to 2026-11-01: a Vulkan backend and build work. State version 17 and `ConfigVersion` 6 are unchanged. `main.cpp`, `profile.cpp`, `save_state_service.cpp`, `disc_service.cpp`, the loaders, `backup_ram.cpp` and `filesystem.cpp` are unchanged, and `settings.cpp` differs by two lines removed. `CHANGELOG.md` calls it 0.4.2, in development. So the facts above should hold for the next release.

## 12. This Mac's data

`~/Library/Application Support/StrikerX3/Ymir/`, 72 KB, all dated 2026-10-06 12:10–12:11:

- `Ymir.toml` (13,938 bytes, `ConfigVersion = 5`, `CheckForUpdates = true`, `PathOverrides` all empty).
- `state/bup-int.bin`: 32 KiB, formatted and empty. `state/smpc.bin`: 25 bytes, nothing set. `state/imgui.ini`, `state/window.txt`, `state/updates/` (`.onboarded` and cached checks).
- `savestates/00000000000000000000000000000000/meta.txt`: the no-disc folder, with no states.
- `backup/exported/`, `roms/ipl/`, `roms/cdb/`, `roms/cart/`, `dumps/`, `screenshots/`: empty.

**Nothing's worth moving over.** No `io.github.strikerx3.ymir` preferences domain, no saved application state.

## 13. OpenEmu's saves

From the Data folder's `OpenEmu Battery Saves archive/Mednafen/Battery Saves/`. All in the issue's checklist, except as said below. Nothing has been moved, and no line can be ticked until tested in Ymir.

### What's there

| File | Size | What it is |
|---|---|---|
| `House of the Dead… - 1.bkr` | 32,768 | Plain internal backup RAM: one save, `HOUSEOFDEAD`, "HOTD Data", English, 1,168 bytes, written 2023-08-18 13:09. File dated 2024-07-02. Byte-identical to the `.bkr` in `~/Dropbox/games/OpenEmu/Application Support/Mednafen/Battery Saves/` |
| `House of the Dead… - 2.bkr` | 32,768 | The same save, **written 2023-08-22 09:58**, 27 bytes different. File dated 2023-08-22 |
| `House of the Dead….bcr` | 570 on disk, **gzip**, 524,288 inside | A 4 Mbit cartridge, formatted, **with no saves** |
| `House of the Dead… - 1.smpc` | 12 | No save: bytes `01 20 23 58 18 13 09 22 00 00 00 00` |
| `House of the Dead… - 2.smpc` | 12 | No save: bytes `01 20 23 58 25 14 13 14 00 00 00 00` |

Why two of each with ` - 1` and ` - 2` isn't known; it's not Mednafen's own naming, by the unsuffixed copies in the older OpenEmu folder.

### Could Ymir read them

- **`.bkr`: yes, as they are, by the source.** The right size, not interleaved, block 0 the header, block 1 zeros, saves from block 2 in the format of §4. Copying one to where Ymir looks (`bup-int.bin`, or the per-Game name) should be all it takes. **Not run.** Which of the two to bring is Daniel's: `- 2`'s save is the later by its own date, `- 1`'s file the later on disk.
- **`.bcr`: nothing to bring.** Blank. It would need `gunzip` first, since Ymir has no gzip support here, and then a cartridge setting.
- **`.smpc`: no, and nothing of value.** By its bytes it's a valid flag then a date in BCD: 2023, Friday August, the 18th, 13:09:22, agreeing with the save's own date, and then four zero bytes (decoded from the bytes and their agreement, not from Mednafen's source: **unverified**). Ymir would read the version as 1, then run off the end of the 12 bytes and ignore the file (`persistence_service.cpp#L27-L48`). So no conversion is worth writing. Ymir's clock is the Mac's.

### What's missing

**The six Virtua Cop and Virtua Cop 2 lines in the issue's checklist have no files.** `Virtua Cop (USA) (DW0030)…{.bcr,.bkr,.smpc}` and `Virtua Cop 2 (USA) (DW0743)…{.bcr,.bkr,.smpc}` aren't in that folder (modified 2026-10-29 10:24) nor anywhere under the Data folder, `~/Dropbox/games/OpenEmu`, or `~/Library/Application Support/OpenEmu`, nor by `mdfind`. The Trash couldn't be read from this shell, so it wasn't searched. Daniel removed them on purpose (said 2026-11-04), so they aren't wanted and aren't to be looked for.

### OpenEmu's Save states

- **Five for Saturn, not three**, all House of the Dead, in `OpenEmu Save States archive - current/Saturn/`: `main menu`, `lvl2`, `2 - rogan2`, `lvl3` and `Auto Save State`, 2023-08-18 to 2024-07-02. Each is a `.oesavestate` folder of `State` (gzip, 1.6–2.1 MB), `ScreenShot` and `Info.plist`, which says `org.openemu.Mednafen` 1.26.1.
- **They can't load in Ymir.** It reads only its own cereal format, and has no importer (§3).
- A second set, under `~/Dropbox/games/OpenEmu/Application Support/Save States/Saturn/`, has the same five names and empty Virtua Cop and Virtua Cop 2 folders.

## 14. Mapping ADRs 0024, 0027, 0028, 0032 and 0035 onto Ymir

| ADR | Ymir | Notes |
|---|---|---|
| Pinned versioned tag and SHA-256 in code | **Same. `v0.4.1`, decided by Daniel 2026-11-04** | `sha256:070a234b…a627a7`. Stable tags keep their assets; nightlies can't be pinned (§8). |
| Unpack without quarantine (0024, 0027) | **Needed** | Ad-hoc signed, not notarised (§8). PCSX2 and ares didn't need it. |
| Confirm the build | **By `Info.plist`, no launch** | As ares, whose `--version` also can't be run. No version flag (§1, §8). |
| Portable marker in the bundle (0024, 0027), or file beside it (0028, 0032) | **Neither needed: `-p <folder>`** | A flag per launch, so every launch needs it. A marker would be a `Ymir.toml` in `Contents/MacOS`, inside an ad-hoc seal (§1). 0035's Amiberry is the nearest: home folder and everything else from the launch. |
| Standing settings before every Play and after Install | **Same** | Into `Ymir.toml`: `ConfigVersion = 6`, absolute `General.PathOverrides`, `CheckForUpdates = false`, and `.onboarded`. Ymir rewrites the file whole, dropping unknown keys (§2). |
| Only while the Emulator isn't running | **Same** | §2, §7. |
| Self-update off | **Only a notice exists** | Nothing replaces the bundle (§2). |
| Save states and Game saves in `Data/Emulators/<Emulator>/` | **Same, by overrides or by the profile** | Two shapes: a profile beside the app with overrides into the Data folder, or `-p` pointing at the Data folder. The second is one flag and no overrides, but puts GUI state and the settings file in Dropbox (§1). |
| Refuse Play while any copy runs | **Same** | §7. |
| Game detail lists Save states, deletes one | **Yes, without pictures** | By `savestates/<hash>/`, matched through `meta.txt`; time from the file. Delete `<n>.savestate` and `<n>-1.savestate` (§3). |
| Play from a Save state | **No way to do it** | No flag or file (§3). All of 0024, 0027, 0028, 0032 had one. |
| Resume (0034) | **None** | §3. |
| Game detail shows Game saves | **A choice** | Per-Game backup RAM gives a file per Game, listed from its blocks. Shared RAM is one image, with no tie to a Game (§4). |
| Rename moves saves (0027, 0028, 0035) | **Not needed** | By the disc's hash and header (§5). |
| Saves keyed by Serial (0024, 0032) | **By hash, and Title and Product Number** | Ludeum reads no Saturn Serial today; it's in the disc's first sector (§5). |
| Per-game settings (0029) | **None to have** | §10. |
| BIOS (0032) | **Same need** | Refuse Play without one; identified by hash (§9). |
| Writes atomic | **No** | Everything's in place, and backup RAM is memory-mapped (§6). |
| Folders available offline in Dropbox | **Same need** | §6. |
| Licence | **GPL-3.0** | A configured copy is fine. |
| Move over by hand once | **Nothing of Ymir's; House of the Dead's `.bkr` by hand** | §12, §13. |
| Architecture | **arm64, native** | No Rosetta (§8). |

## Open questions for the design session

1. **Play from a Save state.** With no way to start one, is it enough to list and delete states and leave loading to Ymir's own keys? Or copy into slot 1 and press `F3`, send the key, ask upstream for a flag yourself (it takes no AI-assisted work), or carry a patched build? (§3)
2. **Backup RAM: per Game or shared?** Per Game gives a Game its own Game save to show; shared is as the console was, and lets one game read another's saves, and can't be shown by Game (§4).
3. **Does a mapped backup RAM file on Dropbox's File Provider path work?** Rehearse before deciding, as it's the one thing that could lose a save: a real save, with the file's bytes, date and Dropbox's copy checked during and after a Play. If it doesn't work, the options are a local image copied on quit, which needs a watcher that ADR 0024 did without, or keeping backup RAM out of Dropbox (§6).
4. **Where does the profile go?** Beside the app with overrides into the Data folder, as every other Emulator does, or `-p` at the Data folder? And which folders are worth keeping: Save States, Backup Memory, BIOS, Screenshots, Cartridge ROMs? `PersistentState` holds the SMPC data and shared backup RAM with GUI state (§1, §2).
5. **How does Ludeum match a state folder and an image to a Game?** Read `meta.txt` and file names against a Saturn Serial, which means reading the Product Number from the disc, as a new Platform for `Serials`; or by hash, which needs XXH3-128; or by title (§5).
6. **Multi-disc.** Stop giving Ymir an `.m3u`: open a Disc's `.cue` through ADR 0026's Disc start, or refuse? And should the Saturn folder stop reading `.m3u` and a bare `.bin` as ready, as PS2's stopped reading `.cue` (ADR 0032)? (§5)
7. **The light gun.** Three of five Saturn ROMs want a Virtua Gun on port 1. Set by hand in Ymir, as a Standing setting, or written per Play as a Game's own setting? (§10)
8. **BIOS.** Copy `mpr-17933.bin` and `sega_101.bin` into the Data folder's `Emulators/Ymir/`, and refuse Play with none there? And confirm Ymir's database knows them at the first run (§9).
9. **House of the Dead's save.** Where to bring it across, given question 2. Daniel chose `- 2.bkr` on 2026-11-04, and the six missing Virtua Cop lines were removed on purpose (§13).
10. **Back up, restore and delete a Game save (#77).** DuckStation, MesenCE, ares and PCSX2 went without. A per-Game image is one small file to delete, but deleting one save inside would mean editing the block format; Ymir's Backup Memory window already does that.
11. **Open from the Emulators sheet.** It must pass `-p` too, or Ymir opens its user profile (§1).
12. **Remove `/Applications/ymir.app` and the old profile?** Same bundle ID, nothing in it worth keeping (§7, §12).

## Side findings (outside #86)

- **The issue's "OpenEmu's Save states: Saturn 3"** is five, all House of the Dead (§13).
- **`Tests/LudeumCoreTests/PlayTests.swift`'s `aMultiDiscVersionOpensItsPlaylist` uses Saturn in Ymir**, which can't open a playlist (§5). Its comment also says Ymir "takes no settings at all", which stops being true here.
- **Ludeum's spec says Ymir's `--version` opens its window**; by the source, an unknown option shows a fatal error dialog (§1). Not run.
- **The README links `StrikerX3/Ymir`**, now `ymir-emu/Ymir`.
- **Upstream**: `UnpauseOnDiscLoadd` is a typo'd settings key (§11), and the Info.plist's minimum of macOS 13 disagrees with the README's and changelog's 12, and an empty path in settings is saved as a path to the current directory (§2).
- **Upstream forbids AI-assisted contributions** (`CONTRIBUTING.md`, `73d320b7`, 2026-10-25): no work with AI assistance "at any point of the development process", naming Claude Code, and "feeding Ymir's source code to an LLM for any reason" among what it covers; such pull requests are closed, and dishonesty about it is a ban. It governs what upstream accepts, not Ludeum's use of a GPL release. But this note was written by an LLM reading Ymir's source, so **nothing from it or from this repo's sessions should go upstream as a patch or as a report drawn from it**. A request would be Daniel's own, in Daniel's own words, from what Daniel sees first-hand.
