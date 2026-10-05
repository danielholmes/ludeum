# Sega Master System emulator for Ludeum

Researched 2026-10-06. Criteria in priority order: run-ahead, accuracy, a live project, performance. Nice to have: Game Gear in the same emulator.

## Recommendation

**First choice: MesenCE.** Ludeum already launches it, and it emulates SMS and Game Gear. Its run-ahead is a frame count (`RunAheadFrames`), implemented once in the shared `Emulator` loop, so it applies to every console, SMS included. That means the existing ADR 0008 launch (`--emulation.runAheadFrames=N --doNotSaveSettings`) works unchanged, with no new emulator, no new settings mechanism, and no new single-instance handling. 2.2.1 ships a macOS Apple Silicon build, and the repo had commits in late September 2026. Its weak spot is accuracy evidence: I found no published SMS test-ROM results for Mesen's SMS core. **Runner-up: Gearsystem.** It is the accuracy pick, very active (3.9.21 released 2026-10-04), has a native macOS arm64 build, and also does Game Gear and SG-1000. Its README shows ZEXALL and SMS VDP Test results, and it has run-ahead of 0–3 frames. Its CLI has no per-setting overrides, though. Run-ahead lives only in `config.ini`, so Ludeum would have to rewrite that file (e.g. in a `--portable` directory it owns) before each launch, and that collides with Gearsystem's single-instance handling. **ares** runs SMS/GG and is now Ludeum's Genesis emulator, but its run-ahead is on/off only.

## Comparison

| Candidate | Run-ahead | Accuracy | Activity (Oct 2026) | macOS arm64 | Game Gear | Per-launch CLI settings | Licence |
|---|---|---|---|---|---|---|---|
| **MesenCE** | Yes, N frames | Good (unverified; no published SMS test results found) | 2.2.1 2026-06-05; commit 2026-09-26 | Yes (release asset) | Yes | Yes (`--emulation.runAheadFrames=N`, `--doNotSaveSettings`, already in use) | GPL-3.0 |
| Gearsystem | Yes, 0–3 frames | Very high; ZEXALL + SMS VDP Test shown | 3.9.21 2026-10-04; push 2026-10-05 | Yes (release asset) | Yes (+ SG-1000) | No; `config.ini` only | GPL-3.0 |
| ares | On/off only (1 frame) | Very high (unverified for SMS specifically) | v148 2026-05-30; push 2026-10-04 | Yes (universal) | Yes (+ SG-1000) | Yes (`--setting`) | ISC (unverified) |
| Emulicious | None found (unverified) | Very high by reputation (unverified for SMS) | Site footer 2026; version unverified | Java, runs on macOS | Yes | Unverified | Freeware, closed |
| BlastEm | None found | Very high (Genesis); SMS via MD back-compat mode | 1.0.0 2026-09-11 | Unverified | Yes (1.0.0) | No (unverified) | GPLv3 (unverified) |
| Genesis Plus GX | Only via RetroArch | Very high | Commit 2026-10-05 | Standalone is Wii/GC only | Yes | — | Non-commercial |
| MEKA | None found (unverified) | Good, long-standing (unverified) | Push 2026-06-04 | Unverified | Yes | Unverified | Unverified |
| SMS Plus GX | Only via RetroArch | Older (unverified) | libretro fork push 2026-09-04 | libretro only | Yes | — | GPL (unverified) |
| Kega Fusion | None | Good for its time | Dead, last 3.64 c. 2010 (unverified) | No (unverified) | Yes | — | Closed freeware |

## Candidates

