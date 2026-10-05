# PlayStation 2 emulator for Ludeum

Researched 2026-10-06. Criteria in priority order: run-ahead / input-latency reduction, accuracy, a live project, performance (Apple Silicon JIT, Metal/Vulkan).

## Recommendation

**Use standalone PCSX2, and keep ARMSX2 as a drop-in swap for native Apple Silicon speed.** **No PS2 emulator has run-ahead.** PCSX2's feature request for it (#14572, June 2026) is still open, and a team member replied that "Savestates on pcsx2 are quiet heavy". So criterion 1 comes down to latency settings: `VsyncQueueSize = 0` ("Optimal Frame Pacing", where the GS finishes and presents each frame before input is polled), VSync off, and "Use Host VSync Timing" off. PCSX2 is by far the most accurate and active PS2 emulator (v2.9.102 shipped 2026-10-05). It has a native Metal renderer. **But its official macOS release is an x86_64 build that runs under Rosetta 2.** Upstream's arm64 port is interpreter-only, and its recompilers are stubbed. **ARMSX2** is a PCSX2 fork with full ARM64 JITs (EE, IOP, VU). It ships nightly `macOS-arm64` builds and keeps PCSX2's Qt frontend, CLI and ini format, so Ludeum's launch code would work for both. It's young (forked 2025-08), its stable releases are Android-only, and it's developed with heavy AI use. That's why it's the swap-in rather than the default. Per-launch settings fit ADR 0008 through PCSX2's `-gamecfg <ini>` flag, which points the game-settings layer at a file Ludeum writes on each Play. Play! is alive but much less compatible. DobieStation is dead, AetherSX2 is Android-only and abandoned, and ares has no PS2 core.

## Comparison

