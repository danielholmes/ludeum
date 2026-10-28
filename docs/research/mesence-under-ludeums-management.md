# MesenCE under Ludeum's management

Researched 2026-10-28 for issue #82. The question: can Ludeum manage MesenCE as ADR 0024 manages DuckStation (install a pinned build, make it portable, write Standing settings that put its Save states and Game saves in the Data folder, refuse Play while it runs, list and Play from Save states in Game detail)? What are the shapes of its settings, folders and files, and what changes because it plays eleven Platforms rather than one? This note lays out the facts and the options. It doesn't make the decision.

Sources:

- **MesenCE source** at tag `2.2.1`, commit `20ba206cef5ba207c21203176d02cb9f43dda9fb` (2026-06-05). That's the version Ludeum expects (`EmulatorVersionSpec(expected: "2.2.1")`, `Sources/LudeumCore/EmulatorVersions.swift` ~52). Links like `T/UI/Config/ConfigManager.cs#L188-L212` mean `https://github.com/nesdev-org/MesenCE/blob/20ba206cef5ba207c21203176d02cb9f43dda9fb/UI/Config/ConfigManager.cs#L188-L212`.
- **MesenCE `master`** at `4b8a196e299b3de297b204fd1208d2981562c89b` (2026-10-07), where it differs. Links like `M/…` mean `https://github.com/nesdev-org/MesenCE/blob/4b8a196e299b3de297b204fd1208d2981562c89b/…`.
- **The GitHub REST API** for releases, tags, digests and repo metadata.
- **The release zip** `Mesen_2.2.1_macOS_ARM64_AppleSilicon.zip`, downloaded into the session scratchpad and checked read-only. It was never run.
- **This Mac's copy**, read without changing or launching anything: `/Applications/Mesen.app` and `~/Library/Application Support/MesenCE/`.
- **OpenEmu's mGBA core** at `OpenEmu/mGBA-Core` `3829cdb34fd90efff2d1240dd037c075f2cf2e38`, for the carry-over question. Links like `OE/…` mean `https://github.com/OpenEmu/mGBA-Core/blob/3829cdb34fd90efff2d1240dd037c075f2cf2e38/…`.

Anything not checked against one of these sources is marked **unverified**.

## Answer

**Mostly yes, but with four differences from DuckStation that matter for the design.**

1. **Firmware can't be pointed anywhere.** Save states, Game saves (Mesen's "Saves") and screenshots each have a `Preferences.Override…Folder` boolean and a `…Folder` absolute-path string in `settings.json`. Firmware (GBA BIOS, PC Engine CD System Card, SGB, boot ROMs) has neither. Nor do the RecentGames resume files, Cheats or GameConfig. They always live in the data root (`T/UI/Config/ConfigManager.cs#L235-L252`), so they'd sit inside the bundle unless Ludeum links or copies them.
2. **There's one Save state folder and one Game save folder for all eleven Platforms, keyed only by the ROM file's stem.** Thirteen stems in today's ROM folders exist on two or three MesenCE Platforms, e.g. `DuckTales (USA)` on Game Boy and NES. Those Games overwrite each other's Save states (reproduced by hand with DuckTales, and not reported upstream that I could find), and three of them could share a `.srm`. MesenCE can't split by Platform per launch. Only `settings.json` sets the folders, and a running MesenCE doesn't re-read it (§9).
3. **Single instance, shared with any other copy.** A second launch hands its arguments to the running MesenCE over a named pipe whose name is a fixed GUID. A Ludeum-installed portable copy and `/Applications/Mesen.app` would hand off to each other. A forwarded launch can set numeric, boolean and enum settings (run-ahead, Game Boy Model), but never a folder. So "refuse Play while running" matters even more than it does for DuckStation, or Ludeum leans on the hand-off as ADR 0008 does today (§7).
4. **The 2.2.1 release needs Homebrew's SDL2.** Its `MesenCore.dylib` links `/opt/homebrew/opt/sdl2/lib/libSDL2-2.0.0.dylib` and fails to load without it. `master` (no release yet) loads SDL2 with `dlopen` and only loses audio without it. Every build since 2.2.0 reports itself as "2.2.1", nightlies included. This Mac runs a nightly (`a60e79feb`, 2026-09-26) that Ludeum's version check takes for 2.2.1 (§8).

The rest maps cleanly:

- **Install.** Versioned tags with SHA-256 digests in the API, and nothing ages off.
- **Portable mode.** A `settings.json` in `Mesen.app/Contents/MacOS/`, the same trick as DuckStation's `portable.txt`.
- **Self-update.** It can be turned off (`Preferences.AutomaticallyCheckForUpdates`).
- **Saves through Compact and Rename.** Saves follow a ROM through Compact, and through Rename of an already Compacted ROM (the name inside the `.7z` doesn't change). Renaming a loose ROM file orphans them.
- **Licence.** GPL-3.0, so a configured copy raises no licence problem.
- **OpenEmu Game saves.** Byte-compatible for Game Boy, Game Boy Color, SNES and GBA flash/SRAM saves after a rename to MesenCE's name and extension. GBA EEPROM saves need each 8-byte block byte-reversed. OpenEmu Save states won't load.

## 0. Which repository

- **`nesdev-org/MesenCE` is canonical.** It is a fork of `SourMesen/Mesen2` (API: `fork: true`, `parent: SourMesen/Mesen2`, `license: GPL-3.0`), and `SourMesen/Mesen2` is archived (`archived: true`). The Mesen2 README opens: "This repository is an archive of Mesen as it was around version 2.1.1 in mid-2025. For the latest version of Mesen, see here: https://github.com/nesdev-org/MesenCE" (https://github.com/SourMesen/Mesen2).
- **MesenCE publishes the macOS zip.** Its releases carry `Mesen_<ver>_macOS_ARM64_AppleSilicon.zip` (§8). The app inside is `Mesen.app`, bundle ID `ca.mesen` (checked in the 2.2.1 zip's `Info.plist`), which is what `Emulator.mesenCE` looks up (`Sources/LudeumCore/Emulators.swift` line 9).
- **Its own name is "MesenCE".** The default data folder name is `MesenCE` (`T/UI/Config/ConfigManager.cs#L23`). The app's `CFBundleShortVersionString` is a placeholder `1.0`, which is why Ludeum reads the version from `settings.json`.

## 1. Settings: `settings.json`

### Shape

- **One JSON object, serialised from `Mesen.Config.Configuration`.** Top-level keys: `Version` (string, `"2.2.1"`), `ConfigUpgrade` (int), `EnableTestMode`, then one object per section: `Video`, `Audio`, `Input`, `Emulation`, `Snes`, `Nes`, `Gameboy`, `PcEngine`, `Sms`, `Cv`, `Gba`, `Ws`, `Preferences`, `AudioPlayer`, `Debug`, `RecentFiles`, `VideoRecord`, `MovieRecord`, `HdPackBuilder`, `Cheats`, `Netplay`, `HistoryViewer`, `MainWindow`, and finally `DefaultKeyMappings`. `T/UI/Config/Configuration.cs#L23-L51`. This Mac's file has exactly these, at 230 KB (most of it key bindings and debugger settings).
- **Serialiser options.** System.Text.Json source generation with `WriteIndented = true`, `IgnoreReadOnlyProperties = true`, `UseStringEnumConverter = true`, and no naming policy. So keys are the C# property names in PascalCase, and enums are their names as strings (`"Model": "AutoFavorBest"`). `T/UI/Utilities/JsonHelper.cs#L41-L46`.
- **Matching, defaults, unknown keys.** No case-insensitive matching is set, so a key must be written exactly. A missing property keeps its C# initialiser. An unknown one is ignored. Both are System.Text.Json defaults, **unverified** against this generated context.
- **Read once, at startup.** `ConfigManager.LoadConfig` deserialises the file the first time `Config` is touched. `Program.Main` starts that on a background task. `T/UI/Config/ConfigManager.cs#L70-L84`, `T/UI/Program.cs#L68-L69`.
- **A file that fails to parse is replaced.** It's copied to `settings.<yyyy-M-dd_HH-mm-ss>.bak` and a fresh first-run config is used. `T/UI/Config/Configuration.cs#L254-L281`.
- **Written whole, non-atomically.** `Configuration.Save` returns at once if `--doNotSaveSettings` was given (`ConfigManager.DisableSaveSettings`). Otherwise `Serialize` writes the whole file, and only when the JSON differs from what was read. It writes with `File.WriteAllText` (truncate and write, no temporary file and rename), retried three times. It's in a try/catch whose comment reads: "This can sometime fail due to the file being used by another Mesen instance". `T/UI/Config/Configuration.cs#L71-L79` and `#L283-L294`; `T/UI/Utilities/FileHelper.cs#L18-L29` and `#L51-L74`.
  - It's written with `Encoding.UTF8`, so it starts with a BOM. This Mac's file does (`EF BB BF`).
- **When it's written:**
  - after a successful ROM load, to record Recent files (`T/UI/Utilities/LoadRomHelper.cs#L50-L56`);
  - on settings dialogs, the setup wizard, the storage-folder move, and the finaliser of `Configuration` (`T/UI/Config/Configuration.cs#L65-L69`).
  - Not on a timer.
- **`ConfigUpgrade` matters to anyone writing the file.**
  - Default key bindings are only filled in when it's `FirstRun` (1) (`InitializeDefaults`, `T/UI/Config/Configuration.cs#L136-L150`).
  - `UpgradeConfig` fills in only SMS, GBA, ColecoVision and WonderSwan inputs for older values. It then sets `ConfigUpgrade` to the latest and `Version` to the running build's (`#L114-L134`).
  - So a file Ludeum seeded with no `ConfigUpgrade` (0) would leave NES, SNES, Game Boy and PC Engine with no controls. A seed with `"ConfigUpgrade": 1` would get them all. Code reading, **unverified** by running.
  - `master` adds a sixth hint, `WindowsAudioLatency` (`M/UI/Config/Configuration.cs#L323-L333`). That's why this Mac's file says `"ConfigUpgrade": 6`, a value 2.2.1 never writes.

### Folder keys

`PreferencesConfig` (`T/UI/Config/PreferencesConfig.cs#L78-L92`):

| What | Boolean | Path (string) | Default when off | Used for |
|---|---|---|---|---|
| Game saves | `OverrideSaveDataFolder` | `SaveDataFolder` | `<home>/Saves` | battery files |
| Save states | `OverrideSaveStateFolder` | `SaveStateFolder` | `<home>/SaveStates` | `.mss` slots |
| Screenshots | `OverrideScreenshotFolder` | `ScreenshotFolder` | `<home>/Screenshots` | `.png` |
| Movies | `OverrideMovieFolder` | `MovieFolder` | `<home>/Movies` | `.mmo` |
| Video recording | `OverrideAviFolder` | `AviFolder` | `<home>/Avi` | |
| Audio recording | `OverrideWaveFolder` | `WaveFolder` | `<home>/Wave` | |
| Game folder | `OverrideGameFolder` | `GameFolder` | (none) | file dialogs, plus a "known game folder" |

- **The boolean and the string go together.** `ConfigManager.GetFolder(default, override, useOverride)` uses the string only when the boolean is true. It creates the folder, and falls back to the default if it can't. `T/UI/Config/ConfigManager.cs#L214-L252`.
- **The core gets the same three overrides.** It gets them as `SaveFolderOverride`, `SaveStateFolderOverride` and `ScreenshotFolderOverride`, empty when the boolean is off (`T/UI/Config/PreferencesConfig.cs#L219-L252`, `T/Core/Shared/EmuSettings.cpp#L318-L333`). `FolderUtilities::GetSaveFolder` and the others use an override verbatim, else `<home>/Saves` and so on (`T/Utilities/FolderUtilities.cpp#L61-L136`).
- **Paths are taken as given.** Nothing makes them relative to the home folder, so an absolute path is what to write. **Unverified:** whether a relative path would resolve against the working directory, which Mesen sets to the home folder (`T/UI/Program.cs#L54`).
- **Firmware has no setting.** The core's `SetFolderOverrides` has a firmware parameter, but `SetPreferences` always passes `""` (`T/Core/Shared/EmuSettings.cpp#L328-L332`). So firmware is always `<home>/Firmware`.
- **Nor do these.** `Cheats`, `GameConfig`, `Satellaview`, `Debugger`, `Backups`, `Tests`, `HdPacks`, `RecentGames` and `Dumps` are all `GetFolder(<home>/<name>, null, false)` (`T/UI/Config/ConfigManager.cs#L242-L252`). `master` adds `Shaders` and `ShaderConfig` the same way (`M/UI/Config/ConfigManager.cs#L245-L246`).

### Other keys Ludeum would care about

- `Preferences.AutomaticallyCheckForUpdates` (default `true`) and `Preferences.SingleInstance` (default `true`). `T/UI/Config/PreferencesConfig.cs#L25-L26`.
- `Preferences.EnableAutoSaveState` (`true`) and `AutoSaveStateDelay` (5 minutes). `#L52-L53`.
- `Preferences.GameSelectionScreenMode` (`ResumeState`), the recent-games screen. Writing the `.rgd` resume files depends on it (§4). `#L70`.
- `Emulation.RunAheadFrames`, `[MinMax(0, 10)]`. `T/UI/Config/EmulationConfig.cs#L19`.
- `Gameboy.Model`: `AutoFavorBest` (the default), `AutoFavorGbc`, `AutoFavorSgb`, `AutoFavorGb`, `Gameboy`, `GameboyColor` or `SuperGameboy`. `T/UI/Config/GameboyConfig.cs#L19` and `#L130-L139`.
  - Ludeum's Auto sends `AutoFavorGbc` (`Sources/LudeumCore/Emulators.swift` line 81). MesenCE's own Auto, since 2.2.0, is `AutoFavorBest`. The 2.2.0 notes list "Added Game Boy model selection option for best model a game explicitly supports" (§8).

### Per-game settings

- **MesenCE's per-game file holds two things.** `GameConfig/<ROM stem>.json` holds only `DipSwitches`, `OverrideOverscan` and `Overscan` (`T/UI/Config/GameConfig.cs#L17-L59`). This confirms ADR 0008: run-ahead and Game Boy Model can't be set per game in MesenCE, so Ludeum keeps sending them on every Play.
- **Each console has video overrides.** `ConfigOverrides` (video filter, aspect ratio) sits in `Snes`, `Gameboy`, `Nes`, `PcEngine`, `Gba`, `Ws`, `Cv`, with `Sms.ConfigOverrides` and `Sms.GgConfigOverrides` for the Sega pair (`T/UI/Config/ConsoleOverrideConfig.cs#L21-L46`).

## 2. Command line

`CommandLineHelper.ProcessCommandLineArgs`, `T/UI/Utilities/CommandLineHelper.cs#L42-L105`:

- **Files.** An argument that is an existing file (absolute, or relative to the launch directory) is a file to load: `.lua` as a script, anything else through `LoadRomHelper.LoadFile`.
- **Switches.** Otherwise, an argument starting with `-`, `--` or `/` is a switch, lower-cased after its dashes are stripped (`ConvertArg`, `#L115-L124`). So a ROM path that doesn't exist is read as a switch and reported as an invalid argument.
- **The fixed switches:**
  - `--noVideo`, `--noAudio`, `--noInput`;
  - `--fullscreen`;
  - `--enableStdout`;
  - `--doNotSaveSettings`;
  - `--loadLastSession`;
  - `--recordMovie=<file>`;
  - `--timeout=<n>` and `--testRunner` (headless Lua).
  - The help text is at `#L184-L190`.
- **`--<section>.<property>=<value>` is any settings path.** `ConfigManager.ProcessSwitch` walks the config object by property name, case-insensitive by reflection (`T/UI/Config/ConfigManager.cs#L151-L181`). It applies only when `ApplySetting` takes the type (`#L88-L149`):
  - `int`, `uint` and `double`, only when the property has a `[MinMax]` attribute. Without one, the value is ignored but still counts as success. Values out of range are refused.
  - `bool`.
  - Any enum, checked against `[ValidValues]` where present.
  - Strings, lists and objects are never set.
- **No folder can be set from the command line.**
  - The switch regex is `([a-z0-9_A-Z.]+)=([a-z0-9_A-Z.\-]+)`, so a value can't contain `/` or a space (`#L153`).
  - String properties aren't handled anyway.
  - So `--preferences.saveStateFolder=/…` can't work. `--preferences.overrideSaveStateFolder=true` would apply, but only with whatever path is already in the file.
  - The help window lists exactly what's settable this way: `GetSwichesForObject` skips strings (`T/UI/Utilities/CommandLineHelper.cs#L210-L247`).
- **`--doNotSaveSettings`** sets the static `ConfigManager.DisableSaveSettings`, and `Configuration.Save` then returns without writing (`T/UI/Config/Configuration.cs#L73-L76`).
  - It's static for the process. Once a launch (or a forwarded launch, §7) passes it, that MesenCE saves no settings until it quits. That includes changes made in its UI and its Recent files list.
  - It doesn't affect Game saves, Save states or `.rgd` files, which the core writes.
- **When overrides apply, and whether they're kept.** The switches are processed in `MainWindow.OnOpened`, after `InitializeEmu`, `InitializeDefaults` and `UpgradeConfig` and before `ApplyConfig` (`T/UI/Windows/MainWindow.axaml.cs#L235-L280`). They change the in-memory config, so without `--doNotSaveSettings` they'd be written into `settings.json` at the next save.
- **`Preferences.SingleInstance` can't be overridden per launch.** It's read in `Program.Main` before any switch is processed (`T/UI/Program.cs#L78-L83`, `T/UI/Utilities/SingleInstance.cs#L24`).
- **`AutomaticallyCheckForUpdates` can.** It's read after the switches (`T/UI/Windows/MainWindow.axaml.cs#L276-L278`).
- **Loading a Save state from the command line:**
  - **A `.mss` file argument** goes to `EmuApi.LoadStateFile` (`T/UI/Utilities/LoadRomHelper.cs#L138-L153`). That calls `SaveStateManager::LoadState(path)` straight away (`T/InteropDLL/EmuApiWrapper.cpp#L357-L360`). `LoadState` does nothing unless a game is already running (`T/Core/Shared/SaveStateManager.cpp#L157-L159`).
  - **Cold start.** A ROM loads on a background task (`LoadRomHelper.InternalLoadRom`, `#L45-L58`). So `Mesen <rom> <state.mss>` on a cold start races the state against the ROM and most likely drops it (**unverified** by running).
  - **Two-step.** Launch with the ROM, then once it's running, launch again with only the `.mss`. The second launch forwards the path (§7) and the state loads into the running game.
  - **No ROM check.** `LoadState` reads the ROM name in the state's header but never compares it. It only refuses another console type (`T/Core/Shared/SaveStateManager.cpp#L196-L202`, `T/Core/Shared/Emulator.cpp#L951-L961`). So Ludeum would have to be sure the right ROM is running.
  - **`--loadLastSession`** loads `RecentGames/<ROM stem>.rgd` once the game has loaded: the session saved when it last closed (`T/UI/Utilities/CommandLineHelper.cs#L162-L166`, `T/UI/Utilities/ShortcutHandler.cs#L105-L108`). That covers "resume", not "this slot".
  - **A Lua script** passed on the command line runs once the game has loaded (`#L131-L148`), and Lua has `emu.loadSavestate(string)` (`T/Core/Debugger/LuaApi.cpp#L1064-L1076`). Reading the file from Lua depends on Mesen's Lua I/O permission settings, **unverified**.

## 3. Data root and portable mode

- **How the home folder is chosen** (`ConfigManager.HomeFolder`, `T/UI/Config/ConfigManager.cs#L188-L212`):
  1. `Path.GetDirectoryName(Program.ExePath)` if a `settings.json` is there. That's the portable folder (`#L22`). `ExePath` is the running process's main module (`T/UI/Program.cs#L29`), so on macOS it's `Mesen.app/Contents/MacOS/`.
  2. Else `Environment.GetFolderPath(ApplicationData)/MesenCE`, which is `~/Library/Application Support/MesenCE` on macOS (`#L23-L32`).
  3. Except: if that has no `settings.json` but `…/Mesen2/settings.json` exists, the legacy `Mesen2` folder (`#L34-L41`).
- **There's no flag or environment variable.** Only `HOME` (through .NET's `ApplicationData`) moves it. Same as DuckStation.
- **First run.** With no `settings.json` anywhere, the setup wizard runs (`T/UI/Program.cs#L56-L66`). It asks:
  - user profile or portable (`ConfigManager.CreateConfig(portable)`, `T/UI/Config/ConfigManager.cs#L57-L68`);
  - default key mappings;
  - "check for updates", which sets `AutomaticallyCheckForUpdates` (`T/UI/ViewModels/SetupWizardViewModel.cs#L77-L94`).
  Then it restarts. If Ludeum writes the portable `settings.json` at Install, the wizard never shows.
- **There's a storage-folder move in the UI.** It copies the whole home folder (except `.exe`, `.dll` and extensionless files) to the other location, then renames the old `settings.json` to `settings.backup.json` (`T/UI/ViewModels/SelectStorageFolderViewModel.cs#L75-L102`). This is the in-app equivalent of making it portable.
- **Native code is unpacked into the home folder on every launch.**
  - `DependencyHelper.ExtractNativeDependencies(HomeFolder)` unpacks the `Dependencies.zip` embedded in the executable: `MesenCore.dylib`, `libSkiaSharp.dylib`, `libHarfBuzzSharp.dylib`, `MesenNesDB.txt`, `Satellaview/BSX012x-0.bin`. It skips entries under `Internal/` and rewrites any whose time or size differs (`T/UI/Utilities/DependencyHelper.cs#L14-L53`; entry list read from the 2.2.1 binary).
  - The resolver then loads `MesenCore`, `SkiaSharp` and `HarfBuzz` from the home folder (`T/UI/Program.cs#L88-L111`).
  - So **the home folder must be a local, writable disk folder, not Dropbox.** Portable puts all of this inside `Contents/MacOS/`, beside (and over) the bundle's own `libSkiaSharp.dylib` and `libHarfBuzzSharp.dylib`.
- **Writing into the bundle and the signature.** That breaks the bundle's code seal, as DuckStation's portable writes do. It loads anyway because the entitlements include `com.apple.security.cs.disable-library-validation` (and `allow-jit`, `allow-unsigned-executable-memory`), checked with `codesign -d --entitlements -` on the 2.2.1 app and in `T/UI/Mesen.entitlements`. The extracted `MesenCore.dylib` is ad-hoc, linker-signed (`codesign -dv` on this Mac's copy).
  - **Unverified:** whether Gatekeeper re-checks a never-quarantined app whose seal is broken. ADR 0024 found it doesn't for DuckStation.
- **What lives in the home folder on this Mac** (`~/Library/Application Support/MesenCE/`):
  - `settings.json`, `MesenCore.dylib`, `libSkiaSharp.dylib`, `libHarfBuzzSharp.dylib`, `MesenNesDB.txt`;
  - folders `Cheats/`, `Firmware/`, `GameConfig/`, `HdPacks/`, `RecentGames/` (14 `.rgd`), `Satellaview/`, `SaveStates/` (2), `Saves/` (7), `Screenshots/` (1), `Shaders/` (`master` only).
  - `Firmware/` holds `[BIOS] Super CD-ROM System (Japan) (v3.0).pce` and `SGB2.sfc`.
  - There's no `Mesen2` folder.

## 4. Save states

- **Folder.** `<home>/SaveStates`, or `Preferences.SaveStateFolder` when overridden (§1).
- **Name.** `<ROM file name without extension>_<slot>.mss` (`SaveStateManager::GetStateFilepath`, `T/Core/Shared/SaveStateManager.cpp#L25-L31`).
  - Slots are 1 to 10 (`MaxIndex = 10`). The automatic save state is slot 11 (`AutoSaveStateIndex = 11`). `T/Core/Shared/SaveStateManager.h#L10` and `#L23-L25`.
  - "File name" is `VirtualFile::GetFileName()`: the loose file's name, or for a ROM inside an archive, the file's name inside the archive (`T/Utilities/VirtualFile.cpp#L156-L159`).
  - Only the extension is stripped, and any folder part of the name inside the archive is dropped (`FolderUtilities::GetFilename`, `T/Utilities/FolderUtilities.cpp#L214-L221`).
  - On this Mac: `Castlevania (USA) (Rev A)_11.mss`, from `Castlevania (USA) (Rev A).7z` holding `Castlevania (USA) (Rev A).nes`.
  - No hash, no Platform, no Serial.
- **Automatic save state.** With `EnableAutoSaveState` on, the emulator thread writes slot 11 every `AutoSaveStateDelay` minutes (default 5) of emulated time (`Emulator::ProcessAutoSaveState`, `T/Core/Shared/Emulator.cpp#L171-L184`).
- **Last session.** On stopping a game (closing, or loading another), unless the game selection screen is disabled, it writes `RecentGames/<ROM stem>.rgd` (`T/Core/Shared/Emulator.cpp#L292-L295`, `T/Core/Shared/SaveStateManager.cpp#L262-L294`).
  - The `.rgd` is a zip of `Screenshot.png`, `Savestate.mss` and `RomInfo.txt`. `RomInfo.txt` holds the name inside the archive, the ROM's absolute path (with `\x01<name inside>` for an archive) and the patch path.
  - On this Mac one reads `…/Dropbox/games/OpenEmu/Game Library/roms/Nintendo (NES)/Castlevania (USA) (Rev A).7z^ACastlevania (USA) (Rev A).nes`, a path from before the move off OpenEmu.
  - Loading one opens the ROM at that stored path, then the state (`LoadRecentGame`, `#L296-L326`). So an `.rgd` breaks when its ROM moves.
  - `RecentGames` can't be relocated (§1).
- **Writes aren't atomic.** `ofstream` straight onto the slot's file (`#L85-L103`).
- **Format.**
  - Header: `"MSS"`, the emulator version (u32, `major<<16 | minor<<8 | revision`), the file format version (u32, 4 in 2.2.1), the console type (u32).
  - Then a zlib-compressed framebuffer with its width, height and scale, then the ROM file name (with extension).
  - Then the state body, written by `Serializer`.
  - `T/Core/Shared/SaveStateManager.cpp#L61-L77` and `#L115-L129`.
  - The body is a key/value map (`unordered_map<string, SerializeValue>`, `T/Utilities/Serializer.h#L80`), zlib-compressed (`T/Utilities/Serializer.cpp#L67-L99`).
  - Checked on this Mac's `Castlevania (USA) (Rev A)_11.mss`: `4D 53 53 | 01 02 02 00 | 04 00 00 00 | 02 00 00 00`, that is MSS, 2.2.1, format 4, console type 2.
- **Do older states load in newer builds?** A state is refused if its emulator version is newer than the running one, or its format is older than 3 (`MinimumSupportedVersion`) (`#L168-L178`).
  - Otherwise it loads. The key/value body tolerates added and removed fields better than DuckStation's versioned binary does, but nothing guarantees a newer core reads an older state right (**unverified** in general).
  - Every build since 2.2.0 reports version 2.2.1 (§8). So the check can't tell nightlies apart, in either direction.
- **The thumbnail.** The `.mss` framebuffer is the console's raw pixel buffer: palette indices for NES, for example. It needs Mesen's video filter to become an image (`GetSaveStatePreview`, `#L328-L374`). The `.rgd` carries a ready `Screenshot.png`. Game detail could show the latter easily and the former only by porting each console's palette/filter (**unverified** effort).

## 5. Game saves (battery)

- **Folder and name.** `<home>/Saves`, or `Preferences.SaveDataFolder`. Named `<ROM stem><extension>` (`BatteryManager::GetBasePath`, `T/Core/Shared/BatteryManager.cpp#L13-L20`). The stem is the same `VirtualFile::GetFileName()` without extension that Save states use (`Emulator::TryLoadRom`, `T/Core/Shared/Emulator.cpp#L590-L592`).
- **Extensions per console**, from every `SaveBattery`/`LoadBattery` call:

| Console | File | Contents | Source |
|---|---|---|---|
| NES / Famicom | `.sav` (PRG RAM); `.chr.sav` (battery CHR RAM); `.eeprom128` / `.eeprom256` (Bandai); `.ips` (FDS disk changes as a patch); `.battlebox.sav`, `.turbofile.sav` (peripherals) | raw | `T/Core/NES/BaseMapper.cpp#L474-L489`, `T/Core/NES/Mappers/FDS/Fds.cpp#L58-L99`, `T/Core/NES/Mappers/Bandai/Eeprom24C01.h#L34-L39` |
| SNES / Super Famicom | `.srm` (SRAM; also SA-1 I-RAM, GSU and DSP RAM when they're the battery); `.rtc` (SPC7110 RTC); `.bs` (BS-X pack); `<cart>.srm` (Sufami Turbo) | raw | `T/Core/SNES/BaseCartridge.cpp#L380-L398`, `T/Core/SNES/Coprocessors/SA1/Sa1.cpp#L912-L926`, `T/Core/SNES/Coprocessors/SPC7110/Rtc4513.cpp#L25-L52` |
| Game Boy / Game Boy Color | `.srm` (cart RAM; `.p2.srm` for the second console over link cable); `.rtc` (MBC3 clock) | raw; `.rtc` is the clock registers plus an 8-byte big-endian Unix-ms timestamp | `T/Core/Gameboy/Gameboy.cpp#L162-L175`, `T/Core/Gameboy/Carts/GbMbc3Rtc.h#L38-L77` |
| Game Boy Advance | `.sav` (SRAM 32 KiB, Flash 64/128 KiB, EEPROM 512 B/8 KiB); `.rtc` (S-3511A clock) | raw, but EEPROM's 8-byte blocks are little-endian (§10) | `T/Core/GBA/Cart/GbaCart.cpp#L160-L182`, `T/Core/Shared/Utilities/S3511ARtc.cpp#L284-L334` |
| Master System / Game Gear | `.sav` | raw cart RAM | `T/Core/SMS/SmsMemoryManager.cpp#L149-L171` |
| PC Engine CD | `.sav` | the CD unit's 2 KiB backup RAM, per Game (per cue sheet), not shared across CD Games as on hardware | `T/Core/PCE/CdRom/PceCdRom.cpp#L26`, `#L49`, `#L72` |
| PC Engine HuCard | none | no battery handling outside the CD unit | `T/Core/PCE/PceConsole.cpp` `SaveBattery`, ~L216–221 |

- **Loading.** A battery file is read raw, and `memcpy`'d up to the size the cart expects (`T/Core/Shared/BatteryManager.cpp#L78-L82`). So a longer file (one with a footer) is cut short and a shorter one zero-padded, with no error.
- **When written.** Only when the game stops: on power off or quit (`Emulator::Stop` with `saveBattery`), or before another ROM loads (`T/Core/Shared/Emulator.cpp#L286-L290` and `#L420-L423`). It's not written periodically, so a crash loses everything since the game was loaded. Plain `ofstream`, not atomic (`T/Core/Shared/BatteryManager.cpp#L32-L44`).
- **GBA save type.** Auto-detected from `SRAM_V`, `EEPROM_V`, `FLASH_V`, `FLASH512_V` or `FLASH1M_V` in the ROM, with a few game-code exceptions, else SRAM. `Gba.SaveType` overrides it (`T/Core/GBA/GbaConsole.cpp#L177-L257`).

## 6. What follows a ROM, and what loses its saves

The key for Save states, Game saves, `.rgd` resume files, `GameConfig` and screenshots is **the ROM file's name without its extension**. For a ROM in an archive, it's the name of the file inside it. Folder, archive name, hash and Platform play no part.

| Change (Ludeum terms) | What MesenCE's key does | Saves |
|---|---|---|
| **Compact** a loose `Tetris (World).gb` into `Tetris (World).7z` | Compact packs the loose file as it is (`ROMArchiver.compact`, `Sources/LudeumCore/Import/ROMArchiver.swift` ~146–160), so the name inside is `Tetris (World).gb` and the stem is unchanged | **follow** |
| **Rename** a Compacted ROM (`A.7z` → `B.7z`) | `ROMMove.rename` moves the top-level files of that name; it doesn't touch what's inside the archive (`Sources/LudeumCore/Import/ROMFolder.swift` ~206–226). MesenCE still sees the name inside, `A.gb` | **follow** (but the name inside and the ROM's name now differ for good) |
| **Rename** a loose ROM (`A.gb` → `B.gb`) | stem changes | **orphaned**, left under the old name |
| Rename of a disc ROM (PC Engine CD) | ADR 0012 renames the subfolder, not the cue sheet inside, and MesenCE keys by the cue sheet's stem | **follow** |
| **Archive** | Only disc Platforms are Archived; for MesenCE that's PC Engine CD. An Archived ROM can't be Played (Glossary), and the stem stays the cue sheet's | n/a |
| Move to another folder or Mac | path plays no part | **follow** (an `.rgd` keeps the old absolute path, and its "resume" fails until the next Play rewrites it) |
| A GBA `.sav` with a wrong save-type guess | loaded up to the wrong size | likely corrupt (**unverified**) |

Other ways to lose a Save state or Game save:

- **The same stem on another Platform** (§9).
- **A crash before quitting.** Game saves are written only at stop (§5).
- **A non-atomic write caught half-done by Dropbox or a power cut.** Every write is a plain truncate-and-write.
- **A Save state loaded into the wrong ROM.** The ROM name isn't checked (§2).

## 7. Single instance

- **How it works.**
  - `SingleInstance.Init` takes a named mutex `Global\{A46696B7-2D1C-4CC5-A52F-40BCAF094AEF}` (`T/UI/Utilities/SingleInstance.cs#L16` and `#L27-L47`).
  - The first instance listens on a named pipe of that GUID (`#L82-L111`).
  - A later launch, if `Preferences.SingleInstance` is true in *its* config, connects with a 200 ms timeout and writes each argument as a line. Existing files are sent as absolute paths. Then it exits without opening a window (`#L49-L80`, `T/UI/Program.cs#L78-L83`).
  - The receiving MesenCE runs the arguments through `CommandLineHelper` again, calls `ApplyConfig`, and loads the files (`T/UI/Windows/MainWindow.axaml.cs#L283-L294`).
  - So forwarded `--emulation.runAheadFrames=…`, `--gameboy.model=…` and `--doNotSaveSettings` all apply to the running one. That's what ADR 0008 and `App/Sources/GameDetailParts.swift` (~518, "A second MesenCE hands its arguments to the running one and quits") rely on.
- **The mutex and pipe name are fixed, not per data root.** So a Ludeum-installed portable copy and `/Applications/Mesen.app` (or any other MesenCE) would hand off to each other: a Play through the managed copy could land in the user's own copy, with its folders.
  - **Unverified:** .NET on macOS keeps named mutexes and pipes per user in temporary directories. Run under another `TMPDIR` they might not meet. Don't rely on that.
- **Implications.**
  - **A running MesenCE never re-reads `settings.json`.** Standing settings Ludeum writes before a forwarded Play don't apply until it restarts. A forwarded launch can't change a folder (§2). So any per-launch folder choice (§9) needs MesenCE not to be running.
  - **A running MesenCE launched without `--doNotSaveSettings` (an Open) rewrites the whole file on its next save**, from memory. It would put back what it read at startup, so Standing keys it read survive, but anything Ludeum wrote while it ran is lost. A forwarded Play with `--doNotSaveSettings` stops that session saving at all.
  - **Ludeum could write `Preferences.SingleInstance: false` into its managed copy.** Every Play would then be a fresh process that reads the file. But two MesenCE processes could then run at once on the same Saves, and each would still listen on the same pipe. **Unverified:** which copy then receives a forwarded launch from another MesenCE.
  - **Two choices.** Refuse Play while any MesenCE is running, as DuckStation's is refused, which also stops a Play landing in the wrong copy. Or keep the hand-off and accept that Standing settings only take effect at the next cold start. Either way, DuckStation never had this question, as it has no single-instance guard (ADR 0024).

## 8. Install

### Releases

`gh api repos/nesdev-org/MesenCE/releases`:

| Tag | Published | macOS ARM64 asset | `digest` |
|---|---|---|---|
| `2.2.1` | 2026-06-05 | `Mesen_2.2.1_macOS_ARM64_AppleSilicon.zip` (76,586,217 B) | `sha256:9c230cc25ad0bae79fed810c9eeb21c1c507b96b1ce795bbd22ca4331ffb6e48` |
| `2.2.0` | 2026-06-04 | `Mesen_2.2.0_macOS_ARM64_AppleSilicon.zip` | `sha256:8119930754ac7b3b9de60836a80d6c285d5e8275d8b5086d47a0e1541dfc7cd5` |

- **Release assets.** Each release also carries `…_macOS_x64_Intel.zip`, two Linux zips and two Windows zips.
- **The digest checks out.** I downloaded the 2.2.1 ARM64 zip, and `shasum -a 256` matched the API digest. MesenCE's own update manifest gives the same hash (§8, Updater).
- **Tags.** Only `2.2.1` and `2.2.0`. They're versioned and immutable. No rolling `latest` or `preview` tag, and no limit of thirty releases (two in five months).
- **The archived Mesen2 still keeps its 2.1.1, 2.1.0 and 2.0.0-preview1 tags.**
- **Nightlies.** These are GitHub Actions artifacts of `master`, linked from the README through nightly.link (`T/README.md` lines 20–23). Artifacts expire (GitHub's default retention is 90 days, **unverified** for this repo), so a nightly can't be pinned the way ADR 0024 pins a tag.
- **Cadence.** Mesen2 released 2.1.0 (2025-05-16) and 2.1.1 (2025-07-06). MesenCE has released only 2.2.0 and the 2.2.1 hotfix since. `master` has had dozens of commits since June: shaders, an Avalonia 12 and .NET 10 move (`40335ce73`, 2026-07-03), core fixes for NES, SNES, PCE, GG and WS. No release yet.

### The zip

- **It's a zip in a zip.** `Mesen_2.2.1_macOS_ARM64_AppleSilicon.zip` holds one entry, `Mesen.app.zip`, which holds `Mesen.app`. CI makes it with `ditto -c -k --sequesterRsrc --keepParent` (`T/.github/workflows/build.yml` ~237). So Install unpacks twice.
- **Signed, not notarised.** CI imports a certificate and signs with an identity named "Mesen", `codesign --force --deep --timestamp --options=runtime --entitlements` (`build.yml` ~215–232). There's no notarisation step.
  - The 2.2.1 app shows `Authority=Mesen`, `TeamIdentifier=not set`, `flags=0x10000(runtime)`.
  - `codesign --verify --deep --strict` passes.
  - `spctl -a` says `rejected` (`origin=Mesen`).
  - README: "Development builds are self-signed and will require approval via Gatekeeper before they are able to be run" (`T/README.md` line 41).
  - This Mac's copy carries `com.apple.quarantine` (from Chrome), so it was approved by hand.
  - Unpacked without quarantine, as ADR 0024 does, it shouldn't need approving (**unverified**: not launched).
- **SDL2.**
  - **2.2.1 needs Homebrew's SDL2.** The release notes say "For the macOS and Linux builds, SDL2 must be manually installed first" (`gh api …/releases/tags/2.2.1`). The makefile links `sdl2-config --libs` (`T/makefile` lines 21–22 and 227), and CI runs `brew install sdl2` (`build.yml` ~188). I pulled `MesenCore.dylib` out of the 2.2.1 binary's embedded `Dependencies.zip` (read-only, in the scratchpad), and `otool -L` shows **`/opt/homebrew/opt/sdl2/lib/libSDL2-2.0.0.dylib`**: an absolute Homebrew path. Without it the core dylib fails to load and MesenCE can't start (**unverified** by running).
  - **This Mac's copy, a `master` nightly, links no SDL2.** `otool -L` on its extracted `MesenCore.dylib` shows none. `master` loads SDL2 at runtime with `dlopen`, trying, in order:
    1. `libSDL2-2.0.0.dylib`
    2. `libSDL2.dylib`
    3. `SDL2.framework/SDL2`
    4. `@rpath/SDL2.framework/SDL2`
    5. `/opt/local/lib/…`
    6. `/opt/homebrew/lib/libSDL2.dylib`
    7. `/usr/local/lib/libSDL2.dylib`

    Failing all of them, it logs "[Audio] Could not load SDL2." and runs without sound (`M/Sdl/include/Sdl2.h#L48-L109`, `M/Sdl/SdlSoundManager.cpp#L21-L33`). SDL2 is only used for audio there; input on macOS is `GameController.framework` (`MacOS/MacOSGameController.mm`). The change came in `392421500`, "Added support for shaders (Windows + Linux) (#270)", 2026-09-23.
  - **Bundling SDL2 into a 2.2.1 copy** would mean rewriting the install name with `install_name_tool -change` on an extracted dylib that MesenCE re-extracts on every launch (§3). It isn't practical. With `master`'s loader, a `libSDL2-2.0.0.dylib` placed where `dlopen` searches by bare name might be found. Where that is for a NativeAOT executable is **unverified**.
  - Homebrew SDL2 2.32.10 is installed on this Mac (`brew list --versions sdl2`).
- **Which build is installed can't be checked from the outside.**
  - `Info.plist` says `1.0`. There's no `--version` switch (§2).
  - `settings.json`'s `Version` is whatever `EmuApi.GetMesenVersion()` returned at the last saved launch (`T/UI/Config/Configuration.cs#L133`), and Ludeum's `--doNotSaveSettings` Plays never save it.
  - `GetVersion()` is hard-coded to 2.2.1 on both the tag and `master` (`T/Core/Shared/EmuSettings.cpp#L161-L168`, same on `M/`).
  - The only exact identity is the commit in the embedded `Internal/BuildSha.txt` (`UpdateHelper.GetCommitHash`, `T/UI/Utilities/UpdateHelper.cs#L17-L20`): `20ba206c…` in the 2.2.1 release, **`a60e79feb4d6dcced5922d636f9211837d01e381`** in this Mac's `/Applications/Mesen.app` (a 2026-09-26 nightly, "Audio: WASAPI - Improve audio quality+latency when fast forwarding (#283)").
  - So Ludeum's 2.2.1 check passes a build that isn't 2.2.1. A managed install would have to trust the zip's digest at Install (as ADR 0024 does) and record it, since it can't ask the app.
- **Updater.**
  - With `Preferences.AutomaticallyCheckForUpdates` on, MesenCE fetches `https://raw.githubusercontent.com/nesdev-org/MesenAutoUpdate/refs/heads/main/latestversion.json` at startup. It currently names 2.2.1 with each asset's SHA-256, matching the API's digests.
  - It accepts only URLs under `github.com/nesdev-org/` or `github.com/SourMesen/`, and prompts if `LatestVersion` is newer than the running one (`T/UI/ViewModels/UpdatePromptViewModel.cs#L41-L93`, `T/UI/ViewModels/MainMenuViewModel.cs#L1152-L1178`).
  - If accepted, it downloads and checks the hash, extracts the zip's first entry into `<home>/Backups/`, and relaunches that file with `--update <src> <dest> <backup>` to replace `Program.ExePath` (`#L95-L146`, `T/UI/Utilities/UpdateHelper.cs#L22-L50`, `T/UI/Program.cs#L49-L52`). On macOS the first entry is `Mesen.app.zip`, so what that does is **unverified**: probably fails.
  - **It can be turned off by a Standing setting** (`Preferences.AutomaticallyCheckForUpdates: false`) or per launch (`--preferences.automaticallyCheckForUpdates=false`, read after the switches, §2).
  - Since every build reports 2.2.1, it won't prompt until a release past 2.2.1 exists.
- **Licence.** GPL-3.0 (`T/LICENSE`, README "Mesen is available under the GPL V3 license").
  - Ludeum downloading the upstream zip onto the user's Mac and writing its `settings.json` isn't distribution.
  - Shipping a pre-configured copy inside a Ludeum build would be allowed, provided it comes with the GPL's source and notice obligations.
  - That's unlike DuckStation's CC BY-NC-ND 4.0, which ADR 0024 found forbade a configured copy outright.

## 9. Eleven Platforms through one Emulator

MesenCE plays NES, Famicom, SNES, Super Famicom, Game Boy, Game Boy Color, GBA, Master System, Game Gear, PC Engine and PC Engine CD (`Emulator.of(platformId:)`, `Sources/LudeumCore/Emulators.swift` line 25). Ludeum has ROM folders for ten of them. PC Engine (HuCard, IGDB 86) has none in `ROMPlatform.all` (`Sources/LudeumCore/Import/ROMPlatform.swift` ~59–132).

### Settings

- **Mostly per console section.** MesenCE's settings split into console sections: `Nes` (NES and Famicom), `Snes` (SNES and SFC), `Gameboy` (GB and GBC), `Gba`, `PcEngine` (HuCard and CD), `Sms` (Master System and Game Gear, with `GgConfigOverrides` for Game Gear video), `Cv`, `Ws`. Each holds its own controllers and core options (`T/UI/Config/Configuration.cs#L31-L38`).
- **The settings Ludeum touches:**
  - **Run-ahead is global.** `Emulation.RunAheadFrames` applies to every console. Ludeum already sends it on every Play, so one Game's value never carries into another.
  - **Game Boy Model is per console.** `Gameboy.Model` covers GB and GBC (and is used when SNES runs SGB). Ludeum sends it only for Platforms 33 and 22. A forwarded GBA Play after a GB Play leaves it as the GB Play set it, which is harmless.
  - **Folders are global.** The folder keys are in `Preferences`, for all consoles (§1).
  - **Command-line overrides reach into console sections.** They walk any path (`--gameboy.model=…`, `--nes.…`, `--snes.…`), so a per-console setting can be sent per launch if it's a number, boolean or enum.
- **Per-game overrides are only DIP switches and overscan** (§1). So Ludeum keeps doing everything per launch, as ADR 0008 says.

### Folders

- **One folder each, shared by all consoles.** There's one Save state folder, one Game save folder and one Screenshots folder (`FolderUtilities::GetSaveStateFolder` etc., `T/Utilities/FolderUtilities.cpp#L69-L136`). No subfolder per console. Files are keyed by stem only (§6).
- **Stems already collide across MesenCE Platforms in today's ROM folders.** I listed the ten ROM folders (785 ROMs) and found 13 stems on more than one Platform (case-insensitive):

| Stem | Platforms |
|---|---|
| Batman - Return of the Joker (USA) | Game Boy, NES |
| Battletoads-Double Dragon (USA) | NES, SNES |
| Bionic Commando (USA) | Game Boy, NES |
| Blackthorne | GBA, SNES |
| Captain America and the Avengers (U) | NES, SNES |
| Darkwing Duck (USA) | Game Boy, NES |
| DuckTales (USA) | Game Boy, NES |
| DuckTales 2 (USA) | Game Boy, NES |
| Earthworm Jim (U) [!] | Game Boy, SNES |
| Monopoly (USA) | Game Boy, NES, SNES |
| Rampart (USA) | Game Boy Color, SNES |
| Teenage Mutant Ninja Turtles - Tournament Fighters (USA) | NES, SNES |
| Toxic Crusaders (U) | Game Boy, NES |

  - **Save states.** All 13 pairs share `<stem>_1.mss`…`_11.mss` and `RecentGames/<stem>.rgd`. Saving in one overwrites the other's slot. The automatic slot 11 and the `.rgd` are overwritten without asking on every Play. Loading the other's state is refused as the wrong system (`T/Core/Shared/Emulator.cpp#L951-L961`), but by then the first one's state is gone.
    - **Reproduced on this Mac, 2026-10-28**, with the MesenCE then installed (a nightly reporting 2.2.1) Played from Ludeum: slot 1 saved in DuckTales (USA) on NES, then in DuckTales (USA) on Game Boy, overwrote the NES state (`DuckTales (USA)_1.mss`, console type at bytes 12–15 going from `02` to `01`; values from `ConsoleType`, `T/Core/Shared/SettingTypes.h#L362-L371`).
    - **Not reported upstream that I could find.** MesenCE and Mesen2 have GitHub Issues and Discussions turned off, and their READMEs and `CONTRIBUTING.md` don't say where bugs go. Searching MesenCE's pull requests, and the issues of the archived single-console `SourMesen/Mesen` and `SourMesen/Mesen-S` (where a stem clash couldn't arise), for save state and save file naming, overwrites and per-console folders found nothing.
  - **Game saves.** Game Boy and SNES both use `.srm`, and NES, GBA, Master System, Game Gear and PC Engine CD all use `.sav` (§5). So Earthworm Jim (U) [!], Monopoly (USA) and Rampart (USA) would share one `.srm` between their Game Boy (or GBC) and SNES ROMs, if both have battery saves. NES and GBA would collide the same way on `.sav` if a stem were shared (none is today).
  - **Within a Platform pair,** e.g. a dual-mode cartridge's `Game (USA).gb` in Game Boy and `Game (USA).gbc` in Game Boy Color, the stems collide across the two folders. None does today.
  - **NES and Famicom (or SNES and Super Famicom)** with the same stem would collide too. Their region tags usually differ, but a `(World)` dump in both wouldn't. None today.
- **Can `Data/Emulators/MesenCE/` be split by Platform?** Only through `settings.json`, written before a cold start (§2, §7). The options:
  1. **One folder each** (`Save States`, `Saves`, `Screenshots`), as MesenCE has them. Simplest. Collisions stay as they are today in `~/Library/Application Support/MesenCE`. Rename could be taught to avoid a cross-Platform stem clash.
  2. **A folder per Platform**, e.g. `Data/Emulators/MesenCE/<Platform>/Save States`. Ludeum rewrites `SaveStateFolder` and `SaveDataFolder` before every Play, which needs MesenCE not running, so no hand-off. A Play while it runs would have to be refused, or MesenCE quit first. Opening MesenCE outside a Play points at whichever Platform was last written.
  3. **A folder per console section** (NES and Famicom together, and so on). Same mechanics as option 2, fewer folders, and NES/Famicom collisions would come back.
- **Single instance decides between these.** With the hand-off (today), only option 1 works. With "refuse while running", or `SingleInstance: false` plus refusal, options 2 and 3 work.

### Firmware

`FirmwareHelper`, all in `<home>/Firmware` with fixed names and exact sizes (`T/Core/Shared/FirmwareHelper.h#L94-L127`):

| Platform | File (alternative) | Size | Needed? | Source |
|---|---|---|---|---|
| GBA | `gba_bios.bin` | 16 KiB | **In practice yes.** Missing, MesenCE prompts to pick one, then runs with a zeroed BIOS. There's no high-level BIOS emulation in `Core/GBA` (no "HLE" anywhere; `SkipBootScreen` only sets registers). Games calling BIOS routines would break (**unverified** by running) | `FirmwareHelper.h#L272-L290`, `T/Core/GBA/GbaConsole.cpp#L76-L78`, `T/Core/GBA/GbaCpu.cpp#L18` |
| Game Boy | `dmg_boot.bin` (`gb_bios.bin`) | 256 B | No: a built-in boot ROM is used | `FirmwareHelper.h#L229-L269`, `T/Core/Gameboy/Gameboy.cpp#L101-L108` |
| Game Boy Color | `cgb_boot.bin` (`gbc_bios.bin`) | 2,304 B | No (built-in) | same |
| Super Game Boy (GB/GBC with Model SGB, or SGB-enhanced) | `SGB1.sfc` / `SGB2.sfc`, plus `sgb_boot.bin` / `sgb2_boot.bin` (`sgb_bios.bin`) | cart size; 256 B | Yes for SGB mode | `FirmwareHelper.h#L208-L226` |
| PC Engine CD | `[BIOS] Super CD-ROM System (Japan) (v3.0).pce` (`syscard3.pce`) | 256 KiB | **Yes** | `FirmwareHelper.h#L332-L342` |
| PC Engine CD (Games Express) | `[BIOS] Games Express CD Card (Japan).pce` (`gecard.pce`) | 32 or 16 KiB | Yes, for those discs | `#L352-L361` |
| Master System / Game Gear | `bios.sms` / `bios.gg` | any | No: loaded only if present | `#L369-L379` |
| Famicom Disk System | `disksys.rom` (`FdsBios.bin`) | 8 KiB | Yes for `.fds` | `#L292-L306` |
| SNES coprocessor games | `dsp1.rom` and others, `st018.rom`, `BS-X.bin`, `SufamiTurbo.sfc` | various | Only for those carts | `#L129-L200` |

- **This Mac's `Firmware/`** holds the Super CD-ROM System v3.0 card and `SGB2.sfc`, and no `gba_bios.bin`.
- **The prompt copies a chosen file in.** When a file is missing, MesenCE asks for one and copies it into `<home>/Firmware` under the expected name (`T/UI/Utilities/FirmwareHelper.cs` ~95–103). In portable mode that's inside the bundle.
- **A managed copy would need one of these:**
  - a symbolic link `Contents/MacOS/Firmware` → `Data/Emulators/MesenCE/Firmware`. `GetFolder` only checks `Directory.Exists`, which follows links. **Unverified** by running.
  - or Ludeum copying firmware in from the Data folder at Install and before each launch;
  - or keeping firmware out of the Data folder entirely (it isn't now: it's in `~/Library/Application Support/MesenCE`).

### Formats per console

Covered in §4 and §5:

- **Save states** share one format and naming for every console. The console type is in the header and is checked at load.
- **Game save extensions** differ by console: `.sav` for NES, GBA, SMS, GG and PCE CD; `.srm` for SNES and GB. Clocks are separate `.rtc` files for GB MBC3, GBA and SPC7110, not footers.
- **PC Engine CD backup RAM** is per Game (per cue sheet), not one shared BRAM.

### Blast radius

- **One pin, eleven Platforms.** One pin and one Install gate Play on all eleven. A bad build stops NES through PC Engine CD at once, where a DuckStation regression stopped only PlayStation.
- **It has happened.** 2.2.0 broke iNES ROMs on NES and Famicom, and 2.2.1 followed the next day: release notes "2.2.1 contains a hotfix for iNES ROMs", the fix being `eaab6b1a7`, "NES: Fix CHR-RAM for iNES ROMs when using the database. (#165)" (`gh api repos/nesdev-org/MesenCE/compare/2.2.0...2.2.1`).
- **`master`'s pace adds risk.** It's moving fast, with core changes across NES, SNES, PCE, GG and WS in September and October and a UI framework swap. A bump to the next release changes every Platform at once.
- **Per-Platform pins aren't practical.** One app is one data root, so two pinned builds would be two installs with two data roots.

### Game detail: ROM to its files

- **The stem is the whole key.** Save states are `<SaveStates>/<stem>_<1–11>.mss`, the resume file `RecentGames/<stem>.rgd`, Game saves `<Saves>/<stem>.<ext>` (extension by console, §5), screenshots `<Screenshots>/<stem>_<NNN>.png`.
  - The stem is the ROM's file stem: the name inside its `.7z` for a Compacted ROM, which after a Rename isn't the ROM's name (§6), and the cue sheet's stem for a disc ROM.
  - So Ludeum needs the name inside a `.7z` (from its listing), not just the ROM's name.
- **The Platform** is needed only to choose which Game save extensions to look for. It can't tell two Platforms' files apart when the stem is shared, unless the folders are split per Platform (option 2 above).
- **What a Save state shows.** Each `.mss` header gives the console type and the ROM's full file name, which Ludeum could use to warn about a collision. The `.rgd` has a PNG screenshot. A `.mss` has only a raw framebuffer (§4).

## 10. OpenEmu carry-over

What's in the Data folder's `OpenEmu Battery Saves archive/` for MesenCE's Platforms (sizes read from disk):

- **Gambatte** (Game Boy and Game Boy Color): 37 `.sav`, every one exactly 8,192 or 32,768 bytes.
- **mGBA** (GBA): 20 `.sav`: 9 of 0 bytes, 5 of 512, one of 8,192, two of 32,768, two of 65,536, one of 131,072.
- **SNES9x**: 18 `.sav` of 1, 2, 8, 32 or 128 KiB.
- **Nestopia**: empty.

None is a power of two plus a few bytes, so none carries a clock footer.

### By core

- **Game Boy / Game Boy Color (Gambatte → MesenCE): compatible, rename `.sav` to `.srm`.**
  - MesenCE reads cart RAM raw from `<stem>.srm`, up to the cart's size (§5).
  - Final Fantasy Adventure is the MBC2 case, 512 4-bit cells. Gambatte's 8 KiB file has the data in the first 512 bytes as low nibbles, and `0xFF` after. MesenCE's MBC2 uses 512 bytes and forces the high nibble to `F` (`T/Core/Gameboy/Carts/GbMbc2.h#L14-L22` and `#L51-L55`). So it reads correctly.
  - Clocks: none of the archived saves has an `.rtc`, and MesenCE's MBC3 `.rtc` layout is its own (registers plus a timestamp, `GbMbc3Rtc.h#L38-L77`). A clock game would start with a reset clock (**unverified** how Gambatte stores its clock; none here needs it).
  - Already in MesenCE on this Mac: `Survival Kids (U) [C][!].srm`. It differs from the archived Gambatte file, as it has been played in MesenCE since (it's on #76's list as not yet brought across).
- **SNES (Snes9x → MesenCE): compatible, rename `.sav` to `.srm`.**
  - MesenCE reads `_saveRamSize` raw from `.srm` (`T/Core/SNES/BaseCartridge.cpp#L380-L386`).
  - **Unverified:** Super Mario RPG's 128 KiB file against MesenCE's SA-1 BW-RAM size, which would read only the first part.
  - Two archive names have a trailing ` - 1` or ` - 2`. One has a doubled `.sav.sav`. They need the ROM's stem.
- **GBA (mGBA → MesenCE): flash and SRAM compatible as they are. EEPROM isn't.**
  - **Flash.** Both keep 128 KiB flash as one flat array with bank 1 at `0x10000`: MesenCE's `_saveRam[_selectedBank | (addr & 0xFFFF)]` (`T/Core/GBA/Cart/GbaFlash.h#L58`) and mGBA's `currentBank = &data[bank << 16]` (`OE/src/gba/savedata.c#L609-L618`). SRAM is raw on both. So the two Games left on #76's list are copy-and-rename:
    - Advance Wars (Europe): 64 KiB, flash.
    - Pokémon LeafGreen: 128 KiB, flash.
  - **EEPROM.** The 512 B and 8 KiB files are THPS 2, THPS 3 (G), Scooby-Doo, Alien Hominid and the rest, but none of these is on #76's list. Each 64-bit block is stored in the opposite byte order on the two sides:
    - mGBA writes data bit *n* of a block into byte `addr*8 + n/8`, bit `7 - n%8`. The first bit received is the top bit of byte 0 (`OE/src/gba/savedata.c#L509-L525`, read back the same way `#L545-L568`).
    - MesenCE shifts the 64 bits into a `uint64_t` and stores it low byte first, so the first bit received is the top bit of byte 7 (`T/Core/GBA/Cart/GbaEeprom.h#L59-L72` and `#L108-L125`).
    - Converting means reversing each 8-byte block. That's from reading both sources; I haven't tested a file.
  - **Clocks.** mGBA appends an RTC buffer to an RTC game's `.sav` (`GBASavedataRTCWrite`, `OE/src/gba/savedata.c#L591-L615`). MesenCE keeps the clock in `.rtc` and would ignore the extra bytes (§5). None of the archived files has one.
  - **The 0-byte files** have nothing to bring across.
- **NES (Nestopia)**: nothing archived.
- **Save states: none will load.**
  - MesenCE refuses anything that doesn't start `MSS` ("SaveStateInvalidFile", `T/Core/Shared/SaveStateManager.cpp#L165-L167` and `#L221`).
  - OpenEmu's are `.oesavestate` bundles holding the core's own state. The Game Boy one I checked, `GameBoy/Mario's Picross (USA, Europe) (SGB Enhanced)/Auto Save State.oesavestate/State`, starts `00 01 00 00 00 61 …`: Gambatte's format.

## 11. Mapping ADR 0024 onto MesenCE

| ADR 0024 (DuckStation) | MesenCE | Notes |
|---|---|---|
| Pinned versioned tag and SHA-256 in code; fetch from the main repo, else `old-releases` | **Same, simpler** | Tags `2.2.0` and `2.2.1` are immutable, and the API gives a `digest`. There's no rolling tag and nothing ages off, so no fallback repo. But there's only one release to pin, 2.2.1, and it needs Homebrew SDL2. `master`, which doesn't, has no release and its nightlies can't be pinned (§8). |
| Unpack without quarantine | **Same, with two unzips** | Zip inside a zip (`Mesen.app.zip`). Signed with its own identity, not notarised. |
| Confirm the build with `-version` | **Not possible** | No version switch. Every build says 2.2.1. Only the embedded `Internal/BuildSha.txt` identifies a build. Options: trust the digest at Install and record it, or read `BuildSha.txt` out of the binary's resource (fragile). |
| Portable: `portable.txt` in `Contents/MacOS` | **Same idea, different file** | A `settings.json` in `Contents/MacOS` makes it portable. Writing it at Install also skips the setup wizard. Seed it with `ConfigUpgrade: 1` (or copy an existing file) so default controls are filled in (§1). MesenCE also unpacks its core dylib and two others into `Contents/MacOS` on every launch (§3). |
| At `Emulators/DuckStation.app` in the Ludeum folder | **Same** | `Emulators/Mesen.app` (its bundle name), or renamed `MesenCE.app` (**unverified** whether anything depends on the bundle name; nothing in the source paths does). |
| Standing settings: absolute paths for every folder worth keeping, under `Data/Emulators/DuckStation/` | **Partly** | Settable, each as `Override…Folder: true` plus an absolute `…Folder`: `Save States` (`SaveStateFolder`), `Saves` (`SaveDataFolder`), `Screenshots` (`ScreenshotFolder`), optionally `Movies`. **Not settable:** `Firmware` (needed for GBA and PC Engine CD), `RecentGames` (resume sessions), `Cheats`, `GameConfig`. Those need a symbolic link from the data root (**unverified**), a copy in and out, or to stay in the bundle (§1, §9). |
| Standing settings: auto-update off | **Same** | `Preferences.AutomaticallyCheckForUpdates: false`. Also settable per launch. |
| Standing settings written before every launch, into an INI | **Different file, same approach, one caveat** | JSON with BOM, PascalCase keys, string enums, written whole. Change only the keys Ludeum owns and keep the rest. A running MesenCE ignores it, so it takes effect only at a cold start (§7). |
| `settings.ini` can't be linked out of the bundle (renamed over) | **Probably linkable, not worth it** | MesenCE writes in place (`File.WriteAllText`), so a link would survive. But the data root also holds the unpacked dylibs, so it can't move to Dropbox anyway. |
| Refuse Play while any DuckStation runs (no single-instance guard) | **A choice** | MesenCE has a single-instance hand-off shared with any other copy. Refusing keeps per-launch folders possible (option 2 in §9) and stops a Play landing in `/Applications/Mesen.app`. Keeping the hand-off (ADR 0008 today) keeps "Play while it's open", but fixes the folders for the session. |
| Per-game file for the Game's own settings | **Not applicable** | MesenCE has no per-game emulation settings. Run-ahead and Game Boy Model stay command-line switches on every Play (ADR 0008). |
| Game detail lists Save states, Plays from one, deletes one | **Mostly** | Listing and deleting by `<stem>_<n>.mss` (and `RecentGames/<stem>.rgd`), with the name inside a Compacted `.7z` as the stem. **Play from a state:** there's no cold-start switch for a slot. Options: launch the ROM and then forward the `.mss` once it's running (a two-step, timing **unverified**); `--loadLastSession` for the resume state only; or a Lua script (**unverified**). |
| Game detail shows Game saves | **Same, by extension per console** | `<Saves>/<stem>.{sav,srm,rtc,…}` (§5). The time written is the file's modification time, written only when the game stops. |
| Saves keyed by Serial (survive Rename) | **Different** | Keyed by file stem. They follow Compact, and Rename of a Compacted ROM. **Renaming a loose ROM orphans them** (§6). Rename could move the matching files, or rename the file inside the archive too, or neither. |
| One Platform | **Eleven** | Shared folders and stem collisions (13 today), one pin for every Platform (§9). |
| Writes atomic (temporary file then rename), so Dropbox never sees half a file | **Different** | Save states, Game saves and `settings.json` are all truncate-and-write. A Dropbox sync mid-write or a crash can leave a partial file. |
| Licence CC BY-NC-ND forbids a configured copy | **Different, permissive** | GPL-3.0. |
| Move over by hand once, with a script | **Same pattern** | Move `~/Library/Application Support/MesenCE/{SaveStates,Saves,Screenshots}` into the Data folder, and `settings.json`, `Firmware`, `RecentGames`, `Cheats`, `GameConfig` and `HdPacks` into the managed copy's data root (or the Data folder, for Firmware). `.rgd` files hold stale absolute ROM paths (`…/Dropbox/games/OpenEmu/…`) and won't resume until replayed. |

## Open questions for the design session

1. **Which build to pin?** 2.2.1, which needs Homebrew SDL2 and is the only release, or wait for the next release, which on `master`'s evidence won't need SDL2? Or pin a nightly by downloading the artifact once and keeping it somewhere Ludeum controls, which is unlike ADR 0024's "a bump is the tag and digest in code".
2. **Refuse Play while any MesenCE runs, or keep the hand-off?** This decides whether Standing settings can change per Play (per-Platform folders) and whether a Play can land in another copy.
3. **One folder for all Platforms, or one per Platform (or per console section)?** The 13 stem collisions today are the cost of one folder. A per-Platform split needs question 2 answered "refuse".
4. **Firmware.** Is it Data folder material (as DuckStation's `BIOS` is)? If yes, does Ludeum link `Contents/MacOS/Firmware` into it (**unverified**) or copy it in? PC Engine CD can't Play without its System Card, and GBA effectively needs its BIOS.
5. **RecentGames (resume).** Does it belong in the Data folder? It's MesenCE's resume-on-start mechanism. It can't be pointed anywhere, and its files carry absolute ROM paths.
6. **Play from a Save state.** Is a two-step (launch, wait for the game, forward the `.mss`) acceptable, or is Play-from-state only "resume" (`--loadLastSession`) for MesenCE?
7. **Rename.** Should Rename of a loose MesenCE ROM also rename its Save states and Game saves, or rename the file inside the archive when Compacting? Or leave them, as DuckStation's Serial-keyed saves never needed?
8. **Version check.** With no way to ask the app, does a managed install record the digest it installed and stop reading `settings.json`'s `Version`?
9. **Seeding `settings.json`.** Start from the existing `~/Library/Application Support/MesenCE/settings.json` (controls already mapped, 230 KB), or a minimal seed with `ConfigUpgrade: 1`?
10. **Non-atomic writes in a Dropbox folder.** Accept them (one Mac at a time, as ADR 0024 already assumes), or keep Game saves local and copy them in and out around each Play?
11. **GBA EEPROM saves from OpenEmu.** None is on #76's list. Is the byte-swap worth a tool, or are they left archived?

### Side findings (outside #82)

- **PC Engine CD formats.** Ludeum's PC Engine CD ROM folder reads `m3u` and `chd` as ready (`Sources/LudeumCore/Import/ROMPlatform.swift` ~122–124), but MesenCE opens only `.pce`, `.cue`, `.sgx` and `.hes` for PC Engine (`T/Core/PCE/PceConsole.h#L51`). Both PC Engine CD ROMs today are Archived `.7z`.
- **No PC Engine ROM folder.** `Emulator.of` sends PC Engine (86) to MesenCE, but there's no PC Engine ROM folder.