### MesenCE
- Supports "NES, SNES, Game Boy (GB/SGB/GBC), Game Boy Advance, PC Engine, SMS/Game Gear, and WonderSwan". https://github.com/nesdev-org/MesenCE
- Run-ahead is system-agnostic. `Emulator::RunFrame` uses `RunFrameWithRunAhead()` when `GetEmulationConfig().RunAheadFrames > 0`, and loops `frameCount` times. https://github.com/nesdev-org/MesenCE/blob/master/Core/Shared/Emulator.cpp (~lines 165, 233–248); `uint32_t RunAheadFrames` in https://github.com/nesdev-org/MesenCE/blob/master/Core/Shared/SettingTypes.h (~423)
- It has a dedicated `SmsConfig` with Game Gear region and overscan settings. https://github.com/nesdev-org/MesenCE/blob/master/Core/Shared/SettingTypes.h (~774–798); core in https://github.com/nesdev-org/MesenCE/tree/master/Core/SMS
- Release 2.2.1 (2026-06-05) includes `Mesen_2.2.1_macOS_ARM64_AppleSilicon.zip`; last commit 2026-09-26. https://github.com/nesdev-org/MesenCE/releases
- CLI: same as Ludeum's existing use (ADR 0008).
- Accuracy: I found no published SMS test-ROM results. The mesen.ca docs cover NES only (https://www.mesen.ca/docs/). **Unverified.**

### Gearsystem
- "A very accurate, cross-platform Sega Master System / Game Gear / SG-1000 emulator", with "Very accurate Z80, VDP, PSG and FM emulation" and "Run-ahead support". https://github.com/drhelius/Gearsystem
- The README's Accuracy Tests section shows ZEXALL and SMS VDP Test screenshots. https://github.com/drhelius/Gearsystem#accuracy-tests
- Run-ahead: `CONFIG_INT_RANGE("Emulator", "RunAhead", config_emulator.runahead, 0, 0, 3)`, i.e. 0–3 frames. https://github.com/drhelius/Gearsystem/blob/master/platforms/shared/desktop/config_definitions.inc.h (~150), https://github.com/drhelius/Gearsystem/blob/master/platforms/shared/desktop/runahead.cpp
- CLI: `gearsystem [options] [rom_file]` with `-f`, `-w`, `--portable`, `--headless`, MCP and link-cable flags. There's no setting override. The README also mentions "single-instance handling". https://github.com/drhelius/Gearsystem#command-line-usage
- Config is `config.ini` in the SDL pref path, or beside the app with `--portable`. https://github.com/drhelius/Gearsystem/blob/master/platforms/shared/desktop/config.cpp (~81–109)
- 3.9.21 (2026-10-04) includes `Gearsystem-3.9.21-desktop-macos-arm64.zip`. https://github.com/drhelius/Gearsystem/releases

### ares
- Has `ms` (Master System/Game Gear) and `sg` cores. https://github.com/ares-emulator/ares/tree/master/ares
- Run-ahead is the boolean `General/RunAhead`; the CLI takes `--setting`. See [genesis-emulator.md](genesis-emulator.md#ares).

### Emulicious
- Emulates "Game Boy, Game Boy Color, Master System, Game Gear and MSX" and runs on any Java SE OS, macOS included. It's free to use, with no licence stated. https://emulicious.net/
- I found no run-ahead and no documented CLI (**unverified**). It's closed source.

### BlastEm
- SMS since 0.5.0 ("SMS emulation in the form of the Genesis/MD's backwards compatibility mode"); Game Gear in 1.0.0; no run-ahead in the changelog. https://www.retrodev.com/blastem/changes.html

### Genesis Plus GX, SMS Plus GX
- Both run on a Mac only as libretro cores (RetroArch, which is ruled out). GPGX: https://github.com/ekeeke/Genesis-Plus-GX; SMS Plus GX: https://github.com/libretro/smsplus-gx (last push 2026-09-04).

### MEKA, Kega Fusion
- MEKA: last push 2026-06-04. https://github.com/ocornut/meka. I didn't check its macOS build or run-ahead (**unverified**).
- Kega Fusion: closed source and unmaintained for over a decade (**unverified**; no primary source checked).

## How Ludeum would launch it

The same as for the Nintendo systems:

```
/Applications/Mesen.app/Contents/MacOS/Mesen \
  --emulation.runAheadFrames=1 \
  --doNotSaveSettings \
  "/path/to/Game.sms"     # or .gg
```

The Gearsystem fallback would be to write `<dir>/config.ini` with `[Emulator] RunAhead=N`, then run `Gearsystem.app/Contents/MacOS/gearsystem --portable "/path/to/Game.sms"`. **Unverified:** whether `--portable` points at a directory Ludeum can control, and how a second launch behaves while one is already running.

## Open questions
- What is MesenCE's SMS/GG accuracy in practice? Run ZEXALL-SMS and SMS VDP Test (http://www.smspower.org/Homebrew/SMSVDPTest-SMS) in MesenCE and compare with Gearsystem's published results.
- Does MesenCE recognise `.sms`/`.gg` passed on the command line to a running instance the same way it does for Nintendo ROMs? This needs a hands-on test.
- Does MesenCE run-ahead behave well with SMS FM audio and Light Phaser games?
- Is MesenCE's 2.2.1 release recent enough, or should Ludeum track nightlies (https://github.com/nesdev-org/MesenCE#readme)?
