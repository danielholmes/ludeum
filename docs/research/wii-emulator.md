# Nintendo Wii emulator for Ludeum

Researched 2026-10-06. Criteria in priority order: run-ahead / input-latency reduction, accuracy, a live project, performance (Apple Silicon native/JIT, Metal/Vulkan).

## Recommendation

**Keep standalone Dolphin, which Ludeum already launches for GameCube and Wii.** For Wii it has no rival: it's the only live, high-compatibility Wii emulator. It ships a universal (arm64 + x86_64) macOS build with an ARM64 JIT as the default CPU core and Metal as the default renderer, and it's very active (release 2609 on 2026-09-24, dev build 2609-61 on 2026-10-05). **No Wii emulator has run-ahead.** Dolphin has no run-ahead code and I found no PR for it. The libretro Dolphin core declares its savestates `basic`, while libretro reserves run-ahead for `deterministic` cores. So criterion 1 comes down to Dolphin's latency settings, which Ludeum already sets for every Play: **Rush Frame Presentation** and **Smooth Early Presentation** (Dolphin measured Rush at 8–14 ms faster in Wind Waker and Sunshine). **WiiWare and Virtual Console `.wad` files work with Ludeum's existing launch line (`-e <file>.wad`) and need nothing installed first.** Dolphin installs the WAD into its emulated NAND as a *temporary* title, then boots it from there. The content stays until a different WAD is booted, and save data stays for good. Dolphin doesn't need a NAND dump, a System Menu, IOS or keys for this. What Ludeum still needs is a Wii ROM folder: there's no `ROMPlatform` for platform 5 yet. Cemu doesn't emulate vWii and won't. Every fork (PrimeHack, Slippi, MMJR, the libretro core) is either single-game, Android-only, dead or behind upstream.

## Comparison

| Candidate | Run-ahead | Latency options | Accuracy / compat | Activity (Oct 2026) | macOS arm64 | Per-launch, non-persisted settings | `.wad` |
|---|---|---|---|---|---|---|---|
| **Dolphin** | No (no code, no PR found) | Rush Frame Presentation, Smooth Early Presentation, Immediately Present XFB, VSync | Highest; 188 per-title fix inis for WiiWare IDs alone | Release 2609 2026-09-24; dev 2609-61 2026-10-05 | **Universal build**, ARM64 JIT default, Metal default, Vulkan via bundled MoltenVK | `-C <System>.<Section>.<Key>=<Value>` (a command-line layer that is never saved) | **Yes**: `-e x.wad` installs temporarily and boots; GUI install/uninstall; `-n <title ID>` |
| libretro Dolphin core (RetroArch) | No: `savestate_features = "basic"` | Subset of Dolphin's | Dolphin, 60 commits behind upstream | commit 2026-10-04 | Via RetroArch | Rejected: RetroArch | `wad` in `valid_extensions` |
| Cemu | — | — | **No Wii/vWii**, "not_planned" | v2.6 2025-02-06; commit 2026-10-04 | x86_64 build under Rosetta (README) | — | — |
| PrimeHack | No | Dolphin's | Metroid Prime Trilogy only | 1.0.9 2026-06-09 | Unverified | — | Inherits Dolphin (unverified) |
| Slippi (Ishiiruka / dolphin) | Rollback netplay for Melee, no general run-ahead | — | SSBM (GameCube) only | v3.6.4 2026-06-15 | Mac dmg (arch unverified) | — | Irrelevant |
| Dolphin MMJR / MMJR2 | No | — | Android-only performance forks | Last push 2021-08 / 2022-06 | No | — | — |

## WiiWare and .wad

