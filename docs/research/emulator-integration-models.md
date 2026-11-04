# Emulator integration models: managed standalone apps, OpenEmu's cores, libretro, launchers

Researched 2026-11-04, when six of Ludeum's ten Emulators were under its management (ADRs 0024, 0027, 0028, 0032, 0035, 0036) and the other four had their research notes and issues (#83 Dolphin, #85 melonDS, #87 PPSSPP, #89 xemu). The question: Ludeum started by launching Emulators installed on the Mac like any app, then moved to installing its own pinned copies and writing their settings before each Play. OpenEmu did neither: it ran each emulator as a core inside itself. Before finishing the last four, which model fits Ludeum, and what does each cost? This note lays out the facts and the comparison. The decision is [ADR 0038](../adr/0038-emulators-are-whole-apps-ludeum-installs-not-cores.md).

Sources:

- **OpenEmu SDK**, `OpenEmuBase/OEGameCore.h`, `OpenEmuBase/OEGameCoreController.h` and `OpenEmuSystem/OESystemResponder.h` on `master` of `OpenEmu/OpenEmu-SDK`, read raw. The SDK's README answered 404, and `OEGameCoreDisplayModes.h`, the `OpenEmuHelperApp` folder and the `OpenEmuKit` submodule were not read.
- **OpenEmu's README and repository root** on `master` of `OpenEmu/OpenEmu`, and the GitHub REST API for its releases and latest commits.
- **libretro's API**, `include/libretro.h` on `master` of `libretro/libretro-common`, read raw in parts (the first 39 KB, the last third, and the end; the middle was summarised, not read).
- **libretro's core registry**, `dolphin_libretro.info` and `ppsspp_libretro.info` in `libretro/libretro-core-info`, and the commit history of `libretro/dolphin`.
- **Each Emulator's README** on its default branch: `stenzek/duckstation`, `ares-emulator/ares` (with its `thirdparty/` and `desktop-ui/` listings), `SourMesen/Mesen2` (archived 2026-06-04, pointing at `nesdev-org/MesenCE`, which was not read), `ymir-emu/Ymir`, and `JesseTG/melonds-ds`.
- **Ludeum's code and docs** on `main` at commit `5ad1ead`: `Sources/LudeumCore/Emulators.swift`, the Emulator ADRs, [managing-emulators-inside-ludeum.md](managing-emulators-inside-ludeum.md) and the four pending notes.

Anything not checked against one of these is marked **unverified**. Nothing was run.

## Answer

**The managed-standalone model Ludeum has now is the right one, and the core model isn't open to it anyway.** Seven of Ludeum's ten Emulators exist as no core at all, OpenEmu's or libretro's (§3), so a core-based Ludeum would be a different set of emulators, mostly worse ones. OpenEmu's own roster shows the trade: Mednafen for PlayStation and Saturn where Ludeum has DuckStation and Ymir, no PlayStation 2, Xbox or Amiga, and a last release in December 2023 (§1). The unification OpenEmu gets from its core API, one save-state list and one set of keys for every system, Ludeum can get at its own layer, and the Save state and Resume work already does (§4). What the managed model costs is per-Emulator work that can be finished; what the core model costs is a ceiling on each emulator's own settings that can't be raised (§2).

## 1. How OpenEmu does it

OpenEmu is a frontend plus a plugin SDK. Each emulator is wrapped as a core plugin, a bundle holding a subclass of `OEGameCore`, and that class is the whole contract between OpenEmu and the emulator:

- **The frame loop is OpenEmu's.** The core implements `executeFrame`, documented as "Called every 1/(rate*frameInterval) seconds by -runGameLoop:. The core should produce 1 frameInterval worth of audio and can output 1 frame of video." OpenEmu owns timing, pause, fast-forward (`rate`) and rewind (`supportsRewinding`, `rewindInterval`, `rewindBufferSeconds`).
- **Video and audio are buffers the core fills.** `getVideoBufferWithHint:`, `screenRect`, `aspectSize`, `pixelFormat`, and `audioBufferAtIndex:` with its rate, depth and channels. A core renders to a bitmap, OpenGL 2 or OpenGL 3 context (`OEGameCoreRendering`); Metal is declared "Not yet implemented."
- **Save states are bytes the core serialises.** `serializeStateWithError:` and `deserializeState:withError:` are optional; `saveStateToFileAtPath:completionHandler:` and `loadStateFromFileAtPath:completionHandler:` are required. OpenEmu owns the files, their naming, screenshots, the slots, quick save and load, and the Save States UI, identically for every system. A core that can't is flagged with `OEGameCoreSaveStatesNotSupportedKey`.
- **Game saves and BIOS are folders OpenEmu hands over.** `batterySavesDirectoryPath`, `biosDirectoryPath` and `supportDirectoryPath`. The core writes what it likes there, in its own format.
- **Input comes through a per-system responder.** `OpenEmuSystem` has a system plugin per console (`OESystemController`, `OESystemResponder`, the bindings and HID device handlers), which maps events to `pressEmulatorKey:` and `releaseEmulatorKey:` on a client protocol the core implements. Controller mapping is OpenEmu's, once, for every core.
- **Discs and cheats** are two optional methods each (`discCount` and `setDisc:`; `setCheat:setType:setEnabled:`).
- **Settings are the thin part.** A core declares option flags in its bundle (cheats, multiple discs, rewind, file insertion, display-mode changes, required files) and can offer a Display Modes menu (`displayModes`, `changeDisplayWithMode:`). There is no general mechanism for a core to expose its own settings; what the standalone emulator offers in its own preferences is simply not reachable. That's structural, not an oversight: the frontend's unified UI is the point.

