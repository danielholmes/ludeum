# PCSX2 under Ludeum's management

Researched 2026-11-03 for issue #88. The question: can Ludeum manage PCSX2 as ADR 0024 manages DuckStation, 0027 MesenCE and 0028 ares (install a pinned build, keep it apart from any other copy, write Standing settings that put its Save states and Game saves in the Data folder, refuse Play while it runs, list and Play from Save states in Game detail, show a Game's Game saves)? Where does PCSX2 keep its Save states and memory cards, what does it name them by, what loses one, and what does today's `-gamecfg` Play do to PCSX2's own per-game settings? This note builds on [ps2-emulator.md](ps2-emulator.md) (2026-10-06, which chose PCSX2 and left three questions open) and answers those. It lays out the facts and the options. It doesn't make the decision.

Sources:

- **PCSX2 source** at tag `v2.9.103`, commit `6f18caf203e2f262c4f70e556c6112eca26fb3be` (2026-10-06). That's the version Ludeum expects (`EmulatorVersionSpec(expected: "2.9.103")`, `Sources/LudeumCore/EmulatorVersions.swift` line 68). Links like `T/pcsx2/VMManager.cpp#L1888-L1903` mean `https://github.com/PCSX2/pcsx2/blob/6f18caf203e2f262c4f70e556c6112eca26fb3be/pcsx2/VMManager.cpp#L1888-L1903`.
- **PCSX2 `master`** at `6a33137aa9ab594e2517eb0bff46b1794b775234` (2026-11-02). Every section cited below is identical there (diffed: `EmuFolders`, the command-line help, state naming, disc formats, the game settings path, the memory card keys and folder-card filtering), so no `M/` links are needed.
- **Nine other tags**, fetched shallowly, for the save-state version only (§4).
- **ARMSX2 `master`** at `f6df1e69255544241132d66441f2f1338fd90bfd` (2026-11-02), four files read through the API (§14). Links like `A/…` mean `https://github.com/ARMSX2/ARMSX2/blob/f6df1e69255544241132d66441f2f1338fd90bfd/…`.
- **The GitHub REST API** for releases, tags, digests and repo metadata.
- **The release asset** `pcsx2-v2.9.103-macos-Qt.tar.xz`, downloaded into the session scratchpad, checked against the API's digest and unpacked read-only. It was never run.
- **This Mac**, read without changing or launching anything: `/Applications/PCSX2.app`, the Ludeum folder (`~/Library/Application Support/Ludeum/`) and the Data folder (`~/Dropbox/games/Ludeum/`).
- **Ludeum's code** on `main` at commit `504ab16`.

Anything not checked against one of these sources is marked **unverified**.

## Answer

**Yes, and it's closer to DuckStation than ares or MesenCE were: every folder is an absolute path in one INI, states and cards are keyed by what's on the disc, not the file's name, and a Play can start from a state.** Six facts shape the design:

1. **Portable mode is a `portable.txt` beside the app, not inside it.** PCSX2's "program directory" on macOS is the folder that holds the bundle, so `Emulators/PCSX2/PCSX2.app` with `Emulators/PCSX2/portable.txt` makes `Emulators/PCSX2/` the data root, with `inis/PCSX2.ini`, `memcards/`, `sstates/` and the rest beneath it, and nothing in the notarised bundle changes. Without it the root is `~/Library/Application Support/PCSX2`; `-datapath <p>` puts it at `<p>/PCSX2` (§1).
2. **Every folder is a `[Folders]` key taking an absolute path**, read from the base `PCSX2.ini` only (a per-game file can't move them). The file is rewritten whole, atomically, one second after any change, from what PCSX2 holds in memory, so it can only be written while PCSX2 isn't running. There's no single-instance guard (§2, §8).
3. **Save states are `<serial> (<CRC>).<slot>.p2s`**, a zip with a PNG screenshot inside, keyed by the disc's serial (`SYSTEM.CNF`'s `BOOT2` line) and the XOR of the boot ELF's 32-bit words. So they follow a ROM through Rename, Archive and a `.chd` conversion, and Ludeum could compute both keys by reading the disc, as it reads PlayStation Serials today. The version constant has been stable since v2.7.200 (2026-03-20), through v2.9.152 and `master`; it changed three times in the nine months before that (§3, §4, §6).
4. **PCSX2 has two kinds of memory card.** A file card (`Mcd001.ps2`, 8 MB, shared by every Game) is no one Game's Game save, as the glossary says. A **folder card** is a directory whose top-level subdirectories are the saves, named as each game names them (`BASLUS-20828…`), and PCSX2 always shows a running game only the saves whose name contains its serial (or its GameDB `memcardFilters`), so one folder card gives every Game its own card, and listing a Game's Card saves is a directory listing. And `[MemoryCards] Slot1_Filename` is a per-game key, so a per-game file (or today's `-gamecfg` ini) can give a Game a card of its own, as DuckStation's ADR 0023 did (§5).
5. **`-gamecfg` replaces PCSX2's per-game file outright, and Game Properties then writes into Ludeum's file.** `GetGameSettingsPath` returns the override for everything, so PCSX2's own `gamesettings/<serial>_<CRC>.ini` is never read and a change made in Game Properties during a Play is saved into `PCSX2 game settings.ini` (and deletes it when it ends up empty), to be overwritten by the next Play. GameDB fixes are a separate layer and apply either way (§9).
6. **The release is an x86_64 build, and this Mac runs it under Rosetta 2**, which is installed (`arch -x86_64 /usr/bin/true` ran). No release through v2.9.152 has an arm64 macOS asset, and `master`'s workflow still builds x86-64 by default. It's Developer ID–signed, notarised and stapled (§10).

The rest:

- **Install.** Every nightly is its own versioned tag (`v2.9.103`, one to five a day) with a `digest` per asset, marked `prerelease`; the last stable is `v2.8.2` (2026-09-04). Some 5,700 releases are kept, back to 2021, so nothing ages off. Licence GPL-3.0. The bundle in the tar is `PCSX2-v2.9.103.app`; `/Applications/PCSX2.app` is it, renamed, byte-identical, still quarantined (§10).
- **Self-update** is skipped on every launch that boots a file, so no Play ever checks; the key to turn it off is `[AutoUpdater] CheckAtStartup`. On macOS it replaces the bundle beside itself under a new name and trashes the old one (§2).
- **This Mac has no PCSX2 data at all**: no `~/Library/Application Support/PCSX2`, no `PCSX2.ini`, card or state anywhere searched, though Ludeum's `PCSX2 game settings.ini` was written on 2026-10-06. So the issue's "shared memory cards in nobody's backup" don't exist here yet, and there's nothing to move over (§12).
- **Formats.** PCSX2 opens `.iso`, `.bin`, `.img`, `.mdf`, `.gz`, `.cso`, `.zso` and `.chd`: no `.cue`, no `.7z`, no `.zip`. Ludeum's PS2 ROM folder reads `.cue` as ready. All 57 PS2 ROMs but one are Archived `.7z` (§6).

## 0. Which repository

- **`PCSX2/pcsx2`**, GPL-3.0 (API `license.spdx_id`), default branch `master`. The bundle ID is `net.pcsx2.pcsx2`, which is what `Emulator.pcsx2` looks up today (`Sources/LudeumCore/Emulators.swift` line 15).
- **`PCSX2/archive`** ("Archive of Legacy Builds of PCSX2", created 2021) holds only v0.9.x builds. Nothing from the main repo has moved there: its oldest release is `v0.9.6` (2021-12-05), still on the main repo's last page.

## 1. Data root, portable mode and resources

`EmuFolders` (`T/pcsx2/Config.h#L1454-L1492`), set up in `QtHost::InitializeConfig` (`T/pcsx2-qt/QtHost.cpp#L1327-L1360`):

- **`AppRoot` on macOS is the folder that holds the bundle.** `SetAppRoot` takes the program's directory, then on macOS replaces it with the parent of the (non-translocated) bundle path (`T/pcsx2/Pcsx2Config.cpp#L2156-L2172`, `T/common/CocoaTools.mm#L117-L131`). For `/Applications/PCSX2.app` that's `/Applications`.
- **Portable mode** is on when `portable.ini` or `portable.txt` exists in `AppRoot`, or `-portable` was passed (`#L2203-L2214`). The data root is then `AppRoot` joined with the trimmed contents of `portable.txt` (`#L2216-L2222`, `#L2275-L2287`): an empty file means `AppRoot` itself (`Path::Combine` drops a trailing separator, `T/common/FileSystem.cpp#L848-L863`), a relative path in it a folder beneath.
  - So **`Emulators/PCSX2/PCSX2.app` with `Emulators/PCSX2/portable.txt`** keeps everything in `Emulators/PCSX2/`, the way ares's `settings.bml` beside the app does (ADR 0028), and unlike DuckStation's and MesenCE's markers inside `Contents/MacOS`. `Emulators/PCSX2.app` with `Emulators/portable.txt` would work too, but would also make DuckStation's and MesenCE's bundles' folder PCSX2's data root.
- **Otherwise** the root is `$HOME/Library/Application Support/PCSX2` (`#L2263-L2266`), or `<path>/PCSX2` when `-datapath <path>` is given: note the appended `PCSX2` (`#L2271-L2272`). `-portable` overrides `-datapath` (help text, `T/pcsx2-qt/QtHost.cpp#L2136-L2137`).
- **`inis/` is always under the root** (`#L2289-L2290`), holding `PCSX2.ini`, `secrets.ini` (`T/pcsx2-qt/QtHost.cpp#L1398-L1416`), `playtime.dat` (`T/pcsx2/GameList.cpp#L977-L980`) and the debugger's files.
- **Resources come from the bundle regardless of the root.** On macOS `Resources` is `Contents/Resources` (`#L2174-L2201`, `T/common/CocoaTools.mm#L174-L185`), where `GameIndex.yaml`, `RedumpDatabase.yaml`, `patches.zip`, shaders, fonts and translations ship (checked in the unpacked release). A file of the same name in the `UserResources` folder (`resources/` under the root) overrides one (`#L2398-L2412`).
- **This Mac's `/Applications/PCSX2.app` has no `portable.txt`** beside or inside it, and no data root exists anywhere (§12).

## 2. Settings: `inis/PCSX2.ini`

### Shape and the folder keys

- **A plain INI** (SimpleIni), sections like `[UI]`, `[Folders]`, `[EmuCore]`, `[EmuCore/GS]`, `[MemoryCards]`, `[Filenames]`, `[AutoUpdater]`. Layered at run time: command line, game, input profile, secrets, base (`T/pcsx2/LayeredSettingsInterface.h#L13-L19`).
- **`[Folders]`** (`T/pcsx2/Pcsx2Config.cpp#L2297-L2363`): `Bios`, `Snapshots`, `Savestates`, `MemoryCards`, `Logs`, `Cheats`, `Patches`, `Covers`, `GameSettings`, `UserResources`, `Cache`, `Textures`, `InputProfiles`, `Videos`, `DebuggerLayouts`, `DebuggerSettings`. Each takes a path; a relative one is joined to the data root (`LoadPathFromSettings`, `#L2315-L2321`; the two debugger ones to `inis/`). The defaults are `bios`, `snaps`, `sstates`, `memcards`, `logs`, `cheats`, `patches`, `covers`, `gamesettings`, `resources`, `cache`, `textures`, `inputprofiles`, `videos`. Every folder is created at startup (`EnsureFoldersExist`, `#L2365-L2385`).
- **Folders are read from the base layer only.** `LoadStartupSettings` and `UpdateFolders` call `EmuFolders::LoadConfig(*Host::Internal::GetBaseSettingsLayer())` (`T/pcsx2/VMManager.cpp#L560-L572`, `#L876-L886`), so a per-game file or `-gamecfg` can't move them. They are re-read when base settings change during a run, and a changed memory card folder reopens the cards (`#L893-L904`).
- **`[UI] SettingsVersion = 1` must be there.** At startup, a missing or unparseable `PCSX2.ini`, or one whose `SettingsVersion` isn't 1, has PCSX2 write defaults for everything, flag the setup wizard (`SetupWizardIncomplete`) and save (`T/pcsx2-qt/QtHost.cpp#L1363-L1395`, `T/pcsx2/VMManager.cpp#L153`, `#L552-L558`, `#L576-L607`). An existing file with the wrong version asks before resetting. So a file Ludeum seeds needs that key, or Ludeum lets PCSX2 write its first file and edits that.
- **Other keys Ludeum would care about:**
  - `[Filenames] BIOS` names the BIOS file within the `Bios` folder (`T/pcsx2/Pcsx2Config.cpp#L1718-L1723`).
  - `[EmuCore] EnableFastBoot` (default `true`, `#L1964`, `#L2007`), `EnableFastBootFastForward`, `SaveStateOnShutdown` (default off), `BackupSavestate` (default `true`, `#L1970`), `EnableGameFixes` (default `true`, `#L1967`).
  - `[EmuCore] SavestateCompressionType` and `SavestateCompressionRatio` (`#L1700-L1701`; defaults Zstandard, Medium, `T/pcsx2/Config.h#L1344-L1345`).
  - `[EmuCore/GS] VsyncQueueSize` and the latency keys, as the earlier note has them.
  - `[MemoryCards] Slot1_Enable`, `Slot1_Filename`, `Slot2_…`, `Multitap1_Slot1_…` (§5).
  - `[AutoUpdater] CheckAtStartup` (default `true`), `UpdateTag` (default `nightly`), `LastVersion` (`T/pcsx2-qt/MainWindow.cpp#L2250-L2256`, `T/pcsx2-qt/AutoUpdaterDialog.cpp#L77`, `#L159`, `#L585`).

### When it's read and written

- **Read once at startup** (`INISettingsInterface::Load`, `T/pcsx2/INISettingsInterface.cpp#L76-L88`, from `InitializeConfig`). Nothing re-reads it while PCSX2 runs.
- **Written whole and atomically**: to a temporary file beside it, then renamed over (`Save`, `#L90-L128`). Any change to a base setting starts a one-second timer and the whole in-memory file is saved when it fires (`Host::CommitBaseSettingChanges`, `T/pcsx2-qt/QtHost.cpp#L60`, `#L1447-L1490`). The settings dialogs, the memory card swap, Recent files and the updater all go through this.
- So anything Ludeum writes into `PCSX2.ini` while PCSX2 runs is lost at its next save, as with DuckStation, and a link out of the bundle folder would be renamed over. The same `Save` writes the per-game files (§9).

### Self-update

- **Supported on macOS** for any tagged build (`AutoUpdaterDialog::isSupported`, `T/pcsx2-qt/AutoUpdaterDialog.cpp#L98-L120`). The default channel is `nightly` (`#L77`), which for this build means every nightly tag.
- **It replaces the bundle beside itself.** The update is unpacked to a staging folder in the app's folder, the old bundle is moved to the Trash, and the new one is renamed into place with the new version in its name (`PCSX2-v2.9.103.app` becomes `PCSX2-v2.9.152.app`, `UpdateVersionNumberInName`, `#L788-L800`, `#L802-L905`), then launched. A managed install's path would break.
- **No Play ever checks.** The startup check runs only when nothing is being booted and not in `-nogui` (`T/pcsx2-qt/QtHost.cpp#L2553-L2559`). Only an Open with no ROM would. `[AutoUpdater] CheckAtStartup = false` turns that off too; Help → Check for Updates stays.

## 3. Save states

- **Named by serial and CRC, in the `Savestates` folder** (`VMManager::GetSaveStateFileName`, `T/pcsx2/VMManager.cpp#L1888-L1903`):
  - slot *n*: `<serial> (<CRC>).<nn>.p2s`, the slot two digits (`SLUS-20062 (2C9A8B3F).01.p2s`);
  - resume: `<serial> (<CRC>).resume.p2s`;
  - backup: `<serial> (<CRC>).<nn>.p2s.backup`.

  The serial is the disc's as `SYSTEM.CNF` gives it (§4); the CRC is eight upper-case hex digits of the ELF's XOR. `NUM_SAVE_STATE_SLOTS` is 10 (`T/pcsx2/VMManager.h#L73`). **A game with no serial has no states**: the name is empty when the serial is, and `DoSaveState` fails on an empty name. An ELF booted directly is named by its file name without the extension (`#L1076`), the BIOS alone by `BiosSerial` (`#L1083`).
- **The backup** is made by renaming the old file to `.backup` before writing the new one, when `BackupSavestate` is on (`#L1973-L1982`), and the default is on. The resume state is written on shutdown only when `SaveStateOnShutdown` is on or the user chose it (`#L1685-L1707`), never backed up. Delete in PCSX2 removes slot, resume and backups (`#L2063-L2080`).
- **Format: a zip.** Entries are `PCSX2 Savestate Version.id` (the version constant and the build's tag, stored, never compressed, `T/pcsx2/SaveState.cpp#L339-L341`, `#L963-L997`), `PCSX2 Internal Structures.dat` and one entry per component, Zstandard by default (`#L927-L960`), and **`Screenshot.png`** (`#L758-L776`, `#L778-L840`): the frame scaled to fit 640 × 480, PNG at libpng level 5, stored uncompressed in the zip. So Game detail can show a state's picture by reading one zip entry, as it does DuckStation's.
- **Not written atomically.** `SaveState_ZipToDisk` opens the final name with `ZIP_CREATE | ZIP_TRUNCATE` and writes into it (`#L1032-L1058`), on a thread. A crash mid-write leaves a truncated file; the `.backup` holds the previous state of that slot.
- **Version-locked, with a stable version.** A state is refused when its version is newer than the build's or its high 16 bits differ (`CheckVersion`, `#L1084-L1120`), with a message to download the version that made it. `g_SaveVersion` (`T/pcsx2/SaveState.h#L25-L29`) across the tags fetched:

| Tag | Date | `g_SaveVersion` |
|---|---|---|
| v2.4.0 | 2025-06-29 | `0x9A54` |
| v2.6.0, v2.6.3, v2.7.0 | 2026-01-04 to 2026-01-05 | `0x9A55` |
| v2.7.100 | 2026-02-08 | `0x9A57` |
| v2.7.200, v2.7.300, v2.7.382 | 2026-03-20 to 2026-05-31 | `0x9A59` |
| v2.8.0, v2.8.2 (stable) | 2026-08-28, 2026-09-04 | `0x9A59` |
| v2.9.1, v2.9.50, **v2.9.103**, v2.9.152 | 2026-08-31 to 2026-11-01 | `0x9A59` |
| `master` | 2026-11-02 | `0x9A59` |

  So a bump within the last seven months of builds keeps every state; three bumps in the nine months before that would each have orphaned them all. A commit that bumps it is tagged `[SAVEVERSION+]` in its message (`SaveState.h` comment), which a bump could check.
- **No check against the running disc.** Loading compares only the version and warns about a different BIOS (`T/pcsx2/SaveState.cpp#L163-L164`); nothing compares the state's game to the disc. So a `-statefile` state from another dump of the same game (another CRC) is loaded as it is. Whether it then runs is **unverified**; the ELF and its data are the same game's, so it likely does.
- **Starting from a state** (`T/pcsx2-qt/QtHost.cpp#L2237-L2246`, `T/pcsx2/VMManager.cpp#L1396-L1418`):
  - `-statefile <file>` loads that file once the game has booted. Any name, anywhere.
  - `-state <index>` loads slot *index* of the boot file's own states, which needs the serial and CRC: taken from PCSX2's game list if the file is in it, else **by scanning the disc then and there** (`GameList::GetSerialAndCRCForFilename`, `T/pcsx2/GameList.cpp#L956-L975`). In batch mode the list is loaded from `cache/gamelist.cache` without a scan (`T/pcsx2-qt/QtHost.cpp#L2530-L2534`), so a ROM not yet cached is scanned at launch.
  - Both are options, so they go before `--`; only the file goes after it (`#L2323-L2327`).

## 4. Serial and CRC

Both come off the disc, so Ludeum could compute them as `PlayStationDisc` computes a PlayStation Serial today (`Sources/LudeumCore/Import/PlayStationDisc.swift`), which reads only PlayStation discs (`Serials.platforms`, `Sources/LudeumCore/Serials.swift` line 61).

- **Serial.** `GetPS2ElfName` reads `SYSTEM.CNF` from the ISO 9660 file system and takes the `BOOT2` line's value (`BOOT` is a PlayStation disc; `VMODE` and `VER` are kept too), `T/pcsx2/CDVD/CDVD.cpp#L471-L524`. `ExecutablePathToSerial` (`#L526-L576`) takes the part after the last `\` (or `:`), drops `;…`, requires `????_???.??*` or `????-???.??*`, removes dots, turns `_` into `-` and upper-cases: `cdrom0:\SLUS_200.62;1` is `SLUS-20062`. A name that doesn't match the pattern is an empty serial. That's DuckStation's and Ludeum's transform (`PlayStationDisc.serial(booting:)`), but with the pattern check.
- **CRC.** The boot ELF is read off the disc (version suffix ignored, `#L393-L420`, `T/pcsx2/Elfheader.cpp#L40-L56`) and the CRC is the XOR of its 32-bit words, in file order, the file truncated to whole words (`ElfObject::GetCRC`, `#L248-L257`). Nothing else: no disc hash. So the same ELF in an `.iso`, a `.chd` or a renamed file gives the same CRC, and the same game's other dump usually does too unless its ELF differs.
- **Both key a Game's files.** States (§3) and PCSX2's per-game file (`gamesettings/<serial>_<CRC>.ini`, `T/pcsx2/VMManager.cpp#L820-L831`) use both; the memory card filter (§5), the GameDB lookup and play time use the serial alone.
- **Multi-disc.** Each disc has its own `SYSTEM.CNF`, so its own serial and CRC. `UpdateDiscDetails` runs on every disc change and re-keys states, settings and the card filter to the new disc (`#L1049-L1095`, `ChangeDisc` at `#L2371`). PCSX2 has no notion of a disc set; a two-disc game has two sets of states. The GameDB keys by serial too, and `memcardFilters` is how it makes several serials share saves (§5).
- **A disc Ludeum can't read.** All but one PS2 ROM is a `.7z` today (§12), which Ludeum's Serials step reads through 7-Zip for PlayStation; `.chd` and `.pbp` are "not read yet" (`Serials.unreadForms`). PCSX2 reads `.chd` itself.

## 5. Memory cards and Game saves

PS2 games save to memory cards and nothing else, so a Game's Game save is its Card saves on whichever card it was given.

### Keys

- `[MemoryCards] Slot1_Enable`, `Slot1_Filename`, `Slot2_Enable`, `Slot2_Filename`, and `Multitap<p>_Slot<s>_Enable`/`_Filename` for the six multitap slots (`T/pcsx2/Pcsx2Config.cpp#L2075-L2098`). A filename is relative to the `MemoryCards` folder (`FullpathToMcd`, `#L2105-L2108`). Defaults: slots 1 and 2 enabled, `Mcd001.ps2` and `Mcd002.ps2`; multitap slots `Mcd-Multitap<p>-Slot<ss>.ps2`, disabled (`#L1977-L1983`, `T/pcsx2/SIO/Memcard/MemoryCardFile.cpp#L244-L250`).
- **They're core settings, so the game layer sets them.** `LoadSaveMemcards` is called from `LoadSaveCore` (`#L2055`), which loads from the layered interface, and Game Properties has a Memory Cards page that shows an inherited card and lets a Game pick its own (`T/pcsx2-qt/Settings/MemoryCardSettingsWidget.cpp#L109-L130`, `#L321-L340`). So `[MemoryCards] Slot1_Filename = <card>` in a `-gamecfg` ini, or in `gamesettings/<serial>_<CRC>.ini`, gives a Game its own card, as ADR 0023 did for DuckStation.
- **There's no auto-manage switch** in this version: no `McdFolderAutoManage` or `AutoEject` key exists in `Pcsx2Config.cpp` or `Config.h`. Folder-card filtering is always on (`FileMcd_EmuOpen`, `T/pcsx2/SIO/Memcard/MemoryCardFile.cpp#L606-L616`).

### File cards

- **A type is detected, not configured**: a directory at the card's path is a folder card, anything else a file card, created if missing (`FileMcd_SetType`, `#L584-L603`; `Open`, `#L262-L300`).
- **Created as 8 MB with ECC**: `Create(fname, 8)` writes 8 × 1,081,344 bytes (`MC2_MBSIZE` is 1024 × 528 × 2, each 512-byte page carrying a 16-byte ECC spare, `#L29-L35`, `#L379-L403`), so a fresh `Mcd001.ps2` is **8,650,752 bytes**. PCSX2 also reads 16, 32 and 64 MB cards, cards without ECC (`.bin`/`.mc2`, converted to raw on open) and 128 KB PlayStation cards (`GetMemoryCardFileTypeFromSize`, `#L841-L856`; the card list accepts `.ps2`, `.mcr`, `.mcd`, `.bin`, `.mc2`, `#L891-L945`).
- **Written in place, page by page**, with `fseek` and `fwrite` at the page's offset as the game writes (`Save`, `#L440-L500`; `EraseBlock`, `#L510-L522`). Not atomic; a crash mid-write corrupts a page, as on a real card.
- **Shared.** A file card holds every game's saves in one PS2 file system. Reading one Game's Card saves out of it means parsing that file system (its directory entries name saves by `B<region><serial>…` as the game chose). Nothing in Ludeum reads a PS2 card today; `MemoryCard` in `Sources/LudeumCore/MemoryCards.swift` is DuckStation's 128 KB PlayStation card.

### Folder cards

- **A directory with a `_pcsx2_superblock` file** in it (`#L858-L862`, `FileMcd_CreateNewCard`, `#L988-L1013`). It appears in PCSX2's card list only with one of the card extensions in its name (`#L919-L922`), so PCSX2 names them `Mcd001.ps2/`; any directory at the configured path is opened as one regardless.
- **One subdirectory per save, named as the game named it**, holding the save's files as they are on the card (`icon.sys`, the game's data files) plus a `_pcsx2_index` YAML of each file's timestamps and order (`T/pcsx2/SIO/Memcard/MemoryCardFolder.cpp#L448-L500`, `#L1270-L1295`). Files named `_pcsx2_*` are PCSX2's and skipped when indexing (`#L1785-L1786`). Files in the root are ignored ("no official software stores files there", `#L459-L462`).
- **The running game sees only its own saves.** On open and on every disc change the card is re-indexed with a filter (`sioSetGameSerial`, `T/pcsx2/SIO/Sio.cpp#L26-L34`; `ReIndex`, `#L215-L226`): a save directory is included when its name contains any `/`-separated term of the filter, plus `DATA-SYSTEM`/`BWNETCNF` (`FilterMatches`, `#L424-L446`; `#L452-L462`, `#L483-L488`). The filter is the GameDB entry's `memcardFilters` when it has them, else the disc's serial (`T/pcsx2/VMManager.cpp#L893-L904`, `#L3112-L3122`). So a folder card is effectively a card per serial, and listing a Game's Card saves is `ls` on the card filtered by its serials, with each save's own `icon.sys` for its title and icon.
- **Flushed two frames after a write** (`FramesAfterWriteUntilFlush`, `T/pcsx2/SIO/Memcard/MemoryCardFolder.h#L248`; `Flush`, `#L1069-L1148`), file by file in place. Not atomic either.
- **The index file's modified time is the save's last write**, near enough; whether the `_pcsx2_index` timestamps match it is **unverified**.

## 6. Through Archive, Compact and Rename

Everything is keyed by serial and CRC, both read from the disc's contents, never from the file's name or form.

- **Rename** (ADR 0012): states, settings and cards all follow. Nothing for Ludeum to move.
- **Archive and Unarchive** (`.7z` of the ROM's folder): PCSX2 can't open a `.7z` (below), so an Archived ROM can't be Played, as now; its states wait, keyed by what's inside, and apply again on Unarchive.
- **A `.chd` conversion**: same ELF, same CRC, so states and settings follow. **Unverified** by running.
- **Compact**: not offered for PS2 (`ROMPlatform.all[8]` has no `compactExtension`, `Sources/LudeumCore/Import/ROMPlatform.swift` ~105–107).
- **Another dump of the same game** (a different region's, or a revision) is another serial, so another Game's set of files, which is right.
- **Formats PCSX2 opens** (`VMManager::IsDiscFileName`, `T/pcsx2/VMManager.cpp#L2481-L2492`; the readers in `pcsx2/CDVD/`): `.iso`, `.bin`, `.img`, `.mdf`, `.gz`, `.cso`, `.zso`, `.chd`, plus `.elf` and GS dumps. **No `.cue`** (nothing in `pcsx2/CDVD/` mentions one), no `.7z`, no `.zip`. The bundle's document types are `iso`, `cso`, `zso`, `chd`, `mdf`, `elf` (its `Info.plist`). Ludeum's PS2 ROM folder reads `iso`, `chd`, `cso`, `zso`, `gz`, `cue`, `bin`, `mdf` as ready (`Sources/LudeumCore/Import/ROMPlatform.swift` ~105), so a cue sheet would be handed to PCSX2 and refused. A multi-track PS2 disc as `.cue`/`.bin` is rare (PS2 discs are single-track DVDs or CDs); its `.bin` alone would open.

## 7. What else loses one

- **A `g_SaveVersion` bump** orphans every state (§3). None since 2026-03-20.
- **A different dump** changes the CRC: states and the per-game file no longer match by name, though a state loads by `-statefile` if pointed at.
- **The data root moving** (another `-datapath`, a `portable.txt` added or removed) leaves everything behind, as PCSX2 only ever looks in one root. Absolute `[Folders]` paths avoid that for what they cover.
- **A crash mid-write**: states and cards are written in place (§3, §5). `PCSX2.ini` and the per-game inis are renamed into place.
- **`.backup`** is kept, not deleted, so saving a slot twice loses the state before the previous one, as DuckStation's `.bak` does.
- **Dropbox online-only files.** Images are opened with `fopen` (`FlatFileReader`, `T/pcsx2/CDVD/FlatFileReader.cpp#L26`), cards and states too (`FileSystem::OpenCFile`), so an evicted file stalls PCSX2 as it would DuckStation. The folders would need marking available offline, as ADR 0024 does.
- **The updater** trashing `PCSX2-v2.9.103.app` (§2).

## 8. Single instance

- **None.** Nothing in `pcsx2-qt` uses `QLocalServer`, `QLockFile`, `QSharedMemory` or a single-application helper (grepped on the tag and `master`). A second launch is a second PCSX2 with its own copy of `PCSX2.ini` in memory, and whichever saves last wins.
- **`-batch`** makes PCSX2 quit when the VM stops (`MainWindow::onVMStopped`, `T/pcsx2-qt/MainWindow.cpp#L2589-L2617`; `T/pcsx2-qt/QtHost.cpp#L1302-L1303`), whether the game was closed from PCSX2's menu, by the shutdown hotkey or by quitting. It's refused without a file to boot (`#L2369-L2376`), loads the game list from its cache without scanning (`#L2530-L2534`), and skips the update check (`#L2553-L2559`). `-nogui` is batch plus a hidden main window.
- **`-fastboot`** sets the boot's fast-boot flag, which overrides `[EmuCore] EnableFastBoot` (default on anyway) for that boot; ELFs always fast-boot, GS dumps never (`T/pcsx2/VMManager.cpp#L1504-L1509`). The GameDB has no key to force a full boot (none in `GameDatabase.cpp`/`.h`), unlike DuckStation's `ForceFullBoot`. `-slowboot` is the opposite.
- So "refuse Play while any PCSX2 runs" is the same cheap rule as for DuckStation and ares.

## 9. `-gamecfg` and PCSX2's own per-game files

Answering the earlier note's open questions:

- **`-gamecfg <file>` must name an existing `.ini`** or the boot fails (`T/pcsx2/VMManager.cpp#L1482-L1497`). It's kept for the VM's life and cleared at shutdown (`#L183`, `#L1381`, `#L1716`).
- **It replaces PCSX2's own per-game file entirely.** `GetGameSettingsPath` returns the override before looking at the serial or CRC (`#L820-L831`), and `UpdateGameSettingsLayer` loads whatever that path holds as the game layer (`#L982-L1030`). `gamesettings/<serial>_<CRC>.ini` (or the legacy `<CRC>.ini`) is never read during such a Play. Any per-game fix, patch choice or input profile the user set there is ignored.
- **GameDB fixes still apply.** They're not a settings layer: `ApplyGameFixes` looks the serial up in the GameDB after the settings are loaded and applies its fixes, clamp modes and GS hardware fixes onto the in-memory config, whenever `EnableGameFixes` is on (`#L609-L629`, `#L733-L755`). Patches from `patches.zip` are applied by serial and CRC too (`#L1165`). So an ini holding only `VsyncQueueSize` loses nothing from the GameDB.
- **Game Properties writes into Ludeum's file.** The dialog opens `VMManager::GetGameSettingsPath(serial, crc)`, which is the override (`T/pcsx2-qt/Settings/SettingsWindow.cpp#L662-L694`), and every change saves that file and reloads the game layer (`#L655-L660`). `QtHost::SaveGameSettings` **deletes the file when it has no keys left** (`T/pcsx2-qt/QtHost.cpp#L1568-L1590`), which a user resetting Ludeum's one key would trigger; Ludeum rewrites it before the next Play anyway. So the earlier note's guess was right: changes go to Ludeum's file and are overwritten, which is ADR 0008's model, and the opposite of ADR 0029's, where DuckStation's per-game files are DuckStation's and last.
- **The alternative** is ADR 0029's shape: the Standing settings carry `[EmuCore/GS] VsyncQueueSize = 0` in `PCSX2.ini` (Ludeum's one per-game key is the same for every Game), `[Folders] GameSettings` points into the Data folder, and PCSX2's own per-game files are left to Game Properties. `-gamecfg` then goes.

## 10. Install

### Releases

- **Every nightly is a versioned tag** `v2.9.<n>` with assets for Linux (AppImage, Flatpak), macOS (`pcsx2-v<ver>-macos-Qt.tar.xz`) and Windows, each with a `digest` in the API. All are `prerelease: true`. Several a day: 52 between 2026-10-05 and 2026-11-01, v2.9.103 among seven published on 2026-10-05 and 2026-10-06.
- **Stable releases** are `prerelease: false`, rarely: v2.4.0 (2025-06-29), v2.6.0–v2.6.3 (2026-01), v2.8.0–v2.8.2 (2026-08-28 to 2026-09-04). v2.8.2's macOS asset is `pcsx2-v2.8.2-macos-Qt.tar.xz` (24,377,200 bytes, `sha256:3ed9eb40…7f7d426`). The nightlies restarted at v2.9.1 the day after v2.8.0.
- **Nothing ages off.** The API lists 58 pages of 100 releases and as many tags, the oldest release v0.9.6 (2021). PCSX2/archive is a separate repo of pre-2012 builds.
- **v2.9.103**: published 2026-10-05T23:21:11Z, target `master`, `pcsx2-v2.9.103-macos-Qt.tar.xz` 24,513,904 bytes, `sha256:42ddda7193846d8bf4c3ee3c2629f537b799e9babfe9327c0fd18a3a0fbe3b0b`. The download matched.
- **No arm64 macOS asset** in v2.9.103, v2.9.152 or v2.8.2. `master`'s `macos_build.yml` still defaults `arch` to `x86-64` (lines 16–19, 133).

### The tar

- It holds **`PCSX2-v2.9.103.app`** (110 MB unpacked): `Contents/MacOS/PCSX2` (17.9 MB, Mach-O thin x86_64), `Frameworks/` with Qt 6, SDL3, MoltenVK, FFmpeg and the rest (26 dylibs), `PlugIns/` (Qt), `Resources/` (§13), `Info.plist`. It needs nothing from Homebrew.
- **Signed and notarised**: `Developer ID Application: Ty Lamontagne (PTMR35SWS3)`, hardened runtime, ticket stapled (`stapler validate` passes, `spctl` says "Notarized Developer ID"). Entitlements: JIT, unsigned executable memory, library validation off, camera and microphone. No sandbox. So no quarantine trick is needed.
- **`-version` prints `PCSX2 v2.9.103` to stderr and exits** (`PrintCommandLineVersion`, `T/pcsx2-qt/QtHost.cpp#L2119-L2125`, `GetAppNameAndVersion`, `#L1537-L1540`), which Ludeum's check already reads from the merged pipe and parses (`EmulatorVersions.swift` lines 132–133, 158–160). `CFBundleShortVersionString` and `CFBundleVersion` are both `v2.9.103`.
- **Unpacking**: it's a `tar.xz`, so `tar -xJf`, not `ditto` or `unzip`. `LSMinimumSystemVersion` 11.0.
- **Nothing in the bundle is data** when the root is outside it (§1), so a reinstall carries nothing across from the bundle; the root beside it stays.

### This Mac

- `/Applications/PCSX2.app` is the release bundle renamed: its `Contents/MacOS/PCSX2` has the same SHA-256 (`e3db7b53…4298a`) as the release's, same `Info.plist`, still `com.apple.quarantine` from Chrome. Rosetta 2 is installed and runs x86_64 (`arch -x86_64 /usr/bin/true` succeeded; `/usr/libexec/rosetta/` exists). macOS 26.5.2, arm64.

## 11. BIOS

- **`[Folders] Bios`** (default `bios/` under the root) and **`[Filenames] BIOS`** naming the file in it (§2). An absolute `Bios` path into the Data folder works as DuckStation's `[BIOS] SearchDirectory` does.
- **None on this Mac.** No PCSX2 data root exists (§12), and the Data folder's `Emulators/DuckStation/BIOS/` holds only PlayStation BIOSes (`SCPH-102B.BIN`, `SCPH101.BIN`, …). No PS2 BIOS was found by name in the places searched. PCSX2 refuses to boot without one (**unverified** here; it's the setup wizard's first page).

## 12. This Mac's data, and the ROM folder

- **No PCSX2 data anywhere searched**: `mdfind` for `PCSX2.ini`, `Mcd001.ps2`, `*.p2s`, `GameIndex.yaml` and `portable.txt` found nothing outside the bundle; nor did a bounded `find` of `~/Library` (Application Support, Preferences, Caches, Saved Application State, Containers), `~/Documents`, `~/Downloads`, `~/Desktop`, `~/.config` and `~/Dropbox/games`. No `net.pcsx2.pcsx2` preferences or saved state either.
- **Yet Ludeum wrote `PCSX2 game settings.ini`** on 2026-10-06 at 11:47 (the Ludeum folder; contents `[EmuCore/GS]\nVsyncQueueSize = 0`), so a Play was tried that day. PCSX2 creates its data root before anything else (`InitializeConfig`), so it never got that far. Why is **unverified**: the quarantined bundle's first-open prompt, or the Play failing, are both possible.
- **The Ludeum folder**: `journal.sqlite`, `Data -> ~/Dropbox/games/Ludeum`, `Emulators/` with `DuckStation.app`, `MesenCE.app` and `ares/`, and the PCSX2 ini. No `Emulators/PCSX2`.
- **The Data folder's `Emulators/`** has `DuckStation/` (BIOS, Game Settings, Input Profiles, Memory Cards, Save States, Screenshots), `MesenCE/<Platform>/` and `ares/` (Saves, Screenshots). Nothing for PCSX2.
- **The PS2 ROM folder** (`ROMs/PS2`, 42 GB): 58 ROMs. 57 are Archived `.7z` (`Okami (USA).7z`, `Shadow of the Colossus (USA).7z`, …), and one is a subfolder holding a loose `.iso` (`Sensible Soccer 2006 (Europe) (En,Fr,De,Es,It)/…​.iso`, 1.5 GB, with a `.ludeum-work` folder beside it dated today, so it was being unpacked as this was read). No `.chd`, `.cue`, `.cso` or `.gz`.

## 13. GameDB and the other resources

- **`Resources/GameIndex.yaml`** (2.7 MB): 12,830 entries keyed by serial, each with `name` (and `name-sort`, `name-en` for Japanese titles), `region` (`NTSC-U`, `PAL-M5`, …), `compat` (0–6), and where needed clamp and rounding modes, `gameFixes`, `speedHacks`, `gsHWFixes`, `patches`, `dynaPatches` and `memcardFilters` (`GameEntry`, `T/pcsx2/GameDatabase.h#L95-L125`). 421 entries have `memcardFilters`, e.g. `PBPX-95502` (Gran Turismo 3, bundle disc) listing `PBPX-95502` and `SCPS-15009` so both discs share saves. ICO is `SCUS-97113`, "Ico", `NTSC-U`, compat 5, with clamp and GS fixes. So Ludeum could name a Game's saves and read the serials that share them from this file, as it reads DuckStation's `discdb.yaml`; it's in the bundle, overridable by a copy in the `UserResources` folder (§1).
- **`RedumpDatabase.yaml`** (1.9 MB) is there too, for PCSX2's dump verification.
- **`patches.zip`** (2.1 MB) holds PCSX2's own `.pnach` patches by serial and CRC; the `Patches` and `Cheats` folders are the user's.
- **Folders worth keeping** (in the Data folder): `Savestates`, `MemoryCards`, `Bios`, `Snapshots` (screenshots), `GameSettings`, `InputProfiles`, `Cheats`, `Patches`, `Textures` (replacement packs the user supplies). **Rebuildable** (leave in the root): `Cache` (`gamelist.cache`, shader caches), `Covers` (downloaded), `Logs`, `Videos`, the debugger folders. `inis/` (`PCSX2.ini`, `secrets.ini`, `playtime.dat`) can't move, as DuckStation's `settings.ini` can't.

## 14. ARMSX2

A side finding, from the API and four files of its `master`:

- **Same code, another root.** Its data root is `~/Library/Application Support/ARMSX2` (`A/pcsx2/Pcsx2Config.cpp#L2561`), portable mode is the same `portable.txt`/`portable.ini` beside the app (`#L2503-L2505`), and `-batch`, `-portable`, `-datapath`, `-state`, `-statefile` and `-gamecfg` are parsed as in PCSX2 (`A/pcsx2-qt/QtHost.cpp#L2188-L2240`). `g_SaveVersion` is `0x9A59` (`A/pcsx2/SaveState.h#L29`), state names and the per-game file path are identical (`A/pcsx2/VMManager.cpp#L2628-L2632`, `#L1132-L1133`). Whether its states load in PCSX2 and back is **unverified**.
- **macOS arm64 builds are nightlies only.** Tags `nightly-<yyyymmdd>` (one most days, each with `ARMSX2-nightly-<date>-<sha>-macOS-arm64.tar.xz` and a `digest`, e.g. `nightly-20261031`, 35,233,384 bytes, `sha256:6441bedd…2ab7e3`); each is its own tag, so pinnable. The stable releases (`2.8.2` to `2.9.1`, 2026-10-07 to 2026-10-28) have Android and Linux assets only. Signing and notarisation of the macOS asset are **unverified** (not downloaded). GPL-3.0, a fork of `PCSX2/pcsx2`, 2,368 stars, pushed 2026-11-02. The app is named `ARMSX2` (`pcsx2-qt/CMakeLists.txt` line 417); its bundle ID is **unverified**.

## 15. Mapping ADRs 0024, 0027 and 0028 onto PCSX2

| ADR 0024 / 0027 / 0028 | PCSX2 | Notes |
|---|---|---|
| Pinned versioned tag and SHA-256 in code; fallback repo once aged off | **Same, no fallback** | Every nightly and stable is an immutable tag with a digest, and nothing ages off (§10). The choice is a nightly (v2.9.103, what Ludeum expects, or a newer one) or the stable channel (v2.8.2 today, with the same state version). |
| Unpack without quarantine | **Not needed** | Notarised and stapled. It's a `tar.xz` holding `PCSX2-v<ver>.app`, so Install untars rather than unzips. |
| Confirm the build with `-version` | **Same as today** | `PCSX2 v2.9.103` on stderr, which Ludeum's parser already reads. |
| Portable: a marker in `Contents/MacOS` (0024, 0027) or a settings file beside the app (0028) | **Beside the app** | `portable.txt` in the app's folder, so `Emulators/PCSX2/PCSX2.app` + `Emulators/PCSX2/portable.txt` with the root `Emulators/PCSX2/` (§1). The bundle stays sealed, as ares's does. `-datapath` is the per-launch alternative, but appends `PCSX2`. |
| Standing settings written into the settings file before every Play and after Install | **Same** | Into `inis/PCSX2.ini`: absolute `[Folders]` paths, `[AutoUpdater] CheckAtStartup = false`, fast boot (default on already), and the latency keys if `-gamecfg` goes (§2, §9). Keep `[UI] SettingsVersion = 1`, or PCSX2 resets the file. Written atomically by PCSX2, so Ludeum's `atomically: true` write matches. |
| Only while the Emulator isn't running | **Same** | In-memory settings, rewritten whole one second after a change; no single-instance guard (§2, §8). |
| Self-update off | **Same, and moot for Play** | The key exists; no launch that boots a file checks. The updater would rename the bundle. |
| Save states and Game saves in `Data/Emulators/<Emulator>/` | **Same** | `[Folders] Savestates` and `MemoryCards` (and `Bios`, `Snapshots`, `GameSettings`, `InputProfiles`, `Cheats`, `Patches`, `Textures`). |
| A folder per Platform (0027) | **Not applicable** | One Platform. |
| Refuse Play while any copy runs | **Same** | §8. |
| Game detail lists Save states, Plays from one, deletes one | **Yes, with pictures** | `<serial> (<CRC>).01`–`.10.p2s`, `.resume.p2s` (only if `SaveStateOnShutdown` is on), `.p2s.backup` as "previous" (§3). `Screenshot.png` inside each. Play from one: `-statefile <file>` or `-state <n>` before `--`. Listing needs the serial, and either the CRC or a glob on `<serial> (`. |
| Game detail shows Game saves | **A choice** | A shared file card is no Game's (glossary). A folder card lists a Game's Card saves as subdirectories whose names contain its serial(s), each with `icon.sys` (§5). A per-Game card by `[MemoryCards] Slot1_Filename` in the per-game file gives a file or folder per Game, as ADR 0023 did. |
| Rename moves the saves (0027, 0028) | **Not needed** | Keyed by the disc's contents (§6). |
| Saves keyed by Serial (0024) | **Serial and CRC** | Ludeum reads no PS2 Serial today; both are computable from the disc (§4), or PCSX2's `cache/gamelist.cache` holds them (format **unverified**). |
| Per-game file for a Game's own settings (0021/0029) | **A choice** | Today's `-gamecfg` hides PCSX2's per-game files and catches Game Properties' changes in Ludeum's file. ADR 0029's shape (Standing settings global, PCSX2's own files in the Data folder) fits (§9). |
| Writes atomic, so Dropbox never sees half a file | **Partly** | `PCSX2.ini` and per-game inis yes; states and cards no (§3, §5, §7). One Mac at a time, as 0024 assumes. |
| Folders marked available offline in Dropbox | **Same need** | Plain `fopen` everywhere (§7). |
| Licence | **GPL-3.0** | A configured copy is fine. |
| Move over by hand once | **Nothing to move** | No PCSX2 data exists on this Mac (§12). |
| Architecture | **x86_64 under Rosetta 2** | Installed here. ARMSX2's nightlies are the arm64 route (§14). |

## Open questions for the design session

1. **Which tag to pin: a nightly or the stable channel?** Nightlies are several a day and are what Ludeum expects (v2.9.103); v2.8.2 is the last stable, two months old, same state version. Both are immutable with digests.
2. **Keep `-gamecfg`, or move to Standing settings plus PCSX2's own per-game files (ADR 0029's shape)?** `-gamecfg` hides every per-game fix or input profile set in Game Properties and catches changes in a file Ludeum overwrites. `VsyncQueueSize = 0` is the same for every Game, so it can be global.
3. **Folder cards or file cards, and one shared card or a card per Game?** A folder card is a card per serial already, and its saves are a directory listing; a file card is one opaque file. A per-Game card (`Slot1_Filename` in the per-game file) is the DuckStation 0023 model that 0024 moved away from. And what, for Ludeum, is a PS2 Game's "Game save" to show: its Card saves on the card in slot 1, by serial (and the GameDB's `memcardFilters` for discs that share saves)?
4. **Should Ludeum compute a PS2 Disc's serial and CRC itself?** The serial is `PlayStationDisc` with `BOOT2` and a pattern check; the CRC needs the ELF read off the ISO 9660 file system and XORed. Or list states by `<serial> (` alone, or read `gamelist.cache`.
5. **Rosetta.** Accept x86_64 under Rosetta (it's installed and the build is notarised), or pin an ARMSX2 nightly (daily tags, arm64, signing unverified, a young fork)? Speed under Rosetta is still the earlier note's open question.
6. **Bumps.** The state version has held since March; should a bump check the new tag's `SaveState.h` (or the `[SAVEVERSION+]` commit tag) before it's taken, or accept the loss as ADR 0028 does?
7. **Resume states.** Turn `SaveStateOnShutdown` on as a Standing setting, so a Game has a Resume state to list, as DuckStation's does? And list `.backup` as "previous", as DuckStation's `.bak`?
8. **BIOS.** Where does a PS2 BIOS come from, and does `[Folders] Bios` point into the Data folder beside DuckStation's?
9. **The `.cue` ready form.** Should the PS2 ROM folder stop reading `.cue` as ready, since PCSX2 opens none?
10. **Why has PCSX2 never run here?** Worth one Play by hand before the design, to see whether the quarantined copy opens and what it writes.
11. **Back up, restore and delete a Game save (#77).** DuckStation, MesenCE and ares went without; a folder card makes a Card save a directory to delete.

### Side findings (outside #88)

- **`-datapath <path>` is not the root**: PCSX2 appends `PCSX2` to it (§1). The issue's note that it "moves the whole data folder" holds, one level down.
- **`SaveGameSettings` deletes an empty per-game file**, so Ludeum's one-key `-gamecfg` file vanishes if that key is reset in Game Properties; the next Play rewrites it (§9).
- **The release bundle's name carries the version** (`PCSX2-v2.9.103.app`); `/Applications/PCSX2.app` was renamed by hand. The updater relies on that naming.
- **PCSX2 opens `.bin` and `.img` images directly, not through a cue sheet**, and has `RedumpDatabase.yaml` to verify a dump (§13).
- **GameDB `memcardFilters`** is PCSX2's own list of which serials share saves (421 games), which Ludeum's Disc sets might use to show one Game's saves across its discs (§5, §13).
- **ARMSX2 keeps PCSX2's data layout under another root** (`~/Library/Application Support/ARMSX2`), so a swap would be a new root, not a conversion (§14).