### Booting a `.wad` directly: a temporary NAND install
- **`-e path/to/Game.wad` (or a bare path argument) boots a WAD.** `-e/--exec` ("Load the specified file") → `BootParameters::GenerateFromFile`. That function sends `.wad` to `DiscIO::CreateWAD` and a `BootParameters` holding a `VolumeWAD`. https://github.com/dolphin-emu/dolphin/blob/master/Source/Core/UICommon/CommandLineParse.cpp (lines 87–91), https://github.com/dolphin-emu/dolphin/blob/master/Source/Core/DolphinQt/Main.cpp (~219–242), https://github.com/dolphin-emu/dolphin/blob/master/Source/Core/Core/Boot/Boot.cpp (lines 276–281). It is recognised by its magic (`0x00204973`, or `0x00206962` for boot2), not only by its extension. https://github.com/dolphin-emu/dolphin/blob/master/Source/Core/DiscIO/Volume.cpp (lines 151–164)
- **What "booting" does.** `CBoot::Boot_WiiWAD` calls `WiiUtils::InstallWAD(ios, wad, InstallType::Temporary)` and then `BootNANDTitle(system, wad.GetTMD().GetTitleId())`. If the install fails, it shows "Cannot boot this WAD because it could not be installed to the NAND." https://github.com/dolphin-emu/dolphin/blob/master/Source/Core/Core/Boot/Boot_WiiWAD.cpp (lines 33–41)
- **"Temporary" isn't cleaned up when the game stops.** `InstallWAD` (https://github.com/dolphin-emu/dolphin/blob/master/Source/Core/Core/WiiUtils.cpp, lines 146–198) works like this:
  - It skips the install if the same contents are already on the NAND (hash-checked).
  - If a *different version* of the title is installed, it asks "Installing this WAD will replace it irreversibly. Continue?" (`AskYesNoFmtT`). That's a modal dialog mid-Play.
  - It deletes the *previous* temporary title's content, then imports the ticket, TMD and contents. Signature checks are off ("A lot of people use fakesigned WADs").
  - It records the title ID in SYSCONF `IPL.TID`, "the same mechanism as the System Menu for temporary SD card title data".
  - The commit that introduced this explains the reasoning: "Because the Wii NAND size is finite, mark titles that were installed only for booting as temporary, and remove them whenever we need to install another title". https://github.com/dolphin-emu/dolphin/commit/dedb61e5bf (2017-10-24; the older "direct WAD launch hack" was dropped in PR #6094, https://github.com/dolphin-emu/dolphin/pull/6094)
  - So **a booted WAD's content stays in the NAND until a different WAD is booted**, and booting the same WAD again reuses it.
- **The removal only deletes the `.app` content files.** `ESCore::DeleteTitleContent` leaves `title.tmd`, the ticket and **`/data` (saves)** in place. https://github.com/dolphin-emu/dolphin/blob/master/Source/Core/Core/IOS/ES/TitleManagement.cpp (lines 635–652)
- When installing, Dolphin also creates the Wii Shop log files, because "some games (eg. Mega Man 9) refuse to load DLC if they are not present". (WiiUtils.cpp lines 111–141)

### Installing and uninstalling, and launching an installed title
- **GUI:** there's **Tools → Install WAD…** (MenuBar.cpp line 331), and a game-list right-click on a WAD offers **Install to the NAND** / **Uninstall from the NAND**. Uninstall says it removes the title "without deleting its save data". Both are disabled while emulation runs. https://github.com/dolphin-emu/dolphin/blob/master/Source/Core/DolphinQt/MenuBar.cpp, https://github.com/dolphin-emu/dolphin/blob/master/Source/Core/DolphinQt/GameList/GameList.cpp (lines 470–497, 656–697). Tools → Manage NAND has Import BootMii NAND Backup and Check NAND.
- **CLI: there's no install or uninstall flag.** The `dolphin` binary only has `-u -m -e -n -C -s -d -l -b -c -v -a`. `dolphin-tool` only has `convert, verify, header, extract`. https://github.com/dolphin-emu/dolphin/blob/master/Source/Core/UICommon/CommandLineParse.cpp (lines 85–125), https://github.com/dolphin-emu/dolphin/blob/master/Source/Core/DolphinTool/ToolMain.cpp (line 25)
- **To launch an installed title, use `-n/--nand_title <16 hex chars>`** (e.g. `-n 0001000157414541`). `CBoot::BootNANDTitle` → `ES::LaunchTitle`. If the title is absent, it shows "Could not launch title … because it is missing from the NAND." https://github.com/dolphin-emu/dolphin/blob/master/Source/Core/DolphinQt/Main.cpp (~228–240), https://github.com/dolphin-emu/dolphin/blob/master/Source/Core/Core/IOS/ES/ES.cpp (~418–434)
  - `dolphin-tool header -j <file>` prints `title_id` for a WAD too, because `CreateVolume` falls back to `TryCreateWAD`. The ID is printed as a JSON number. HeaderCommand.cpp lines 71–99, Volume.cpp lines 176–187. Whether `dolphin-tool` is in the macOS app bundle is **unverified**.
  - Ludeum has no need for `-n`, because `-e x.wad` does the install itself.

