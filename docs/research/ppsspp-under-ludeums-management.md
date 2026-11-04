# PPSSPP under Ludeum's management

Researched 2026-11-04 for issue #87. The question: can Ludeum manage PPSSPP as ADR 0024 manages DuckStation, 0027 MesenCE, 0028 ares, 0032 PCSX2 and 0035 Amiberry (install a pinned build, keep it apart from any other copy, write Standing settings that put its Save states and Game saves in the Data folder, refuse Play while it runs, list and Play from Save states in Game detail, show a Game's Game saves)? Where does PPSSPP keep its Save states and Game saves, what does it name them by, what loses one, and what does today's `--config=` Play actually do? This note builds on [psp-emulator.md](psp-emulator.md) (2026-10-06) and answers its open questions. It lays out the facts and the options. Apart from waiting for PPSSPP 1.21, which Daniel decided on 2026-11-04 (open question 2), it doesn't make the decision.

Sources:

- **PPSSPP source** at tag `v1.20.4`, commit `fa50bb1976065c4f8b1b47af227d367fe9771555` (2026-05-16). That's the latest release and the version Ludeum expects (`Sources/LudeumCore/EmulatorVersions.swift` line 69). Links like `T/Core/SaveState.cpp#L324-L333` mean `https://github.com/hrydgard/ppsspp/blob/fa50bb1976065c4f8b1b47af227d367fe9771555/Core/SaveState.cpp#L324-L333`.
- **PPSSPP `master`** at `a2001917b2cc32145b24a4274dfa06fc1c6d5b98` (2026-11-04), 4,402 commits past the tag. Links like `M/Core/CmdLine.cpp#L225` mean the same at that commit. Every file cited here was diffed against it, and it differs a lot (§0). Where it matters, what's said is for the tag, with `master` said separately.
- **Tags `v1.14.4`, `v1.17.1`, `v1.19.3` and `v1.20`**, fetched shallowly, for the Save state section versions only (§3).
- **The GitHub REST API** for releases, assets, digests and commits, last re-checked as this was written.
- **The release asset** `PPSSPPSDL-macOS-v1.20.4.zip`, downloaded into the session scratchpad, checked against the API's digest and unpacked. Its executable was read with `strings`, `otool` and `codesign`. **It was never run.**
- **This Mac**, read without launching anything or writing outside the scratchpad: `/Applications/PPSSPPSDL.app`, the Ludeum folder, its journal (read-only), the Data folder and `~/Dropbox/games/OpenEmu/`. OpenEmu's two PSP states and the archive folders' `Info.plist`s were read, so Dropbox will have brought down any of those that were online-only.
- **Ludeum's code** on `main` at commit `6b86a1f` (read at `466e232`; only research notes changed between).

Anything not checked against one of these sources is marked **unverified**. **Nothing here has been checked by running PPSSPP**, so behaviour read from source is what the code says, not what was seen.

**No PSP ROM's contents were read, not even a header.** All 21 files in `ROMs/PSP` are `dataless` (online-only in Dropbox, 0 blocks on disk), and reading one would have downloaded it. So `PARAM.SFO`, `UMD_DATA.BIN` and what's inside the `.7z` files are from source, not from a real disc.

## Answer

**Yes, but not the way the issue and the earlier notes say, because the flags they rely on aren't in any release. At v1.20.4 the memory stick can only be moved as a whole, by a macOS preference or `$HOME`, and `ppsspp.ini` moves with it.** Past that it fits well: Save states and Game saves are keyed by what's on the disc, a Play can start from a state, and a state from an old release still loads. Ten facts shape the design:

1. **`--memstick=`, `--config=` and `--controlconfig=` aren't in v1.20.4 on a Mac.** They're on `master` only: `--memstick` arrived on 2026-08-18 (`ef943ba205`), and `--config=` reached the SDL build on 2026-07-20, when the parser moved to `Core` and every backend began calling it (`29836ea74e`, `a59637975a`). At the tag, `--config=` is Windows's alone (`T/Windows/main.cpp#L1054-L1057`). Neither string is in the release's executable or in `/Applications/PPSSPPSDL.app`'s (`strings`; §1). The earlier notes read `master` as if it were the release.
2. **So today's Play does nothing with its settings file.** `--config=<copy>` is silently ignored by v1.20.4's parser. PPSSPP starts on `~/.config/ppsspp`, on its defaults: the latency keys Ludeum writes have never applied, and the copy is never read (§2, §10).
3. **What moves the memory stick at v1.20.4 is one of two things**: the `UserPreferredMemoryStickDirectoryPath` preference, which PPSSPP's own Set Memory Stick folder writes, or `$HOME`, as the default is `$HOME/.config/ppsspp`. Neither is a flag, and there's no portable mode. `-UserPreferredMemoryStickDirectoryPath <dir>` on the command line can't work, as PPSSPP would take `<dir>` for the file to boot (§1).
4. **Everything moves together.** `ppsspp.ini`, `controls.ini`, per-game inis, Game saves, Save states, shader caches, cheats and textures are all under the memory stick, and no ini key moves one of them. Settings in the Ludeum folder with saves in the Data folder needs links at v1.20.4, or a `master` build, which has no release to pin (§1, §2).
5. **Save states are `<DISC_ID>_<DISC_VERSION>_<slot>.ppst`** in `PSP/PPSSPP_STATE/`, with `<…>.jpg` beside them, and a slot's previous one as `<…>.undo.ppst`. **Game saves are folders, `PSP/SAVEDATA/<gameName><saveName>/`**, named by the game, each with a `PARAM.SFO` and usually an `ICON0.PNG`. Both are keyed by the disc, so they follow a ROM through Rename, Archive and a change of form. Only a homebrew file with no ID is named by its file name (§3, §4, §5).
6. **`--state=FILE` starts a Play from any state, in one go, and checks nothing.** It's queued before boot and applied before the first frame, so no race like MesenCE's, by the source. A state from another game is loaded all the same, and a broken one resets the game (§3).
7. **PPSSPP makes no automatic or on-exit state, so ADR 0034's Resume has nothing to read.** `AutoLoadSaveState` only loads the newest of the slots the player already saved (§3).
8. **A state's loader looks at each section's version, and old states stay loadable.** No section's minimum has risen past what any earlier tag checked wrote, from v1.14.4 to `master`. But `master`'s states won't load in v1.20.4 (§3).
9. **The release is ad-hoc signed, and `/Applications/PPSSPPSDL.app` is a different build of the same version**, Developer ID–signed and notarised, from a disk image rather than GitHub. Both are universal and self-contained, and `--version` exits before touching anything (§8).
10. **A PSP Serial is `DISC_ID` in `PSP_GAME/PARAM.SFO`**, not `UMD_DATA.BIN`. Ludeum reads none today. `PlayStationDisc.Volume` can find the file, and the SFO format is small. But 20 of the 21 ROMs here are Archived `.7z` and all 21 are online-only, which `ROMSerials` skips (§5).

The rest:

- **It has never been opened on this Mac.** No `~/.config/ppsspp`, no preferences, no `PPSSPP ppsspp.ini` in the Ludeum folder, so no Play has reached it either. Ludeum's `--version` check may have run it; by the source that leaves nothing (§11).
- **Refuse Play while it's open** is the right rule. There's a per-user instance counter rather than a guard: a second copy opens a full window, muted, that saves no settings but does write states and saves (§7).
- **No BIOS or firmware.** The fonts it needs are in the bundle (§9). **No self-update**, and no update check on a Mac at all (§2).
- **OpenEmu.** Its `SAVEDATA` is empty, as the issue says. **The issue's "PSP 7" doesn't hold: there's no PSP state in either archive folder.** Two exist, `Auto Save State`s of Assassin's Creed: Bloodlines and Syphon Filter: Dark Mirror, in `~/Dropbox/games/OpenEmu/`, and neither game has a PSP ROM here (§12).

## 0. Which repository, and how far `master` has moved

- **`hrydgard/ppsspp`**, default branch `master`. The API's `license.spdx_id` is `NOASSERTION`, as `LICENSE.TXT` is a pile of notices; the source headers say GPL "version 2.0 or later" (`T/Core/Instance.cpp#L5`). The bundle ID is `org.ppsspp.ppsspp` (`Emulator.ppsspp`, `Sources/LudeumCore/Emulators.swift` line 15).
- **Nothing newer than `v1.20.4`** (2026-05-16T12:35:08Z). No newer tag or release, re-checked as this was written. `README.md` calls it "an unusually big followup release" to "cover the longer gap to 1.21" (`T/README.md#L32`). There's no date for 1.21 in the repository.
- **`master` is 4,402 commits ahead**, last pushed 2026-11-04. In the files cited here only `Common/Data/Format/IniFile.cpp` and `SDL/macbundle.sh` are unchanged. `Core/SaveState.cpp`, `UI/NativeApp.cpp`, `Core/Config.cpp` and `SDL/SDLMain.cpp` each differ by over a thousand lines. It's been rewriting the command line (`Core/CmdLine.cpp`, new since the tag), Save state loading (on a worker thread), and the instance counter. Names on disk haven't changed: state and undo extensions, `GenerateFullDiscId`, the `PSP/…` folders, `_ppsspp.ini`, `UserPreferredMemoryStickDirectoryPath` and the "secondary instances" rule are all still there (grepped).

