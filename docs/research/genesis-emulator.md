# Sega Genesis / Mega Drive emulator for Ludeum

Researched 2026-10-06. Criteria in priority order: run-ahead, accuracy, a live project, performance.

## Recommendation

**First choice: RetroArch with the Genesis Plus GX libretro core.** It is the only option that gives a variable run-ahead frame count (1+ frames, plus a "preemptive frames" mode) that can be set on every launch. RetroArch's `--appendconfig` overlays a small per-launch config file holding `run_ahead_frames`, and `config_save_on_exit = false` stops it writing anything back. That matches ADR 0008's "send the full set every time, never persist" model. Genesis Plus GX claims "very accurate emulation and 100% compatibility" with released Genesis, Sega CD, SMS and Game Gear software, and both its upstream and libretro repos had commits this week. It has no 32X. **Runner-up: ares.** It's highly accurate (its Mega Drive core comes from higan), natively cross-platform, covers Mega CD and 32X, and has a CLI `--setting name=value` override that it puts back before saving. But its run-ahead is only an on/off switch (one frame), so Ludeum's 0–10 range would collapse to off or on. **BlastEm** is the accuracy pick (the first emulator to run Overdrive 2, and 1.0.0 added Sega CD and 32X in Sept 2026), but I found no run-ahead in it, so it can't meet criterion 1.

## Comparison

| Candidate | Run-ahead | Accuracy | Activity (Oct 2026) | macOS arm64 | CD / 32X | Licence |
|---|---|---|---|---|---|---|
| **RetroArch + Genesis Plus GX core** | Yes, N frames, plus preemptive frames (RetroArch) | Very high, claims 100% compatibility | GPGX upstream commit 2026-10-05; libretro core 2026-10-02; RetroArch commit 2026-10-05 (last tag v1.22.2, 2025-11-20) | Yes (RetroArch universal build, unverified that the core is in the arm64 buildbot) | CD yes / 32X no | GPGX non-commercial; RetroArch GPLv3 |
| ares | On/off only (1 frame) | Very high | v148 2026-05-30; commit 2026-10-04 | Yes | Yes / Yes | ISC (unverified) |
| BlastEm | None found (unverified) | Very high (Overdrive 2) | 1.0.0 2026-09-11 (previous 0.6.2 was 2019) | New non-x86 interpreters in 1.0.0; Mac build availability unverified | Yes / Yes (1.0.0) | GPLv3 (unverified) |
| BlastEm libretro core | Via RetroArch | As above | libretro/blastem commit 2026-09-26 | Unverified | Has Sega CD fixes | GPLv3 (unverified) |
| clownmdemu | None found (has rewind) | Good, still developing | frontend v1.6.12 2026-09-17; core commit 2026-10-02 | Unverified | CD partial (unverified) / no | AGPLv3 (unverified) |
| PicoDrive | Via RetroArch | Lower (speed-focused) | notaz upstream last commit 2025-04; libretro fork 2026-09-26 | Via RetroArch | Yes / Yes | Non-commercial (unverified) |
| OpenEmu GenesisPlus-Core | No | GPGX, but old | last release 1.7.5.1 2023-10 | Yes | CD yes | Non-commercial |
| Exodus | No | High, but Windows-only | Dead (unverified) | No | — | — |
| MesenCE | — | — | No Genesis support | — | — | — |

## Candidates

### Genesis Plus GX (via RetroArch)
- Accuracy: the author's README claims "very accurate emulation and 100% compatibility" with Genesis/Mega Drive, Sega/Mega CD, Master System, Game Gear and SG-1000 released software. https://github.com/ekeeke/Genesis-Plus-GX
- The standalone port is only for GameCube and Wii, so on a Mac it runs only as the libretro core (or in OpenEmu). https://github.com/ekeeke/Genesis-Plus-GX
- Licence: non-commercial. https://github.com/ekeeke/Genesis-Plus-GX/blob/master/LICENSE.txt
- Activity: upstream merged PR #665 on 2026-10-05; libretro fork committed on 2026-10-02 (`gh api repos/{ekeeke,libretro}/Genesis-Plus-GX/commits`).
- No 32X. https://github.com/ekeeke/Genesis-Plus-GX (its scope list leaves 32X out)

### RetroArch (frontend)
- Run-ahead settings are `run_ahead_enabled`, `run_ahead_frames`, `run_ahead_secondary_instance` and `preemptive_frames_enable`. https://github.com/libretro/RetroArch/blob/master/configuration.c (lines ~2207–2209, 3651)
- CLI: `-L/--libretro <core>` and `--appendconfig <file>`. https://github.com/libretro/RetroArch/blob/master/retroarch.c (~7800–7812)
- `config_save_on_exit` controls whether the config is written back. https://github.com/libretro/RetroArch/blob/master/retroarch.cfg
- Activity: commit 2026-10-05; last tagged release v1.22.2, 2025-11-20. https://github.com/libretro/RetroArch/releases
- Single-instance behaviour on macOS: **unverified**. Running the binary directly probably starts a new process each time, so Ludeum would have to quit or replace any running instance. That's the "fresh emulator per Play" approach ADR 0008 decided against for MesenCE.