### Requirements: none beyond Dolphin
- **No IOS:** "we can't rely on titles being installed as we don't require system titles". IOS is HLE'd, and only MIOS (GameCube via the System Menu) must exist on the NAND. https://github.com/dolphin-emu/dolphin/blob/master/Source/Core/Core/IOS/ES/ES.cpp (lines ~378–392)
- **No keys:** the retail and Korean ("new") common keys, plus default device credentials, are built into `IOSC`. https://github.com/dolphin-emu/dolphin/blob/master/Source/Core/Core/IOS/IOSC.cpp (lines ~564–623). `keys.bin` in the Wii root is optional and only overrides them.
- **No System Menu or NAND dump** is needed to boot a WAD (the boot path above never touches the System Menu). The NAND guide says a dump is for the Wii Menu, saves and "some games [that] may require files only found in a full NAND dump". The Shop channel refuses to run with default credentials. https://dolphin-emu.org/docs/guides/nand-usage-guide/, ES.cpp lines 341–355
- **Out of the box, Dolphin ships** HLE IOS, built-in keys, a generated SYSCONF and per-title GameSettings. Those settings include fixes for many WiiWare (`W*`, 188 inis) and VC IDs, e.g. `NAC.ini` (Ocarina of Time VC). https://github.com/dolphin-emu/dolphin/tree/master/Data/Sys/GameSettings

### Save data, and why it doesn't break ADR 0008
- Saves go to `<user>/Wii/title/00010001/<lower 8 hex of title ID>/data/`. https://github.com/dolphin-emu/dolphin/blob/master/Source/Core/Common/NandPaths.cpp (`GetTitlePath`/`GetTitleDataPath`). On macOS, `<user>` is `~/Library/Application Support/Dolphin` (`NORMAL_USER_DIR`), unless `portable.txt`, `$DOLPHIN_EMU_USERPATH` or `-u` says otherwise. https://github.com/dolphin-emu/dolphin/blob/master/Source/Core/Common/CommonPaths.h (line 17), https://github.com/dolphin-emu/dolphin/blob/master/Source/Core/UICommon/UICommon.cpp (~420–448)
- **Saves persist across Plays, which is what we want.** They're game data, like GameCube memory cards, not Emulator settings. Each `-e x.wad` Play does write to the NAND, though: the title contents, ticket and TMD, and SYSCONF `IPL.TID`. That's emulated-console state, not Dolphin preferences, so ADR 0008 isn't affected. But it means **a Play isn't read-only on Dolphin's user folder.**
- Saves don't live in Ludeum's Data folder (Dropbox). The same is already true for GameCube.
  - An option is to pass `-C Main.General.NANDRootPath=<dir>`. `MAIN_FS_PATH` is read in `UICommon::Init` → `InitCustomPaths`, after `ParseArguments` adds the command-line layer, so a per-launch NAND root should take effect. https://github.com/dolphin-emu/dolphin/blob/master/Source/Core/Core/Config/MainSettings.cpp (line 335), UICommon.cpp lines 102–104. That's from code order only and is **unverified** in practice.
  - It would also move disc games' Wii saves.

### Formats: which extensions are Wii ROMs
- Dolphin's boot path treats these as disc images: `.gcm .bin .iso .tgc .wbfs .ciso .gcz .wia .rvz .nfs .dol .elf`. It also takes `.wad`, `.json` (mod descriptor), `.dff` (FIFO log) and `.m3u/.m3u8` (Boot.cpp lines 217–283). The game list scans the same set (`.wad` included). https://github.com/dolphin-emu/dolphin/blob/master/Source/Core/UICommon/GameFileCache.cpp (lines 32–33)
- The FAQ lists GCM/ISO, GCZ, CISO, WBFS, WIA, NFS ("Wii games purchased from the Wii U eShop") and RVZ. It warns that "WBFS and CISO are lossy" (scrubbed) and recommends RVZ. Dolphin can compress to GCZ, WIA and RVZ. https://dolphin-emu.org/docs/faq/
- **Suggested `readyExtensions` for Wii (IGDB 5): `["rvz", "wbfs", "iso", "wia", "gcz", "ciso", "wad"]`.**
  - Leave out `.gcm` and `.tgc` (GameCube-only conventions) and `.bin` (too ambiguous).
  - Leave out `.dol`, `.elf` and `.json` (homebrew and mods).
  - Leave out `.m3u` (Wii multi-disc is effectively non-existent; **unverified**).
  - Leave out `.nfs`. It isn't a single file: Dolphin wants `…/content/hif_000000.nfs` plus siblings, and the key at `…/code/htk.bin`. https://github.com/dolphin-emu/dolphin/blob/master/Source/Core/DiscIO/NFSBlob.cpp (lines 27–45, 84, 131)