## 1. The memory stick, and how it moves

### Where it is

- **On a Mac: `UserPreferredMemoryStickDirectoryPath` if set, else `defaultCurrentDirectory/.config/ppsspp`** (`T/UI/NativeApp.cpp#L467-L469`, `T/Core/Util/DarwinFileSystemServices.mm#L309-L325`).
- **`defaultCurrentDirectory` is `$HOME`.** It's `SYSPROP_USER_DOCUMENTS_DIR` (`T/UI/NativeApp.cpp#L382-L383`), which the SDL build answers with `getenv("HOME")` (`T/SDL/SDLMain.cpp#L625-L629`).
- **So `~/.config/ppsspp` is right as the default**, as the earlier note has it. The preference and `$HOME` are the only inputs. `memstick_dir.txt` is Android's and UWP's (`T/UI/NativeApp.cpp#L416`, `#L442-L443`), `installed.txt` Windows's (`T/Windows/main.cpp#L920`).
- **The folders are made at every start** (`PostLoadConfig` → `CreateSysDirectories`, `T/UI/NativeApp.cpp#L239-L248`, `T/Core/Util/PathUtil.cpp#L105-L142`), so a launch that gets as far as `NativeInit` leaves a mark.
- **A memory stick folder itself named `PSP`** is treated as the `PSP` folder rather than given one inside (`T/Core/Util/PathUtil.cpp#L45-L53`, `T/Core/HLE/sceIo.cpp#L660-L665`).

### What's in it

From `GetSysDirectory` (`T/Core/Util/PathUtil.cpp#L45-L103`), `<memstick>/` holding:

| Path | Holds | Keep? |
|---|---|---|
| `PSP/PPSSPP_STATE/` | Save states and their screenshots | Yes |
| `PSP/SAVEDATA/` | Game saves, and games' installed data (§4) | Yes |
| `PSP/SYSTEM/ppsspp.ini` | Settings, recent files, play time | Settings |
| `PSP/SYSTEM/controls.ini` | Key bindings | Settings |
| `PSP/SYSTEM/<id>_ppsspp.ini` | A Game's own settings, only if made (§10) | Yes |
| `PSP/SYSTEM/ppsspp_<name>.dat` | Stored secrets, such as a RetroAchievements login (`T/UI/NativeApp.cpp#L1529`) | Local |
| `PSP/SYSTEM/CACHE/` | Shader caches, `icon.cache` (`T/UI/NativeApp.cpp#L705`, `#L712`) | Rebuildable |
| `PSP/SYSTEM/DUMP/` | Debug dumps and `log.txt` | Rebuildable |
| `PSP/SYSTEM/FailedGraphicsBackends.txt` | Backend failures (`T/UI/NativeApp.cpp#L275`) | Rebuildable |
| `PSP/SCREENSHOT/` | Screenshots (`T/Core/Screenshot.cpp#L499`) | Yes |
| `PSP/Cheats/<id>.ini` | Cheats (`T/Core/CwCheat.cpp#L333`) | Yes, if any |
| `PSP/TEXTURES/<id>/` | Replacement packs the user supplies | Yes, if any |
| `PSP/GAME/` | Homebrew and demos, installed from a zip (`T/Core/Util/GameManager.cpp#L75`) | If any |
| `PSP/PLUGINS/`, `PSP/VIDEO/`, `PSP/AUDIO/`, `PSP/shaders/`, `PSP/themes/` | As named | If any |
| `EXDATA/<id>/`, `PAUTH/` | At the root, not under `PSP/`: HD remaster data, Pauth files | If any |

`flash0` isn't in it (§9). `appCacheDirectory` could move the caches, but the SDL build passes no cache folder (`T/SDL/SDLMain.cpp#L1652`).

### What can move it at v1.20.4

**1. The preference.** `defaults write org.ppsspp.ppsspp UserPreferredMemoryStickDirectoryPath <dir>` before a Play.

- It's PPSSPP's own mechanism: Settings ▸ System ▸ Set Memory Stick folder writes the same key (`T/UI/GameSettingsScreen.cpp#L104-L113`, `#L1294-L1297`, `T/Core/Util/DarwinFileSystemServices.mm#L327-L331`). Read once at startup. That menu moves no files.
- **It's per bundle ID, so it's shared with any other PPSSPP**, `/Applications/PPSSPPSDL.app` included. A copy opened by hand would use Ludeum's memory stick, which is the reverse of 0024's "shares nothing".
- It would be Ludeum's first Standing setting kept in a preferences domain rather than a file or a launch's environment. It outlives Ludeum, too.

**2. `$HOME` for the launch.** Ludeum's Play already carries an environment (`App/Sources/GameDetailParts.swift` lines 489–493), which ADR 0035 added for Amiberry.

- The memory stick is then `$HOME/.config/ppsspp`, a hidden folder under whatever's chosen, and it only holds for launches from Ludeum, which since ADR 0027 is all of them.
- The preference still wins if it's ever set, so `/Applications`'s copy or Set Memory Stick folder could defeat it.
- `$HOME` also becomes the file browser's start and `savegame_dir` (`T/SDL/SDLMain.cpp#L1630-L1640`). What it does to Cocoa's own folders, or to `NSUserDefaults`, is **unverified**. ADR 0024 rejected a changed `HOME` for DuckStation, as leaning on a side effect "rather than a feature", and for holding only for Ludeum's launches.

**3. A link at `~/.config/ppsspp`.** ADR 0024 rejected the same for DuckStation: any other copy shares it.

**What can't:**

- **The command line form of the preference.** `NSUserDefaults` would read `-UserPreferredMemoryStickDirectoryPath <dir>`, but `NativeInit` takes any argument not starting with `-` for the boot file, and a second one is `exit(1)` ("Can only boot one file", `T/UI/NativeApp.cpp#L601-L657`). The only exception is `-NSDocumentRevisionsDebugMode` (`#L533-L539`). So it can't go beside a ROM. Not run.
- **An ini key.** `memStickDirectory` isn't a `ConfigSetting`. `CurrentDirectory` (`T/Core/Config.cpp#L237`) is only where the file browser starts. There's no `MemStickDirectory`, and no key for any folder within it.
- **`--root=`.** That's `host0:`, not `ms0:` (`T/UI/NativeApp.cpp#L582-L584`, `T/Core/Config.h#L689`).

**So no portable mode is available on a Mac**, as the earlier note says, and nothing goes in or beside the bundle.

### Splitting settings from saves at v1.20.4

The ini is found through the search path `<memstick>/PSP/SYSTEM` (`T/UI/NativeApp.cpp#L505`, `T/Core/Config.cpp#L1243-L1251`), and nothing changes that. So:

- **The whole memory stick in the Data folder**, as ADR 0035 did with Amiberry's home folder. No links. `ppsspp.ini` with its recent files, `controls.ini`, and caches go in Dropbox. `ppsspp.ini` is rewritten in place (§2), the riskiest thing in there.
- **The memory stick in the Ludeum folder, with `PSP/SAVEDATA`, `PSP/PPSSPP_STATE` and others as links into the Data folder.** Keeps settings local. The reads and writes go through `DirectoryFileSystem` and plain file calls, which should follow a link; **unverified** without running, and it's new for Ludeum.
- **The memory stick in the Data folder, with `PSP/SYSTEM` a link back to the Ludeum folder.** The same in reverse, and per-game inis stay local with it.

### On `master`, for reference

- `--memstick=<dir>` (`M/Core/CmdLine.cpp#L225`, `#L717-L723`, `M/UI/NativeApp.cpp#L734-L739`) sets the root, before the config loads, and isn't saved. It moves everything above.
- `--config=<file>` and `--controlconfig=<file>` (`M/Core/CmdLine.cpp#L404-L405`) set only those two files, by absolute path if given one (`FindConfigFile`, `T/Core/Util/PathUtil.cpp#L12-L19`). `<id>_ppsspp.ini` and all else stay in `<memstick>/PSP/SYSTEM`.
- **So on the next release, `--memstick=<Data> --config=<Ludeum>/ppsspp.ini --controlconfig=<Ludeum>/controls.ini` would be the clean split**, if they survive to it. Not available today.
- **`master` has no build to pin.** A macOS asset is made only for a tag (`T/.github/workflows/build.yml#L389-L391`), and other builds are Actions artifacts (`#L375`), ADR 0027's objection to a nightly. `README.md` points to a `/devbuilds` page on ppsspp.org (`T/README.md#L26`); whether those are kept and versioned is **unverified**, and it's not GitHub's API, so there'd be no digest from there.

