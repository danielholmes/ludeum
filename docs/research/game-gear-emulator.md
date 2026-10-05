# Sega Game Gear emulator for Ludeum

Researched 2026-10-06. Criteria in priority order: run-ahead, accuracy (Game Gear-specific), a live project, performance. Builds on [master-system-emulator.md](master-system-emulator.md) and [genesis-emulator.md](genesis-emulator.md), whose general findings (run-ahead mechanics, CLI, activity, macOS builds) are reused here rather than re-checked.

## Recommendation

**First choice: MesenCE.** Game Gear is the same `Core/SMS` core Ludeum already launches for Master System, run with an `SmsModel::GameGear` model. MesenCE's run-ahead is system-agnostic and counts frames ([master-system-emulator.md](master-system-emulator.md#mesence)), so the existing `--emulation.runAheadFrames=N --doNotSaveSettings` launch works unchanged for `.gg` files. The core has real GG-specific code paths: 12-bit GG palette RAM, stereo PSG panning on port 0x06, GG-only I/O ports, LCD frame blending (on by default), and a separate GG region and overscan. Its gaps are the link cable (the ext/serial ports are stubbed, marked `TODOSMS`) and SMS-compatibility mode: the model is chosen by file extension only, and I found no "SMS game on a GG" mode. It also has no published GG test results. **Runner-up: Gearsystem.** It is the most complete for GG: a game-database-driven "Game Gear in SMS compatibility mode", GG ASIC revisions, Gear-to-Gear link cable, and published accuracy tests. It has run-ahead of 0–3 frames, but only through `config.ini`, with no CLI overrides ([master-system-emulator.md](master-system-emulator.md#gearsystem)). **ares** is also GG-complete (SMS mode, stereo, interframe blending) and is already Ludeum's Genesis emulator, but its run-ahead is on/off only.

## Comparison

| Candidate | Run-ahead | GG palette / 160x144 | Stereo PSG | SMS mode on GG | Link cable | LCD blending | Activity (Oct 2026) | Per-launch CLI settings |
|---|---|---|---|---|---|---|---|---|
| **MesenCE** | Yes, N frames | Yes / unverified (GG overscan setting exists) | Yes | No (model by `.gg` extension) | No (stubbed) | Yes, default on | Commit 2026-09-26 | Yes, already in use |
| Gearsystem | Yes, 0–3 frames | Yes / yes | Yes | Yes (game DB) | Yes (Gear-to-Gear) | Unverified (no setting found) | 3.9.21 2026-10-04 | No; `config.ini` only |
| ares | On/off only | Yes / unverified | Yes | Yes | Unverified | Yes (Interframe Blending) | v148 2026-05-30; push 2026-10-04 | Yes (`--setting`) |
| BlastEm | None found | New in 1.0.0; quality unverified | Unverified | Unverified | Unverified | Unverified | 1.0.0 2026-09-11 | No (unverified) |

RetroArch cores (Genesis Plus GX, SMS Plus GX) are excluded: RetroArch is ruled out.

## Candidates

