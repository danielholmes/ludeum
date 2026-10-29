# ares under Ludeum's management

Researched 2026-10-29 for issue #84. The question: can Ludeum manage ares as ADR 0024 manages DuckStation and ADR 0027 manages MesenCE (install a pinned build, keep it apart from any other copy, write Standing settings that put its Save states and Game saves in the Data folder, refuse Play while it runs, list and Play from Save states in Game detail)? Where does ares keep its Save states and Game saves, what does it name them by, and what loses one? This note lays out the facts and the options. It doesn't make the decision.

Sources:

- **ares source** at tag `v148`, commit `0aafd85789215e84e1e43415c07d4c88461b7899` (2026-05-28). That's the version Ludeum expects (`EmulatorVersionSpec(expected: "148")`, `Sources/LudeumCore/EmulatorVersions.swift` ~63) and the newest release. Links like `T/desktop-ui/emulator/emulator.cpp#L27-L37` mean `https://github.com/ares-emulator/ares/blob/0aafd85789215e84e1e43415c07d4c88461b7899/desktop-ui/emulator/emulator.cpp#L27-L37`.
- **ares `master`** at `47bab688e68c2939fa15de8200d7e2d109e3dd2a` (2026-10-28), where it differs.
- **The GitHub REST API** for releases and digests.
- **The release zip** `ares-macos-universal.zip` for v148, downloaded into the session scratchpad and checked read-only. It was never run.
- **This Mac's copy**, read without changing or launching anything: `/Applications/ares.app` and `~/Library/Application Support/ares/settings.bml`.
- **The Curse of Illmoore Bay**, the one Game save from OpenEmu brought across (2026-10-29), tested in ares by Daniel and working.

Anything not checked against one of these sources is marked **unverified**.

## Answer

**Yes, and more simply than MesenCE, because ares can be told where to save on the command line and keeps a folder per system.** Four facts shape the design:

1. **By default ares saves beside the ROM.** Its Saves path (`Paths/Saves` in `settings.bml`) is empty on this Mac, and then a Game save and every Save state go next to the file ares was given, named by its file name without the extension: `ROMs/Mega Drive/The Curse of Illmoore Bay.ram`, `….bs1`. The ROM folders are already in the Data folder, so Dropbox has them today with nothing written (§4, §5).
2. **`--setting Paths/Saves=<folder>/` sets it for one launch.** ares puts the saved value back when it quits, unless it was changed in its own UI meanwhile. With a Saves path, everything goes to `<folder>/<system>/<name>.<ext>`: `Mega Drive/`, `Nintendo 64/`, and, for the Sega CD's own backup RAM, `Mega CD/`. So no file need be written before a Play, and a copy in `/Applications` would do (§2).
3. **A Save state loads only in the build that wrote it.** Each core checks a version string in the state's header and refuses any other. Of the six releases checked since v140, Mega Drive's changed in three and N64's in four, and `master` has changed both since v148. Bumping ares will orphan every Save state, as it would in DuckStation, and there's no screenshot in a state to list (§4).
4. **The Sega CD can't Play yet on this Mac.** ares has no Sega CD BIOS (its `MegaCD/Firmware/BIOS.*` are empty and there's no `Firmware/` folder), and none was found on the Mac. Nor does ares open `.m3u`, `.iso` or `.bin`, which Ludeum's Sega CD ROM folder reads as ready. All six Sega CD ROMs are Archived `.7z` today (§9).

The rest:

- **Install.** Versioned tags (`v146`, `v147`, `v148`) with SHA-256 digests in the API, plus a rolling `nightly` that can't be pinned. The zip holds a **Developer ID–signed, notarised and stapled** universal `ares.app` with its frameworks inside, so it needs no Homebrew and no quarantine trick. This Mac's `/Applications/ares.app` is byte-identical to the v148 release's binary (§8).
- **Portable mode.** A `settings.bml` beside `ares.app` wins over Application Support. So do `Firmware/` and `Systems/` folders there. `--settings-file <path>` names one outright. Nothing inside the bundle need change (§3).
- **No single-instance guard.** A second launch is a second ares. Each rewrites the whole `settings.bml` at startup and at quit (§7).
- **Saves through Compact, Archive and Rename.** They follow Compact and Archive (the file name doesn't change) and are orphaned by Rename (§6).
- **Licence.** ISC.
- **OpenEmu carry-over.** GenesisPlus's Mega Drive saves need converting, not just renaming, where the cartridge's SRAM is byte-wide (§10). OpenEmu's Save states won't load.

## 0. Which repository

- **`ares-emulator/ares`**, ISC (`LICENSE`), the macOS bundle ID `dev.ares.ares`, which is what `Emulator.ares` looks up (`Sources/LudeumCore/Emulators.swift` line 12).
- The bundle's `CFBundleShortVersionString` is `v148`. Ludeum reads the version with `--version` already (`EmulatorVersions.swift` ~63).

## 1. Settings: `settings.bml`

- **One BML file** (indentation-nested `Name: value` lines), 2,500 lines and 40 KB on this Mac, most of it input bindings for every system ares plays.
- **Read at startup, written whole at startup and at quit.** `Settings::load` parses the file and immediately calls `save()`. `nall::main` calls `settings.save()` again after the run loop ends (`T/desktop-ui/settings/settings.cpp#L31-L40`, `T/desktop-ui/desktop-ui.cpp#L250-L260`). `file::write` truncates and writes, with no temporary file and rename. So anything written into `settings.bml` while ares runs is lost when it quits.
- **Folder keys** (`T/desktop-ui/settings/settings.cpp#L118-L126`):

| Key | Used for | When empty |
|---|---|---|
| `Paths/Home` | `Systems/` (system-level saves, such as the Sega CD's backup RAM) | `locate("Systems/")`: beside `ares.app` if a `Systems/` is there, else `~/Library/Application Support/ares/Systems/` |
| `Paths/Firmware` | where Firmware → Scan looks for BIOS files | `locate("Firmware/")`, the same search |
| `Paths/Saves` | Game saves **and** Save states | beside the ROM |
| `Paths/Screenshots` | screenshots | beside the ROM |
| `Paths/Debugging` | memory and graphics dumps, logs | beside the ROM |

- **A path must end in `/`.** ares appends the system name straight on (`{path, system, "/"}`, `T/desktop-ui/emulator/emulator.cpp#L34`). Its own Paths panel stores the folder with the slash.
- **Firmware is a path per BIOS.** `MegaCD/Firmware/BIOS.US` and the like hold an absolute path to the file, filled in by Settings → Firmware → Scan, which hashes every file under 10 MB in the firmware folder against the SHA-256s ares knows (`T/desktop-ui/settings/firmware.cpp#L105-L135`, the Sega CD's at `T/desktop-ui/emulator/mega-cd.cpp#L17-L19`). There's no scan at startup.
- **Other keys Ludeum cares about:**
  - `General/RunAhead`, which Play already sets per launch.
  - `General/AutoSaveMemory` (on by default and here), which writes Game saves every 30 seconds of play as well as when the game closes (`T/desktop-ui/program/program.cpp#L114-L121`).
  - No update check was found in the source.

## 2. Command line

From `--help` (`T/desktop-ui/desktop-ui.cpp#L155-L176`) and the parsing above it:

- `--system <name>` (`Mega Drive`, `Mega CD`, `Nintendo 64`) and a ROM path. That's what Play passes today.
- `--setting <path>=<value>` for any key in the file. **This launch only:** each override records the value it replaced. At quit, a key still holding the overridden value gets the original back before `settings.save()`, and a key changed in the UI meanwhile keeps the change (`T/desktop-ui/desktop-ui.cpp#L114-L150`, `#L250-L260`). An unknown key stops ares with "Invalid setting".
- `--settings-file <path>` replaces `settings.bml` outright, for reading and writing.
- `--save-state <1–9>` loads that slot as soon as the game has loaded (`T/desktop-ui/program/load.cpp#L153-L155`). That is Play from a Save state, with no file to write first.
- `--no-file-prompt` and `--kiosk`, `--fullscreen`, `--shader`, `--dump-all-settings`, `--version`.

## 3. Data root and portable mode

- **`locate(name)` looks in order** (`T/desktop-ui/desktop-ui.cpp#L9-L57`):
  1. the folder that holds `ares.app` (`Path::program()` is the bundle's path, and `Path::real` takes its folder, `T/nall/nall/path.hpp#L17-L25`);
  2. `~/Library/Application Support/ares/`;
  3. `/Library/Application Support/ares/`;
  4. `ares.app/Contents/Resources/` (where `Database/` and `Shaders/` ship).

  If none has it, it's made in `~/Library/Application Support/ares/`.
- **So a copy of ares in its own folder, with a `settings.bml` beside it, is portable.** `settings.bml`, `Firmware/` and `Systems/` all resolve there once they exist. A Ludeum-installed `Emulators/ares/ares.app` with `Emulators/ares/settings.bml` shares nothing with `/Applications/ares.app`. Putting it directly in `Emulators/` beside `DuckStation.app` and `MesenCE.app` would work too, but its `settings.bml` would sit loose in that folder.
- **Nothing is written inside the bundle**, so its notarised seal stays intact. That's unlike DuckStation and MesenCE, whose portable data roots are in `Contents/MacOS`.
- **This Mac's ares** has only `~/Library/Application Support/ares/settings.bml`: no `Systems/`, no `Firmware/`, no saves. Its `MegaDrive/Path` (the file dialog's last folder) is the Mega Drive ROM folder.

## 4. Save states

- **Named by the ROM's file name, beside it or under the Saves path:** `Emulator::locate(game->location, ".bs<slot>", settings.paths.saves)`. That's `<ROM without extension>.bs1` … `.bs9` when the Saves path is empty, else `<Saves>/<system>/<name>.bs<slot>` (`T/desktop-ui/emulator/emulator.cpp#L27-L37`, `T/desktop-ui/program/states.cpp#L1-L45`). For a `.zip` it's the zip's own name. The name of the file inside doesn't matter.
- **The system folder is the core's name, not the Platform's.** A Sega CD Game's states go under `Mega Drive/`, as the Mega CD is the Mega Drive core (`information.name = "Mega Drive"`, `T/ares/md/system/system.cpp#L92-L98`, `#L126`). None of today's Sega CD ROM names is also a Mega Drive ROM's.
- **Undo files.** Saving over a slot moves the old state to `.bsu` first. Loading one writes the state it replaced to `.blu`. Both are deleted when the game is unloaded (`T/desktop-ui/program/states.cpp#L5-L10`, `#L27-L29`, `#L84-L92`, `T/desktop-ui/program/load.cpp#L162-L172`).
- **There's no resume state.** ares saves nothing on quit except Game saves. Nine numbered slots are all.
- **Format.** The core's serializer output, written raw, with no compression and no screenshot. The header is a signature, a `synchronize` flag, a 16-byte version string and a 512-byte description (empty) (`T/ares/md/system/serialization.cpp#L1-L37`). Game detail could show a state's slot and the file's modified time, but no picture, unless Ludeum keeps a screenshot itself.
- **Version-locked.** `unserialize` refuses a state whose version string isn't the core's own:

| Release | Mega Drive | N64 |
|---|---|---|
| v140 | v135 | v135 |
| v143 | v142 | v141.2 |
| v145 | v144 | v144 |
| v146 | v145 | v144 |
| v147 | v145 | v145 |
| **v148** | **v145** | **v152** |
| `master` | v146 | v153 |

  So the next release will refuse every Save state v148 makes, on both cores. A bump is a choice to lose them, or to keep the old build for them.

## 5. Game saves

`Pak::saveLocation` (`T/mia/pak/pak.cpp#L154-L172`): with a Saves path, `<Saves>/<saveName>/<name><ext>`. Otherwise, for a ROM file, `<ROM without extension><ext>` beside it.

| Platform | What | File | Source |
|---|---|---|---|
| Mega Drive | cartridge SRAM | `<name>.ram` | `T/mia/medium/mega-drive.cpp#L80-L118` |
| Mega Drive | cartridge EEPROM | `<name>.eeprom` | same |
| N64 | SRAM, EEPROM, FlashRAM, RTC | `<name>.ram`, `.eeprom`, `.flash`, `.rtc` | `T/mia/medium/nintendo-64.cpp#L119-L147` |
| N64 | Controller Pak, per Game and port | `<name>.pak` (port 1), `<name>.2.pak` … | `T/desktop-ui/emulator/nintendo-64.cpp#L163-L170`, `#L273-L276`, `#L398` |
| Sega CD | the console's 8 KB backup RAM, shared by every Sega CD Game | `<Home>/Mega CD.sys/backup.ram`, or `<Saves>/Mega CD/Mega CD.bram` | `T/mia/system/mega-cd.cpp#L14-L37`, `T/mia/system/system.cpp#L81-L83` |

- **Formats.** Raw memory in the cartridge's own width. Byte-wide SRAM on odd or even addresses (`lower`/`upper` in ares's manifest) is kept as those bytes alone, half the address range. Word-wide SRAM is kept big-endian (`T/ares/md/cartridge/board/board.cpp#L31-L49`, `T/ares/md/cartridge/board/standard.cpp#L40-L81`, sizes from the header at `T/mia/medium/mega-drive.cpp#L301-L325`).
- **A file appears on first Play of any Game with save memory**, filled with `0xFF` until the game writes it, and its modified time moves every 30 seconds of play (§1). So the time a Game save was last written is really when it was last played. That's unlike MesenCE, which writes only when the game stops.
- **The Sega CD's backup RAM is no one Game's Game save** (as the glossary has it for a PS2's shared card). ares doesn't emulate the separate RAM cartridge (`cart.brm` in GenesisPlus); nothing in v148 mentions one.
- **Not atomic.** Every write truncates and writes, as MesenCE's do.

## 6. What follows a ROM, and what loses its saves

Everything is keyed by the ROM's file name without its extension, and nothing else: no checksum, no serial.

- **Compact** (loose `.md`/`.n64` to `.zip`): same name, so they follow.
- **Archive and Unarchive** (`.zip` to `.7z` and back): same name, so they follow. An Archived ROM can't be Played by ares anyway.
- **Rename** (ADR 0012): orphans them. Ludeum would move `<old>.*` to `<new>.*`, as it does for MesenCE.
- **A disc ROM** (Sega CD) is a cue sheet in its subfolder, so with no Saves path its states would land **inside that subfolder**. Archive packs "the ROM's folder's contents" (`Sources/LudeumCore/Import/ROMArchiver.swift` ~194–204), so they'd go into the `.7z` with it and come back on Unarchive (**unverified**). With a Saves path they stay out of the ROM folders.
- **A bump of ares** loses every Save state (§4), though not Game saves.
- **A second ares writing the same Game save** (§7).

## 7. Single instance

- **None.** There's no hand-off or lock in the source. A second launch is a second process with its own copy of `settings.bml` in memory, and whichever quits last writes the file.
- **Two copies Playing one Game** would each write its Game save every 30 seconds.
- So "refuse Play while any ares is running", as for DuckStation, is cheap to keep. Ludeum has no reason to rely on a hand-off, as there's none.

## 8. Install

### Releases

- **Tags `v146` (2025-08-26), `v147` (2025-12-23), `v148` (2026-05-30)**, each with `ares-macos-universal.zip` and a `digest`. v148's is `sha256:1ae232ab6de341210f171f51d84b311527eb1399060706589334a8a7de136bb0` (79,914,130 bytes), and the download matched it.
- **`nightly`** is a rolling tag (published 2024-12-30, its assets replaced since), so it can't be pinned.

### The zip

- It holds `ares-v148/ares.app` (165 MB unpacked, 5,523 entries, most of them `Resources/Shaders/` and `Resources/Database/`).
- **Signed and notarised.** Developer ID Application: Giovanni Bajo (`L4BF7MF6UH`), hardened runtime, ticket stapled (`stapler validate` succeeds, `spctl` says "Notarized Developer ID"). So it needs no unquarantining, unlike MesenCE.
- **Self-contained.** Universal (`x86_64 arm64`), macOS 11 or later, with `SDL3.framework`, `libMoltenVK.dylib` and `librashader.dylib` in `Contents/Frameworks`, so it needs nothing from Homebrew.
- **`/Applications/ares.app`** has the same `Contents/MacOS/ares` (SHA-256 `7a49f00f…fa345`) as the release, so this Mac runs v148 as released.

## 9. Three Platforms through one Emulator

- **Folders split themselves.** With a Saves path, ares puts each system in its own folder (§4, §5), so the name clashes MesenCE had across Platforms (ADR 0027) can't happen between Mega Drive and N64. Mega Drive and Sega CD share `Mega Drive/` for Save states, and no ROM name is on both today.
- **One build for all three.** A bump to a new core version loses N64 and Mega Drive states together (§4).
- **The Sega CD isn't ready:**
  - **No BIOS.** Every `MegaCD/Firmware/BIOS.*` in `settings.bml` is empty, there's no `Firmware/` folder, and no Sega CD BIOS was found on the Mac by name. OpenEmu's `BIOS/` holds only PlayStation and Saturn files. ares then refuses to start a disc ("no firmware", `T/desktop-ui/emulator/mega-cd.cpp#L76-L86`).
  - **Formats.** ares opens `.cue` and `.chd` (`T/mia/medium/medium.hpp#L22-L27`; CHD is a build option, on by default, `T/thirdparty/CMakeLists.txt#L7`). Ludeum's Sega CD ROM folder also reads `.m3u`, `.iso` and `.bin` as ready (`Sources/LudeumCore/Import/ROMPlatform.swift` ~116–117), and ares opens none of those.
  - Today all six Sega CD ROMs are Archived `.7z`.

## 10. OpenEmu carry-over

- **Game saves.** GenesisPlus keeps a Mega Drive cartridge's SRAM as 64 KB of its address range, whatever the cartridge's width. Where the SRAM is byte-wide, ares keeps only the bytes it uses, so the file is converted, not copied.
  - The Curse of Illmoore Bay's header says SRAM at `0x200001`–`0x20FFFF`, odd bytes only. Its ares save is GenesisPlus's odd bytes: 32 KB.
  - The even bytes from offset `0x8A2` held words the game wrote, which a byte-wide cartridge and ares both drop.
  - Tested in ares by Daniel on 2026-10-29: it works.
- **That was the only one wanted.** The ten Mupen64Plus N64 saves aren't (they'd need renaming to ares's `.eeprom`/`.ram`/`.pak`, and their formats weren't checked). The two Sega CD backup RAMs (`scd_U.brm`, `cart.brm`) are shared, not one Game's (#84's checklist).
- **Save states won't load.** OpenEmu's are its cores' (GenesisPlus GX, Mupen64Plus), and ares checks its own signature and version (§4).

## 11. Mapping ADRs 0024 and 0027 onto ares

| ADR 0024 / 0027 | ares | Notes |
|---|---|---|
| Pinned versioned tag and SHA-256 in code | **Same** | `v148` and its digest. Versioned tags stay. |
| Unpack without quarantine | **Not needed** | Notarised and stapled, so a quarantined copy opens too. |
| Confirm the build | **Same as today** | `--version`. |
| Portable: a marker in `Contents/MacOS` | **Simpler** | A `settings.bml` beside the app, in a folder of its own (`Emulators/ares/`), so the bundle is untouched (§3). Or `--settings-file`. |
| Standing settings written into the settings file before every Play | **A choice** | Either `--setting Paths/Saves=…/` (and `Paths/Screenshots`) on every launch, writing nothing, or written into `settings.bml` before launch (it's rewritten at startup and quit, so only while ares isn't running). |
| Self-update off | **Not applicable** | There's no update check. |
| Save states and Game saves in `Data/Emulators/<Emulator>/` | **Possible, or already true** | Beside the ROM is already the Data folder. A Saves path of `Data/Emulators/ares/` gives `Mega Drive/`, `Nintendo 64/` and `Mega CD/` beneath it. |
| A folder per Platform (0027) | **ares's own** | Per core (§9). |
| Refuse Play while any copy runs | **Same** | No single-instance guard (§7). |
| Game detail lists Save states, Plays from one, deletes one | **Yes, without pictures** | `<name>.bs1`–`.bs9` (ignore `.bsu`/`.blu`). Play from one is `--save-state <n>`. There's no screenshot in a state and no resume state. |
| Game detail shows Game saves | **Yes** | `<name>.{ram,eeprom,flash,rtc,pak,2.pak,…}`. Its modified time is the last play (§5). The Sega CD's backup RAM is no Game's. |
| Rename moves the saves (0027) | **Same** | By name, `<old>.*` to `<new>.*` (§6). There's no name inside a `.zip` to keep in step: ares uses the zip's name. |
| Move over by hand once | **Little to move** | No Game saves or states exist outside the ROM folders. One file, Illmoore Bay's `.ram`, sits beside its ROM. |

## Open questions for the design session

1. **Leave saves beside the ROMs, or set a Saves path?** Beside the ROM needs no settings at all and is already in Dropbox. But it mixes saves into the ROM folders, a disc ROM's states land in (and Archive into) its subfolder, and the Data folder's `Emulators/` wouldn't hold ares's. A Saves path keeps them apart, by system.
2. **`--setting` per launch, or a managed `settings.bml`?** `--setting` works with `/Applications/ares.app` and writes nothing, but Ludeum's Open (no ROM) would need the same arguments, and a path changed in ares's UI during a session sticks. A managed install with its own `settings.bml` matches ADRs 0024 and 0027.
3. **Install ares, or keep using `/Applications`?** It's notarised, self-contained and byte-identical to v148 already, so the case for a managed copy is isolation (its own `settings.bml`, `Firmware/`, `Systems/`) and pinning, not getting it to run.
4. **Bumps lose Save states.** Accept it, keep the old build while its states matter, or warn before a bump that a Game has states?
5. **Save states without screenshots.** List slot and time only, or have Ludeum take one?
6. **Sega CD.**
   - Where does its BIOS come from, and where should it live: the Data folder, as DuckStation's `BIOS/` does, with `Paths/Firmware` pointed at it and Scan run once?
   - Should the Sega CD ROM folder stop reading `.m3u`, `.iso` and `.bin` as ready, since ares opens none of them?
7. **Game saves' "last written".** With `AutoSaveMemory` on, it's really "last played". Turn it off as a Standing setting (saves only on close, at the risk of losing play to a crash), or show it as it is?
8. **Back up, restore and delete a Game save (#77).** DuckStation and MesenCE went without.

### Side findings (outside #84)

- **A loose `.smd` isn't an ares extension.** Mega Drive's are `md`, `gen` and `bin` (`T/mia/medium/mega-drive.cpp#L3`). Ludeum reads `.smd` as ready. The Curse of Illmoore Bay is a plain binary named `.smd` and Plays from its `.zip`. Whether ares loads a loose `.smd` given on the command line, and whether it de-interleaves a true SMD dump, is **unverified**.
- **The `Mupen64Plus/` folder had already left the OpenEmu Battery Saves archive** when this was checked (2026-10-29).