## 2. Settings

- **A plain INI**, sections `[General]`, `[CPU]`, `[Graphics]`, `[Sound]`, `[Control]`, `[SystemParam]` and so on (`T/Core/Config.cpp#L1162-L1181`). Ludeum's `[Graphics]` is the right section for its three keys (`T/Core/Config.cpp#L731`, `#L772`, `#L786`). A missing or partial file is defaults (`#L1331-L1336`). There's no version key to satisfy, and **no first-run wizard** on a Mac: an empty memory stick path is what asks, and a Mac's is never empty (`T/UI/NativeApp.cpp#L716-L718`). `bFirstRun` only shows a hint (`T/UI/EmuScreen.cpp#L398-L400`).
- **Read at startup**, once (`T/UI/NativeApp.cpp#L509`), and again when leaving game-specific mode.
- **Written in place, not atomically**: `fopen(…, "w")` (`T/Common/Data/Format/IniFile.cpp#L518-L540`). But **it loads the file first and overlays its values**, so a key or section it doesn't know is kept, and comments too (`T/Core/Config.cpp#L1462-L1465`). A link to the ini would survive, unlike DuckStation's, whose rename replaces it.
- **Written often**: on quitting (`T/UI/NativeApp.cpp#L1493`), on leaving a game (`T/UI/EmuScreen.cpp#L507`), on leaving any settings screen (`T/UI/GameSettingsScreen.cpp#L133`), and **every time a Save state is saved** or loaded through a slot, for the undo's bookkeeping (`T/Core/SaveState.cpp#L422`, `#L490`). So anything Ludeum writes while it runs is lost.
- **`--appendconfig=<file>`** does exist at v1.20.4. It reads the file's keys over the settings, then saves (`T/UI/NativeApp.cpp#L595-L598`, `T/Core/Config.cpp#L1253-L1273`), and it applies again at each Game's first per-game load (`#L1938-L1943`). So it writes its keys into `ppsspp.ini` and into a Game's own ini, if it has one. The earlier note was right to avoid it on the user's own settings. On a memory stick that's Ludeum's, that's less of a worry, but it would overwrite a Game's own choice of the same key.
- **`-j`, `-i`, `-r`, `-J`** at v1.20.4 pick a CPU core and set `bSaveSettings = false` (`T/UI/NativeApp.cpp#L551-L566`), so settings aren't written that run. `master` removes them, as an error (`M/Core/CmdLine.cpp` `Parse`).

### Keys a Standing settings write would touch

All `[General]` unless said, with lines in `T/Core/Config.cpp`:

- `AutoLoadSaveState` (0, off; 2, newest; `#L247`), `EnableStateUndo` (on, `#L269`), `SaveStateSlotCount` (5, UI 1–30, clamped 1–100, `#L274`, `#L1614`), `StateSlot` (`#L268`).
- `[Graphics]` `InflightFrames` (3 at the tag, 2 on `master`, `#L786`, `M/Core/Config.cpp#L1040`), `LowLatencyPresent` (off, `#L772`), `FrameSkip` (0, already, `#L731`), `VerticalSync` (on, `#L771`), `GraphicsBackend` (Vulkan on Apple Silicon, `#L510-L513`).
- `[SystemParam]` `EncryptSave` (on, `#L1099`), `MemStickSize` (16 GB, `#L1100`).
- `PER_GAME` keys are ignored when a Game has its own ini (§10).

### Update checks

**None happen on a Mac.** `Config::Load` calls `CheckForUpdate` (`T/Core/Config.cpp#L1419`), which fetches `http://www.ppsspp.org/version.json` every fifth run (`#L1653`, `#L1678-L1682`), but only if `SupportsUpgradeCheck`, which tests `PPSSPP_PLATFORM(MACOS)` (`#L1640-L1646`). The config header defines `PPSSPP_PLATFORM_MAC`, not `MACOS` (`T/ppsspp_config.h#L7`, `#L114`), so it's false here. `version.json` isn't in either executable on this Mac (`strings`). `master` has the same test (`M/Core/Config.cpp#L2183`).

So `CheckForNewVersion` (`T/Core/Config.cpp#L240`) needs no Standing setting. Even where the check runs, it only shows a bar with a Download button on the main screen (`T/UI/MainScreen.cpp#L481-L500`, `#L551`). Nothing in PPSSPP replaces its bundle.

## 3. Save states

### Names and files

In `PSP/PPSSPP_STATE/`, with lines in `T/Core/SaveState.cpp` unless said:

- **Slot `n`, from 0: `<DISC_ID>_<DISC_VERSION>_<n>.ppst`** (`#L324-L347`), e.g. `ULUS10455_1.00_0.ppst`. Shown to the player as `n + 1` (`#L822`). Five slots by default, more if `SaveStateSlotCount` says.
- **Its screenshot, `<…>_<n>.jpg`** (`T/Core/SaveState.h#L39`, `#L480`, `#L506`), taken as it's saved. It can fail and be absent (`SCREENSHOT_FAILURE_RETRIES`, `#L64`), so a state may have no picture.
- **Its previous one, `<…>_<n>.undo.ppst` and `.undo.jpg`** (`#L66-L68`, `#L485-L487`, `#L501-L505`), when `EnableStateUndo` is on, the default on a Mac (`T/Core/Config.cpp#L190-L196`). That's DuckStation's `.bak` and PCSX2's `.backup`.
- **`load_undo.ppst`**, one file, not per Game, overwritten at each load from a slot, with the Game in `[General] StateLoadUndoGame` (`#L70`, `#L413-L427`). What a state replaced, not a state of a slot. Not made by `--state=`, which isn't a slot load.
- **`<…>.ppst.tmp`** only during a write.

Delete in PPSSPP removes the state and its `.jpg` (`#L539-L548`), or both to the Trash from its browser (`T/UI/GameInfoCache.cpp#L166-L176`), leaving any `.undo`. `master` adds `<…>_<n>.name.txt`, a slot's custom name (`M/Core/SaveState.cpp#L85`).

**When it was saved** is the file's modified time; PPSSPP reads the same (`#L681-L707`).

### Format

`T/Common/Serialize/Serializer.h#L320-L333`, `T/Common/Serialize/Serializer.cpp#L489-L511`:

| Offset | Bytes | What |
|---|---|---|
| 0x00 | 4 | Revision, 5 |
| 0x04 | 4 | Compression: 2, Zstandard |
| 0x08 | 4 | Compressed size |
| 0x0C | 4 | Uncompressed size |
| 0x10 | 32 | The build that saved it: `v1.14.4` |
| 0x30 | 128 | The Game's title, UTF-8 |
| 0xB0 | | The compressed state |

OpenEmu's two states on this Mac have exactly this header (§12). So **Ludeum can read a state's title and build from its first 176 bytes**, with nothing decompressed. `SaveState::GetTitle` does the same (`T/Core/SaveState.cpp#L305-L318`). A state is 3.7–6.5 MB, by those two.

### Written how

Saved under `.tmp`, then the old state is renamed to `.undo.ppst` (or deleted), then the `.tmp` is renamed into place (`T/Core/SaveState.cpp#L483-L495`). So a crash mid-write loses nothing but the temporary file. The compressed write is a plain file write, with no sync in `SaveFile` (`T/Common/Serialize/Serializer.cpp#L417-L523`). The `.jpg` isn't atomic, nor the ini it rewrites (§2).

### Versions

**There's no one version constant.** Each section of a state (94 at the tag) carries its own, and a loader says which it takes: `p.Section("name", min, max)`. A version outside that fails the state (`T/Common/Serialize/Serializer.cpp#L59-L117`). Compared across the tags fetched (a script over `.Section(` calls in `Core`, `GPU`, `Common` and `UI`, so a section read another way would be missed):

| From → to | A section's minimum above what the older tag wrote |
|---|---|
| v1.14.4 → v1.17.1, v1.19.3, v1.20, v1.20.4, `master` | None |
| v1.17.1 → v1.19.3, v1.20, v1.20.4, `master` | None |
| v1.19.3 → v1.20, v1.20.4, `master` | None |
| v1.20, v1.20.4 → `master` | None |

