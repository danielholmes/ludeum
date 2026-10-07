# Nintendo 3DS emulator for Ludeum

Researched 2026-10-07. Criteria in priority order: compatibility, input latency, a live project, Apple Silicon performance (native arm64, JIT, Metal/Vulkan).

## Recommendation

**Use standalone Azahar.** It's the merge of Lime3DS and PabloMK7's Citra fork, and is now the only live, high-compatibility 3DS emulator. It ships a native **arm64** macOS build (plus x86_64 and universal) with every release. It uses the dynarmic ARM64 JIT and an ARM64 shader JIT, and renders through **Vulkan via a bundled MoltenVK**. On macOS, OpenGL is compiled out. Every other candidate is far behind on compatibility (Panda3DS, Tanuki3DS, 3Beans) or is a slower-moving Citra fork (Mandarine).

**Compatibility is good, with one caveat.** Of the 551 rated titles on the official list, 482 (87%) are playable from start to finish ("Okay" or better), and 365 (66%) are "Great" or "Perfect". The caveat: the list only accepts **OpenGL** reports, and macOS has no OpenGL build, so none of the ratings were measured on the renderer Macs use. A few Vulkan bugs only show up on macOS (see below). More than half the list (663 of 1214) is untested.

It fits Ludeum about as well as melonDS or Ymir do:

- **Games open straight from a file.** Decrypted `.cci`/`.3ds`/`.cxi`/`.3dsx` and their Z3DS-compressed forms (`.zcci`, `.zcxi`, `.z3dsx`) boot by path. Only `.cia` has to be installed first. **Encrypted dumps are refused.**
- **CLI:** `azahar -f <rom>` boots straight into fullscreen. Use the short flag: in 2126.x, long options containing `c`, `x` or `o` (`--fullscreen`, `--windowed`) are swallowed by the new compression CLI (#2548).
- **No config override flag**, and the app doesn't quit when the game stops. A Play ends when the user quits Azahar.
- **No run-ahead.** A maintainer says it isn't possible. The main latency lever is turning **Async Presentation** off, which saves one frame on Vulkan.

**Launch with no settings to start with** (the melonDS/Ymir pattern). If per-Game settings such as screen layout are added later, there are two routes (see "How Ludeum would launch it"). One is the per-game ini Azahar already reads. The other, untested, points `XDG_CONFIG_HOME` at a temp copy of the config, which matches the DuckStation/PPSSPP temp-copy pattern.

## Comparison

| Candidate | Activity (Oct 2026) | macOS build | Graphics on macOS | Compat | Formats | CLI boot | Run-ahead |
|---|---|---|---|---|---|---|---|
| **Azahar** | 2126.1.2 2026-09-20; commit 2026-10-06 | arm64, x86_64, universal `.zip`; ad-hoc signed, not notarized | Vulkan (MoltenVK 1.4.1) only; OpenGL compiled out | 482 of 551 rated titles playable start to finish (OpenGL reports only) | Decrypted only: cci/3ds/cxi/app/3dsx + z-variants; cia installs | `-f <rom>` | No |
| Citra | Dead since March 2024; `citra-emu/citra` is gone | — | — | — | — | — | No |
| Lime3DS | Discontinued; archive repo, last code commit 2024-11-09 | — | — | — | — | — | No |
| Mandarine-Neo | r1.3.0 2026-04-15; commit 2026-04-19 | universal `.zip` | Vulkan (OpenGL off on Apple) | No list of its own (**unverified**) | Citra-style, including encrypted with keys | Citra-era flags | No (**unverified**) |
| Panda3DS | v0.9 2024-12-25; commit 2026-10-04 | `MacOS-Qt.zip`/`MacOS-SDL.zip`; universal nightly | OpenGL by default; Vulkan and Metal available | "Many games boot, many don't"; 57 of 139 reports Playable/Perfect | 3ds/cci/cxi/app/3dsx/elf, encrypted with `aes_keys.txt`; no CIA | `Alber <rom>` | No (**unverified**) |
| Tanuki3DS | v0.5.1 2026-04-13; commit 2026-06-28 | `macos-arm64.zip`, `macos-x86_64.zip` | OpenGL | No list found (**unverified**) | Decrypted only; no CIA | `<rom>` | No (**unverified**) |
| 3Beans (LLE) | release 2026-08-05 | `3beans-mac.zip` | Software/OpenGL (**unverified**) | "still young and has plenty of issues" | Needs *encrypted* dumps | — | No (**unverified**) |
| OpenEmu | No 3DS core | — | — | — | — | — | — |
| libretro (citra, azahar) | Live, but needs RetroArch | — | — | — | — | — | Rejected: RetroArch |

## Candidates

### Azahar
- **Origin:** the first changelog (2120, 2025-03-21) "treats the merge of PabloMK7's fork and Lime3DS as a base". https://github.com/azahar-emu/azahar/releases/tag/2120. `Lime3DS/Lime3DS` now redirects to `azahar-emu/azahar`.
- **Activity:** latest release 2126.1.2 on 2026-09-20, 28 stable releases since 2025-03, last commit 2026-10-06 (`gh api repos/azahar-emu/azahar/{releases,commits}`). https://github.com/azahar-emu/azahar/releases
- **macOS builds:** each release ships `azahar-macos-arm64-<ver>.zip`, `azahar-macos-x86_64-<ver>.zip` and `azahar-macos-universal-<ver>.zip`. The README recommends the universal build, or `macos-arm64` "for Apple Silicon Macs". Minimum macOS is 13.4. https://github.com/azahar-emu/azahar/blob/master/README.md, https://github.com/azahar-emu/azahar/blob/master/CMakeLists.txt (`CMAKE_OSX_DEPLOYMENT_TARGET "13.4"`)
- **Bundle:** `Azahar.app/Contents/MacOS/azahar`, bundle identifier `org.azahar-emu.azahar`. Its `CFBundleDocumentTypes` claims 3dsx/cci/cxi/cia/3ds. https://github.com/azahar-emu/azahar/blob/master/src/citra_meta/CMakeLists.txt, https://github.com/azahar-emu/azahar/blob/master/dist/apple/Info.plist.in, https://github.com/azahar-emu/azahar/blob/master/.ci/macos-universal.sh
- **Signing:** ad-hoc only (`codesign --deep -fs -`), not notarized. https://github.com/azahar-emu/azahar/blob/master/CMakeModules/BundleTarget.cmake. Issue #1012 "Notarize the app on macOS" is open. A maintainer wrote that "signing the app causes some low-level issue with the emulator", so it's on ice. Users have to approve it in Privacy & Security "with every single update". https://github.com/azahar-emu/azahar/issues/1012
- **CPU:** dynarmic (Azahar's fork, A32 frontend), which has an `arm64` host backend and a macOS exception handler. https://github.com/azahar-emu/azahar/blob/master/externals/CMakeLists.txt, https://github.com/azahar-emu/dynarmic/tree/master/src/dynarmic/backend. The PICA shader JIT has an ARM64 compiler (`shader_jit_a64_compiler.cpp`, built on oaknut). https://github.com/azahar-emu/azahar/tree/master/src/video_core/shader
- **Graphics:** `ENABLE_OPENGL` is a `CMAKE_DEPENDENT_OPTION` that's forced OFF when `APPLE`, so macOS builds have Vulkan and Software only, and Vulkan is the default. https://github.com/azahar-emu/azahar/blob/master/CMakeLists.txt, https://github.com/azahar-emu/azahar/blob/master/src/common/settings.h (`graphics_api`). MoltenVK v1.4.1 is downloaded and linked. https://github.com/azahar-emu/azahar/blob/master/CMakeModules/DownloadExternals.cmake (`download_moltenvk`). The README still lists "OpenGL 4.3 or Vulkan 1.1" as the minimum GPU, which is stale for macOS.
- **macOS-specific issues** (open unless noted):
  - #856: glitched lighting on the Main Street cliff in Animal Crossing: New Leaf, "macOS only" (the blue flicker happens on all Vulkan platforms). A maintainer traced it to duplicate-frame handling in the Vulkan stream buffers. https://github.com/azahar-emu/azahar/issues/856
  - #717: macOS folder permissions. Installing CIAs to an emulated SD on an external drive fails. https://github.com/azahar-emu/azahar/issues/717
  - #1543: crash when a Bluetooth controller disconnects. https://github.com/azahar-emu/azahar/issues/1543
  - #1637 (closed 2026-06-29): hang at startup on macOS 26.2. https://github.com/azahar-emu/azahar/issues/1637
  - 2126.1 fixed local-network access on macOS 27 (Artic Base, system-files setup). https://github.com/azahar-emu/azahar/releases/tag/2126.1
  - Only 7 open issues match "mac", and 1 matches "moltenvk".
- **Input latency** (all open issues on Azahar):
  - #1615: Azahar adds "exactly +2 frames" over a real 3DS in commercial games, plus one more with Vulkan **Async Presentation** on. Homebrew measures about 1 frame. https://github.com/azahar-emu/azahar/issues/1615
  - #2475: finished frames wait for the next vblank to be presented (median 0.818 frames). https://github.com/azahar-emu/azahar/issues/2475
  - #2476: SDL controllers are polled on a fixed 10 ms timer, adding up to 10 ms. https://github.com/azahar-emu/azahar/issues/2476
  - #1595 (closed): Async Presentation adds one frame. The fix was a tooltip change. https://github.com/azahar-emu/azahar/issues/1595
  - **Run-ahead:** PabloMK7 on #2581: "Not possible, this requires rewinding which isn't possible on a powerful device as the 3DS." https://github.com/azahar-emu/azahar/issues/2581
  - Latency-relevant settings (`[Renderer]` group, all per-game capable `SwitchableSetting`s): `async_presentation` (default true), `use_vsync` (default true on desktop), `use_skip_duplicate_frames` (default false), `use_display_refresh_rate_detection` (default true). https://github.com/azahar-emu/azahar/blob/master/src/common/settings.h

### Compatibility (Azahar)
- Source: `compatibility_list.json` in the official repo (last commit 2026-08-20). https://github.com/azahar-emu/compatibility-list. Ratings run 0–5, and 99 means untested. https://github.com/azahar-emu/compatibility-list/blob/master/CONTRIBUTING.md
- Counts (1214 entries):

  | Rating | Titles | Share of rated |
  |---|---|---|
  | 0 Perfect | 177 | 32% |
  | 1 Great | 188 | 34% |
  | 2 Okay (major glitches, beatable) | 117 | 21% |
  | 3 Bad (can't finish) | 43 | 8% |
  | 4 Intro/Menu | 19 | 3% |
  | 5 Won't Boot | 7 | 1% |
  | 99 Untested | 663 | — |

- **Not macOS-specific, and not Vulkan at all.** The README says "Vulkan is not included in this compatibility list, as it is considered to be in an unstable state. Compatibility reports should only be made against the OpenGL renderer". https://github.com/azahar-emu/compatibility-list/blob/master/README.md. macOS builds have no OpenGL, so a Mac can't reproduce the list's conditions.
- The list was seeded from Citra's data. A 2024-07-05 commit removed Switch games as "a holdover from the previously combined Citra+Yuzu compatibility database". So many ratings probably date from Citra (**unverified** how many). https://github.com/azahar-emu/compatibility-list/commit/b29d56c0
- A search of the list's issues for "macos" returns 2.

### Citra
- Shut down in March 2024. `citra-emu/citra` returns 404, and the org holds only `citra-web`, archived 2024-03-04 (`gh api orgs/citra-emu/repos`). Azahar's blog calls Tropic Haze "the company behind the now defuct emulators Yuzu and Citra". https://azahar-emu.org/blog/game-loading-changes/. PabloMK7's fork (`PabloMK7/citra`) is also gone; it became Azahar.

### Lime3DS
- Discontinued. `Lime3DS/lime3ds-archive` is archived: "a copy of the final source code of the now-discontinued Lime3DS emulator project … please use Azahar". Last tag 2119.1, last code commit 2024-11-09. https://github.com/Lime3DS/lime3ds-archive

### Mandarine-Neo
- `mandarine3ds/mandarine` redirects to `ptyfyre/mandarine-neo`. Latest release r1.3.0 (2026-04-15) includes `mandarine-macos-universal-….zip`, and the last commit was 2026-04-19, so it's slow. Its own README says "Azahar is still the reccomended choice for most people". https://github.com/ptyfyre/mandarine-neo
- It's a Citra fork that still decrypts encrypted NCCH (`is_encrypted = true; // Find primary and secondary keys`). https://github.com/ptyfyre/mandarine-neo/blob/neo/src/core/file_sys/ncch_container.cpp. OpenGL is also off on Apple. https://github.com/ptyfyre/mandarine-neo/blob/neo/CMakeLists.txt

### Panda3DS
- Latest release v0.9 (2024-12-25) with `MacOS-Qt.zip` and `MacOS-SDL.zip`. Nightly universal app bundles, ad-hoc signed. Last commit 2026-10-04. https://github.com/wheremyfoodat/Panda3DS, https://github.com/wheremyfoodat/Panda3DS/blob/master/.github/workflows/MacOS_Build.yml
- README: "Many games boot, many don't. Lots of games have at least some hilariously broken graphics". Encrypted dumps work with `sysdata/aes_keys.txt`. ".cia files are not supported yet". https://github.com/wheremyfoodat/Panda3DS/blob/master/readme.md
- Games list (issue labels): perfect 6, playable 51, ingame 41, menu 19, intro 4, broken 18. https://github.com/Panda3DS-emu/Panda3DS-Games-List
- dynarmic plus an arm64 shader recompiler. OpenGL is the default on macOS, with Vulkan and Metal backends. `config.toml` is read from the current directory if present, otherwise from app data. https://github.com/wheremyfoodat/Panda3DS/blob/master/include/config.hpp, https://github.com/wheremyfoodat/Panda3DS/blob/master/src/emulator.cpp

### Tanuki3DS, 3Beans, others
- Tanuki3DS: v0.5.1 (2026-04-13) has `Tanuki3DS-macos-arm64.zip`, last commit 2026-06-28. "All games must be decrypted". Formats are cci/3ds/cxi/app/elf/3dsx (no CIA). OpenGL (glad + imgui opengl3). CLI is `getopt "hl"` plus a ROM path, and config is `ctremu.ini`. I found no compatibility list. https://github.com/burhanr13/Tanuki3DS
- 3Beans: low-level. Release 2026-08-05 has `3beans-mac.zip`. It "requires encrypted cartridge dumps" and is "still young and has plenty of issues". https://github.com/Hydr8gon/3Beans
- CitraVR is a Meta Quest port, not macOS. https://github.com/amwatson/CitraVR
- OpenEmu: an org search for "citra" or "3ds" returns nothing, so there's no 3DS core.
- libretro: `libretro/citra` (last commit 2026-09-20) and Azahar's own `azahar-libretro-macos-arm64` release asset both exist. Excluded, because RetroArch is rejected.

## Game formats, keys and system files (Azahar)

- **Recognised extensions** (`GuessFromExtension`): `.cci`/`.zcci`/`.3ds` → NCSD cartridge, `.cxi`/`.zcxi`/`.app` → NCCH, `.3dsx`/`.z3dsx` → homebrew, `.cia`/`.zcia` → installable archive, `.elf`/`.axf`. https://github.com/azahar-emu/azahar/blob/master/src/core/loader/loader.cpp
  - `.3ds` was dropped in 2120 ("rename the file to use the `.cci` extension") and restored on 2026-01-29 ("frontend: Revert removal of .3ds support (#1701)").
  - Z3DS compression (zstd) was added 2025-07-27. The `.z*` names are the compressed forms; there's no `.z3ds` extension. `azahar -c <rom> [-o dir]` compresses and `-x` decompresses. https://github.com/azahar-emu/azahar/blob/master/src/citra_meta/common_strings.h
- **Encrypted dumps are refused.** `if (!ncch_header.no_crypto) { // Encrypted NCCH are not supported; return ErrorEncrypted; }`. https://github.com/azahar-emu/azahar/blob/master/src/core/file_sys/ncch_container.cpp. The blog says Azahar "will not allow launching or installing encrypted games, unless they have been obtained through Nintendo's official applications, such as the eShop". The cryptographic keys are now bundled, so users don't provide `aes_keys.txt`. https://azahar-emu.org/blog/game-loading-changes/
- **System files aren't needed for most games.** Open-source replacements for the JPN/EUR/USA system font and the bad-word list are bundled. https://github.com/azahar-emu/azahar/blob/master/externals/open_source_archives/Readme.md. Real system files (Home Menu, eShop, some applets) now come only from a real 3DS through the Artic Setup Tool (2120 changelog). Which games need them is **unverified**.
- **CIA must be installed.** Passing a `.cia` to Play shows "CIA must be installed before usage … Do you want to install it now?" and doesn't boot. `azahar -i <file.cia>` installs to the emulated SD, prints the result to stdout on macOS and exits: code 0 on success, `InstallStatus + 2` on failure. https://github.com/azahar-emu/azahar/blob/master/src/citra_qt/citra_qt.cpp (`GMainWindow` constructor, `BootGame`, `ShowCommandOutput`). An installed title lives at `<user>/sdmc/Nintendo 3DS/<id0>/<id1>/title/<high>/<low>/content/<id>.app` (`GetTitleContentPath`). https://github.com/azahar-emu/azahar/blob/master/src/core/hle/service/am/am.cpp
- **Updates/DLC overlay automatically.** When a cartridge image boots, the NCCH loader looks for an installed update (`0004000E…`) on the emulated SD and overlays it. https://github.com/azahar-emu/azahar/blob/master/src/core/loader/ncch.cpp. So updates and DLC are CIAs installed once, and the base game is still opened from its file.

**For Ludeum:** keep a **decrypted `.cci`/`.3ds` (or `.zcci`)** as the ROM and hand that path to Azahar. Decrypted `.cxi` and `.3dsx` work the same way. A `.cia` base game would need an Install step and then a Play of the installed `.app`, like Vita but lighter, so it's simplest to tell users to convert to `.cci`. Ludeum can't tell encrypted from decrypted by extension. Check the NCCH header's `no_crypto` flag at import (exact byte offset **unverified**), or let Azahar's "Encrypted application" error explain it (**unverified** which is better). Update and DLC `.cia` files aren't Games. They're installed into Azahar once (`-i`).

## CLI (from the parser)

`main()` in https://github.com/azahar-emu/azahar/blob/master/src/citra_meta/main.cpp first runs `CitraCLI::CheckForOptions("c:x:o:")` with `getopt`. If any of `-c`/`-x`/`-o` appears, it runs the compression CLI instead of the GUI. Otherwise the Qt frontend parses `QApplication::arguments()` by hand in the `GMainWindow` constructor (https://github.com/azahar-emu/azahar/blob/master/src/citra_qt/citra_qt.cpp):

- `<path>`: the **last** argument, if it doesn't start with `-`, is booted (`BootGame`). A lone argument also works (drag/drop).
- `-f`/`--fullscreen`, `-w`/`--windowed`: set the Fullscreen action, which `BootGame` applies.
- `-i`/`--install <cia>` (install and exit), `-g <port>` (gdb), `-p`/`-r`/`-a` (TAS movies), `-d <file>` (dump video), `-v`, `-h`. `-m` (multiplayer) is "not yet implemented for the Qt frontend".
- **No `--config`, no `--no-gui`, no "exit when the game closes", and no per-setting override.** #1556 ("Screen layout as command line arguments") and #1711 ("QoL improvements for CLI") are open. On #1711 PabloMK7 suggests "a frontend can just edit the ini file". https://github.com/azahar-emu/azahar/issues/1556, https://github.com/azahar-emu/azahar/issues/1711
- **Long options are broken in 2126.x (#2548, open):** `getopt` reads `--fullscreen` as `-f -u -l -l -s -c reen`, so it starts compressing a file called "reen". Any long option containing `c`, `x` or `o` is hit (`--fullscreen`, `--windowed`, `--movie-play`…). `-f` and `-w` work. The report is from Linux; the same code runs on macOS (**unverified** there). https://github.com/azahar-emu/azahar/issues/2548
- **Fullscreen is saved back.** `BootGame` calls `UpdateUISettings()` (which sets `UISettings::values.fullscreen` from the action) and then `config->Save()`. So `-f` persists `[UI] fullscreen=true` into `qt-config.ini`. Passing `-f` or `-w` on every Play keeps this predictable.
- **When the game stops** (F5, an error, or the title exiting), `ShutdownGame` hides the render window and shows the game list again. The process keeps running. In the default single-window mode, closing the window quits Azahar. With a game running, it first asks "Would you like to exit now?" (`confirm_before_closing`, default true).
- **Its own desktop shortcuts** launch `azahar [-f] "<path>"` (`OnGameListCreateShortcut`). ES-DE's macOS rules run `/Applications/azahar.app/Contents/MacOS/azahar %ROM%`. https://gitlab.com/es-de/emulationstation-de/-/raw/master/resources/systems/macos/es_systems.xml

## Config files (macOS)

From `SetUserPath` in https://github.com/azahar-emu/azahar/blob/master/src/common/file_util.cpp and https://github.com/azahar-emu/azahar/blob/master/src/common/common_paths.h:

- **Default:** `~/Library/Application Support/Azahar/`, with `config/qt-config.ini` (all settings, controls and hotkeys), plus `nand/`, `sdmc/`, `sysdata/`, `cache/` and so on.
- **XDG override:** if `$XDG_DATA_HOME/azahar-emu`, `$XDG_CONFIG_HOME/azahar-emu` *or* `$XDG_CACHE_HOME/azahar-emu` exists (defaults `~/.local/share`, `~/.config`, `~/.cache`; the env vars are read with `getenv`), those XDG paths are used instead. Config then sits directly in `$XDG_CONFIG_HOME/azahar-emu/`.
- **Portable:** a `user/` folder in the current directory. On macOS `LaunchQtFrontend` first changes directory to the folder that contains `Azahar.app`, so the folder must sit next to the app (#1406). Ludeum can't use this per launch.
- Legacy `Citra`/`Lime3DS` folders are migrated (`user_data_migrator`).
- **Per-game config:** `<config>/custom/<TITLE ID as 16 hex digits>.ini`, or the file name for title ID 0. `BootGame` loads it before booting. It holds only `SwitchableSetting`s, each written as `key\use_global=false` plus `key=value` in QSettings INI format. Azahar rewrites it on load (`Reload()` calls `SaveValues()`), but otherwise only when the user edits Properties. `OnStopGame` restores the global values. https://github.com/azahar-emu/azahar/blob/master/src/citra_qt/configuration/config.cpp
  - Inferred from source: `BootGame` saves the *global* config after loading the per-game one, and `WriteBasicSetting` writes `GetValue()` (the per-game value while it's active). So per-game values may sit in `qt-config.ini` until Azahar's next save on quit. That only matters if Azahar is killed (**unverified**).

## Dual-screen layout settings

All of these are in `[Layout]` and can be set per game (`SwitchableSetting`), from https://github.com/azahar-emu/azahar/blob/master/src/common/settings.h:

- `layout_option`: 0 Default (top over bottom), 1 Single Screen, 2 Large Screen, 3 Side by Side, 4 Separate Windows (desktop only), 5 Hybrid, 6 Custom.
- `swap_screen` (bottom screen as the main one), `upright_screen` (rotated, for vertical games), `large_screen_proportion` (1–16, default 4), `small_screen_position` (0 TopRight … 2 BottomRight (default) … 6 AboveLarge, 7 BelowLarge), `screen_gap`, `aspect_ratio`.
- In-game hotkeys: F10 cycles layouts (`layouts_to_cycle`), F9 swaps screens, F8 rotates upright.
- Candidates for per-Game settings in Ludeum: **layout** (Default / Large / Side by Side / Hybrid / Single), **swap screens** (bottom-screen-heavy games) and **upright** (e.g. games played with the 3DS turned sideways). Custom-layout rectangles are global only.

## How Ludeum would launch it

```
Emulator(name: "Azahar", bundleIdentifier: "org.azahar-emu.azahar")

# Play: no settings, straight into fullscreen. Short flag only (#2548).
/Applications/Azahar.app/Contents/MacOS/azahar -f "/path/to/Game.cci"
```

In `Emulators.swift` that's `case .azahar: ["-f", rom.path(percentEncoded: false)]`. A Play ends when the Azahar process exits, as with Vita3K, because stopping the game leaves Azahar on its game list.

If per-Game settings are added (layout, Async Presentation off), there are two routes:

1. **Per-game ini (works today, persists).** Read the title ID from the ROM's NCCH header (the program ID Azahar's loader reads). Merge Ludeum's keys into `~/Library/Application Support/Azahar/config/custom/<TITLEID>.ini`, keeping the user's other keys, the same `Ini.setting` approach DuckStation uses:
   ```
   [Layout]
   layout_option\use_global=false
   layout_option=2
   [Renderer]
   async_presentation\use_global=false
   async_presentation=false
   ```
   The catch: this **is** saved into the user's emulator config. Ludeum could restore the file when the process exits.
2. **XDG temp copy (closer to the DuckStation pattern; untested).** Launch through `NSWorkspace.OpenConfiguration.environment` with `XDG_CONFIG_HOME=<Ludeum>/Azahar config`. That folder's `azahar-emu/` holds a copy of `qt-config.ini` with Ludeum's keys written over it (and `custom/` copied in). Point `XDG_DATA_HOME` and `XDG_CACHE_HOME` at folders whose `azahar-emu` entry is a symlink to `~/Library/Application Support/Azahar` (and its `cache/`), so saves, NAND and SD stay the user's. Azahar's writes land in the copy. Whether symlinks behave everywhere (CIA installs, the migrator) is **unverified**.

## Open questions
- How close does Vulkan-on-MoltenVK get to the OpenGL-based ratings on the user's own Games? Only a hands-on test answers this. #856 shows at least one macOS-only rendering bug.
- Is #2548 (long options) also broken on macOS's BSD `getopt`? `-f` sidesteps it either way.
- Does Gatekeeper need re-approving after every Azahar update? (#1012 says yes.) Does that affect Ludeum's launch, or only the first manual open?
- Is it worth exposing Async Presentation off (one frame less latency) as a per-Game setting, or only telling the user to turn it off globally? Does it cost frame pacing under MoltenVK?
- Should Ludeum refuse `.cia` base games at import, or add an Install step (`-i`) plus a Play of the installed `.app`?
- Does the XDG temp-copy route work end to end, and does Azahar's `user_data_migrator` misfire when it sees the XDG layout?