### MesenCE
- `.gg` selects `RomFormat::GameGear` / `SmsModel::GameGear`; anything else is SMS, SG-1000 or ColecoVision. So the model comes from the extension, and an SMS-mode GG cartridge isn't specially handled (**inferred from source**). https://github.com/nesdev-org/MesenCE/blob/master/Core/SMS/SmsConsole.cpp (~47–59)
- GG forces NTSC timing, VDP revision SMS2, and a GG BIOS when one is present. Same file (~75, 199–200, 228, 256–261).
- GG palette: 0x40 bytes of palette RAM, `WriteGameGearPalette` RGB444. https://github.com/nesdev-org/MesenCE/blob/master/Core/SMS/SmsVdp.cpp (~66–69, 1263, 1305–1311)
- Stereo: `GameGearPanningReg` per-channel left/right. https://github.com/nesdev-org/MesenCE/blob/master/Core/SMS/SmsPsg.cpp (~83–96, 171)
- GG ports: start button and region on port 0; ext/serial ports 1–5 just return latched values, under a `//TODOSMS GG - input/output ext port` comment, so there's no link cable. https://github.com/nesdev-org/MesenCE/blob/master/Core/SMS/SmsMemoryManager.cpp (~458–477)
- LCD ghosting: `GgBlendFrames` (default `true`; UI label "Enable LCD frame blending (Game Gear)") enables a blend filter only for GG. https://github.com/nesdev-org/MesenCE/blob/master/Core/SMS/SmsDefaultVideoFilter.h (~28), https://github.com/nesdev-org/MesenCE/blob/master/Core/Shared/SettingTypes.h (~780–798: `GameGearRegion`, `GgBlendFrames`, `GameGearOverscan`)
- Run-ahead: applies to GG because it lives in the shared `Emulator` loop. See [master-system-emulator.md](master-system-emulator.md#mesence).
- Accuracy: I found no published GG test results (**unverified**).

### Gearsystem
- `IsGameGearInSMSMode`, set by cartridge type (`CartridgeGG1ASICSMSMode`/`CartridgeGG2ASICSMSMode`) or a game-database flag `GS_DB_FEATURE_SMS_MODE` ("Game Gear in SMS compatibility mode"). In SMS mode, the VDP uses SMS width and 32-byte CRAM. https://github.com/drhelius/Gearsystem/blob/master/src/Cartridge.cpp (~105–235, 938–944), https://github.com/drhelius/Gearsystem/blob/master/src/Video.cpp (~129, 284–357)
- GG ASIC revisions (`iGGASIC`), dedicated `GameGearIOPorts.cpp`, and GG stereo (`ggstereo`). https://github.com/drhelius/Gearsystem/tree/master/src, https://github.com/drhelius/Gearsystem/blob/master/src/Audio.cpp (~81–92)
- Link cable: "Gear-to-Gear and Mark III Link Cable", including `--link-session N`. https://github.com/drhelius/Gearsystem#readme
- I found no LCD ghosting option in `config_definitions.inc.h` (**unverified**; it may exist under a shader).
- Run-ahead, CLI, activity: see [master-system-emulator.md](master-system-emulator.md#gearsystem).

### ares
- `System::Model::GameGear`, with `Mode::GameGear()` false when `system.ms()` is set, which is SMS mode on GG. `Display::LCD()` for GG. https://github.com/ares-emulator/ares/blob/master/ares/ms/system/system.hpp (~49, 90–99)
- GG 12-bit colour and an "Interframe Blending" setting (default on). https://github.com/ares-emulator/ares/blob/master/ares/ms/vdp/vdp.cpp (~42–51)
- GG-specific PSG paths (stereo). https://github.com/ares-emulator/ares/blob/master/ares/ms/psg/psg.cpp (~37, 62)
- Run-ahead is on/off only; the CLI takes `--setting`. See [genesis-emulator.md](genesis-emulator.md#ares).

### BlastEm
- Game Gear was added in 1.0.0; I found no run-ahead. https://www.retrodev.com/blastem/changes.html. Rejected on criterion 1.

## How Ludeum would launch it

The same as for Master System:

```
/Applications/Mesen.app/Contents/MacOS/Mesen \
  --emulation.runAheadFrames=1 \
  --doNotSaveSettings \
  "/path/to/Game.gg"
```

The ROM must keep its `.gg` extension, or MesenCE runs it as an SMS game.

## Open questions
- What is MesenCE's GG accuracy in practice? Run the SMS VDP Test and ZEXALL on GG and compare with Gearsystem's results (https://github.com/drhelius/Gearsystem#accuracy-tests).
- Does MesenCE crop to 160x144 by default, or does the `GameGearOverscan` default need setting? Needs a hands-on check.
- How does MesenCE handle GG titles that run in SMS mode (SMS ROMs sold as GG carts, e.g. Japanese ports dumped as `.gg`)? It may need per-Game handling, or Gearsystem/ares as a fallback.
- Should Ludeum pass the frame-blending setting per launch? If so, what is the CLI key (probably `--sms.ggBlendFrames=`, **unverified**)?
- Link-cable multiplayer is out of scope for MesenCE. Does anyone need it?