- **So going forward, every state loads**, as far as this check goes. No version changed between v1.20 and v1.20.4.
- **Going back fails.** `master` has raised 27 sections' maximums (`SaveStart` 3 → 6, `PSPSaveDialog` 2 → 6, `sceNetAdhoc` 8 → 13…) and added new ones, so its states won't load in v1.20.4.
- **PPSSPP warns about old states rather than refusing them**: "Loaded. Save in game, restart, and load for less bugs" when the state's first build is older, or it's been reused for over 4 hours' play (`T/Core/SaveState.cpp#L744-L781`). A state keeps "bugs from old PPSSPP versions" (`#L778`). Whether a given old state then runs right is **unverified**.
- **A bump is therefore likelier to be free than ares's or PCSX2's** (ADR 0028, 0032). The file's revision minimum is 4 and the compression Zstandard at every older tag checked and at v1.20.4.

### What a load checks

- **Only the versions, and the title's not compared.** Nothing compares the state's Game to the one running at the tag: `CChunkFileReader::Load` then `SaveStart::DoState` (`T/Core/SaveState.cpp#L826-L860`, `#L136-L198`). At `master`, section version 6 records `DISC_ID` first and only logs a mismatch (`M/Core/SaveState.cpp#L239-L259`), and there's a `PeekBootInfo` that can read it (`M/Core/SaveState.h#L113-L114`).
- **A broken state resets the game**, as "our only remaining option" (`HandleLoadFailure`, `T/Core/SaveState.cpp#L717-L738`, `#L851-L855`). Other failures show a message and carry on (`#L856-L859`).
- **A state rolls back the game's idea of its Game saves.** "Game may refuse to save over newer savedata" (`#L782-L790`). That's a warning, and PPSSPP's own.

### Starting from one

`--state=<file>` at the tag (`T/UI/NativeApp.cpp#L572-L573`, `#L695-L702`):

- **It needs a ROM on the same command line**, and any file, anywhere, with any name.
- **It's queued, not raced.** `SaveState::Load` adds the operation (`T/Core/SaveState.cpp#L221-L230`) during `NativeInit`. Boot's `SaveState::Init` doesn't clear the queue (`#L965-L979`). `Process()` runs it from `RunEmulation`, "before running the frame" (`T/UI/EmuScreen.cpp#L1754-L1755`), and that only runs once `PSP_IsInited()` (`#L1622-L1625`), by which time the kernel's running (`T/Core/HLE/sceKernel.cpp#L170-L176`). So the first frame shown is the state's. There's nothing like MesenCE's lost race. **Unverified by running.**
- **A missing file** is a message, and the game boots normally (`T/Core/SaveState.cpp#L856-L859`).
- **Not during a network connection** (`NetworkAllowSaveState`, `T/Core/SaveState.cpp#L221-L224`, `T/Core/HLE/sceNet.cpp#L166-L168`), nor in RetroAchievements hardcore mode (`T/Core/SaveState.cpp#L204-L211`). Neither is on by default.
- **It's still there on `master`** (`M/Core/CmdLine.cpp#L227`, `M/UI/NativeApp.cpp#L862-L863`).

So a Play can list and Play from a Save state, as with DuckStation and PCSX2: `--state=<file> <rom>`.

### Resume

**No state is made automatically, at the tag or on `master`.** Nothing in `SaveState.cpp` or `EmuScreen.cpp` saves on quitting. The rewind buffer (`RewindSnapshotInterval`, default 0, `T/Core/Config.cpp#L273`) is memory only. PPSSPP only asks for confirmation about leaving with unsaved progress (`T/UI/PauseScreen.cpp#L815-L835`).

**`AutoLoadSaveState`** is the opposite direction: at boot, it loads the oldest, the newest or a set slot of the ones that exist (`T/UI/EmuScreen.cpp#L2031-L2068`, `T/Core/Config.h#L352`). It's off by default, it's a `PER_GAME` key, and it applies only to a boot without Ludeum's asking.

So **ADR 0034's Resume can't be met as DuckStation's, PCSX2's or MesenCE's is**, and ADR 0034's line that PPSSPP keeps "none Ludeum reads" stands. The nearest things are:

- Nothing: Play is a fresh start, as ares's, with states in the section below.
- Treat the newest `.ppst` by its date as the "resume" Ludeum offers. It's what `AutoLoadSaveState = 2` would pick, but it's the player's last deliberate save, not "where the game was", which is what 0034 said Resume means: "a slot… is never resumed from".

## 4. Game saves

### Shape

`T/Core/Dialog/SavedataParam.cpp`:

- **A folder per save: `ms0:/PSP/SAVEDATA/<gameName><saveName>/`** (`#L49`, `#L238-L245`, `#L269-L280`), on the host `<memstick>/PSP/SAVEDATA/…`. `gameName` and `saveName` are both **what the game passes** in `sceUtilitySavedata`, not anything PPSSPP works out, and neither is checked against `DISC_ID`.
- **In it** (`#L40-L44`, `#L491-L612`): `PARAM.SFO`, the game's data file or files, usually `ICON0.PNG`, and maybe `ICON1.PMF`, `PIC1.PNG` and `SND0.AT3`.
- **`PARAM.SFO` is plain**, whatever else is: `TITLE`, `SAVEDATA_TITLE`, `SAVEDATA_DETAIL`, `SAVEDATA_DIRECTORY`, `CATEGORY` (`MS`), `SAVEDATA_FILE_LIST`, `SAVEDATA_PARAMS` (`#L500-L546`).
- **It's the same format as the disc's** (`ReadSFO`, `T/Core/ELF/ParamSFO.cpp#L121-L185`): a magic `\0PSF`, then an index of key offsets, types (`0x0404` a number, `0x0004`/`0x0204` a string) and data offsets. A reader is a few dozen lines, with no dependency.
- **Encrypted saves.** `EncryptSave` is on by default, and a game that asks for secure saving gets its data file encrypted (`#L455-L488`). That hides nothing Ludeum would show: the title, icon and date aren't in it.

### Which are a Game's

- **PPSSPP's own rule is a name prefix**: the folders in `SAVEDATA` beginning with the Game's `DISC_ID` (`GameInfo::GetSaveDataDirectories`, `T/UI/GameInfoCache.cpp#L253-L276`). So for a Serial, it's a directory listing, as PCSX2's folder cards are.
- **One game can use other IDs.** Since `gameName` is the game's choice, nothing stops a game saving under a different product code from its disc's, and a game's search can match by pattern across the folder (`T/Core/Dialog/SavedataParam.cpp#L1216-L1224`). Which real games do is **unverified**. Such a folder would show under no ROM, or under the wrong one.
- **A folder can also be "installed data".** PPSSPP treats a folder holding over 10 MB in its top level as a game's install rather than a save, which its code calls a hack (`T/UI/GameInfoCache.cpp#L278-L327`). Such a folder would go to Dropbox with the saves. Which games do it is **unverified**.

### What Ludeum could show

For a Game with a Serial, the folders with that prefix, each with:

- **Its title**, `SAVEDATA_TITLE` and `SAVEDATA_DETAIL`, from `PARAM.SFO`. UTF-8, and PPSSPP shows them as they are (`T/Core/Dialog/SavedataParam.cpp#L1690-L1692`).
- **Its icon**, `ICON0.PNG`, if there.
- **When last written**, `PARAM.SFO`'s modified time, which is what PPSSPP shows (`T/UI/GameInfoCache.cpp#L240-L243`). Every save rewrites it (`T/Core/Dialog/SavedataParam.cpp#L552`).

A Rename needs no move (§5). No PSP Game save exists on this Mac to check this against (§11, §12).

### Written how

**Plainly and in place**: open with truncate, write, close, one file after another (`WritePSPFile`, `T/Core/Dialog/SavedataParam.cpp#L87-L97`). A crash mid-save, or Dropbox syncing between files, can leave a save half written. `SaveState::NotifySaveData` counts these for the warning in §3.

## 5. Through Archive, Compact and Rename

### The ID

- **`DISC_ID` is read from `disc0:/PSP_GAME/PARAM.SFO`**, inside the image (`LoadParamSFOFromDisc`, `T/Core/PSPLoaders.cpp#L129-L141`, `T/Core/System.cpp#L295-L305`). Nothing about the file's name or form goes in.
- **`DISC_VERSION`, from the same file, is in a state's name.** So another revision of the same `DISC_ID` is another set of Save states, but the same per-game ini (§10) and the same Game saves.
- **`UMD_DATA.BIN` isn't where the ID comes from.** It's read only to tell HD remasters and some prototypes apart (`T/Core/PSPLoaders.cpp#L161-L170`, `T/Core/HDRemaster.cpp#L25-L50`). Those entries show its form: `ULJM-05170|55C069C631B22685|0001|G`.
- **The form differs.** `DISC_ID` has no hyphen: `ULUS10455`, as in `T/Core/HDRemaster.cpp#L25-L50` and OpenEmu's cache file names (§12). A glossary Serial has one (`SLUS-00551`). So Ludeum would keep PPSSPP's form, as it's what names the files, or translate.