| Candidate | Run-ahead | Latency options | Accuracy / compat | Activity (Oct 2026) | macOS arm64 | Per-launch, non-persisted settings |
|---|---|---|---|---|---|---|
| **PCSX2** | No (FR #14572 open) | VSync queue size 0–2 / Optimal Frame Pacing, VSync, Host VSync timing | Highest | v2.9.102 2026-10-05 | **Rosetta 2** (release built x86_64); Metal + Vulkan renderers | `-gamecfg <ini>` |
| ARMSX2 | No (no issues found) | Same as PCSX2 (inherited) | PCSX2-derived; claims no known interpreter divergence (unverified for its JIT) | nightly 2026-10-05, Android 2.8.1 2026-10-05 | **Native ARM64 JIT**, nightly `macOS-arm64` builds | Same CLI as PCSX2 (`-gamecfg`) |
| Play! | No (unverified) | None found | Lower (own compatibility tracker; unverified) | 0.77 2026-07-02; commit 2026-09-03 | JIT; arm64 Mac build unverified | Only `--disc/--elf/--state/--fullscreen` |
| DobieStation | No | — | Incomplete | Last commit 2021-04 | — | — |
| AetherSX2 / NetherSX2 | No | — | — | Android-only; abandoned (unverified) | No | — |
| ares | — | — | No PS2 core | — | — | — |

## Candidates

### PCSX2
- Activity: v2.9.100–v2.9.102 were all released 2026-10-05. The macOS asset is `pcsx2-v2.9.102-macos-Qt.tar.xz` (`gh api repos/PCSX2/pcsx2/releases`). https://github.com/PCSX2/pcsx2/releases
- **Apple Silicon:** the macOS build workflow defaults to `arch: x86-64`, so `CMAKE_OSX_ARCHITECTURES=x86_64`. The `arm64` job only runs on PRs and forks (`if: github.repository != 'PCSX2/pcsx2' || …`). https://github.com/PCSX2/pcsx2/blob/master/.github/workflows/macos_build.yml, https://github.com/PCSX2/pcsx2/blob/master/.github/workflows/macos_build_matrix.yml. Upstream `pcsx2/arm64/` has only VIF/NEON code plus `RecStubs.cpp` ("recompiler state is stubbed in arm64!", `vtlb_DynBackpatchLoadStore` → "Not implemented."). https://github.com/PCSX2/pcsx2/tree/master/pcsx2/arm64. ARMSX2's README confirms this: upstream "ships an ARM64 *interpreter* build … JIT recompilers … are x86-64 only." I didn't measure how well PCSX2 runs under Rosetta (**unverified**). Rosetta 2's future on macOS is **unverified** here too.
- Renderers: `GS/Renderers/{Metal, Vulkan, OpenGL, SW, …}`. https://github.com/PCSX2/pcsx2/tree/master/pcsx2/GS/Renderers
- **Run-ahead: none.** Feature request #14572 is open. Its comments note that "Frame Pacing / Latency Control" is not the same thing, and a maintainer says savestates are too heavy. https://github.com/PCSX2/pcsx2/issues/14572
- Latency settings, all in `[EmuCore/GS]`: `VsyncQueueSize` (default 2; "Maximum Frame Latency"), "Optimal Frame Pacing" ("Sets the VSync queue size to 0, making every frame be completed and presented by the GS before input is polled"), `VsyncEnable` (default false), `SyncToHostRefreshRate`, and `UseVSyncForTiming` ("smoother frame pacing, but at the cost of increased input latency"). https://github.com/PCSX2/pcsx2/blob/master/pcsx2-qt/Settings/EmulationSettingsWidget.cpp (lines 18–40, 137–157), https://github.com/PCSX2/pcsx2/blob/master/pcsx2/Pcsx2Config.cpp (~930–941). There's no "Reduce latency" option apart from these (searched; **unverified** for hidden keys).
- CLI (from `-help` in https://github.com/PCSX2/pcsx2/blob/master/pcsx2-qt/QtHost.cpp, ~2120–2342):
  - `-batch` ("exits after shutting down"), `-nogui` (hides the main window; implies batch), `-fullscreen` / `-nofullscreen`, `-fastboot` / `-slowboot`, `-bios`, `-state <index>`, `-statefile <file>`, `-portable`, `-datapath <path>`, `-bigpicture`, `-- <file>`.
  - **`-gamecfg <file>`**: "Overrides the game settings with the ones in the specified INI file." It must end in `.ini` and must exist (VMManager.cpp ~1482–1496). `GetGameSettingsPath()` then returns that file instead of `gamesettings/<serial>_<CRC>.ini`. https://github.com/PCSX2/pcsx2/blob/master/pcsx2/VMManager.cpp (~820–831)
  - Unknown `-` arguments pop up an error dialog and abort, so Ludeum must not pass any flag PCSX2 doesn't know.
- There's no generic `--setting key=value` flag (none in the parser).

### ARMSX2
- "Native ARM64 JIT Fork of PCSX2". Its status list says EE, VU (COP2, mVU, VU1) and IOP JITs are "fully complete with extensive unit test framework". It targets macOS, Windows, Linux, Android and iOS from one core. https://github.com/ARMSX2/ARMSX2
- Forked from PCSX2/pcsx2, created 2025-08-11, GPL-3.0. Last push 2026-10-05, 2.1k stars (`gh api repos/ARMSX2/ARMSX2`).
- Releases: stable 2.8 / 2.8.1 (2026-10-03/05) are Android APKs only. **Nightlies** (e.g. `nightly-20261005`) include `ARMSX2-…-macOS-arm64.tar.xz`. https://github.com/ARMSX2/ARMSX2/releases
- It keeps `pcsx2-qt/QtHost.cpp` with the same `-batch` / `-gamecfg` parsing (grep of the fork's file). Its ini keys are therefore presumably identical (**unverified** beyond the parser).
- The README states AI is used in development. Whether its accuracy holds up against upstream on the JIT path is **unverified**. No run-ahead issues found.

### Play!
- Commit 2026-09-03; last tag 0.77 (2026-07-02); about 100 commits since 2026-01-01. https://github.com/jpd002/Play-
- CLI: `--disc`, `--elf`, `--arcade`, `--state`, `--fullscreen`. It has no settings override. https://github.com/jpd002/Play-#command-line-options-windowsmacoslinux
- It uses JIT code generation (README). Whether its macOS arm64 build is native, and which renderer it uses, are **unverified**. Its compatibility is tracked at https://github.com/jpd002/Play-Compatibility and is generally lower than PCSX2's (**unverified**).

### DobieStation
- Last commit 2021-04-21. Dead. https://github.com/PSI-Rockin/DobieStation

### AetherSX2 / NetherSX2
- Android-only. AetherSX2 is abandoned and NetherSX2 is a patch of it (**unverified**, no primary repo). ARMSX2 has taken over this niche.

### ares
- Cores: a26, a52, cv, fc, gb, gba, md, ms, msx, myvision, n64, ng, ngp, pce, ps1, saturn, sfc, sg, ws. **No PS2.** https://github.com/ares-emulator/ares/tree/master/ares

## How Ludeum would launch it

For each Play, write a per-game ini and pass it with `-gamecfg`:

```
# ~/…/Ludeum/PCSX2 game.ini  (rewritten on every Play)
[EmuCore/GS]
VsyncQueueSize = 0        # game.lowLatency ? 0 : 2
VsyncEnable = false
UseVSyncForTiming = false

/Applications/PCSX2.app/Contents/MacOS/PCSX2 \
  -batch -fastboot \
  -gamecfg "/…/Ludeum/PCSX2 game.ini" \
  -- "/path/to/Game.iso"
```

(The bundle path, binary name and bundle id are **unverified**. ARMSX2 would use the same arguments with its own app path.) `-batch` makes PCSX2 exit when the game shuts down, which matches "one Play = one process".

## Options for passing per-Game settings

1. **`-gamecfg` with a Ludeum-written ini** (recommended). PCSX2's settings are layered (base `PCSX2.ini` → game layer), so controllers, BIOS and renderer still come from the user's `PCSX2.ini`, and only the game layer is replaced. Two catches. First, this hides the user's own `gamesettings/<serial>_<CRC>.ini` (fixes and patches they set up per game), and Ludeum doesn't know the serial/CRC to merge it in. Second, if the user edits per-game settings in PCSX2 during the Play, the edits probably get saved into Ludeum's file, which is then overwritten. That's fine under ADR 0008 (**unverified** that the write goes there).
2. **DuckStation-style temp copy of `PCSX2.ini` + `-datapath`/`-portable`**: rejected. Those relocate *all* data (memory cards, saves, BIOS), not just settings.
3. **Edit `PCSX2.ini` before launch**: rejected, because it persists.

## Open questions
- How fast is PCSX2 under Rosetta 2 on M-series compared with ARMSX2's native JIT? This needs a hands-on test with a heavy game (e.g. Shadow of the Colossus, MGS3).
- Does PCSX2 write UI per-game setting changes back into the `-gamecfg` file, and does an empty or minimal `-gamecfg` ini still let the GameDB's automatic fixes apply? (The GameDB is a separate layer, **unverified**.)
- Single-instance behaviour: does a second launch while PCSX2 is running open a second instance?
- Ludeum's 0–10 run-ahead range doesn't map onto PS2. Should it become a boolean "low latency" (`VsyncQueueSize` 0 vs 2) for this Platform, as for PSP?
- When do ARMSX2's macOS builds leave nightly? Do they need a signed or notarized app for `NSWorkspace` launching (**unverified**)?