### ares
- Run-ahead is a boolean setting, `General/RunAhead` (`ares::setRunAhead(true)`), with no frame count. https://github.com/ares-emulator/ares/blob/master/desktop-ui/settings/settings.cpp, https://github.com/ares-emulator/ares/blob/master/desktop-ui/program/program.cpp
- CLI: `--system name`, `--setting name=value`, `--settings-file path`, `--fullscreen`, `--no-file-prompt`. The `--setting` overrides keep the original values in a `cliSettingOverrides` list, which looks designed to stop the overrides being saved (**unverified** that the save path restores them). https://github.com/ares-emulator/ares/blob/master/desktop-ui/desktop-ui.cpp
- Activity: v148 2026-05-30; commit 2026-10-04. https://github.com/ares-emulator/ares/releases

### BlastEm
- 1.0.0 (2026-09-11) added Sega/Mega CD, 32X, Pico and more, plus new 68K and Z80 interpreters for non-x86 targets. The previous release was 0.6.2 in March 2019. https://www.retrodev.com/blastem/changes.html
- "The first emulator to properly run Titan's Overdrive 2 demo." https://www.retrodev.com/blastem/
- Run-ahead: none found in the changelog (**unverified**). A libretro port is active (https://github.com/libretro/blastem, commit 2026-09-26), which would get RetroArch run-ahead, but I didn't verify that its save states are fast or deterministic enough for run-ahead.

### clownmdemu
- Frontend v1.6.12 2026-09-17; core commit 2026-10-02. https://github.com/Clownacy/clownmdemu-frontend/releases
- The README lists rewind, but I found no run-ahead. https://github.com/Clownacy/clownmdemu-frontend

### PicoDrive
- The notaz upstream's last tag is v1.93 (2019) and its last commit was 2025-04-03. The libretro fork is active (2026-09-26). It's known as a speed-oriented emulator for weak hardware (**unverified** primary source). https://github.com/notaz/picodrive, https://github.com/libretro/picodrive

### OpenEmu Genesis core
- GenesisPlus-Core's last release is 1.7.5.1 (2023-10-17), and OpenEmu's last release is v2.4.1 (2023-12-30). It has no run-ahead. https://github.com/OpenEmu/GenesisPlus-Core/releases, https://github.com/OpenEmu/OpenEmu/releases

### Mesen / MesenCE
- MesenCE (nesdev-org/MesenCE, 2.2.1, 2026-06-05) supports NES, SNES, GB/SGB/GBC, GBA, PC Engine, SMS/Game Gear and WonderSwan. It has **no Genesis**, and an issue search for "genesis" returned nothing. https://github.com/nesdev-org/MesenCE

### Exodus
- Windows-only and inactive. **Unverified**: I didn't check its activity.

## How Ludeum would launch it

For each Play, write a temporary override file containing the full settings set, then run:

```
# /tmp/ludeum-retroarch.cfg (rewritten on every Play)
config_save_on_exit = "false"
run_ahead_enabled = "true"            # "false" when the Game's frames == 0
run_ahead_frames = "2"                 # game.runAheadFrames
run_ahead_secondary_instance = "true"  # avoids audio glitches from the save-state rollback

/Applications/RetroArch.app/Contents/MacOS/RetroArch \
  -L ~/Library/Application\ Support/RetroArch/cores/genesis_plus_gx_libretro.dylib \
  --appendconfig /tmp/ludeum-retroarch.cfg \
  "/path/to/Game.md"
```

The ares fallback would be: `ares --system "Mega Drive" --setting General/RunAhead=true "/path/to/Game.md"`.

## Open questions
- RetroArch's single-instance behaviour on macOS. If every Play starts a new process, Ludeum must handle an instance that's already running, which revisits ADR 0008.
- Does `--appendconfig` combined with `config_save_on_exit=false` really leave `retroarch.cfg` untouched, given that core options and remaps are saved separately? This needs a hands-on test.
- The core's path depends on how RetroArch was installed (Online Updater vs bundled). Check that the arm64 build includes Genesis Plus GX.
- Ludeum's 0–10 range: how many frames are actually needed for Genesis games? Usually 1–2.
- 32X games would need PicoDrive, ares or BlastEm, since Genesis Plus GX doesn't run them.