### What Ludeum would read

- **ISO 9660: `PSP_GAME/PARAM.SFO`.** `PlayStationDisc.Volume` (`Sources/LudeumCore/Import/PlayStationDisc.swift`) already walks a 2048-byte sector volume and finds a file, ignoring case, so it needs an SFO reader and a new `Serials` branch, not a new volume reader. Whether every real PSP image has the plain ISO 9660 tree this assumes is **unverified** (PPSSPP itself has a UDF block device beside it, `T/Core/FileSystems/BlockDevices.cpp#L257-L263`).
- **Through 7-Zip**, as PlayStation's and PlayStation 2's are (`ROMSerials`, `Sources/LudeumCore/Import/SerialsImport.swift`), since 20 of 21 ROMs are Archived. `PARAM.SFO` sits somewhere within the image, not at a fixed offset, so it costs the windows `ROMSerials` already reads.
- **But `SevenZip.isOnDisk` skips an evicted archive** (`SerialsImport.swift` line 64, `Sources/LudeumCore/Import/SevenZip.swift` line 42). All 21 here are online-only, so as things stand no PSP Serial would be read until the file's been downloaded.
- **`.chd` and `.pbp` are "not read yet"** (`Serials.unreadForms`, `Sources/LudeumCore/Serials.swift` line 64), and `.cso` isn't an ISO 9660 image either: a CSO is compressed blocks. A `.pbp` has its SFO at an offset in the header (`T/Core/PSPLoaders.cpp#L182-L190`).
- **Regions.** `Serials.prefixRegions` (`Serials.swift` lines 35–40) knows only PlayStation's prefixes. PPSSPP takes a PSP Region from the third letter: E, U, J, K, A (`T/Core/ELF/ParamSFO.cpp#L365-L370`).

### What PPSSPP opens

`T/Core/Loaders.cpp#L109-L120`, `#L203-L281`, `T/Core/FileSystems/BlockDevices.cpp#L222-L263`, `T/Core/System.cpp#L214-L247`. Ludeum's PSP entry: `readyExtensions: ["iso", "cso", "chd", "pbp"]`, `archiving: .singleFile`, no `compactExtension` (`Sources/LudeumCore/Import/ROMPlatform.swift` lines 112–114).

| Form | Ludeum: ready? | PPSSPP |
|---|---|---|
| `.iso` | Yes | Opens |
| `.cso` | Yes | Opens (by its `CISO` magic) |
| `.chd` | Yes | Opens (by its magic) |
| `.pbp` | Yes | Opens, a PSN one as a disc image, a homebrew one as a program; a PlayStation one is refused ("PS1 EBOOTs are not supported") |
| `.7z` | Archived | **No**: "7z file detected (Require 7-Zip)" |
| `.zip` | Not read | Not booted: "ZIP file detected". Its UI installs one to `PSP/GAME` |
| `.elf`, `.prx`, a folder | Not read | Open, for homebrew |

So **all of Ludeum's ready forms play, and Ludeum's reading matches**. An Archived ROM is Unarchived first, as now. The bundle's `Info.plist` lists `iso`, `cso` and `pbp` only, which only matters for double-clicking.

### Through each

- **Rename (ADR 0012)**: nothing moves. Keyed by the disc. PPSSPP's `[Recent]` list keeps an old path, and that's a dead menu entry.
- **Archive and Unarchive**: `.7z` of the one file, unpacked to one file named after the ROM. PPSSPP can't open the `.7z`, so an Archived ROM can't be Played. Its saves wait and apply on Unarchive.
- **Compact**: not offered for PSP.
- **A change of form** (`.iso` to `.cso` or `.chd`): the same `PARAM.SFO`, so the same names. Not run: **unverified**.
- **Another region or revision**: another `DISC_ID` or `DISC_VERSION`, so other states, which is right.
- **Multi-disc.** PSP titles are almost all one UMD, and none here is split (`discNumber` empty on all 21). PPSSPP has a UMD swap (`g_UMDReplacePermit`, `T/Core/HLE/sceUmd.cpp#L107-L112`) and no playlist support, and Ludeum's PSP folder reads no `.m3u`.

### A file with no ID

- **Homebrew's ID is made from its file name**: the first four characters, upper-cased, then the sum of all its characters' codes, extension included (`GenerateFakeID`, `T/Core/ELF/ParamSFO.cpp#L318-L346`).
- **So a Rename or a change of extension orphans that file's Save states and per-game ini.** Its Game saves are named by what it asks for. There's a migration for older naming schemes only (`T/Core/PSPLoaders.cpp#L426-L442`).
- **A loose `.pbp` can be taken for homebrew even if it isn't.** `LoadParamSFOFromPBP` keeps a `DISC_ID` only if it doesn't look like homebrew reusing a real ID: not `NP`/`UL`/`UC`, or an unusual region letter, or non-zero `DISC_TOTAL`, or a system version of 5 or above (`T/Core/PSPLoaders.cpp#L201-L213`).
- **An `.iso` has its `PARAM.SFO`**, so doesn't hit this. What's inside this Mac's two `(PSN)` and one `(minis)` archives couldn't be listed, online-only as they are, so their form is **unverified**.

## 6. What else loses one

- **Deleting the memory stick folder**, or pointing at another: it's all one tree (§1). `/Applications`'s copy, or the preference unset, starts empty, and nothing warns.
- **Non-atomic writes.** Game saves (§4), `ppsspp.ini` and per-game inis (§2), and a state's `.jpg` are written in place. A Save state itself is renamed in.
- **A settings write while running** is lost (§2). The other way, `AutoLoadSaveState` or a backend change saved by PPSSPP would stay until the next Standing write.
- **A version bump**: not, as far as the loader goes (§3). Going back to an older build loses newer states to it. `master`'s bumps make that a real one-way door. `EnableStateUndo`'s `.undo` holds only the state before the last.
- **Dropbox online-only files.** `LocalFileLoader` opens and `pread`s the image directly (`T/Core/FileLoaders/LocalFileLoader.cpp#L96`, `#L203-L218`). States, saves and inis are opened with plain file calls. An evicted file stalls the read. This Mac's PSP ROMs are all online-only already, so by that a first Play of the loose `.iso` would download 898 MB as PPSSPP reads it. So the save folders want marking available offline, as ADR 0024 does, and the ROMs raise the same question.
- **A `DISC_ID` differing by region or revision**: expected, and per-Game things go with it. `DISC_VERSION` changes a state's name only.
- **A game saving under an ID that isn't its disc's** isn't lost, just not shown under it (§4).
- **Loading a state over newer Game saves**: PPSSPP warns the game may refuse to save (§3).
- **A crash makes the next launch a muted one that saves no settings** (§7).
- **Set Memory Stick folder, in PPSSPP's own settings**, would move a Play away from Ludeum's folder if the preference is what Ludeum uses, until the next Standing write; or defeat `$HOME` for good if `$HOME` is.

## 7. Single instance

`T/Core/Instance.cpp`, `T/Core/Config.cpp`:

- **A counter in shared memory, `/PPSSPP_ID`** (`#L54`, `shm_open`, `#L148-L156`). `PPSSPP_ID = ++next`, `total++` (`#L159-L162`). `IsFirstInstance` is `PPSSPP_ID == 1` (`T/Core/Instance.h#L30-L32`).
- **A second copy runs in full**: its own window and game. **What it does differently**: it doesn't save settings ("Not saving config - secondary instances don't", `T/Core/Config.cpp#L1445-L1451`), it's muted (`iGameVolume = 0`, `#L1593-L1596`), and it can't change backend. **It still writes Save states and Game saves**, as neither looks at the ID. So two copies of one Game can overwrite each other's. That answers the earlier note's question: yes, a second window, if launched as a new instance, which Ludeum's Play does (`createsNewApplicationInstance`, `App/Sources/GameDetailParts.swift` line 498). Not run.
- **It isn't per memory stick or per bundle.** A second copy of any PPSSPP counts, whichever folder it uses.
- **A crash leaves the counter.** Shutdown decrements and `shm_unlink`s (`T/Core/Instance.cpp#L168-L190`), and the comment there says a crash leaves the object's contents. So the next launch after a crash is `PPSSPP_ID` 2, **muted and saving no settings**, until it quits normally and unlinks the name. Any copy quitting unlinks it, so a third copy started then counts as first while another still runs. That's a real oddity to expect after a crash; **unverified** by running. `master` has reworked the counter's locking (`M/Core/Instance.cpp#L59-L73`).

