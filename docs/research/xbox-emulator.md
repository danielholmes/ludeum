# Original Xbox emulator for Ludeum

Researched 2026-10-14. Criteria in priority order: run-ahead / input-latency reduction, accuracy, a live project, performance (Apple Silicon native, Metal/Vulkan). Source citations are against xemu `master` at 36334d9 (2026-10-12).

## Recommendation

**Use xemu. It's the only Xbox emulator that runs on macOS.** It ships a notarized universal (arm64 + x86_64) app, it's active (v0.8.136 on 2026-06-08, 58 commits on master since, dev build 2026-10-12), and `brew install --cask xemu` works. **It has no run-ahead.** The only latency setting is VSync (`display.window.vsync`). **The catch is the disc format: xemu boots only XISO images (the game partition alone). A full Redump ISO reaches the dashboard's "DVD Playback Kit" message instead of booting.** The FAQ says Redump isn't supported "yet". The one PR that added it (#2915) was closed unmerged. CHD (#2809) and CCI (#2808) PRs are open and unmerged. So Ludeum's Xbox ROMs have to be XISOs, made with `xdvdfs pack` or by stripping the first 387 MiB. The launch line is `xemu -dvd_path <iso> [-full-screen]`. That path isn't saved to `xemu.toml`. Any other setting for one launch needs `-config_path` pointing at a copy of `xemu.toml` that Ludeum writes. The user has to set up the MCPX boot ROM, flash BIOS and HDD image in xemu first.

## Comparison

| Candidate | Run-ahead | Latency options | Activity (Oct 2026) | macOS | Disc formats |
|---|---|---|---|---|---|
| **xemu** | No | VSync on/off | v0.8.136 2026-06-08; master 2026-10-12 | Universal, notarized; OpenGL only | XISO only (no Redump, CHD, CCI, archives or folders) |
| Cxbx-Reloaded | No | — | push 2026-04-19 | "MacOS with Wine is known not to work" | — |
| MAME `xbox` | No | — | — | MAME runs on macOS | `MACHINE_NOT_WORKING` |

## xemu

- **Releases:** v0.8.134 came out 2026-02-26, v0.8.135 2026-05-20 and v0.8.136 2026-06-08. A rolling `pre-release` tag holds 0.8.136-58-g36334d95b8 (2026-10-12) (`gh api repos/xemu-project/xemu/releases`). Tagged releases have `xemu-<v>-macos-universal.zip` (Developer ID signed and notarized; checked with `spctl` and `stapler`) and `-macos-universal-unsigned.zip`. The pre-release has only the unsigned zip, which is ad-hoc signed (`.github/workflows/build-macos.yml` 96–125). None of them is a `.dmg`. `lipo -archs` shows `x86_64 arm64`.
- **Homebrew:** the `xemu` cask is at 0.8.136 and installs the signed zip to `/Applications/Xemu.app` (`brew info --cask --json=v2 xemu`).
- **Bundle id: `xemu.app.0`**, executable `xemu` (`Info.plist` 7–12). The bundle folder is `xemu.app`.
- **Version:** `build.sh` 69–76 sets `CFBundleShortVersionString` and `CFBundleVersion` to `XEMU_VERSION` cut at the first `-`. CI writes that from `git describe` (`build.yml` ~32–47). The shipped 0.8.136 plist reads `0.8.136`, matching tag `v0.8.136` minus the `v`. Dev builds also read `0.8.136`. `-version` prints QEMU's version, not xemu's (`system/vl.c` 896–900, 3374), so read the plist.
- **CLI** (https://xemu.app/docs/cli/): `-full-screen`, `-dvd_path <iso>`, `-snapshot` (discards HDD writes), `-config_path <toml>`. Anything else goes to QEMU, e.g. `-machine xbox,short-animation=on`.
  - `-dvd_path` overrides `sys.files.dvd_path` in a local variable and doesn't write it back (`system/vl.c` 3076–3095). The settings are still saved at exit (`ui/xemu.c` 1402).
  - `-config_path` is read before the settings load (`ui/xemu.c` 1382–1391). The FAQ suggests `open --args -config_path …` on macOS.
  - **An unknown flag aborts.** QEMU's parser prints "invalid option" and calls `exit(1)` (`system/vl.c` 1674–1677).
  - **Fullscreen** is `-full-screen` OR `display.window.fullscreen_on_startup` (`ui/xemu.c` 1179–1181).
  - **One process per launch.** xemu has no IPC for loading a disc. It only does that from its own UI (`xemu_load_disc`, `ui/xemu.c` ~1462). QEMU's `-qmp` socket and `blockdev-change-medium` might work, but would skip xemu's SMC eject sequence (**unverified**). I found no drop-file or open-document handler (grep for `DROP_FILE` in `ui/`), so `open -a xemu file.iso` probably does nothing with the file (**unverified**).
- **Disc formats:**
  - The docs say: "xemu requires game discs to be in the form of xiso images". Redump ISOs must be repacked with `xdvdfs pack` or cut down with `dd … skip=387 bs=1M` (https://xemu.app/docs/disc-images/). The FAQ says: "Does xemu support 'redump' style ISOs? No, not yet". On CHD it says: "No, it does not."
  - The source has no Redump or partition-offset code (grep for `redump`, `xdvdfs`, `18300000` outside subprojects). The disc goes in as a plain `-drive …,media=cdrom` (`system/vl.c` 3091–3094).
  - PR #2915 "Add Redump ISO support" (extracted the game partition) was closed unmerged on 2026-07-16. #1659 (DVD security challenge for Redump and retail BIOS) has been open since 2024-06. #2809 (CHD) and #2808 (CCI) are open. Compressed-image issue #238 has been open since 2021.
  - QEMU probes the format of a file it opens, so `.zip`, `.7z` or `.cso` would be read as raw bytes and won't boot (inferred). A folder isn't supported. The UI file filter and games-directory scan accept only `.iso` and `.xiso` (`ui/xui/actions.cc` 41, `ui/xui/popup-menu.cc` 393).
- **User setup:** an MCPX boot ROM (512 bytes, checked), a flash BIOS (a modded retail or debug BIOS, since a retail one can't boot games) and an HDD image (xemu provides a clean `xbox_hdd.qcow2`) (https://xemu.app/docs/required-files/). If the EEPROM path is empty, xemu generates one at `<base>/eeprom.bin` (`system/vl.c` 2909–2949). These live under `[sys.files]` `bootrom_path`, `flashrom_path`, `hdd_path`, `eeprom_path` (`config_spec.yml` 362–367). Autostart is off until the welcome screen is dismissed (`general.show_welcome`) and the flash file opens (`system/vl.c` ~3041–3055).
- **Config location:** `SDL_GetPrefPath("xemu","xemu")` + `xemu.toml`. That's `~/Library/Application Support/xemu/xemu/xemu.toml`, unless a portable `xemu.toml` sits in the bundle's `Contents/Resources` (`ui/xemu-settings.cc` 51–105; the exact SDL path is **unverified**).
- **Latency:** there's no run-ahead code or issue (searched "run ahead" and "runahead"). Issue #746 "Improve controller input latency" (2022, 6–7 frames measured) is open. The only knob is `[display.window] vsync` (default true), applied with `SDL_GL_SetSwapInterval` (`config_spec.yml` 257–259, `ui/xemu.c` 1157). I found no frame-pacing setting.
- **Rendering on macOS:** Vulkan is built only for Windows and Linux (`meson.build` 2387–2394), so macOS uses the OpenGL renderer, which Apple layers on Metal. The CPU is QEMU TCG, native on arm64.

## How Ludeum would launch it

```
/Applications/Xemu.app/Contents/MacOS/xemu -full-screen -dvd_path "/path/Game.xiso.iso"
# per-launch settings: copy the user's xemu.toml, change e.g. [display.window] vsync, then
#   … -config_path "/…/Ludeum/xemu.toml" -dvd_path …
```

The copy keeps the user's ROM and HDD paths. xemu saves into the copy at exit, and Ludeum overwrites it on the next Play.

## Alternatives

- **Cxbx-Reloaded:** works on Windows and on Linux under Wine. Its README says "MacOS with Wine is known not to work". https://github.com/Cxbx-Reloaded/Cxbx-Reloaded
- **MAME:** its `xbox` driver is `MACHINE_NO_SOUND | MACHINE_NOT_WORKING` (`src/mame/microsoft/xbox.cpp` 166).

## What Ludeum does

Ludeum requires XISOs and doesn't convert. Each kind has the game partition's media header (`MICROSOFT*XBOX*MEDIA`) at a fixed place: 64 KiB into an XISO, and 64 KiB into the game partition, 387 MiB in, in a Redump image. So Play reads 20 bytes at each and refuses a Redump image before xemu would only reach its dashboard. The first Xbox ROM in the journal, Dino Crisis 3 (Europe), checked on 2026-10-14, is an XISO under a Redump name (4,146,200,576 bytes, its header at 64 KiB).