- **Archiving:** Dolphin can't open a `.wad` or a disc image inside `.7z`/`.zip` (no archive blob reader in `Blob.h`'s `BlobType`). So Wii fits `archiving: .singleFile` like GameCube, with no `compactExtension`. Converting a WAD to RVZ isn't offered: `dolphin-tool convert` opens its input with `CreateDisc` and is about disc images. https://github.com/dolphin-emu/dolphin/blob/master/Source/Core/DolphinTool/ConvertCommand.cpp
- **Box art:** WiiWare and VC entries live in `libretro-thumbnails/Nintendo_-_Wii` with No-Intro-style suffixes, e.g. `World of Goo (USA) (WiiWare).png` and `Super Mario 64 (USA) (N64) (Virtual Console).png`. There's no separate "Wii (Digital)" thumbnails repo, though libretro-database has a `Nintendo - Wii (Digital).rdb`. https://github.com/libretro-thumbnails/Nintendo_-_Wii, https://github.com/libretro/libretro-database/tree/master/rdb

### Caveats
- **Different installed version:** a modal "replace it irreversibly" prompt appears during a Play (see above). Examples are an update WAD (`v257` vs `v258` both appear in the box-art repo) or a version installed from a NAND dump.
- **DLC WADs** (e.g. `Mega Man 9 (USA) (WiiWare) (DLC)`) are separate titles that have to be *installed*, through the GUI only. Booting one as a Play makes no sense, and what happens if you do is **unverified**. Ludeum should treat a DLC WAD as not a Playable ROM, or keep DLC out of the ROM folder. A temporarily booted base game later loses its content when another WAD boots, but its DLC title (separate ID) and its save stay.
- **Fakesigned / "decrypted" WADs:** signature checks are off on install, and `GetTicketWithFixedCommonKey()` repairs a wrong common-key index in zero-signature tickets. https://github.com/dolphin-emu/dolphin/blob/master/Source/Core/DiscIO/VolumeWad.cpp (lines 171–…). A WAD's contents must still be in the standard encrypted WAD layout. Fully decrypted "WAD" dumps aren't a format Dolphin reads (**unverified**).
- **Wii U Virtual Console titles are Wii U titles, not WADs**, so Cemu, not Dolphin, runs those (**unverified**, no primary source checked). Wii games bought from the *Wii U* eShop are NFS folders (see above), not `.wad`.
- **Per-title issues:** e.g. Ocarina of Time (Wii VC) has more lag frames than hardware, per Dolphin bug #12831 (https://bugs.dolphin-emu.org/issues/12831; I didn't read it, because the tracker and wiki sit behind a bot check, so **unverified**). For the same reason, the wiki's WiiWare/VC compatibility pages are **unverified**.
- The Wii Shop Channel can't be used with default credentials (ES.cpp lines 341–355), so nothing can be re-downloaded in-emulator.

## Candidates