**"Refuse Play while any PPSSPP is open"** fits, for three reasons: Standing settings written while it runs are lost (§2), a second copy would be silent and not save settings, and both could write one Game's files. It's the same cheap rule as the others (`Sources/LudeumCore/Play.swift` lines 254–263, which don't include PPSSPP today). A check by bundle ID would see `/Applications`'s copy too, as they share an ID. It doesn't cover the muted launch after a crash, since nothing's running then, and Ludeum would know nothing about that.

**Ending a Play**: `--pause-menu-exit` changes the pause menu's "Exit to menu" to "Exit", and `--escape-exit` makes Escape quit (`T/UI/NativeApp.cpp#L574-L577`, `T/SDL/SDLMain.cpp#L1407-L1408`), both `DONT_SAVE` (`T/Core/Config.cpp#L343-L344`). Without them, leaving a game from that menu leaves PPSSPP open at its own menu; closing its window quits (`T/SDL/SDLMain.cpp#L942-L944`). They're the nearest to PCSX2's `-batch`, and a Play refused while it's open is why that might matter.

## 8. Install

### Releases

- **Versioned tags keep their assets.** Of 80 releases, 35 have a `PPSSPPSDL-macOS-v<ver>.zip`, back to v1.12.1 (2021), all still listed. **From v1.19.1 on, 8 of them have a `digest` in the API**, and older ones don't.
- **`v1.20.4`**: `PPSSPPSDL-macOS-v1.20.4.zip`, 37,389,023 bytes, **`sha256:fb32a215861a293c28f641bf47f3164766ba512214025f4457796c8d14242665`**. The download matched, as the issue's numbers do. Built by the tag's workflow (`T/.github/workflows/build.yml#L350`, `#L389-L391`).
- **No nightly can be pinned from GitHub** (§1).

### The zip

- **One thing at the top: `PPSSPPSDL.app`**, 90 MB unpacked, 291 entries.
- **`Contents/MacOS/PPSSPPSDL`** is universal (x86_64 and arm64), 54,020,016 bytes, SHA-256 `fe7db073…3ef8`. `Contents/Frameworks/` holds `SDL2.framework` and `libMoltenVK.dylib`; its other links are system ones (`otool -L`), so **nothing from Homebrew**, unlike MesenCE's.
- **`Info.plist`**: `CFBundleIdentifier` `org.ppsspp.ppsspp`, `CFBundleExecutable` `PPSSPPSDL`, `CFBundleName` `PPSSPP`, `CFBundleShortVersionString` and `CFBundleVersion` both `1.20.4` (`T/SDL/macbundle.sh#L39-L46`), no `LSMinimumSystemVersion`. It has a URL scheme, `ppsspp`.
- **Ad-hoc signed, not notarised**: `codesign -dvv` says `Signature=adhoc`, `flags=0x2(adhoc)`, no team (`T/SDL/macbundle.sh#L52-L57`). `codesign --verify --deep --strict` passes. `spctl` says rejected, and there's no stapled ticket. Entitlements: JIT, unsigned executable memory, executable page protection off. So **Install needs DuckStation's and MesenCE's step**: `ditto`, then remove quarantine. Nothing should be written inside it. Nothing needs to be, as the memory stick's outside.

### The version check

- **`--version` prints `v1.20.4` and returns** before SDL, the config or a window (`T/SDL/SDLMain.cpp#L1419-L1427`). So it's safe to run, and prints what `EmulatorVersions.parse` reads. Not run here. The string's in the executable (`strings`), from `git-version.cpp` for a tag (`T/.github/workflows/build.yml#L305`).
- **`Info.plist`'s version is real too**, so `source: .appVersion` would need no process, as ares's, Amiberry's and Ymir's do. Today's spec, `.commandLine("--version")`, is fine either way.
- **No self-update**: no check runs on a Mac, and nothing replaces the bundle (§2).

### This Mac

`/Applications/PPSSPPSDL.app` is **not the GitHub release**:

| | Release | `/Applications` |
|---|---|---|
| Executable SHA-256 | `fe7db073…3ef8` | `80710bd7…f42b` |
| Size | 54,020,016 | 53,661,584 |
| `codesign` | ad-hoc | Developer ID Application: Millionth Line AB (97NS59EENG), hardened runtime |
| `spctl` | rejected | accepted, "Notarized Developer ID" |
| Ticket stapled | No | No |
| Built in | CI | `/Users/hrydg/ppsspp-buildbot/temp/1.20.4_macOS_BUILD` (in its `strings`) |

Same version, `Info.plist`, `Resources`, entitlements, bundle ID and flags (`diff -rq` differs only in the two executables, SDL2, MoltenVK and the signature): neither has `--memstick` or `--config=`. LaunchServices still remembers it at `/Volumes/PPSSPP/PPSSPPSDL.app` (`lsregister -dump`), so it came from a disk image, which the earlier note says is the site's `PPSSPP_macOS.dmg`. Its quarantine says Chrome, 2026-10-06 00:59 UTC, with no URL recorded. Whether that dmg has a stable, versioned URL is **unverified**. So there are two builds to choose from: GitHub's, with a digest in the API and ad-hoc; or the site's, notarised, with a digest Ludeum would have to pin itself.

## 9. BIOS and firmware

- **None needed.** PPSSPP is a high-level emulator of the system's modules. There's no BIOS folder, no key for one and no check at boot.
- **`flash0` is in the bundle**: `external_dir/flash0` (`T/UI/NativeApp.cpp#L469`), `external_dir` being `SDL_GetBasePath()/assets` (`T/SDL/SDLMain.cpp#L1642-L1651`). `Contents/Resources/assets/flash0/font/` has 18 `.pgf` fonts, `jpn0.pgf`, `kr0.pgf`, `ltn0`–`ltn15` (read in the unpacked release). They're read from there, as `flash0:/font/` (`T/Core/HLE/sceFont.cpp#L880`). Nothing's written there, and nothing for the memory stick.
- **OpenEmu's fonts** in its `PPSSPP/font/` are the same set by name, and not needed.
- **`master`** adds a NAND folder (`PSP/NAND`, `--nand`, `--vsh`) for booting real firmware if you have it (`M/Core/CmdLine.cpp#L226`, `M/UI/NativeApp.cpp#L743`). Whether anything comes to need it is **unverified**.

So unlike PCSX2 and Ymir, Play has nothing to refuse for.

## 10. Per-Game settings and latency

### PPSSPP's own

- **`<memstick>/PSP/SYSTEM/<DISC_ID>_ppsspp.ini`** (`T/Core/Util/PathUtil.cpp#L144-L149`).
- **Only if asked for**: Create Game Config on the game's screen or the pause menu (`T/UI/GameScreen.cpp#L538-L539`, `#L627-L628`, `T/UI/PauseScreen.cpp#L899-L900`). A Game without one uses the global file.
- **Loaded at boot** (`T/Core/PSPLoaders.cpp#L305`, `#L444`). While it's in use, `Save` writes `PER_GAME` keys only there and skips them in `ppsspp.ini` (`T/Core/Config.cpp#L1456`, `#L1475-L1478`).
- **It holds every `PER_GAME` key**, not just changed ones (`SaveGameConfig`, `#L1852-L1860`), plus post-processing and **its own key bindings** (`KeyMap::SaveToIni`, `#L1876`). So once a Game has one, a Standing setting on a `PER_GAME` key no longer reaches it: `LowLatencyPresent`, `FrameSkip`, `VerticalSync`, `AutoLoadSaveState` and `EnableStateUndo` among them.
- **It's named by `DISC_ID` alone**, so it follows a Rename, and is shared by revisions of the disc.

### Does `--config` redirect them?

Answering [psp-emulator.md](psp-emulator.md)'s first question: at v1.20.4 **the flag doesn't exist**. On `master`, no: `configFilename` sets only `iniFilename_`, `controlsConfigFilename` only `controllerIniFilename_`, and per-game inis stay under the search path (`M/UI/NativeApp.cpp#L756`, `T/Core/Config.cpp#L1243-L1251`, which `master` keeps). `controls.ini` needs `--controlconfig` to move, as the earlier note guessed.

### How ADR 0029's shape fits

It fits without trouble:

- A Game's own settings are PPSSPP's, in its per-game file, set during a Play, kept with the rest of the memory stick. If that's in the Data folder, Dropbox has them, as 0029's are for DuckStation.
- Ludeum writes nothing per Game. It has nothing per Game for a PSP Game today: `PPSSPPSettings` takes none (`Sources/LudeumCore/Emulators.swift` line 86), and the glossary says only MesenCE's and ares's Games have Emulator settings.
- So the earlier note's last question (Ludeum's 0–10 run-ahead range) is closed: PPSSPP has no run-ahead, and a PSP Game has no setting of it.

