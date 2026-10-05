# PlayStation Portable emulator for Ludeum

Researched 2026-10-06. Criteria in priority order: run-ahead / input-latency reduction, accuracy, a live project, performance (Apple Silicon JIT, Metal/Vulkan).

## Recommendation

**Use standalone PPSSPP.** It's effectively the only live, high-compatibility PSP emulator, and it ships native arm64 macOS builds with a Vulkan (MoltenVK) backend and an ARM64 JIT. **No PSP emulator has run-ahead.** PPSSPP's own tracking issue for input lag lists only "Buffered frames as low as possible" and a high refresh rate as the current levers. So criterion 1 shrinks to "latency settings": `InflightFrames=1` (buffered frames), `LowLatencyPresent`, VSync, and frame skip off. For per-launch settings that aren't saved back, the cleanest route is the DuckStation pattern. Copy the user's `ppsspp.ini` to a temp file, write Ludeum's keys into it, and launch with `--config=<temp>`. PPSSPP will save into the temp copy, which Ludeum then throws away. **Don't use `--appendconfig` on the real ini.** It calls `Save()` right after merging ("Let's prevent reset"), so the overrides would persist. The only other candidate is JPCSP (Java, low-level, commits in Sept 2026), and it isn't competitive on latency, compatibility or performance. OpenEmu's PPSSPP core is stale (last release 2023-06). ares has no PSP core.

## Comparison

| Candidate | Run-ahead | Latency options | Accuracy / compat | Activity (Oct 2026) | macOS arm64 | Per-launch, non-persisted settings |
|---|---|---|---|---|---|---|
| **PPSSPP (standalone)** | No | Buffered frames 1–2, Low-latency present, VSync, frame skip | Highest of the field (HLE) | v1.20.4 2026-05-16; commit 2026-10-05 | Yes: ARM64 JIT, Vulkan via MoltenVK, OpenGL | `--config=<temp ini>` (yes); `--appendconfig` (persists; avoid) |
| JPCSP | No (unverified) | None found (unverified) | LLE-leaning, lower practical compat (unverified) | commit 2026-09-24; last release tag 2024-08 | Java, so runs, but no JIT parity (unverified) | Unverified |
| OpenEmu PPSSPP-Core | No | Via OpenEmu only | Old PPSSPP | last release v1.14.4 2023-06-23; commit 2024-02 | Yes, via OpenEmu | No CLI |
| libretro PPSSPP (via RetroArch) | RetroArch run-ahead theoretically; impractical for PSP (unverified) | — | Same as PPSSPP | `libretro/ppsspp` fork dead (2020); core is built from upstream tree (unverified) | Yes | Rejected: RetroArch |
| ares | — | — | No PSP core | — | — | — |

## Candidates

### PPSSPP
- Activity: latest release v1.20.4 on 2026-05-16, last commit 2026-10-05 (`gh api repos/hrydgard/ppsspp/{releases,commits}`). https://github.com/hrydgard/ppsspp/releases
- **Run-ahead: none.** Issue #17685 ("Input lag too high – ideas for improvement", open) says the current options are "Set 'Buffered frames' as low as possible" and "Run at high refresh rate". Future ideas include Reflex-style frame-start delay and single-threaded Vulkan. Searches for "runahead" / "run ahead" turn up no feature. https://github.com/hrydgard/ppsspp/issues/17685
- Latency-relevant settings (all `CfgFlag::PER_GAME` except InflightFrames): `FrameSkip` (default 0), `AutoFrameSkip`, `VerticalSync` (default true), `LowLatencyPresent` (default false), and `InflightFrames` (default 2, clamped 1–2, DEFAULT flag only, so global). https://github.com/hrydgard/ppsspp/blob/master/Core/Config.cpp (lines ~708–762, 1621)
- Graphics on macOS: Vulkan via MoltenVK ("We only support Vulkan on Unix, macOS (by MoltenVK)…"). MoltenVK is bundled into the .app. https://github.com/hrydgard/ppsspp/blob/master/CMakeLists.txt (lines 107, 1506). The CLI picks a backend with `--graphics=vulkan|opengl|software` (the GPU backend choice isn't saved). https://github.com/hrydgard/ppsspp/blob/master/Core/CmdLine.cpp
- CLI (application mode), from `g_autoParams` and `Parse()` in https://github.com/hrydgard/ppsspp/blob/master/Core/CmdLine.cpp:
  - `--fullscreen` / `--windowed` (not saved), `--escape-exit` ("Escape key exits the application"), `--pause-menu-exit` ("Exit to menu" becomes "Exit"), `--state=FILE` (load a save state), `--resolution-scale=N` (not saved), `--cpu=jit|jit-ir|ir|interpreter`, `--config=FILE`, `--controlconfig=FILE`, `--appendconfig=FILE`, `--memstick=DIR`.
  - `-s` sets `bSaveSettings = false` **and** `bAutoRun = false`. That would block every save, but it also stops the game auto-starting (**unverified** in practice), so it's unsuitable.