**Process model.** The repository has an `OpenEmuHelperApp` folder, and `OEGameCoreController`'s `newGameCore` is declared `bycopy`, a Distributed Objects marker, so the core runs in a helper process and a crash there doesn't take OpenEmu down. The transport (XPC or otherwise) is **unverified**, as the manager headers weren't found.

**Roster.** The README lists each system's core: Stella, Atari800, ProSystem, Mednafen (Lynx, NeoGeo Pocket, PC-FX, Saturn, PlayStation, PC Engine and CD, Virtual Boy, WonderSwan), CrabEmu, Nestopia and FCEUX, Gambatte, mGBA, Dolphin, Genesis Plus (Game Gear, SG-1000, Sega CD, Mega Drive, Master System), Bliss, Mupen64Plus, DeSmuME, O2EM, picodrive, PPSSPP, BSNES and Snes9x, VecXGL. Each core is a fork in OpenEmu's own organisation (`Mednafen-Core`, `Mupen64Plus-Core`, `DeSmuME-Core` and the rest, pinned as submodules), maintained by OpenEmu, not by the emulator's author.

**State of the project.** Releases: v2.4.1 and v2.4 on 2023-12-30 ("Binaries are Intel-only"), before that v2.3.3 on 2021-01-09. The latest commit on `master` was 2025-10-22, a year before this note. Building needs Xcode 14.3 and Ventura. There has been no Apple Silicon release.

## 2. The other models

Four shapes, which every launcher I know of is one of or a mix of:

1. **Core host.** OpenEmu, and libretro's frontends (RetroArch, Ludo, Lakka). The emulator is a library the frontend calls once per frame, and the frontend owns everything around it. libretro's `libretro.h` is the same contract in C: `retro_run` ("Runs the game for one video frame."), `retro_load_game`, `retro_serialize` and `retro_unserialize` for Save states, `retro_get_memory_data(RETRO_MEMORY_SAVE_RAM)` for battery saves ("Regular save RAM. This RAM is usually found on a cartridge, backed up by a battery."), and `RETRO_ENVIRONMENT_SET_CORE_OPTIONS_V2` for the options a core shows the frontend. libretro's options are richer than OpenEmu's (categories, descriptions, a value list each), but they're still what the core's port chose to expose, not the emulator's own settings UI. Pros: one Save state format and UI, one input mapping, rewind, run-ahead and shaders for every system at once, a crash contained to one process. Cons: a wrapper per emulator that someone must maintain (OpenEmu kept 25 forks), a ceiling on settings, and cores that lag or fork their standalone (§3).
2. **Launcher.** EmulationStation Desktop Edition, LaunchBox, Pegasus. A launch command per system, pointing at whatever emulator is installed. Nothing is owned: Save states, Game saves and settings are the emulator's and live where it puts them. Pros: nothing to maintain. Cons: a hand update can break a launch (as DuckStation build 8843 did, ADR 0024), and the launcher can show nothing of what the emulator keeps. This was Ludeum's first model.
3. **Configurator.** Batocera, RetroBat, EmuDeck. The launcher installs pinned emulators, owns their data folders and generates each emulator's config at launch from its own settings, leaving the rest to the emulator. Batocera's `configgen` rewrites each emulator's config file before every launch; EmuDeck installs the emulators and writes their settings into its own layout. Pros: the emulator's own quality and settings, with the launcher owning what it cares about (paths, latency, a state to start from), and the emulator's own UI for the rest. Cons: a research note per emulator, as its file formats and flags differ, and the launcher can only do what the emulator's settings and flags allow. **This is Ludeum's current model**, and the one the Steam Deck and arcade-cabinet distributions converged on for the same reasons.
4. **Hybrid.** Those same distributions use RetroArch cores for 8-bit and 16-bit systems and standalones for GameCube, PlayStation 2, Xbox and later, because the standalones are better there and the cores don't exist or lag. ES-DE's default launch rules list both for most systems.