### The copy-the-ini model

`PPSSPPSettings` (`Sources/LudeumCore/Emulators.swift` lines 230–259) at v1.20.4:

- **It reads `~/.config/ppsspp/PSP/SYSTEM/ppsspp.ini`**, which doesn't exist here.
- **It writes `PPSSPP ppsspp.ini` in the Ludeum folder.** No Play has, as there's none there.
- **It passes `--config=`**, which v1.20.4 ignores. In `NativeInit`, an unknown `--` option just falls through the `case '-'` (`T/UI/NativeApp.cpp#L567-L600`). The game boots, on `~/.config/ppsspp`, with PPSSPP's defaults.

So the comment there, "Changes made in PPSSPP during that Play go to the copy and are lost", is wrong too: they go to `~/.config/ppsspp/PSP/SYSTEM/ppsspp.ini` and stay. **This model can't work at the pinned version**, and a managed memory stick would make it pointless on any later one: Ludeum could just write its keys into the real file, or leave them to PPSSPP. It has a test expecting the flag (`Tests/LudeumCoreTests/EmulatorTests.swift` line 115), and the spec describes it (`docs/spec.md` line 198).

### Latency keys

At the tag, what Ludeum wants set (all `[Graphics]`):

- **`InflightFrames`**: default 3, with choices "No buffer" (1), "Up to 1" (2), "Up to 2" (3) (`T/UI/GameSettingsScreen.cpp#L535-L540`). `DEFAULT`, not `PER_GAME`. The earlier note's default of 2 is `master`'s. Vulkan supports setting it (`T/Common/GPU/Vulkan/thin3d_vulkan.cpp#L919`). The UI's hint says only "Faster, input lag", with a TODO to improve it. What `1` costs here is **unverified**.
- **`LowLatencyPresent`**: default off. Used only if the device has `MAILBOX` present mode (`T/Core/FrameTiming.cpp#L118-L127`). Whether MoltenVK offers that on this Mac is **unverified**; the setting's checkbox only shows if so (`T/UI/GameSettingsScreen.cpp#L441-L450`). This is the earlier note's second question and still wants a hands-on test.
- **`FrameSkip`**: default 0 already, so nothing to do unless it's been changed.

**As Standing settings or not?** ADR 0033 moved how DuckStation plays out of the Standing settings, so fast boot and frame pacing are set in DuckStation; ADR 0032 kept `VsyncQueueSize = 0` in PCSX2's. Either could fit. As `InflightFrames` is `DEFAULT` and the other two `PER_GAME`, only `InflightFrames` is certain to reach a Game with its own ini.

## 11. This Mac's data