### Dolphin
- Activity: tag `2609` 2026-09-24, `2606a` 2026-08-11, `2606` 2026-06-25, `2603` 2026-03-12 (`gh api repos/dolphin-emu/dolphin/git/tags/…`). The download page lists dev build 2609-61 "13 hours ago" (PR #14889), and the last push to master was 2026-10-05. Every release and dev build has a "macOS (ARM/Intel Universal)" download. https://dolphin-emu.org/download/, https://github.com/dolphin-emu/dolphin. GitHub Issues is disabled, and bugs go to https://bugs.dolphin-emu.org/.
- **Apple Silicon:** universal binaries are built by `BuildMacOSUniversalBinary.py`. `DefaultCPUCore()` returns `JITARM64` on `_M_ARM_64`. https://github.com/dolphin-emu/dolphin/blob/master/Source/Core/Core/PowerPC/PowerPC.cpp (lines 243–251), https://github.com/dolphin-emu/dolphin/tree/master/Source/Core/Core/PowerPC/JitArm64
- **Renderers:** on macOS, Metal is placed first (the default), Vulkan comes before OpenGL ("OpenGL support being deprecated by Apple"), and MoltenVK is bundled (`USE_BUNDLED_MOLTENVK`, "with Dolphin-specific patches"). https://github.com/dolphin-emu/dolphin/blob/master/Source/Core/VideoCommon/VideoBackendBase.cpp (lines 214–225), https://github.com/dolphin-emu/dolphin/blob/master/CMakeLists.txt (lines 116, 158, 640)
- **Run-ahead: none.** There's no "runahead" or "run ahead" anywhere in `Source/`. A GitHub PR search for "runahead"/"run-ahead" finds nothing relevant. A Dolphin feature request on bugs.dolphin-emu.org may exist, but I couldn't search the tracker (bot check), so that's **unverified**. Dolphin's stated latency approach is presentation timing, not rollback.
- **Latency settings** (Progress Report Release 2512, https://dolphin-emu.org/blog/2025/12/22/dolphin-progress-report-release-2512/, PR #14037 https://github.com/dolphin-emu/dolphin/pull/14037):
  - `Main.Core.RushFramePresentation` (default false): throttling is "centered around presenting the frame as soon as it can after the input is read", measured at "somewhere between 8 - 14ms" in Wind Waker and Sunshine.
  - `Main.Core.SmoothEarlyPresentation` (default false): delays presentation "roughly 1-2ms" to even out frame pacing.
  - `GFX.Hacks.ImmediateXFBEnable` (default false): bigger cuts, but "a hack that relies on games behaving in a specific manner".
  - Melee click-to-photon from the report: console on CRT 62 ms, Dolphin default 56, Rush 53.3, Immediate 37.
  - Both new options are "disabled by default in the Configuration -> Advanced Tab".
  - https://github.com/dolphin-emu/dolphin/blob/master/Source/Core/Core/Config/MainSettings.cpp (lines 55–58), https://github.com/dolphin-emu/dolphin/blob/master/Source/Core/Core/Config/GraphicsSettings.cpp (lines 202–204)
- CLI (https://github.com/dolphin-emu/dolphin/blob/master/Source/Core/UICommon/CommandLineParse.cpp):
  - `-e/--exec <file>` (repeatable; multiple discs).
  - `-n/--nand_title <16-hex title ID>`.
  - `-C/--config <System>.<Section>.<Key>=<Value>` (repeatable).
  - `-b/--batch`: "Run Dolphin without the user interface (Requires --exec or --nand-title)". In batch mode the app exits when emulation stops. https://github.com/dolphin-emu/dolphin/blob/master/Source/Core/DolphinQt/MainWindow.cpp (line 934)
  - `-u/--user <dir>`, `-s/--save_state <file>`, `-v/--video_backend`, `-a/--audio_emulation HLE|LLE`, `-c/--confirm`, `-d`, `-l`, `-m`.
- **`-C` is never saved.** The values form a `CommandLine` config layer whose `Save()` is "// Save Nothing" (lines 63–74). Layer search order: CurrentRun → Netplay → Movie → **LocalGame → GlobalGame → CommandLine** → Base. https://github.com/dolphin-emu/dolphin/blob/master/Source/Core/Common/Config/Enums.h (lines 39–47). **So a game ini (Dolphin's shipped `Sys/GameSettings` or the user's) that sets the same key beats `-C`.**

### libretro Dolphin core
- A fork of upstream: last commit 2026-10-04, 417 ahead and 60 behind `dolphin-emu/dolphin` master (`gh api …/compare`). `valid_extensions = "elf|dol|gcm|iso|tgc|wbfs|ciso|gcz|wad|wia|rvz|m3u"`. https://github.com/libretro/dolphin/blob/master/Source/Core/DolphinLibretro/Main.cpp (line 164)
- **Run-ahead: not supported.** The core info has `savestate_features = "basic"`, and libretro's own key reads "basic, serialized (rewind), deterministic (netplay/runahead)". https://github.com/libretro/libretro-core-info/blob/master/dolphin_libretro.info, https://github.com/libretro/libretro-core-info/blob/master/00_example_libretro.info. It "exposes only a subset" of Dolphin's features (same info file). Excluded anyway, because RetroArch is rejected.

### Cemu
- A Wii U emulator only. Two issues closed as `not_planned`: #1788 "vWii support?" (2026-01-18: "For Wii emulation see Dolphin Emulator") and #1845 (2026-03-21; maintainer Exzap: "We don't have any plans to support vWii mode in Cemu because it works so differently it's almost like developing a wholly new emulator"). https://github.com/cemu-project/Cemu/issues/1788, https://github.com/cemu-project/Cemu/issues/1845
- Latest release v2.6 (2025-02-06), with a `macos-12-x64` dmg. The README calls the macOS build "purely experimental", with "degraded performance due to the use of MoltenVK and Rosetta for ARM Macs". https://github.com/cemu-project/Cemu

### PrimeHack
- A Dolphin fork "intended to give Metroid Prime Trilogy mouselook controls". 1.0.9 released 2026-06-09. https://github.com/shiiion/dolphin. One-game focus, so not a general Wii emulator.

### Slippi (Ishiiruka and the mainline-based fork)
- `project-slippi/Ishiiruka` v3.6.4 (2026-06-15, includes a Mac dmg) and `project-slippi/dolphin` (pushed 2026-08-30) are for Super Smash Bros. Melee (GameCube) netplay. https://github.com/project-slippi/Ishiiruka. Not relevant for Wii. Dolphin's own report notes Slippi's latency lead comes from "deep modifications to how Super Smash Bros. Melee outputs".

### Dolphin MMJR / MMJR2
- Android-only performance forks. Last pushes were 2021-08-29 (`acidtech/Dolphin-MMJR`) and 2022-06-04 (`Mato00KAN/Dolphin-MMJR2`). Dead, and not macOS.

## How Ludeum would launch it

The launch is the same as today's Dolphin line in `Emulator.arguments` (`Sources/LudeumCore/Emulators.swift`), and it works unchanged for discs and WADs:

```
/Applications/Dolphin.app/Contents/MacOS/Dolphin \
  -C Main.Core.RushFramePresentation=True \
  -C Main.Core.SmoothEarlyPresentation=True \
  -e "/…/ROMs/Wii/World of Goo (USA) (WiiWare).wad"
```

(The binary path inside the bundle is **unverified**. Ludeum opens Dolphin by bundle id `org.dolphin-emu.dolphin`.)

- Optionally add `-b`, so Dolphin opens no main window and quits when the game stops. That makes one Play = one process, as with PCSX2's `-batch`.
- What Ludeum still has to add is a `ROMPlatform` for IGDB 5 (Wii):
  - folder `Wii`
  - `readyExtensions: ["rvz", "wbfs", "iso", "wia", "gcz", "ciso", "wad"]`
  - `libretroRepo: "Nintendo_-_Wii"`
  - `archiving: .singleFile`
- Whether IGDB lists WiiWare/VC games under platform 5 rather than a separate platform is **unverified**.

## Options for passing per-Game settings

1. **`-C` overrides** (recommended, already used). They're per-launch and never saved (the `CommandLine` layer's `Save()` does nothing). Watch out: Dolphin's game-ini layers beat the command line, so a shipped or user game ini setting the same key wins.
2. **`-u <dir>`** with a Ludeum-owned user folder: rejected. It relocates everything (NAND/saves, controllers, GameCube memory cards), not just settings.
3. **Editing `Dolphin.ini` before launch:** rejected, because it persists.
4. A WAD-specific option, only if wanted: **`-C Main.General.NANDRootPath=<Data folder>/Wii NAND`** keeps Wii saves (and temporary WAD installs) inside the Data folder (**unverified** in practice; see above).

## Open questions
- Does `-e x.wad` misbehave when the user already has that title installed at another version? It brings up a modal mid-Play. Should Ludeum warn about this, or just accept it?
- What does Dolphin do if a DLC WAD (`00010005…`) is passed to `-e`? Should Import ignore `(DLC)` WADs or flag them in the Review queue?
- Does Hasheous identify WADs by checksum (No-Intro "Nintendo - Wii (Digital)")? And are No-Intro WAD hashes over the same bytes Ludeum hashes?
- Does `-C Main.General.NANDRootPath=…` really redirect the NAND for that launch only, and does it also move SYSCONF (language, aspect ratio)?
- Ludeum's 0–10 run-ahead range doesn't map onto Wii. Should Wii (and GameCube) get a per-Game "Immediately Present XFB" toggle instead, since that's Dolphin's biggest latency lever but breaks some games?
- Would `-b` (batch) suit Ludeum's Dolphin Plays, given the spec currently says Dolphin "open[s] another window"?