## 3. Which of Ludeum's Emulators exist as a core

| Emulator (Platforms) | OpenEmu | libretro |
|---|---|---|
| MesenCE (NES, SNES, Game Boy, GBA, Master System, Game Gear and the rest) | no | none shown in Mesen 2's README; MesenCE's not read (**unverified**) |
| DuckStation (PlayStation) | no; Mednafen | none of its own: its README's licence treats "pre-configured settings and packages" as modifications and forbids publishing modified versions, and its author withdrew the libretro core, which lives on as a fork (**unverified**: not on the pages read) |
| PCSX2 (PlayStation 2) | no PlayStation 2 at all | not found: `libretro/pcsx2` and `libretro/lrps2` both answer 404 |
| Dolphin (GameCube, Wii) | yes, a fork pinned in OpenEmu's tree | yes, `libretro/dolphin`, a fork merging upstream (last on 2026-09-24) with its own commits to 2026-10-29; its registry entry says "the dolphin-launcher core may be a better fit" |
| ares (N64, Mega Drive, Sega CD) | no | none in its README, `thirdparty/` or `desktop-ui/` |
| melonDS (DS) | no; DeSmuME | yes, melonDS DS, "An enhanced remake of the melonDS core for libretro", statically linking standalone melonDS; no Save states for homebrew or DSi mode |
| Ymir (Saturn) | no; Mednafen | no; "A work-in-progress Sega Saturn emulator", ad-hoc signed |
| PPSSPP (PSP) | yes | yes, official, with serialised Save states and core options |
| xemu (Xbox) | no | no |
| Amiberry (Amiga) | no | no; libretro's Amiga core is PUAE, a different emulator |

So a core-based Ludeum keeps three of ten at best (Dolphin, melonDS, PPSSPP), and for the rest plays a different, older or lesser emulator, or nothing. DuckStation, the Emulator with the most Ludeum work behind it (ADRs 0021 to 0026, 0029, 0033), can't be a core at all under its licence.

## 4. Where Ludeum stands

**What the managed model has bought**, Emulator by Emulator:

- A pinned build, fetched and checked by digest, apart from any other copy, so a hand update can't break Play, and a new Mac is one Install from playing (0024, 0027, 0028, 0032, 0035, 0036).
- Save states and Game saves in the Data folder, so Dropbox has them and Game detail lists them, with Play from a state and Delete (every managed Emulator) and Resume (DuckStation, PCSX2, MesenCE; 0034).
- Ludeum's settings kept to where things go, latency and a state to start from, with the Emulator's own UI for how it plays (0033), chosen per setting rather than all or nothing.

**What it costs**, as the notes record:

- A research note per Emulator before its ADR, each finding a different shape: DuckStation's `portable.txt` inside the bundle, ares's `settings.bml` beside the app, PCSX2's data root, Ymir's `-p` profile, Amiberry's home folder in the environment, Dolphin's state folder that no setting can move, PPSSPP's flags that aren't in a release yet.
- Save states that look different per Emulator: ares's and Ymir's have no screenshot; ares's and Dolphin's load only in the build that saved them, so a bump loses them; Ymir's load only with its own keys once the Game is running.
- Play refused while an Emulator is open, because each rewrites its settings file whole (0024, 0028).
- No rewind, no run-ahead and no shader on a Platform whose Emulator lacks it, and no one set of keys across Emulators.

**What a core would give that the managed model can't:** one Save state format with screenshots for every Platform, rewind and run-ahead everywhere, one controller mapping, and no refusing Play while an Emulator is open. Of those, the 8-bit and 16-bit Platforms are where it would show, and MesenCE covers them natively with run-ahead, rewind, screenshots in its states and an automatic state every minute. A hybrid that hosted libretro cores for those Platforms would duplicate MesenCE for a unified UI Ludeum can draw itself from the files, and would carry the one thing the managed model doesn't: a frame loop, audio, video and input stack inside Ludeum.

## 5. What the Emulators still to manage look like under each model

- **Dolphin (#83):** a core exists in both ecosystems, but it's a fork, and Ludeum's note found Game saves have settings and `-C` flags while Save states need the whole user folder. Managed is harder than the others but possible.
- **melonDS (#85):** a well-kept core, but standalone melonDS is the same code, and the managed model reads its files where they are.
- **PPSSPP (#87):** an official core, and the only one where a core would be strictly simpler, as its flags for a managed copy are on `master` only. The note's conclusion was to wait for 1.21, not to change model.
- **xemu (#89):** no core anywhere; managed or launcher is the only choice.