- **No PPSSPP data found**: no `~/.config/ppsspp`, no `org.ppsspp.ppsspp` preferences domain (so no `UserPreferredMemoryStickDirectoryPath`), no saved application state, nothing in `~/Library/{Application Support,Preferences,Caches,Saved Application State,Containers}`, `~/Documents`, `~/Downloads` or `~/Desktop` by a bounded `find` for `ppsspp*`, `*.ppst`, `PPSSPP_STATE`, `SAVEDATA`, `ppsspp.ini` and `controls.ini`, save OpenEmu's (§12). `mdfind` returned nothing here even for `PPSSPPSDL`, which exists, so it's no evidence either way in this shell.
- **So it's never reached `NativeInit`** on this Mac, which would have made those folders (§1). Quarantine agrees: `/Applications/PPSSPPSDL.app` has flags `0381`, where `/Applications/ymir.app`, which ran once, has `03c1`. That the differing bit means "first launch approved" is **unverified**, Apple's definition not being among these sources.
- **Ludeum's `--version` check may have run it.** It runs once per launch for each installed Emulator (`docs/spec.md` line 201). By the source it leaves nothing (§8). Whether it got past Gatekeeper here isn't known.
- **No Play reached it either**: no `PPSSPP ppsspp.ini` in the Ludeum folder, which any Play writes first. That folder has `Emulators/` with `Amiberry.app`, `DuckStation.app`, `MesenCE.app`, `PCSX2/` and `ares/`, and PCSX2's old ini. Nothing for PPSSPP there or in the Data folder's `Emulators/`.
- **The PSP ROM folder** (`ROMs/PSP`): 21 files, all `dataless`. **20 Archived `.7z`** (The 3rd Birthday, Castlevania: The Dracula X Chronicles, Dariusburst, Daxter, both God of War, three Grand Theft Autos, two Metal Gear Acids, Portable Ops, N+, OMG-Z, both Patapons, Retro City Rampage DX, Scooby-Doo!, Silent Hill: Shattered Memories, Ultimate Ghosts 'n Goblins), 7.9 MB to 1.2 GB. **One loose `.iso`**, Geronimo Stilton (898 MB). No `.cso`, `.chd` or `.pbp` at the top level. All 21 matched to a Game in the journal, `serialsLookedUp = 0`, and no `serials`. Only Geronimo has an MD5. What's inside each `.7z` wasn't listed, as that would have downloaded it.

So there's nothing of PPSSPP's to move over.

## 12. OpenEmu's saves

- **No Game saves to bring across**, as the issue says. `~/Dropbox/games/OpenEmu/Application Support/PPSSPP/PSP/SAVEDATA`, `SYSTEM` and `PPSSPP_STATE` are empty, as they are in `~/Library/Application Support/OpenEmu/PPSSPP/`. What's there is 18 fonts and two `.glshadercache`s, 92 and 140 bytes, `UCES00310` and `ULUS10455`, dated within the same minutes as the two states below. The `OpenEmu Battery Saves archive` has `DeSmuME`, `GenesisPlus` and `Mednafen` only.
- **The issue's "PSP 7, across the two `OpenEmu Save States archive` folders" wasn't found.** `current` has GameBoy, NES, PlayStation, Saturn and SuperNES. `long time ago` has NDS (one empty folder), PlayStation and SuperNES. No PSP folder, and none of their 280 `Info.plist`s says `org.openemu.PPSSPP`. Those folders were last changed on 2026-10-29, the day after the issue's text was researched, and #84's checklist records battery saves removed from the archive as not wanted that day. Whether seven PSP states went too is **unverified**, and Dropbox's history wasn't checked.
- **Two exist elsewhere**, identical in `~/Dropbox/games/OpenEmu/Application Support/Save States/PSP/` and `~/Library/Application Support/OpenEmu/Save States/PSP/`:

| Game | ID | File | Saved | `State` |
|---|---|---|---|---|
| Assassin's Creed: Bloodlines (USA) | `ULUS10455` | `Auto Save State.oesavestate` | 2026-09-05 11:07 UTC | 6,516,777 bytes |
| Syphon Filter: Dark Mirror (Europe) | `UCES00310` | `Auto Save State.oesavestate` | 2026-09-05 11:08 UTC | 3,654,321 bytes |

  Each `Info.plist` says `org.openemu.PPSSPP` 1.14.4.
- **Could they load?** By the format, probably. `State` is an ordinary `.ppst`: revision 5, Zstandard, `v1.14.4`, with the title (§3). No section's minimum has risen past what v1.14.4 wrote (§3), so the loader should accept it with `--state=`, with its warning about old versions. That OpenEmu's core is plain v1.14.4, and that the states then run, are **unverified**.
- **But there's nothing to load them into.** Neither is in `ROMs/PSP` by name, and the journal has no ROM with either state's `ROM MD5`, though it holds an MD5 for only one PSP ROM. "Syphon Filter: Dark Mirror" in the journal and `ROMs/PS2` is the PlayStation 2 version. Each is one automatic state, saved a minute apart, and OpenEmu's `Game Library/roms` is empty.

## 13. Mapping ADRs 0024, 0027, 0028, 0032 and 0035 onto PPSSPP

| ADR | PPSSPP | Notes |
|---|---|---|
| Pinned versioned tag and SHA-256 in code | **Same** | `v1.20.4`, `sha256:fb32a215…2665`. Tags keep their assets (§8). The site's notarised build has no API digest. |
| Unpack without quarantine (0024, 0027) | **Needed for GitHub's** | Ad-hoc signed (§8). |
| Confirm the build | **Either** | `--version` exits before touching anything, or `Info.plist`, with no process (§8). Would become exact. |
| Portable marker in the bundle (0024, 0027), file beside it (0028, 0032) | **Neither exists** | No portable mode on a Mac. The preference or `$HOME` (§1). 0035's environment variable is the nearest, and a `HOME` is what 0024 turned down. |
| Standing settings before every Play and after Install | **Into `<memstick>/PSP/SYSTEM/ppsspp.ini`** | Plus, if the preference is the way, a `defaults write`. PPSSPP keeps keys it doesn't know (§2). |
| Only while the Emulator isn't running | **Same** | Rewritten on quitting, leaving a game, settings and every state (§2). |
| Self-update off | **Nothing to turn off** | No check on a Mac, and nothing replaces the bundle (§2). |
| Save states and Game saves in `Data/Emulators/<Emulator>/` | **Only with everything else, or by links** | At v1.20.4 the whole memory stick moves. 0035 did the same with Amiberry's home (§1). |
| Refuse Play while any copy runs | **Same** | §7. A crash's muted next launch isn't covered. |
| Game detail lists Save states, deletes one | **Yes, with pictures** | `<DISC_ID>_<DISC_VERSION>_<n>.ppst` with `.jpg`, `.undo.ppst` as Previous (§3). Delete takes the state, its `.jpg` and any undo. |
| Play from a Save state | **Yes** | `--state=<file> <rom>`, no race by the source (§3). |
| Resume (0034) | **None** | No automatic state (§3). |
| Game detail shows Game saves | **Yes, as folders** | Prefix on `PSP/SAVEDATA`; title and icon from each; date from `PARAM.SFO` (§4). PCSX2's folder cards are the nearest. A game's other IDs won't show. |
| Rename moves saves (0027, 0028, 0035) | **Not needed** | By the disc (§5). Homebrew excepted. |
| Saves keyed by Serial (0024, 0032) | **`DISC_ID`, and `DISC_VERSION` for states** | Not read today. `PARAM.SFO`, not a boot line (§5). |
| Per-game settings (0029) | **Fits** | PPSSPP's own `<id>_ppsspp.ini`, which Ludeum doesn't touch (§10). The copy-the-ini goes. |
| BIOS (0032) | **None needed** | §9. |
| Writes atomic | **States yes, the rest no** | §3, §4, §6. |
| Folders available offline in Dropbox | **Same need** | Plain file calls (§6). All 21 ROMs are online-only now. |
| A bump costs the Save states (0028, 0032) | **Doesn't, by the loader** | §3. |
| Licence | **GPL-2.0-or-later** | By the source headers. A configured copy is fine. |
| Move over by hand once | **Nothing to move** | §11, §12. |
| Architecture | **Universal, arm64 native** | §8. |

## Open questions for the design session

1. **Move the memory stick how?** The preference (`defaults write`; PPSSPP's own mechanism, shared with any other copy by bundle ID, and a new kind of Standing setting), `$HOME` in the launch's environment (per launch, as 0035's; 0024 turned it down, and its side effects on Cocoa are unverified), or a link at `~/.config/ppsspp` (0024 turned that down too)? (§1)
2. **Wait for 1.21: decided by Daniel on 2026-11-04.** `--memstick`, `--config` and `--controlconfig` are the clean answer, and aren't released. There's no date, and a `master` build has no pin, so #87 waits for the 1.21 release, and this note's facts about the flags want checking against its tag. (§0, §1)
3. **Whole memory stick in the Data folder, or settings kept local?** Whole is simplest and what 0035 did, but `ppsspp.ini` (rewritten in place on every state), recent ROM paths, and caches go in Dropbox. Links keep them local but are new, and unverified. What's worth keeping, from §1's table? (§1)
4. **Which build?** GitHub's ad-hoc zip with an API digest, needing the no-quarantine step, or the site's notarised dmg with a digest of Ludeum's own, if it has a stable URL? (§8)
5. **What's a PSP Play to do at the first Install, given it's never run?** Worth one Play by hand first, to see the folders appear, and confirm `--state=`, the launch's `HOME`, whether `MAILBOX` is offered and what `InflightFrames = 1` costs. Everything here's from source.
6. **Read PSP Serials?** `DISC_ID` from `PSP_GAME/PARAM.SFO` is what lists a Game's Save states and Game saves and names its ini. It's `PlayStationDisc.Volume` plus an SFO reader. Which form: `ULUS10455`, which names the files, or `ULUS-10455`, as the glossary's are and `UMD_DATA.BIN` has it? Should `.cso` be read, and should Serials also say a PSP ROM's Regions, by ADR 0025? And all 21 ROMs being online-only means none would be read until downloaded: mark them available offline? (§5, §6)
7. **Delete the copy-the-ini model.** Remove `PPSSPPSettings`, its `--config=`, its test and the spec's line, whichever way the rest goes? It's been dead since it was written, and today's Play is on defaults. Or fix it first as a smaller change, with the keys as `--appendconfig`? (§2, §10)
8. **Latency keys: Standing settings, or left to PPSSPP as ADR 0033 did for DuckStation?** Only `InflightFrames` is sure to reach a Game with its own ini. (§10)
9. **Resume.** Leave it out, as ares's, or call the newest slot's state "Resume", against ADR 0034's wording that a slot is never resumed from? Should `AutoLoadSaveState` stay off? (§3)
10. **Which of a state's files does Game detail list?** Slots by `<id>_<ver>_<n>`, in what number (PPSSPP shows `n + 1`), and `.undo.ppst` as Previous? `SaveStateSlotCount` is up to 30 in PPSSPP's UI, not 10. `load_undo.ppst` isn't a slot's. (§3)
11. **A state from another `DISC_VERSION`.** Game detail by `<DISC_ID>_` shows every revision's states together, and `--state=` will load one into another with no check. List by prefix, or by the exact version, which needs `DISC_VERSION` read too? (§3)
12. **Game saves that don't start with the disc's ID**, and installed data over 10 MB in `SAVEDATA`: show the latter as saves, or hide them as PPSSPP's size hack does? (§4)
13. **Quitting.** Pass `--pause-menu-exit` and `--escape-exit`, so that closing the game closes PPSSPP and Play can be pressed again? Without them it stays at its own menu and Play is refused. (§7)
14. **The muted launch after a crash.** Accept it as a quirk? Is there anything for Ludeum to do, other than knowing it? (§7)
15. **Back up, restore and delete a Game save (#77).** DuckStation, MesenCE, ares, PCSX2 and Amiberry went without. A save here is a folder, so deleting one is easy, and PPSSPP's own Savedata screen already does (`T/UI/GameInfoCache.cpp#L125-L141`), to the Trash; Dropbox keeps earlier versions. Does this Emulator need anything more? (§4)
16. **OpenEmu's two states.** Nothing to do unless Assassin's Creed: Bloodlines and Syphon Filter: Dark Mirror (PSP) come into the ROM folder. And the issue's "PSP 7": correct it, and should Dropbox's history be looked at? (§12)
17. **Remove `/Applications/PPSSPPSDL.app`?** Same bundle ID, nothing of it elsewhere. With the preference, it would use Ludeum's memory stick; with `$HOME`, it wouldn't. (§1, §8)

## Side findings (outside #87)

- **The earlier notes read `master` as if it were the release.** `psp-emulator.md` and `managing-emulators-inside-ludeum.md`'s PPSSPP row cite `blob/master/Core/CmdLine.cpp` for flags that no release has, which is how `--config=` got into Ludeum and `--memstick` into the issue. In the same way: `--cpu=`, `--resolution-scale=`, `-s` and `InflightFrames`'s default of 2 are `master`'s, not v1.20.4's. Reading a tag's source for a pinned Emulator would have caught it.
- **`--config=` is silently ignored**, so nothing about today's Play would show it (§10): the game starts, and a comment and a passing test say otherwise. On `master`, an unknown `--` option stops the launch with an error (`M/Core/CmdLine.cpp#L558-L560`).
- **Upstream: `PPSSPP_PLATFORM(MACOS)` is never defined**, so the update check is compiled out on a Mac, at the tag and on `master` (§2). A typo, by the look of it, for `MAC`.
- **The glossary's "Save state" says slots are 1 to 10.** PPSSPP's aren't (§3), so the glossary would want a line if it comes under management.
- **`/Applications/PPSSPPSDL.app` is Developer ID–signed and notarised, but the release isn't.** So the project has a signing identity, and the GitHub build doesn't use it (`T/SDL/macbundle.sh#L52-L57`).
- **PPSSPP's `[Recent]` keeps ROM paths in `ppsspp.ini`**, which would go in Dropbox with a whole memory stick (§1).
- **The instance counter's `next` is a `uint8_t`** and is never decremented, only recreated when the name's unlinked (`T/Core/Instance.cpp#L48-L52`, `#L159-L162`). No effect in Ludeum's use.
