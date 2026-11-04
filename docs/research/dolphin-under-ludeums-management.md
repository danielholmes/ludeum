# Dolphin under Ludeum's management

Researched 2026-11-04 for issue #83. The question: can Ludeum manage Dolphin as ADR 0024 manages DuckStation, 0027 MesenCE, 0028 ares and 0032 PCSX2 (install a pinned build, keep it apart from any other copy, write Standing settings that put its Save states and Game saves in the Data folder, refuse Play while it runs, list and Play from Save states in Game detail, show a Game's Game saves)? Where does Dolphin keep its Save states, memory cards and Wii NAND, what does it name them by, what loses one, and what can be moved without moving everything? This note builds on [wii-emulator.md](wii-emulator.md) (2026-10-06) and the Dolphin row of [managing-emulators-inside-ludeum.md](managing-emulators-inside-ludeum.md) (2026-10-28), rechecked here against pinned commits. It lays out the facts and the options. It doesn't make the decision.

Sources:

- **Dolphin source** at tag `2609`, commit `f84df02055ab9610feec48e65648cac5a3c098fa` (2026-09-23). That's the version Ludeum expects (`EmulatorVersionSpec(expected: "2609")`, `Sources/LudeumCore/EmulatorVersions.swift` line 64), and the commit in `/Applications/Dolphin.app`'s `CFBundleLongVersionString`. Links like `T/Source/Core/Core/State.cpp#L306-L310` mean `https://github.com/dolphin-emu/dolphin/blob/f84df02055ab9610feec48e65648cac5a3c098fa/Source/Core/Core/State.cpp#L306-L310`.
- **Dolphin tag `2609a`**, commit `409881c34357d0f105fd473167d15ab0bd9c1628` (2026-10-07), the newest release: 11 commits on `2609`, diffed. None touches the code cited here. The nearest is `Source/Core/Common/ChunkFile.h` (bounds checks on state pointers, with no format change).
- **Dolphin `master`** at `df4bd441dec5d6f3cff606eea76f183963e97a44` (2026-11-02), 173 commits past `2609`. The files cited were diffed. Of those, `State.cpp` and `MainWindow.cpp` changed in ways near this note (the selected slot moved into `State`, a locale fix), `STATE_VERSION` is still 192, and the other changes don't touch anything cited (GBA audio keys, a `Sounds` folder under `Load`, NetPlay's GCAdapter handling, a rounding helper). No path key or save-on-exit was added, so no `M/` links are needed.
- **Thirteen other tags**, read for `STATE_VERSION` only (§4).
- **`dolphin-emu/sadm`** at `3465813deb5cf00bc1966c9ea9b79c9deb3b3cf4` (2026-11-02), the build and signing configuration. Links like `S/roles/buildbot/etc/master.cfg#L498-L528` mean `https://github.com/dolphin-emu/sadm/blob/3465813deb5cf00bc1966c9ea9b79c9deb3b3cf4/roles/buildbot/etc/master.cfg#L498-L528`.
- **`weisslj/cpp-optparse`** at `2265d647232249a53a03b411099863ceca35f0d3`, Dolphin's option parser submodule at `2609`, for `--version`.
- **The release artifacts**, downloaded into the session scratchpad and inspected with `hdiutil` mounted read-only, `codesign`, `spctl`, `stapler`, `plutil` and `lipo`, then detached. Never run.
  - `https://dl.dolphin-emu.org/releases/2609/dolphin-2609-universal.dmg`: 41,965,559 bytes, SHA-256 `b8910a6f8710cbe93b916f5b3867a46e67e49aa8272657d282d4accae359cd6b`.
  - `https://dl.dolphin-emu.org/releases/2609a/dolphin-2609a-universal.dmg`: 42,010,379 bytes, SHA-256 `9a810043538f21b53cf8f8f747b1672df74895d3d6eb30940d96042823f20ecb`.
- **`dl.dolphin-emu.org`**, by `HEAD` request, for which builds are still there (§12).
- **This Mac**, read without changing or launching anything: `/Applications/Dolphin.app`, `~/Library/Application Support/Dolphin`, the Ludeum folder, the Data folder's `Emulators/` and `ROMs/`, `journal.sqlite` with `sqlite3 -readonly`, and the first bytes of the Discs in the three GameCube archives Dropbox holds locally.
- **Ludeum's code** on `main` at commit `466e232`.

`https://dolphin-emu.org/download/` answered HTTP 403 to `curl` and to the fetch tool, so the download page wasn't read this time; the bug tracker and wiki were not tried, as the earlier note found them behind the same bot check. Nothing of Dolphin's was run, so what the code implies at run time is marked "from code". Anything not checked against one of these sources is marked **unverified**.

## Answer

**Yes for Game saves and for the install, with one thing that no other managed Emulator has had: Save states have no setting. Dolphin's `StateSaves` folder can only follow the whole user folder (`-u`, `DOLPHIN_EMU_USERPATH`) or be a directory link.** Eight facts shape the design:

1. **There's no key for Save states.** `D_STATESAVES_IDX` is set in one place, as `<user>/StateSaves/` (`T/Source/Core/Common/FileUtil.cpp#L852`), and nothing calls `SetUserPath` on it. `InitCustomPaths` reads keys only for the NAND, Load, Dump, resource packs, WFS, the SD image and GBA (`T/Source/Core/UICommon/UICommon.cpp#L102-L118`). The same goes for `GameSettings`, `ScreenShots`, `Config` and `Cache`. So the choices are the whole user folder in the Data folder, or a user folder outside it with links for what has no key (§2, §14).
2. **Game saves do have keys, and `-C` can set them for one launch.** `[General] NANDRootPath` moves the Wii NAND and `[Core] GCIFolderAPath` (with `GCIFolderBPath`, `MemcardAPath`, `MemcardBPath`) the GameCube cards. Dolphin can be told all of it on the command line without writing `Dolphin.ini`, as ADR 0035 does for Amiberry (§2).
3. **Portable mode is a `portable.txt` beside the app, and the user folder is then `User/` beside it.** `Emulators/Dolphin/Dolphin.app` with `Emulators/Dolphin/portable.txt` makes `Emulators/Dolphin/User/`. Nothing Dolphin writes goes in the notarised bundle unless its updater runs (§1, §3).
4. **A Save state is `<game ID>.s01` to `.s10`, keyed by the disc's six-character ID, with no screenshot.** Its header holds the game ID, when it was saved, the state version and the build's name, all readable without unpacking. It loads only if the state version is exactly the build's, which changed in seven of the last nine quarterly releases (never in a hotfix), from 168 in 2407 to 192 in 2609. The one undo file, `lastState.sav`, is shared by every game (§4).
5. **A GameCube Game's Card saves are files.** Dolphin's default device is the GCI folder, one `<maker>-<gamecode>-<name>.gci` per save, with a 64-byte header and in a folder per region. A Game's Card saves are the files whose first four bytes are the first four of its game ID. Nothing has to parse a card image (§6).
6. **A Wii Game's Game save is one folder**, `title/<type>/<8 hex digits of the ID's first four characters>/data/`, with a `banner.bin` holding its name, description, banner and icon. But the NAND root is also where a `.wad` is installed to boot it, so a NAND in the Data folder holds a copy of whichever WAD last ran (§7).
7. **A ROM's game ID needs reading, and `dolphin-tool` isn't in the app.** It's the first six bytes of an `.iso`, offset `0x58` of an `.rvz` or `.wia`, inside the TMD of a `.wad`. Nothing in Ludeum reads it yet. A Disc 2 has the same ID as its Disc 1 and differs only in byte 6 (read off this Mac's three two-disc ROMs), so its Save states share a name and a state doesn't say which Disc it was saved on (§5, §10).
8. **There's no Resume state.** Dolphin saves nothing on closing, and no key or flag asks it to. `-s <file>` starts a Play from any state file (§10).

The rest:

- **Install.** Not on GitHub. A dmg (UDBZ, HFS+) at a versioned URL, Developer ID signed and notarised, with the ticket stapled to the dmg and not to the app inside. No checksum file beside it, so the digest would be computed by whoever pins it. Every release back to `2407` is still there. Universal, arm64 included (§12).
- **Self-update** is skipped by `-b`, and `[AutoUpdate] UpdateTrack` empty turns it off. It writes into the bundle in place (§3).
- **This Mac has nothing to bring across.** One 11-second boot of Castlevania ReBirth on 2026-10-06 left no `.gci`, no state and an empty Wii `data` folder (§13).
- **All 17 GameCube ROMs are Archived `.7z`s**, which Dolphin can't open, and the 4 Wii ROMs are loose `.wad`s. 14 of the 17 archives and all 4 WADs are evicted to Dropbox online-only (§13).

## 0. Which repository

- **`dolphin-emu/dolphin`**, default branch `master`, GitHub Issues off, no GitHub Releases (the API lists none). The API's licence is `NOASSERTION`, but `Readme.md` lines 6-7 say GPLv2+, source files carry `SPDX-License-Identifier: GPL-2.0-or-later` and the bundle's `NSHumanReadableCopyright` says "Licensed under GPL version 2 or later (GPLv2+)". The bundle ID is `org.dolphin-emu.dolphin`, which `Emulator.dolphin` looks up today (`Sources/LudeumCore/Emulators.swift` line 11).
- Tags are `<yymm>`, with `a` for a hotfix: 2606, 2606a, 2609, 2609a.

## 1. User folder and portable mode

`UICommon::SetUserDirectory` (`T/Source/Core/UICommon/UICommon.cpp#L304-L482`) decides it once at startup, in this order on macOS:

1. **`-u <path>`** beats everything (`#L306-L311`), and the folder is made if missing.
2. **`./Contents/Resources/User`** relative to the working directory, if it exists (`#L402-L405`, `T/Source/Core/Common/CommonPaths.h#L27-L29`). A launch from `NSWorkspace` doesn't have its working directory in the bundle (**unverified** what it is; nothing else in Ludeum depends on it).
3. **`portable.txt` in `GetExeDirectory()`** gives `<that folder>/User/` (`#L435-L439`). `GetExePath()` on macOS is the bundle, untranslocated (`T/Source/Core/Common/FileUtil.cpp#L721-L733`, `#L675-L718`), and `GetExeDirectory()` its parent (`#L755-L758`). Only the file's existence counts; its contents aren't read, unlike PCSX2's.
4. **`DOLPHIN_EMU_USERPATH`** (`UICommon.cpp#L440-L443`). So a `portable.txt` beats the environment variable.
5. **`$HOME/Library/Application Support/Dolphin/`** (`UICommon.cpp#L444-L448`, `T/Source/Core/Common/CommonPaths.h#L16-L17`).

So **`Emulators/Dolphin/Dolphin.app` with `Emulators/Dolphin/portable.txt`** gives `Emulators/Dolphin/User/`, as `Emulators/PCSX2/` works for PCSX2 and `Emulators/ares/` for ares.

**`Sys` comes from the bundle** whatever the user folder is: `Contents/Resources/Sys` (`T/Source/Core/Common/FileUtil.cpp#L772`), holding `GameSettings` (1,880 shipped game inis), `wiitdb-*.txt` (the titles), the Wii files copied into a NAND on boot and so on.

## 2. Settings: what has a key

`Config/Dolphin.ini` is a plain INI of sparse keys: only what differs from the code's defaults, 16 lines on this Mac. Every key can also be given for one launch as `-C Main.<Section>.<Key>=<Value>` (§11).

Every path in the user folder is computed in `RebuildUserDirectories` (`T/Source/Core/Common/FileUtil.cpp#L838-L917`). Outside that file `SetUserPath` is called by `InitCustomPaths`, by the Paths and Wii settings panes through the same keys, by the `-u` line, for the session NAND (`T/Source/Core/Core/WiiRoot.cpp#L221-L225`) and on the Linux XDG branch. So the table's keys are all there are.