- `--appendconfig` semantics: `LoadAppendedConfig()` reads every section, then calls `Save("Loaded appended config")`. It is also re-applied after each game-specific config load. So the overrides **are written** to `ppsspp.ini` (or to the per-game ini). https://github.com/hrydgard/ppsspp/blob/master/Core/Config.cpp (lines ~1245–1266, 1945–1950)
- `Save()` is skipped when `bSaveSettings` is false, or when this is not the first instance ("secondary instances don't"). https://github.com/hrydgard/ppsspp/blob/master/Core/Config.cpp (~1442–1452)
- Game-specific settings: PPSSPP has a per-game ini (`SaveGameConfig(gameId_)`, loaded on boot). A user-created per-game ini overrides the `--config` values for PER_GAME keys (**unverified** which ini path is used when `--config` points elsewhere).

### JPCSP
- Java PSP emulator; last commit 2026-09-24, latest release tag "2024-08". https://github.com/jpcsp/jpcsp
- No run-ahead or latency options found, and not checked further (**unverified**). Its compatibility and performance are widely regarded as below PPSSPP's (**unverified**, no primary source).

### OpenEmu PPSSPP-Core
- Last release v1.14.4 (2023-06-23), last commit 2024-02-02. No CLI and no run-ahead. https://github.com/OpenEmu/PPSSPP-Core/releases

### libretro PPSSPP / RetroArch
- `libretro/ppsspp`'s last commit was 2020-03-18. The live core lives in the upstream tree under `libretro/` (**unverified**). Running RetroArch run-ahead on a PSP game would mean serialising a full PSP state every frame. I found no evidence it's practical (**unverified**). Excluded anyway, because RetroArch is rejected.

### ares / others
- ares's cores are a26, a52, cv, fc, gb, gba, md, ms, msx, myvision, n64, ng, ngp, pce, ps1, saturn, sfc, sg, ws. **No PSP.** https://github.com/ares-emulator/ares/tree/master/ares
- A GitHub repo search for "psp emulator" sorted by activity (>100 stars) returns only PPSSPP and JPCSP. "Rocket PSP" didn't come up (**unverified**, I didn't search further).

## How Ludeum would launch it

For each Play, copy `~/Library/Application Support/PPSSPP/PSP/SYSTEM/ppsspp.ini` (default memstick path **unverified**) to a temp file, set the keys, then run:

```
# /tmp/ludeum-ppsspp.ini  (copy of the user's ini, rewritten on every Play)
[Graphics]                 # section names unverified
FrameSkip = 0
AutoFrameSkip = False
InflightFrames = 1         # game.lowLatency ? 1 : 2
LowLatencyPresent = True
VerticalSync = True

/Applications/PPSSPPSDL.app/Contents/MacOS/PPSSPPSDL \
  --config=/tmp/ludeum-ppsspp.ini \
  --graphics=vulkan \
  --escape-exit --pause-menu-exit \
  "/path/to/Game.iso"
```

(The macOS app/binary name, `PPSSPPSDL.app` vs `PPSSPP.app`, is **unverified**.)

## Options for passing per-Game settings

1. **Temp-copy + `--config=`** (recommended). This matches the DuckStation `-settings` copy in `Emulators.swift`. Every key is sent on every launch, and PPSSPP's writes land in the throwaway copy. Watch out: saves/memstick paths derive from the memstick, not the ini, so they're unaffected (**unverified**).
2. **Direct CLI flags** for the few settings that have them (`--resolution-scale`, `--graphics`, `--fullscreen`). They aren't persisted (`DoNotSaveSetting`), but there are no flags for the latency keys.
3. **`--appendconfig`**: rejected, because it saves the merged values into the user's ini.
4. **`-s`**: blocks all saving but turns off auto-run. Rejected unless a test shows the game still boots.

## Open questions
- Does `--config=` also redirect where the per-game ini and `controls.ini` are read from? Is `--controlconfig` needed so key bindings still come from the user's file?
- Does `LowLatencyPresent` with `InflightFrames=1` measurably cut latency under MoltenVK, or only on Windows/Android present paths? This needs a hands-on test.
- Single-instance behaviour on macOS. A second launch while one is running wouldn't save config ("secondary instances don't"), but does it open a second window?
- Ludeum's 0–10 run-ahead range doesn't map onto PSP at all. Should it become a boolean "low latency" setting for this Platform?