| Under the user folder | What it holds | Key that moves it | Worth keeping? |
|---|---|---|---|
| `StateSaves/` | Save states | **None** | Yes |
| `GC/<region>/Card A/` | GCI folder memory card | `[Core] GCIFolderAPath`, `GCIFolderBPath` (`T/Source/Core/Core/Config/MainSettings.cpp#L104-L105`), or `GCIFolderAPathOverride`, `GCIFolderBPathOverride` (`#L116-L119`) | Yes |
| `GC/MemoryCardA.<region>.raw` | Raw memory card, if a slot is set to one | `[Core] MemcardAPath`, `MemcardBPath` (`#L80-L81`) | Yes, if used |
| `GC/SRAM.raw` | GameCube system settings, 68 bytes | None (`D_GCUSER_IDX` isn't settable on macOS) | Rebuilt from a default when missing (`T/Source/Core/Core/HW/Sram.cpp#L33-L48`) |
| `Wii/` | The NAND: saves, installed titles, SYSCONF, Miis | `[General] NANDRootPath` (`#L335`) | Yes |
| `Load/WiiSD.raw` | Wii SD card image | `[General] WiiSDCardPath` (`#L336`), `WiiSDCardSyncFolder` (`#L337-L338`) | If a game uses it (§9) |
| `GameSettings/` | Per-game inis (ADR 0029's shape) | **None** | Yes |
| `ScreenShots/` | Screenshots | **None** | Others are kept (ADR 0024) |
| `Load/` | Textures, Riivolution, graphics mods | `[General] LoadPath` (`#L333`) | Packs supplied by hand |
| `Dump/` | Dumps | `[General] DumpPath` (`#L332`) | No |
| `ResourcePacks/` | Resource packs | `[General] ResourcePackPath` (`#L334`) | Supplied by hand |
| `WFS/` | Dolphin's emulated WFS storage | `[General] WFSPath` (`#L339`) | Empty here; which games use it wasn't looked into |
| `GBA/Saves/` | GBA link saves | `[GBA] SavesPath` (`#L408`) | If GBA link is used (§9) |
| `Config/` | `Dolphin.ini`, `GFX.ini`, `GCPadNew.ini`, `GCKeyNew.ini`, `WiimoteNew.ini`, `Qt.ini`, `TimePlayed.ini`, controller `Profiles/` (`T/Source/Core/InputCommon/InputConfig.cpp#L153`) | **None** | Controls yes, the rest is Dolphin's own |
| `Cache/` | Game covers, RetroAchievements, shader UID caches | **None** on macOS (only the Linux XDG path sets it, `UICommon.cpp#L473-L475`) | Rebuildable |
| `Backup/`, `Logs/`, `Maps/`, `Shaders/`, `Styles/`, `Themes/`, `Triforce/`, `SavedAssembly/` | Dolphin's own | **None** | No |

So for what matters, three things have no key: **`StateSaves`, `GameSettings` and `ScreenShots`**.

### The GameCube card keys

- **`GCIFolderAPath` set** gives `<path>/<region>`, the region as `USA`, `EUR`, `JPN` or `DEV`, replacing a region already on the end of the path (`T/Source/Core/Core/Config/MainSettings.cpp#L848-L902`). The default layout is different: `GC/USA/Card A`, `GC/EUR/Card A`, `GC/JAP/Card A`, with the legacy `JAP` (`#L851-L858`, `#L738-L739`). So the keyed layout is one level shorter and spells Japan's differently (`JPN`, `JAP`).
- **`GCIFolderAPathOverride` set** is used exactly as given, with no region added and no migration from a raw card (`T/Source/Core/Core/HW/EXI/EXI_DeviceMemoryCard.cpp#L153-L156`). So a per-launch `-C Main.Core.GCIFolderAPathOverride=<folder>` could hand a Game a card of its own, as ADR 0023 did for DuckStation.
- **`MemcardAPath` set** gives `<dir>/<name>.<region>[.<blocks>].raw`, the region put in or replaced (`#L776-L836`).
- **The slots.** `[Core] SlotA` defaults to the GCI folder, `SlotB` to nothing (`#L133-L136`). `SlotA` isn't set on this Mac, so the default applies, and `GC/USA/Card A` exists though no GameCube game has run: the device is created on a Wii boot too (`T/Source/Core/Core/HW/EXI/EXI.cpp#L144-L145`).

### Links instead of keys

From code, not run:

- **A directory link works where a file link doesn't.** Dolphin writes every INI to `<file>.xxx` and renames it over (`T/Source/Core/Common/IniFile.cpp#L319-L353`, `T/Source/Core/Common/FileUtil.cpp#L665-L672`), and every state to a temporary name in the same folder then renames it (`T/Source/Core/Core/State.cpp#L397-L409`, `#L461`). A link at `User/StateSaves` to a folder keeps both ends on the target's volume. A link at `Config/Dolphin.ini` would be replaced by the first save, as ADR 0024 found for DuckStation's `settings.ini`.
- **Making directories is safe.** `CreateFullPath` calls `fs::create_directories` and accepts any path where `fs::is_directory` holds, which follows links (`T/Source/Core/Common/FileUtil.cpp#L228-L242`). `UICommon::CreateDirectories` asks for `StateSaves`, `GameSettings`, `ScreenShots`, `GC/…` and the rest at every launch (`T/Source/Core/UICommon/UICommon.cpp#L264-L302`), so a link already there stays.
- **A dangling link is the failure.** With the Data folder gone, `create_directories` fails and logs only, and then a state fails with "Failed to create state file" on screen (`State.cpp#L409-L414`). Ludeum's `checkData()` already refuses a Play then.
- **Precedent:** the Data folder itself is a link (ADR 0010), and ADR 0027 turned a link for MesenCE's firmware down only because it can be set up again.

## 3. `Dolphin.ini`: reading, writing, first run

- **Loaded at startup, layered.** Search order, first found wins: CurrentRun, Netplay, Movie, LocalGame (user's game ini), GlobalGame (shipped game ini), CommandLine, Base (`T/Source/Core/Common/Config/Enums.h#L39-L47`). So a game ini beats `-C`, and `-C` beats `Dolphin.ini`. `-C` is added first, then `UICommon::Init` adds Base (`T/Source/Core/DolphinQt/Main.cpp#L185`, `#L196`, `UICommon.cpp#L136`). `InitCustomPaths` is a config-changed callback, so it runs with both layers present and again on any change (`UICommon.cpp#L131-L136`). That answers the earlier note's "should take effect" for `-C Main.General.NANDRootPath`, from code.
- **Written on change and at exit, atomically, merged.** `Config::Save` runs at main window destruction (`T/Source/Core/DolphinQt/MainWindow.cpp#L369`), when the settings window closes (`T/Source/Core/DolphinQt/Config/SettingsWindow.cpp#L216`) and from `SConfig::SaveSettings`. Each layer saves only when dirty (`T/Source/Core/Common/Config/Layer.cpp#L82-L89`). The base saver reads the file back in, sets every key it holds in memory over it, and renames `Dolphin.ini.xxx` into place (`T/Source/Core/Core/ConfigLoaders/BaseConfigLoader.cpp#L179-L231`). A key Ludeum adds during a run that Dolphin didn't load survives; a key Dolphin loaded is overwritten with its old value at the next dirty save. So writing only while Dolphin isn't running is the same rule as DuckStation's.
- **`-C` is never saved.** The layer's `Save` does nothing (`T/Source/Core/UICommon/CommandLineParse.cpp#L71-L74`).
- **Single instance: none.** Nothing in `DolphinQt`, `UICommon` or `Common` uses `QLockFile`, `QLocalServer`, `QSharedMemory` or a flock (grepped at `2609`), and a comment in `State.cpp#L399-L400` allows for "multiple instances of dolphin operating on the same user folder". Ludeum launches with `createsNewApplicationInstance = true` (`App/Sources/GameDetailParts.swift` line 498), so a Play today opens a second Dolphin beside a running one. `/Applications/Dolphin.app` and a managed copy have the same bundle ID, so `Emulator.isRunning` (`App/Sources/EmulatorVersionChecks.swift` line 310) would see either.
- **First run with no file.** Defaults come from code, with no setup wizard. A missing `Dolphin.ini` isn't an error (`BaseConfigLoader.cpp#L156-L157` loads and goes on), so a seeded file needs only Ludeum's keys. On this Mac one boot left default keyboard mappings in `GCPadNew.ini`, `GCKeyNew.ini` and `WiimoteNew.ini` without any seeding, unlike PCSX2's first-run controls.
- **Analytics prompt.** A modal dialog shows on the first launch unless `[Analytics] PermissionAsked` is true, batch mode included (`T/Source/Core/DolphinQt/Main.cpp#L281-L299`). `[Analytics] Enabled` defaults to false (`MainSettings.cpp#L453`). On this Mac `PermissionAsked = True` with no `Enabled`, so it's off.
- **Self-update.** `Main.cpp#L301-L306` starts the checker only when not in batch mode, and it does nothing for an empty track (`T/Source/Core/UICommon/AutoUpdate.cpp#L209-L210`). `[AutoUpdate] UpdateTrack` empty is the "disabled" choice in Dolphin's own settings (`T/Source/Core/DolphinQt/Settings/GeneralPane.cpp#L40`). What a macOS release's default track is, is **unverified**: `GeneralPane.cpp#L258-L259` calls `beta` "the default config value on Dolphin release builds", but sadm passes `DOLPHIN_DEFAULT_UPDATE_TRACK=beta` only in the Windows factory (`S/roles/buildbot/etc/master.cfg#L257`, `#L280`) and not in the universal macOS one (`#L452-L461`), though it does write macOS update manifests (`#L595-L603`). `[AutoUpdate] UpdateTrack =` settles it either way, as `IniFile::ParseLine` gives an empty value (`T/Source/Core/Common/IniFile.cpp#L25-L36`).
- **The updater writes into the bundle in place.** Its install base is `GetExeDirectory()`, the bundle's parent (`AutoUpdate.cpp#L287`), and it runs a relocated copy of `Contents/Helpers/Dolphin Updater.app` (`AutoUpdate.cpp#L58`, `#L294-L305`). Otherwise nothing in Dolphin writes inside the bundle: `Sys` is read and every write goes through `GetUserPath`.

## 4. Save states

- **Named by game ID and slot, in `StateSaves`.** `<game ID>.s<nn>`, slots 1 to 10 (`T/Source/Core/Core/State.cpp#L306-L310`, `T/Source/Core/Core/State.h#L23`). The game ID is `SConfig::GetGameID()`: a disc's six characters, or a WAD's title code and group ID (§5). On this Mac Dolphin's own per-game keys show `WD9EA4` for Castlevania ReBirth (`Config/TimePlayed.ini`, `Cache/WD9EA4.uidcache`), so a state of it would be `WD9EA4.s01`.
- **Any path works for a state,** through Load State/Save State File (`*.sav *.s??`, `T/Source/Core/DolphinQt/MainWindow.cpp#L1514`, `#L1526`) and `-s`. Only slots are tied to the folder.
- **The header, little-endian, needs no unpacking** (`State.h#L25-L51`, `#L61-L67`, written at `State.cpp#L370-L390`):

| Offset | Size | What |
|---|---|---|
| `0x00` | 6 | Game ID, not terminated |
| `0x08` | 4 | `lzo_size`, 0 for any modern state |
| `0x10` | 8 | When saved: a double, seconds since Unix time less `38*365*86400` (`#L284`, `#L294-L297`) |
| `0x18` | 4 | Version cookie, `0xBAADBABE + STATE_VERSION` (`#L108`, `#L377`) |
| `0x1C` | 4 | Length of the build string |
| `0x20` | n | The build string (`Common::GetScmRevStr()`, for example `Dolphin 2609`, `T/Source/Core/Common/Version.cpp#L28-L41`) |
| then | 16 | Extended header: compression type (1 is LZ4), uncompressed size |
| then | | LZ4 blocks |

  So Ludeum could show when a state was saved and whether this build can load it, reading 64 bytes. Dolphin's own slot menu shows that time (`#L611-L624`).
- **No screenshot.** There's none in the header or beside the file. A picture would mean decompressing the state and decoding emulated video memory, which wasn't looked into. ADR 0028 accepted the same for ares.
- **Sidecars.** `<state>.dtm` exists only when a movie was recording (`#L449-L453`). Ordinary play has none, and an old `.dtm` of that name is deleted.
- **Undo.** Saving over a slot first renames its file to `lastState.sav` (and `.dtm`), deleting the one there (`#L426-L447`). So it's **one file across every game and slot**, not a slot's Previous as DuckStation's `.bak` and PCSX2's `.backup` are. Its header says whose it is, but not which slot. Undo Load State lives only in memory (`#L815-L825`), and `undo.dtm` only for movies.
- **Written under a temporary name.** To `<state><thread id>.tmp` on a worker thread, then the old file moved aside and the new one renamed in (`#L397-L409`, `#L431-L447`, `#L461`). Rename is atomic, though a crash between the two renames leaves the slot empty with its old state in `lastState.sav`. A failed write shows only a two-second message (`#L410-L414`, `#L423-L424`).
- **Version-locked, exactly.** A state loads only when its version equals the build's (`#L726-L729`); the build string isn't compared ("We don't require an exact revision string match", `#L711`). It's also refused for another game's ID (`#L701-L708`). `STATE_VERSION` by tag:

| Tag | Date | `STATE_VERSION` |
|---|---|---|
| 2407, 2409 | 2024-07-02, 2024-09-04 | 168 |
| 2412 | 2024-12-01 | 169 |
| 2503, 2503a | 2025-03-10, 2025-04-21 | 170 |
| 2506, 2506a | 2025-06-04, 2025-06-05 | 174 |
| 2509, 2512 | 2025-09-15, 2025-12-21 | 175 |
| 2603, 2603a | 2026-03-11, 2026-03-17 | 177 |
| 2606, 2606a | 2026-06-24, 2026-08-10 | 191 |
| **2609**, 2609a | 2026-09-23, 2026-10-07 | 192 |
| `master` | 2026-11-02 | 192 |

  So of the nine steps between quarterly releases, seven changed it (all but 2407 to 2409 and 2509 to 2512), and no hotfix did. Fourteen of the bumps came between 2603 and 2606 alone (Triforce support and the rest). A bump past a change orphans every state, as for ares (ADR 0028). The constant has a comment naming the PR, `// Last changed in PR 14646`.
- **A state doesn't carry Game saves.** A GameCube card's contents go in a state only when a movie is recording (`T/Source/Core/Core/HW/EXI/EXI_DeviceMemoryCard.cpp#L498-L519`), and a Wii state holds the NAND's `/tmp` only, the rest only for a movie on a temporary NAND (`T/Source/Core/Core/IOS/FS/HostBackend/FS.cpp#L296-L346`). So loading an old state doesn't roll back a Game save, nor does a save made since go with the state. If a state's card header differs from the current one, the GCI card is re-created with the state's header (`T/Source/Core/Core/HW/EXI/EXI_Channel.cpp#L266-L286`).
- **Size** wasn't measured: there are no states on this Mac. It'd be tens of MB each, LZ4-compressed, from the emulated memory sizes (**unverified**).
- **Refused in** NetPlay and RetroAchievements hardcore mode (`#L209-L219`).

## 5. A ROM's game ID

Glossary note: the glossary's **Serial** avoids the words "game ID", and defines Serial only for PlayStation discs. Dolphin's own name is used here until the design says whether this is a Serial (open question 3).

- **A disc.** The first six bytes of its header (`T/Source/Core/DiscIO/VolumeDisc.cpp#L19-L60`), byte 6 the disc number (`#L177-L180`), byte 7 the revision (`#L144-L148`). `0x1C` holds GameCube's magic, `C2339F3D`, and `0x18` Wii's (`T/Source/Core/DiscIO/Volume.cpp#L121-L124`). Region is a `u32` in the disc: `0x458` on GameCube (`T/Source/Core/DiscIO/VolumeGC.cpp#L108`), `0x4E000` on Wii (`T/Source/Core/DiscIO/VolumeWii.cpp#L332`).
- **Read off this Mac's three archives that are local**, through `7zz e -so`:

| Disc | Bytes 0-5 | Byte 6 | Byte 7 | Region at `0x458` |
|---|---|---|---|---|
| Resident Evil (USA) (Disc 1) | `GBIE08` | 0 | 0 | 1 |
| Resident Evil (USA) (Disc 2) | `GBIE08` | 1 | 0 | 1 |
| Resident Evil Zero (USA) (Disc 1) | `GBZE08` | 0 | 0 | 1 |
| Resident Evil Zero (USA) (Disc 2) | `GBZE08` | 1 | 0 | 1 |
| Metal Gear Solid: The Twin Snakes (Europe) (Disc 1) | `GGSPA4` | 0 | 0 | 2 |
| Metal Gear Solid: The Twin Snakes (Europe) (Disc 2) | `GGSPA4` | 1 | 0 | 2 |

  So **a Disc 2 has its Disc 1's ID.** Revisions share an ID too: `Data/Sys/GameSettings` has `GALE01r0.ini`, `GALE01r1.ini`, `GALE01r2.ini` for one ID. So a Rev 1 and a Rev 2 ROM of a game would share Save states and Card saves.
- **What a running game goes by** is that unencrypted ID for a disc (`T/Source/Core/Core/ConfigManager.cpp#L190-L200`), and its TMD's for a WAD (`#L407-L426`). A Wii disc's game partition has its own copy, and Dolphin's verifier reports a disagreement between the two as a problem, but for an oddity like the Wii Backup Disc (`T/Source/Core/DiscIO/VolumeVerifier.cpp#L868-L880`), so they agree on a good dump.
- **Through the forms Ludeum reads as ready** (`Sources/LudeumCore/Import/ROMPlatform.swift` lines 103-107):
  - `.iso`, `.gcm`: at offset 0.
  - `.rvz`, `.wia`: magic `RVZ\x01` or `WIA\x01` (`T/Source/Core/DiscIO/WIABlob.h#L40-L41`), then a `0x48`-byte header 1, a 16-byte start of header 2, then the first `0x80` bytes of the disc uncompressed, so the ID is at **`0x58`** (`T/Source/Core/DiscIO/WIABlob.h#L81-L119`). The region isn't within those `0x80` bytes.
  - `.ciso`: a `0x8000`-byte header with a block map (`T/Source/Core/DiscIO/CISOBlob.h#L17-L29`), so the ID is at `0x8000` when the map's first block is used.
  - `.wbfs`: `hd_sector_shift` at byte 8 gives the HD sector size, and the disc header's copy starts the second HD sector, as Dolphin seeks past it there (`T/Source/Core/DiscIO/WbfsBlob.h#L70-L78`, `WbfsBlob.cpp#L38-L40`; from code).
  - `.gcz`: a 32-byte header, `num_blocks` of `u64` pointers and `u32` hashes, then blocks, zlib unless the pointer's top bit is set (`T/Source/Core/DiscIO/CompressedBlob.h#L33-L41`, `CompressedBlob.cpp#L34`, `#L54-L57`). So the first block needs inflating.
  - `.7z`: streamed through 7-Zip as `PlayStationDisc` does (ADR 0021, 0032). In a two-Disc solid archive Disc 2's first bytes come after all of Disc 1, so reading them means decompressing that first.
- **A WAD.** Big-endian sizes at `0x00` (header), `0x08` (certs), `0x10` (ticket), `0x14` (TMD), each section aligned to `0x40` (`T/Source/Core/DiscIO/VolumeWad.cpp#L35-L46`). In the TMD the title ID is at `0x18C` and the group ID at `0x198` (`T/Source/Core/Core/IOS/ES/Formats.h#L65-L89`). This Mac's installed Castlevania ReBirth TMD has `00010001 57443945` at `0x18C`, `WD9E`. The game ID is the title code's four characters then the group's two, or the 16 hex digits of the title ID when they aren't alphanumeric (`T/Source/Core/Core/IOS/ES/Formats.cpp#L295-L305`).
- **`dolphin-tool` can't be used from a release.** `header -j` prints all of this (`T/Source/Core/DolphinTool/HeaderCommand.cpp#L73-L108`), and the build option defaults on (`T/CMakeLists.txt#L97`), but neither the 2609 nor the 2609a app holds it: `Contents/MacOS` has only `Dolphin`, `platforms` and `styles`. Nor is it in the dmg outside the app. Whether Dolphin publishes it separately for macOS is **unverified**.
- **Nothing in Ludeum reads one yet.** `Serials.platforms` is PlayStation and PlayStation 2 (`Sources/LudeumCore/Serials.swift` line 61). In the journal all 21 GameCube and Wii ROM rows have `serialsLookedUp = 0` and no `serials`. `grep` of `Sources` finds no disc header or `boot.bin` reader for Nintendo discs.

## 6. GameCube memory cards and Game saves

### The GCI folder, Dolphin's default

- **One file per save** in the card's folder, named `<maker>-<gamecode>-<filename>.gci` from its header, escaped for the file system (`T/Source/Core/Core/HW/GCMemcard/GCMemcardDirectory.cpp#L42-L62`). A number is inserted before `.gci` if the name is taken (`#L654-L657`).
- **The header is 64 bytes, then blocks of `0x2000`** (`T/Source/Core/Core/HW/GCMemcard/GCMemcard.h#L89`, `#L104`, `#L239-L310`):

| Offset | Size | What |
|---|---|---|
| `0x00` | 4 | Game code, the game ID's first four characters |
| `0x04` | 2 | Maker code |
| `0x07` | 1 | Banner format and icon animation |
| `0x08` | 32 | The save's file name on the card |
| `0x28` | 4 | Last modified, big-endian seconds since 2000-01-01 |
| `0x2C` | 4 | Image data offset |
| `0x30` | 2 | Icon formats |
| `0x32` | 2 | Animation speeds |
| `0x34` | 1 | Permissions |
| `0x35` | 1 | Copy counter |
| `0x38` | 2 | Length in blocks |
| `0x3C` | 4 | Offset of the two comments in the data |

  The comments are two 32-byte strings at that offset of the save's data (`T/Source/Core/Core/HW/GCMemcard/GCMemcard.cpp#L512-L539`), Shift JIS on a Japanese card and CP1252 otherwise: the title and description the game gave the save. So a **Card save** here shows a title, an icon, a size and when it was written, as a PlayStation card's do.
- **Listing one Game's saves.** Dolphin itself filters on the header's game code (`GCMemcardDirectory.cpp#L209`, and the NetPlay helper `GetFileNamesForGameID`, `#L126-L178`). So a Game's Card saves are the `.gci` files in the region folders whose first four bytes match, regardless of file name. The region needn't be known: the fourth character already differs by region (`GGSP` against the US disc's `GGSE`, both shipped game inis). The maker code doesn't enter the filter. The file name's second field says the same unless someone renamed the file; the header is what Dolphin goes by.
- **Every game's saves are loaded into the virtual card.** The current game's first, then others while under 112 files and over 10% blocks free (`#L229-L247`). Filtering to the current game alone is a session setting that only NetPlay sets (`T/Source/Core/Core/ConfigLoaders/NetPlayConfigLoader.cpp#L200`). Only changed saves are written back (`#L626-L716`). A card holds 127 files (`GCMemcard.h#L98`) and 2,043 blocks unless a game ini sets a smaller `MemoryCardSize` (`T/Source/Core/Core/HW/EXI/EXI.cpp#L123-L126`; 8 shipped inis do).
- **Written in place, not atomically.** One second after the last write, and at stop, each changed save is opened `"wb"`, which truncates it, and written (`GCMemcardDirectory.cpp#L261-L296`, `#L665-L671`). A crash between truncating and finishing loses that save. A save the game deletes is renamed `<name>.gci.deleted`, replacing any earlier one (`#L691-L700`), so one is recoverable by hand.
- **Migration.** If the folder doesn't exist (and no override is set), the slot's raw card, if any, is exported into it as `.gci`s (`T/Source/Core/Core/HW/EXI/EXI_DeviceMemoryCard.cpp#L186-L193`, `GCMemcardDirectory.cpp#L739-L761`).
- **A duplicate loses silently.** Two files with the same game code, maker and internal name: the first found is loaded and the second skipped with a log line (`#L66-L77`). Files are searched sorted by path (`T/Source/Core/Common/FileSearch.cpp#L92`). From code, a Dropbox conflicted copy, `Name (conflicted copy).gci`, sorts before `Name.gci` (a space before a dot), so it would be the one a game sees, and later writes go to it. Not run.

### The raw card

- `GC/MemoryCardA.USA.raw`, 16 MB at 2,043 blocks, held in memory. Written whole, in place (`"r+b"`), every 15 seconds if dirty and at exit (`T/Source/Core/Core/HW/GCMemcard/GCMemcardRaw.cpp#L103-L153`). Dropbox would see 16 MB on each flush, and a crash inside the 15 seconds loses them.
- A Game's saves are in it: blocks 0 to 4 are the header, two directories and two allocation tables (`GCMemcard.h#L95`), a directory being those same 127 64-byte entries with an update counter choosing the active one (`#L316-L329`), the data elsewhere by block. So reading one is realistic (the entry format is the GCI header), but a table's more work than a directory listing. No card here is raw.

## 7. The Wii NAND and Game saves

- **The save of a title** is `<NAND root>/title/<type>/<id>/data/` (`T/Source/Core/Common/NandPaths.cpp#L63-L72`), lower-case hex of the 64-bit title ID's halves. The low half is the four-character title code. The high half is the type (`T/Source/Core/Core/IOS/ES/Formats.h#L33-L41`): `00010000` a disc game, `00010001` a downloaded channel (WiiWare, Virtual Console), `00010004` a disc game with a channel, `00010005` DLC.
- **A disc game** gets its `data` folder from `ES::DIVerify` when it boots (`T/Source/Core/Core/IOS/ES/ES.cpp#L868-L873`), under the title ID in its partition's ticket (`VolumeWii.cpp#L270-L276`). A game ID's first four characters normally give the low half, and `00010000` or `00010004` the high. Reading the ticket would settle which, or a listing of both does. Which of Ludeum's future Wii discs would use `00010004` is **unverified**; there are no Wii discs in the ROM folder.
- **A WAD** is under `00010001/<low half>`, and its TMD gives it (§5). This Mac has `title/00010001/57443945/` with `content/` and an empty `data/`.
- **One save folder per title.** So a Wii Game's Game save is one folder, not a list of Card saves. Its file names are the game's.
- **`banner.bin`** in `data` is what the Wii Menu shows: "WIBN", flags, then at `0x20` a name and at `0x60` a description, 32 UTF-16BE characters each, then a 192x64 RGB5A3 banner and 48x48 icons from `0xA0` (`T/Source/Core/DiscIO/WiiSaveBanner.h#L16-L37`, `WiiSaveBanner.cpp#L18-L46`). A game may not have written one yet (**unverified** how often). The newest modified file in the folder would stand for "last written".
- **Writes.** A game's files are host files opened `"r+b"` and written in place (`T/Source/Core/Core/IOS/FS/HostBackend/File.cpp#L47`); the NAND's `fst.bin`, holding metadata, goes through a temporary file and rename (`FS.cpp#L206-L232`). So not atomic for one file, though Wii games commonly write to `/tmp` and rename (**unverified** for any game here), and a rename is a host rename (`FS.cpp#L529`).
- **The rest of the NAND.** `shared2/sys/SYSCONF` (console settings, and `IPL.TID`), `shared2/wc24`, Miis at `shared2/menu/FaceLib/RFL_DB.dat`, `sys/`, `ticket/`, `shared1/`, `meta/`, `tmp/`, and files at its root such as `fst.bin` and, for a Wiimote, its EEPROM copies (`T/Source/Core/Core/HW/WiimoteEmu/WiimoteEmu.cpp#L84`, `#L153`). `SysConf` reads through the NAND's own file system, so it moves with `NANDRootPath`. And Dolphin copies `Sys/Wii/shared2` into any NAND at boot, not overwriting (`T/Source/Core/Core/WiiRoot.cpp#L283-L317`, `#L329`).
- **One quirk with a moved NAND**, from code: `UICommon::Init`'s first line, `RestoreWiiSettings(CrashRecovery)`, runs before `InitCustomPaths` (`UICommon.cpp#L128-L136`). So after a crash, the backed-up `setting.txt` and SYSCONF (`Backup/`, `WiiRoot.cpp#L257-L278`) are restored into `<user>/Wii/`, not the configured root. It costs a game-ini override that stays in SYSCONF, not a save.

### The WAD case

`CBoot::Boot_WiiWAD` installs the WAD as a temporary title and boots it (`T/Source/Core/Core/Boot/Boot_WiiWAD.cpp#L33-L41`). In `WiiUtils::InstallWAD` (`T/Source/Core/Core/WiiUtils.cpp#L146-L198`):

- The same contents already there, hash-checked: the install is skipped (`#L157-L166`).
- **A different version of that title installed: a modal "Installing this WAD will replace it irreversibly. Continue?" during the Play** (`#L170-L180`), and it's then not temporary (`#L192-L195`).
- The previous temporary title's `.app` files are deleted (`#L183-L184`, `T/Source/Core/Core/IOS/ES/TitleManagement.cpp#L635-L652`). **Its `title.tmd`, ticket and `data` stay.** So WiiWare saves survive switching games, as the earlier note said.
- So a NAND root holds the content of the last WAD run: 33 MB of this Mac's 35 MB NAND is Castlevania ReBirth. With the NAND in the Data folder, each switch between WADs deletes one's `.app`s and writes another's, 16 to 38 MB in this library, into Dropbox, of bytes already in `ROMs/Wii`.
- A DLC WAD can't boot: "This WAD is not bootable" (`ConfigManager.cpp#L414-L418`, as `00010005` isn't a channel).

## 8. Through Archive, Compact and Rename

Everything is keyed by what's inside the disc or WAD, never its file's name or form.

- **Rename** (ADR 0012): states, cards, NAND saves and per-game inis all follow, with nothing for Ludeum to move. A disc ROM's playlist names files relative to itself, as ADR 0031 has it.
- **Archive and Unarchive** (`.7z`): Dolphin has no archive reader (`T/Source/Core/DiscIO/Blob.cpp#L230-L242` lists the formats), so an Archived ROM can't be Played, as now. Its saves wait under its ID, and apply again on Unarchive.
- **Compact**: not offered for GameCube or Wii (`ROMPlatform.swift` lines 101-107 have `archiving: .singleFile`, no `compactExtension`).
- **RVZ, WIA, GCZ, ISO conversion**: the disc's header is kept, so the same ID. **Unverified** by running. A state from an unscrubbed image loaded on a scrubbed one is the same disc as far as the game reads it (**unverified**).
- **A WAD**: Rename changes nothing, and the title's `data` stays, though its `.app`s are replaced when another WAD runs (§7).
- **Another dump of the same game**: another region's is another ID, another Game's files. A revision is the same ID, so shares them (§5).

## 9. What else loses one

- **A `STATE_VERSION` bump** orphans every state (§4). Dolphin says "created using the incompatible version <build>", on screen, for a few seconds. The file stays.
- **A different revision** of a game's disc loads the other's state, as only the ID is compared (`State.cpp#L701-L708`). Whether it then runs is **unverified**.
- **`lastState.sav`** keeps only the latest overwritten state of any game (§4).
- **A crash mid-write**: a `.gci` is truncated then rewritten, a raw card's flush is delayed up to 15 seconds, NAND files are written in place (§6, §7). INIs and states are renamed in.
- **The user folder moving** (`-u`, `portable.txt` added or removed): Dolphin only looks in one root. Absolute keys avoid that for what they cover, but not for what has no key.
- **Region.** A USA and a PAL disc of a game use separate folders, so a save isn't shared between them. On a real console neither would it be. A `MAIN_FALLBACK_REGION` is used for discs with an unknown region (`ConfigManager.cpp#L489-L490`).
- **Dropbox online-only.** Images and saves go through ordinary file calls, so card and NAND files and ROMs would stall if evicted, as for DuckStation, and the folders would need marking available offline (ADR 0024). A game list pointed at a ROM folder finds every Dolphin format in it (`T/Source/Core/UICommon/GameFileCache.cpp#L31-L36`), not `.7z`, and opening each to list it would hydrate it (**unverified** how much of each it reads).
- **Wii SD card.** `Load/WiiSD.raw` (`[General] WiiSDCardPath`; on by default, `[Core] WiiSDCard`, `MainSettings.cpp#L205`) holds anything a game saves to SD, and it isn't under the NAND. Only some games use it (**unverified** for this library). With `[Core] WiiSDCardEnableFolderSync` it's also packed from and unpacked to a folder around each boot (`T/Source/Core/Core/Core.cpp#L548-L553`).- **GBA link.** `GBA/Saves` holds what a linked GBA core saves, and has its key. Four Swords Adventures is in the library, but only uses it if GBA link is set up by hand (**unverified** whether it would be).
- **The updater**, if it ran, replacing the pinned files in the bundle (§3).
- **Dolphin's own NetPlay or a movie** uses `WiiSession` and `RedirectSession` temporaries under the user folder, deleted at the end, and backs up one if present (`WiiRoot.cpp#L206-L245`). Ludeum starts neither.

## 10. Starting from a state, and Resume

- **`-s <file>` / `--save_state`** (`T/Source/Core/UICommon/CommandLineParse.cpp#L102-L106`) is carried in the boot's session data (`T/Source/Core/DolphinQt/Main.cpp#L211-L227`) and loaded by the CPU thread once booted (`T/Source/Core/Core/Core.cpp#L344-L349`). The file isn't deleted. It's refused without a game (`Main.cpp#L251-L257`). Any path; it needn't be in `StateSaves`. It works with `-b`: nothing in that path looks at batch mode. It's applied to whatever was booted, and a state of another game's ID is refused with an on-screen message and the game then runs fresh (from code, §4).
- **Wrong Disc.** `DVDThread::DoState` says it: the disc isn't in a state, and "This won't catch cases of having the wrong disc inserted" (`T/Source/Core/Core/HW/DVD/DVDThread.cpp#L77-L84`). A state's header has no disc number. So a Save state made on Disc 2 is named as if for either Disc, and an `.m3u` boot starts on Disc 1 (`T/Source/Core/Core/Boot/Boot.cpp#L217-L232`). Loading it there would have the game read Disc 1 where it expects Disc 2. What happens then is **unverified**, not having run it. `-e` taking several files makes `-e Disc2.iso -e Disc1.iso` a way to boot Disc 2 first, keeping the auto-change between them (`Boot.cpp#L196-L232`; §11), but Ludeum couldn't tell from the file which Disc a state wants. Comparing the state's save time with what Ludeum recorded of the last Disc, or asking, are the only handles.
- **No Resume state.** There's no save on stop, close or quit: grep of `Source/Core` for save-on-exit or auto-save names finds only the debugger's branch watch. The nearest things are the hotkeys Load Last State 1 to 10 (`LoadLastSaved`, sorted by the header's time, `State.cpp#L915-L934`, `T/Source/Core/Core/HotkeyManager.cpp#L323`), Save Oldest State (`SaveFirstSaved`, `State.cpp#L936-L953`) and Undo Load State. A Standing setting can't make one. A Game's latest slot by time is what Ludeum could read, which is the player's own choice, not Dolphin's. ADR 0034 already says Dolphin keeps none it reads.

## 11. `-b`, `-C`, game inis, multi-disc

- **`-e`** is repeatable (`CommandLineParse.cpp#L87-L91`), `.m3u` and `.m3u8` are read with paths relative to themselves, with a panic alert for a missing file (`Boot.cpp#L64-L108`, `#L217-L228`).
- **`Main.Core.AutoDiscChange`**: when the game stops the drive and there's a list, the next one goes in at most half a second later (`T/Source/Core/Core/HW/DVD/DVDInterface.cpp#L1136-L1142`, `#L519-L527`), wrapping round. Default false (`MainSettings.cpp#L282`). No game ini shipped sets it. The list is from `-e`, an `.m3u` or the game list's second disc (`T/Source/Core/DolphinQt/MainWindow.cpp#L1127-L1136`).
- **`-b` / `--batch`** hides the main window (`MainWindow.cpp#L238-L241`), turns Render to Main off (`CommandLineParse.cpp#L37-L40`), skips the update check (`Main.cpp#L301-L306`) and quits when emulation stops (`MainWindow.cpp#L934-L939`). It needs `-e` or `-n` (`Main.cpp#L258-L264`). Today's Play doesn't use it, so a main window sits behind the game and stays when the game stops. Whether the macOS menu bar and its Options, Controllers and Graphics items remain usable with the main window hidden is **unverified**, and it matters: ADR 0027 has an Emulator's own settings changed during a Play. **Game Properties** (the per-game settings) opens only from a right-click in the game list (`T/Source/Core/DolphinQt/GameList/GameList.cpp#L429`), which `-b` hides, and which holds nothing here as `[General] ISOPaths` is unset.
- **Confirm on Stop** defaults on (`[Interface] ConfirmStop`, `MainSettings.cpp#L437`): stopping asks Yes or No (`MainWindow.cpp#L975-L1040`). `-b` doesn't change that. `-c` is declared (`CommandLineParse.cpp#L117`) but nothing reads it at `2609`.
- **Today's `-C` keys against Standing settings** (`Sources/LudeumCore/Emulators.swift` lines 69-72; `Main.Core.RushFramePresentation`, `SmoothEarlyPresentation`, `AutoDiscChange`, `MainSettings.cpp#L55-L58`, `#L282`):
  - As `-C`: never saved, beat `Dolphin.ini`, so a change in Dolphin's settings has no effect during a Ludeum Play. A per-launch list keeps `Dolphin.ini` free of Ludeum's writes, and the "only while not running" rule doesn't apply to them.
  - As Standing keys in `Dolphin.ini`: a change in Dolphin's settings lasts until the next Play, as DuckStation's did before ADR 0033.
  - Neither beats a game ini. None of the 1,880 shipped inis sets any of these three keys (grepped at `2609`), nor `SlotA`, `MemcardAPath`, `GCIFolderAPath` or `NANDRootPath`. A user's own could.
  - ADR 0033 lists Dolphin's latency settings among those that are still Ludeum's.
- **`-C` limits.** The format is `<System>.<Section>.<Key>=<Value>`: the system ends at the first dot, the section at the second, the key at the first `=`, and the value at the next `=` (`CommandLineParse.cpp#L45-L60`), so a value with `=` in it is cut there. An unknown system is dropped silently. Paths with spaces are fine in `argv`; Ludeum's have no `=`.
- **Game inis** (`T/Source/Core/Core/ConfigLoaders/GameConfigLoader.cpp#L33-L59`): for ID `GALE01`, `G.ini`, `GAL.ini`, `GALE01.ini`, `GALE01r<rev>.ini`, in that order, each overriding the last. `Sys/GameSettings` is the global layer (`#L188-L191`), `GameSettings/` in the user folder the local one (`#L195-L196`). Saving a local layer writes `<id>r<rev>.ini` if that exists, else `<id>.ini` (`#L283-L325`). They take any `[Core]`, `[Video_*]` or `[Main.Section]` key (`#L108-L119`, `#L127-L156`), and they also hold cheats and patches.
- **Per-game settings in the Data folder (ADR 0029's shape)** means `GameSettings/` is there. It has no key, so it's a directory link, or the whole-folder option (§14). Its `.xxx` rename works through a directory link. A local ini is keyed by ID and revision, so Rename doesn't affect it.
- **Version.** `--version` is the parser's: it prints `GetScmRevStr()` (`CommandLineParse.cpp#L83`; `OptionParser.cpp` lines 290-291, 376-378 at `weisslj/cpp-optparse` `2265d64`) and `std::exit(0)` inside `parse_args`, before `SetUserDirectory`, so from code it writes nothing, though `QApplication` is already made (`Main.cpp#L182-L194`). Not run here. `CFBundleShortVersionString` gives the same with no process, which is what Ludeum reads (`EmulatorVersions.swift` line 64).

## 12. Install

### Releases

- **Where.** `https://dl.dolphin-emu.org/releases/<ver>/dolphin-<ver>-universal.dmg` (`S/roles/buildbot/etc/master.cfg#L538-L539`). Dev builds: `https://dl.dolphin-emu.org/builds/<aa>/<bb>/dolphin-<branch>-<rev>-universal.dmg`, with `<aa>` and `<bb>` the first bytes of the SHA-256 of the file's name (`#L119-L127`, `#L541-L542`, `#L549-L550`).
- **Nothing has aged off that was tried.** `HEAD` got 200 for every release from `2407` to `2609a` (`Last-Modified` from 2024-07-02), and for dev builds `master-2609-61` and `master-2412-1`. `Last-Modified` of 2609 is 2026-09-24. Whether dev builds are ever removed is **unverified**.
- **Cadence.** Roughly quarterly since `2407`: 2407, 2409, 2412, 2503, 2506, 2509, 2512, 2603, 2606, 2609, with hotfixes 2503a, 2506a, 2603a, 2606a, 2609a one day to seven weeks later. Dev builds are every merged change.
- **No checksum beside it.** `<dmg>.sha256` is a 404; the ETag is size and time, not a digest. sadm's `send_build.py` posts only the commit hash and URL (`roles/buildbot/etc/send_build.py` lines 20, 35-54). Whether the download page shows a checksum is **unverified** (it's 403 here), though it didn't come up in the earlier note. So the digest in code would be computed from the download, as Ludeum's other dmg (ADR 0035) took GitHub's. Update manifests hash a build's files, and are signed, not the dmg (`#L595-L603`).
- **2609 or 2609a.** Same `STATE_VERSION` and same paths. The eleven commits are game inis, NetPlay input checks, FIFO and state bounds checks, a `MemArenaDarwin` change, a crash in the assembler and Android. 2609a's `CFBundleShortVersionString` is `2609a` and its `CFBundleVersion` `2609.1`.

### The dmg

- **Made by** `hdiutil create -format UDBZ -fs HFS+` of `Dolphin.app` and an `Applications` link, volume `Dolphin <ver>` (`#L470-L506`), so `hdiutil attach` reads it. `AmiberryInstall` already mounts a dmg unseen and copies out with `ditto` (`Sources/LudeumCore/AmiberryInstall.swift` lines 120-134). Unpacking without a mount: sadm notes HFS+ is "Needed for 7-Zip support" (`#L500`), so `7zz x` should too; **unverified**, as not tried.
- **Signed**: `Developer ID Application: Stichting Dolphin Emulator (97835T4369)`, hardened runtime, the dmg signed separately, `Identifier=dolphin` (`#L508`, and `codesign -dv`).
- **Notarised, stapled to the dmg only.** sadm notarises and staples the dmg (`#L514-L528`). `stapler validate` passes on the dmg and says "does not have a ticket stapled" of `Dolphin.app`. `spctl` accepts both as "Notarized Developer ID". So an app copied out, with its quarantine off as `EmulatorInstall.removeQuarantine` does, has no ticket of its own. A copy with no quarantine isn't expected to be assessed by Gatekeeper at all (**unverified** here, as nothing was run). The earlier note's "signed, notarized, stapled" is right of the dmg.
- **Entitlements**: JIT, library validation off, audio input, Apple Events. No sandbox.

### The app

- 121 MB. `Contents/MacOS/Dolphin` is universal (`x86_64 arm64`), 47.6 MB. `Frameworks/` has Qt and MoltenVK, `Helpers/Dolphin Updater.app` is `org.dolphin-emu.updater`, `LSUIElement`, `Resources/Sys` (§1). `LSMinimumSystemVersion` 11.0.0. No Homebrew needs.
- **`CFBundleShortVersionString` is `2609`, `CFBundleVersion` `2609.0`, `CFBundleLongVersionString` the commit.** No process needed, as for ares and Amiberry (ADRs 0028, 0035).
- **Nothing in it is data** with the user folder outside (§1, §3), so a reinstall swaps the app alone, as PCSX2's does.

## 13. This Mac's data, and the ROM folders

### `~/Library/Application Support/Dolphin`

Made 2026-10-06 12:12, last written 22:19 that day. 35 MB, nearly all the Wii NAND. Everything is as one boot of one WAD leaves it:

- **`Config/`**: `Dolphin.ini` (16 lines: analytics asked, NetPlay and SDL defaults, a generated `WirelessMac`, `DSPThread`; no paths, no slots), `GCPadNew.ini`, `GCKeyNew.ini`, `WiimoteNew.ini` all on the keyboard (`Device = Quartz/0/Keyboard & Mouse`), `Qt.ini`, and `TimePlayed.ini` (`WD9EA4 = 0x2c9b`, 11.4 seconds). No `Profiles/` folder, and no controller mapped.
- **`GC/`**: `SRAM.raw` (68 bytes), empty `USA/Card A/`, `EUR/`, `JAP/`. **No `.gci` and no `.raw` card.**
- **`Wii/`**: `title/00010001/57443945/` (Castlevania ReBirth, `WD9E`) with 33 MB of `content/` and an **empty `data/`**, `title/00000001/00000002/data/` (`setting.txt`, `state.dat`), `shared1/`, `shared2/`, `sys/`, `ticket/`, `fst.bin`. No `00010000` titles.
- **`StateSaves/`, `GameSettings/`, `ScreenShots/`**: empty. **`Cache/`**: 16 KB. No `Load/WiiSD.raw`.
- No `Dolphin` preference file, saved application state or cache elsewhere in `~/Library`.

So **nothing needs moving across, and nothing would be lost** by leaving the folder behind. That also settles the issue's "NAND and GameCube memory cards are in nobody's backup": here they hold no saves.

### `/Applications/Dolphin.app`

The 2609 release's app: its `Contents/MacOS/Dolphin` has the same SHA-256 as the dmg's (`b3c369bc…d5d3ccf`), same signature and timestamp, not stapled, with `com.apple.quarantine` from Chrome. No `portable.txt` beside it.

### Ludeum folder and Data folder

- **`Emulators/`** in the Ludeum folder: `Amiberry.app`, `DuckStation.app`, `MesenCE.app`, `PCSX2/`, `ares/`. No Dolphin.
- **`Emulators/`** in the Data folder: `Amiberry`, `DuckStation`, `MesenCE`, `PCSX2`, `ares`. No Dolphin.

### ROM folders

- **`ROMs/GameCube`**: 17 ROMs, 14.2 GB in all, 5.5 GB local, every one an Archived `.7z`, as the journal says (`archived = 1`). So none can be Played until Unarchived. No loose image, no subfolder. 16 are USA; Metal Gear Solid: The Twin Snakes is PAL, so it uses Dolphin's `EUR` folder.
  - The three merged by ADR 0031 are local and hold two `.iso`s and an `.m3u` each. The other 14 are evicted, so their inner forms weren't listed, as that would download them (**unverified**).
- **`ROMs/Wii`**: 4 loose `.wad`s, 111 MB, all evicted: Castlevania The Adventure ReBirth, Contra ReBirth, Mega Man 9, Mega Man 10, all USA WiiWare. No disc ROM at all. Neither Mega Man's DLC is there.
- **All 21 rows** have `serialsLookedUp = 0` and no `serials` (§5).

## 14. Where the folders could go

Facts on each, without choosing. Nothing here was run.

| | A: Portable, keys and links | B: The whole user folder in the Data folder | C: Portable, states left in the local user folder |
|---|---|---|---|
| How | `Emulators/Dolphin/portable.txt`; keys or `-C` for Wii and cards; directory links `User/StateSaves`, `User/GameSettings`, `User/ScreenShots` into `Data/Emulators/Dolphin/` | `-u <Data>/Emulators/Dolphin/User` on every launch (or `DOLPHIN_EMU_USERPATH`, with no `portable.txt`) | As A, with no link for states |
| Save states in Dropbox | Yes, through a link | Yes | No, against the issue; a quarterly bump orphans them anyway (§4) |
| Game saves in Dropbox | Yes, by keys | Yes | Yes, by keys |
| Controls and settings | In the Ludeum folder, so per Mac, as DuckStation's and PCSX2's `settings` are | In Dropbox, so a new Mac has them | Per Mac |
| Rebuildable things | Stay local | `Cache/`, `Logs/`, `Dump/`, `Shaders/`, `Qt.ini` in Dropbox unless linked back out; shader UID caches and `TimePlayed.ini` rewritten during or after every Play | Stay local |
| A hand-opened copy | Portable, so it sees the same folders, but not any `-C` keys | With only `-u`, it writes `~/Library/Application Support/Dolphin` instead | As A |
| New in Ludeum | Makes and repairs three links; `Dolphin.ini` writes unless all `-C` | Nothing to write about folders. Like ADR 0035's `AMIBERRY_HOME_DIR` in `Data/Emulators/Amiberry/` | One fewer link |
| Fails if the Data folder's missing | Link dangles, `checkData()` refuses first | `-u` would try to make the folder at that path unless `checkData()` refused first | Same as A for keys |
| The NAND's WAD contents | In Dropbox unless the NAND stays local | In Dropbox | As A |

Other pieces that combine with those:

- **NAND local, with `title/*/*/data` linked out**: `data` folders appear as games first run, so Ludeum would have to make each link before its Play, by ID. It'd keep `.app`s out of Dropbox. `HostFileSystem` opens through ordinary paths, so a directory link there should work (from code), but it's an unusual shape.
- **GCI per Game with `-C Main.Core.GCIFolderAPathOverride`**: a folder per ID or ROM, with no other game's saves on the virtual card, and no region level. ADR 0024 and 0032 rejected the like, as a Game save being the Emulator's concern.
- **`-C` for all of it** (as ADR 0035): no `Dolphin.ini` write, and no "only while not running" rule for it. Links, if any, are still made on disk.

## 15. Mapping ADRs 0024, 0027, 0028, 0029, 0032, 0034 onto Dolphin

| ADR | Dolphin | Notes |
|---|---|---|
| Pinned version and SHA-256 in code (0024) | **Version yes, digest computed** | Versioned URLs that don't age off, but not on GitHub and no published digest found. `2609` or `2609a` (§12). |
| Unpack without quarantine | **Same as ADR 0035** | A dmg: mount, `ditto`, `removeQuarantine`. The app has no stapled ticket of its own (§12). |
| Confirm the build | **App version, no process** | `CFBundleShortVersionString`, as today and ares's. `CFBundleVersion` tells `2609` from `2609a`. |
| Portable marker | **Beside the app** | `portable.txt`, with the data under `User/`, as PCSX2's beside its app (§1). `-u` is the per-launch alternative, and beats it. |
| Standing settings before every Play and after Install | **In `Dolphin.ini`, or all by `-C`** | `[General] NANDRootPath`, `[Core] GCIFolderAPath`, `[AutoUpdate] UpdateTrack`, `[Analytics] PermissionAsked`, `[Interface] ConfirmStop` (§2, §3). `-C` makes them per-launch, as ADR 0035's. |
| Only while the Emulator isn't running | **Same for `Dolphin.ini`** | It's saved from memory at exit and on change. `-C` needs no such rule. |
| Self-update off | **Yes, and `-b` skips it** | `UpdateTrack` empty (§3). It writes into the bundle. |
| Save states and Game saves in `Data/Emulators/<Emulator>/` | **Not by setting, for Save states** | No `StateSaves` key. Options in §14. Game saves by keys. |
| A folder per Platform (0027) | **Not needed for what's keyed by ID** | GameCube and Wii IDs don't normally clash, and cards and NAND are apart anyway. A state's name has nothing of the console in it, as MesenCE's hasn't, but its ID is the disc's, not a file name's. |
| Refuse Play while any copy runs | **Same** | No single-instance guard, same bundle ID on every copy (§3). Today Play doesn't refuse. |
| Game detail lists Save states, Plays from one, deletes one | **Yes, with no pictures** | `<ID>.s01` to `.s10`, time and version from the header. `-s <file>`. Deleting is a file. `lastState.sav` isn't a slot's Previous (§4). |
| Game detail shows Game saves | **Yes, by Platform** | GameCube: Card saves as `.gci`s by the header's game code, with comments, icon, time (§6). Wii: one `data` folder, with `banner.bin` (§7). Both are in a shared container in principle (as the glossary has it) but readable one Game at a time. |
| Rename moves the saves (0027, 0028) | **Not needed** | Keyed by the disc's or WAD's contents (§8). |
| Saves keyed by Serial (0024, 0032) | **By game ID** | Not read yet (§5). A Disc 2's is its Disc 1's, so one Game has one, not one per Disc, and a revision shares it. |
| Per-game file (0029) | **Dolphin's own, in `GameSettings/`** | Same model as DuckStation's, but no key, and it's reached from the game list (§11). |
| Fast boot, latency (0033) | **Still Ludeum's by `-C`** | ADR 0033 said so. `[Core] SkipIPL` defaults to true, so boots already skip the IPL (`MainSettings.cpp#L42`). |
| Writes atomic (0024) | **Partly** | INIs and states are renamed in. `.gci`s, raw cards and NAND files aren't (§6, §7). One Mac at a time. |
| Available offline in Dropbox | **Same need** | §9. |
| Licence | **GPL-2.0-or-later** | A configured copy is fine. |
| Move over by hand once | **Nothing to move** | §13. |
| Resume state (0034) | **None** | No save on closing (§10). Play stays as ADR 0034's consequences say. Only a latest-slot default could stand in. |
| Multi-disc (0031) | **Unchanged for booting** | `.m3u` and `AutoDiscChange`, by `-C` or as a Standing key. Save states don't say their Disc (§10). |
| Architecture | **Universal** | arm64 native. |

## Open questions for the design session

1. **Where do Save states go?** A directory link from a local user folder, the whole user folder in the Data folder, or left local (§14). Given most quarterly bumps orphan every state, how much is a state in Dropbox worth, against ADR 0024's "Save states live in the Data folder, full stop"?
2. **The NAND in the Data folder, with a WAD's content in it?** The 16 to 38 MB copy of each last-played WAD goes to Dropbox on every switch. Or a local NAND with `data` links, or accept it?
3. **Is a game ID a Serial?** `rom.serials` is one per Disc, in Disc order; a GameCube ROM's would be the same twice. If so, ADR 0025 could read Regions from it, and the glossary would change. Or a column of its own, or read it each time?
4. **When is the game ID read?** At Import, through `.7z` streaming (only the first Disc is needed, and that's the start of the archive) or at Unarchive. Only what's present is listable, so an Archived ROM's saves wait until then, unless the ID is known. All 17 GameCube ROMs are Archived, and all but three evicted.
5. **What of a two-Disc Game's Save states and Play from one?** A state doesn't say which Disc it wants, and Dolphin doesn't check (§10). Boot order `-e Disc2 -e Disc1`, ask at Play, or Play from a state only on Disc 1, with the risk unmeasured? It needs one by-hand test.
6. **Should Play use `-b`?** One Play is one process, no main window, no update check. But it hides the game list and Game Properties, and the menu bar's state is unverified. Would per-game settings still be reachable? Worth one Play by hand.
7. **`-C` or Standing settings for today's three keys, and for the new ones?** ADR 0035 went all per-launch. ADR 0033 says how an Emulator plays is its own for DuckStation, but that Dolphin's are Ludeum's.
8. **What can be a Resume?** None from Dolphin. A Game's latest slot by header time, or nothing, leaving Play as it is?
9. **Which build?** `2609` is what the launch code was written for and what's on this Mac; `2609a` is newest with the same states and fixes for malformed-state and NetPlay crashes. Note `EmulatorVersions.parse` reads `2609a` as `[2609]`, so an exact check as coded would pass either (side findings).
10. **GCI folder layout.** Keep the default device and give it `GCIFolderAPath` (`<path>/USA`, `/EUR`, `/JPN`), or a card per Game by override? Slot B stays empty? Should Ludeum also read raw cards, or say a raw card isn't read, as PCSX2's file card isn't?
11. **Which folders go across?** `Screenshots` and `GameSettings` for ADR 0024's list; `Config/Profiles` and `Config/GCPadNew.ini` for controls have no key either; `Load/` (texture packs) and `WiiSD.raw` have keys.
12. **`.deleted` and `lastState.sav`.** List the latter as Previous on the Game its header names, and delete it with a Game? List `.gci.deleted`? Hide both?
13. **A Game's ROM being a different revision's**, sharing the ID (§5): nothing for Ludeum to do, but a Game detail listing by ID would show them all under both.
14. **DLC WADs.** A `00010005` WAD can't boot. Should a Wii Play say so, as Import could tell by its TMD? None are here yet.
15. **Back up, restore and delete a Game save (#77).** The earlier Emulators went without. Here a Card save is one file and a Wii save one folder, so either is simple, but only GameCube's has its own `.deleted` trace.

### Side findings (outside #83)

Against the earlier notes and the issue:

- **`wii-emulator.md`**'s "Whether `dolphin-tool` is in the macOS app bundle is **unverified**" is now **it isn't**, and its "(The binary path inside the bundle is **unverified**)" is `Contents/MacOS/Dolphin`.
- **`wii-emulator.md`**'s `Main.General.NANDRootPath` "**unverified** in practice" holds, but the code order is checked at a pinned tag, and it moves `SYSCONF` too. Its open question of what `-e` does with a DLC WAD is answered: "This WAD is not bootable".
- **`wii-emulator.md`** gives 2609 as the latest. **`2609a`** (2026-10-07) is, a day after that note. Its `-C` section, `-b`, WAD and layer facts all hold at `2609`.
- **`managing-emulators-inside-ludeum.md`**'s "Developer-ID signed, notarized, stapled" is true of the dmg, and not of the app inside.
- **Issue #83**'s "`-u` / `DOLPHIN_EMU_USERPATH` moves the whole user folder" is right, but `portable.txt` beats the environment variable, and `-u` beats both (§1). Its "Worth checking whether GCI folders make that simpler": they do, and they're already the default on this Mac, though no save exists yet.

Others:

- **`EmulatorVersions.parse` can't tell `2609a` from `2609`.** `.dotted` falls to the bare number and gives `[2609]` (`Sources/LudeumCore/EmulatorVersions.swift` lines 165-168), so an exact pin of `2609a` would accept `2609`. `CFBundleVersion` is `2609.1` against `2609.0`, which it would read apart.
- **`.wia` isn't ready for GameCube** in `ROMPlatform` though Dolphin opens it and it's ready for Wii (`Sources/LudeumCore/Import/ROMPlatform.swift` lines 103-107). None exist here.
- **Ludeum's comment** at `App/Sources/GameDetailParts.swift` lines 496-497 says Play refuses a running Emulator "for DuckStation, MesenCE and ares"; PCSX2 and Amiberry refuse too by their ADRs, so the comment lags.
- **`GameSettings` ships per-revision inis**, such as `GALE01r2.ini`. The same shape in the user's folder is written only if one already exists (§11).
- **Dolphin's own `TimePlayed.ini`** has a play time per game ID in milliseconds, which Ludeum doesn't read. ADR 0007 is against activity, so noted only.
- **`Sys/wiitdb-*.txt`** in the bundle map game IDs to titles, in twelve language files, which Ludeum could read to name an ID it doesn't recognise.
