# PlayStation Vita emulator for Ludeum

Researched 2026-10-07. The question: "PS Vita emulators for macOS — any usable?"

## Recommendation

**Yes, one: Vita3K.** It's the only live PS Vita emulator, and it ships a native **arm64** macOS build (plus an x86_64 one) that is rebuilt on every commit. On macOS it renders only through **Vulkan via a bundled MoltenVK**. About two thirds of the commercial games on its compatibility list are "Playable", but the list doesn't record which OS a report came from, so it says nothing specific about macOS.

It fits Ludeum less well than the other Platforms do, for three reasons:

1. **Games can't be opened from a file.** Every format (.vpk/.zip, .pkg + zRIF, .vci, decrypted folder) gets *installed*. Vita3K extracts it, decrypting where needed, into its own `ux0/app/<TITLE_ID>`. A Play then boots the installed copy by **title ID** (`-r PCSE00000`). So Ludeum needs an Install step, and each Game takes twice the disk space.
2. **Closing the game doesn't quit Vita3K.** The game window closes and Vita3K's main window comes back. A feature request to quit after the game closes has been open since 2023, and both PRs for it were closed without merging.
3. **`--fullscreen` does nothing** in the current Qt frontend. Fullscreen comes from the `boot-apps-full-screen` config key instead.

**No run-ahead, and no input-latency settings** beyond `v-sync`.

Settings for a single launch can be passed through a temp copy of `config.yml` (`-c <temp>.yml -w`), but this has two quirks (see below). Ludeum has no per-Game settings that apply to Vita (run-ahead, Game Boy model), so **launch with no settings to start with**.

## Comparison

| Candidate | macOS build | Activity (Oct 2026) | Compat | CLI boot | Per-launch, non-persisted settings | Run-ahead |
|---|---|---|---|---|---|---|
| **Vita3K** | Yes: `macos-arm64-latest.dmg` and `macos-latest.dmg` (x86_64), Vulkan via MoltenVK only | Continuous build 2026-10-06; commit 2026-10-06 | 1293 of 2010 commercial titles Playable | `-r <TITLE_ID>` (installed) or `<file.vpk>` (installs, then boots) | `-c <temp.yml> -w`, with caveats | No |
| Vita3K-Plus (fork) | **No**: AppImage, .apk, .zip only | v1.2 2026-09-30 | Claims extra per-game fixes | Same as Vita3K (**unverified**) | — | No |
| EmuCoreV | No: Android only | commit 2026-10-05 | Vita3K-based | — | — | — |
| OpenEmu / libretro / ares | No Vita core | — | — | — | — | — |

## Candidates

### Vita3K
- Activity: the `continuous` release was last built 2026-10-06 and holds `macos-arm64-latest.dmg` and `macos-latest.dmg`. Last commit 2026-10-06 (`gh api repos/Vita3K/Vita3K/{releases,commits}`). https://github.com/Vita3K/Vita3K/releases/tag/continuous. Numbered builds are mirrored at https://github.com/Vita3K/Vita3K-builds/releases (build 4134, 2026-10-06).
- The README calls it "experimental" ("Expect crashes, glitches, low compatibility and poor performance"). https://github.com/Vita3K/Vita3K/blob/master/README.md
- **Apple Silicon:** CI builds a separate `ci-macos-arm64` preset (`CMAKE_OSX_ARCHITECTURES: arm64`) next to `ci-macos-x64`, so it runs natively with no Rosetta. https://github.com/Vita3K/Vita3K/blob/master/CMakePresets.json, https://github.com/Vita3K/Vita3K/blob/master/.github/workflows/c-cpp.yml. The CPU JIT is dynarmic, and Vita3K's fork has an `arm64` host backend. https://github.com/Vita3K/dynarmic/tree/master/src/dynarmic/backend. Minimum macOS is 13.3 (`CMAKE_OSX_DEPLOYMENT_TARGET`). https://github.com/Vita3K/Vita3K/blob/master/CMakeLists.txt
  - The website still lists "any x86_64 CPU" as the minimum and OpenGL 4.4 as the minimum GPU. That's stale for macOS. https://github.com/Vita3K/Vita3K.github.io/blob/master/src/routes/quickstart/%2Bpage.svelte
- **Graphics:** on `__APPLE__` the backend is forced to Vulkan, and OpenGL is left out of the Settings menu. https://github.com/Vita3K/Vita3K/blob/master/vita3k/app/src/app_init.cpp (`set_backend_renderer`), https://github.com/Vita3K/Vita3K/blob/master/vita3k/gui-qt/src/settings_dialog.cpp. MoltenVK **v1.4.1** is downloaded and bundled into `Contents/Frameworks`. https://github.com/Vita3K/Vita3K/blob/master/external/CMakeLists.txt, https://github.com/Vita3K/Vita3K/blob/master/vita3k/CMakeLists.txt
- macOS-specific limitations found in source and issues:
  - The `memory-mapping` modes other than "Disabled" are compiled out on Apple (`get_supported_mapping_methods_mask`). https://github.com/Vita3K/Vita3K/blob/master/vita3k/renderer/src/vulkan/renderer.cpp. Any performance cost is **unverified**.
  - #4109 (open, 2026-08-30): **programmable blending reads stale framebuffer data on macOS**, on both the `high-accuracy` false and true paths. This causes visible artefacts (e.g. TIME TRAVELERS). The cause is in MoltenVK, a patch is proposed upstream, and Vita3K will need a MoltenVK bump. https://github.com/Vita3K/Vita3K/issues/4109
  - #3047 (open, 2023): freeze on macOS when loading Papers Please with save data present. https://github.com/Vita3K/Vita3K/issues/3047
  - The app is only ad-hoc codesigned (`codesign --sign -`) and packed with `create-dmg`. It isn't notarized, so expect a Gatekeeper prompt on first launch (exact behaviour **unverified**). https://github.com/Vita3K/Vita3K/blob/master/vita3k/CMakeLists.txt, https://github.com/Vita3K/Vita3K/blob/master/.ci/package-desktop.sh
- Bundle: `Vita3K.app`, bundle identifier `com.github.Vita3K.Vita3K`, executable `Vita3K` (`OUTPUT_NAME Vita3K`). https://github.com/Vita3K/Vita3K/blob/master/vita3k/CMakeLists.txt
- **Run-ahead / latency:** none. The config has no latency, run-ahead or frame-delay key, only `v-sync` (default true) and `fps-hack`. https://github.com/Vita3K/Vita3K/blob/master/vita3k/config/include/config/config.h. An issue search for "input lag", "input latency", "runahead" and "run ahead" returns 0 results.

### Compatibility
- Source: the official feed `https://api.vita3k.org/list/commercial` (dated 2026-10-05), which the website reads. It's built from issues in https://github.com/Vita3K/compatibility. Counted the way the site counts them (https://github.com/Vita3K/Vita3K.github.io/blob/master/src/lib/compatibility-summary.ts: grouped by game name, a report's worst label, a game's best report, online-only games left out), there are **2010 titles**:
  - Playable 1293 (64%), Ingame + 260, Ingame − 201, Menu 82, Intro 117, Bootable 32, Nothing 25.
  - Raw open-issue counts are higher because each region gets its own issue: Playable 1874, Ingame + 493, Ingame − 383, Menu 182, Intro 237, Bootable 94, Nothing 72.
- **Nothing macOS-specific.** The compatibility repo has no OS labels (it has status labels plus bug-type labels like "vulkan crash"), so a status doesn't say which OS it was tested on. Games that use programmable blending may look worse on macOS (#4109).

### Vita3K-Plus
- A fork with per-game fixes. Latest release v1.2 (2026-09-30) ships `Vita3K+-x86_64-v1.2.AppImage`, `.apk` and `.zip`, with **no macOS build**. https://github.com/nckstwrt/Vita3K-Plus/releases

### Others
- EmuCoreV: an Android-only app with a Vita3K-based core. https://github.com/sashkinbro/EmuCoreV
- A GitHub repo search for "vita emulator" (>50 stars, sorted by activity) returns only Vita3K and its forks or frontends. Emu4VitaPlus is a frontend that runs *on* a Vita, not an emulator of one.
- OpenEmu has no Vita repo (an org search for "vita" returns 0). The libretro org has no Vita or Vita3K core (search returned nothing). ares's cores are a26, a52, cv, fc, gb, gba, md, ms, msx, myvision, n64, ng, ngp, pce, ps1, saturn, sfc, sg, ws. https://github.com/ares-emulator/ares/tree/master/ares

## Setup the user must do

- **Firmware:** install **both** the PS Vita system software `PSP2UPDAT.PUP` (3.74, from playstation.com) **and** the font package. The quickstart says some games need the system modules, and the troubleshooting tip says to install both packages when a game won't boot. https://github.com/Vita3K/Vita3K.github.io/blob/master/translations/en/website.json (`quickstart_firmware_desc`, `quickstart_font_firmware_desc`, `quickstart_trouble_boot_desc`). The welcome dialog links to `https://www.playstation.com/<region>/support/hardware/psvita/system-software/` and to the font package. https://github.com/Vita3K/Vita3K/blob/master/vita3k/gui-qt/src/welcome_dialog.cpp
  - One `install_pup` call handles both PUPs: it extracts `vs0` (firmware), `sa0` (fonts) and `pd0`. https://github.com/Vita3K/Vita3K/blob/master/vita3k/packages/src/pup.cpp. Before each boot Vita3K warns if `vs0` or `sa0` is missing (`warn-missing-firmware`). https://github.com/Vita3K/Vita3K/blob/master/vita3k/gui-qt/src/main_window.cpp (`confirm_missing_firmware_warning`)
  - CLI: `--firmware <file.pup>` installs it and quits. https://github.com/Vita3K/Vita3K/blob/master/vita3k/config/src/config.cpp
- **Game formats:** "Vita3K supports .pkg, VCI, NoNpDrm, FAGDec, or manually decrypted games (Vitamin dumps are not supported and Maidump is unstable)". Games install from `.zip`/`.vpk`/`.vci`, or a decrypted folder can be copied into `vita_fs/ux0/app` (not NoNpDrm, .pkg or .vci). https://github.com/Vita3K/Vita3K.github.io/blob/master/translations/en/website.json (`quickstart_dumping_supported_formats`)
- **Every format is installed, none is opened in place.** From the source (https://github.com/Vita3K/Vita3K/blob/master/vita3k/interface.cpp, `install_archive_content`, `install_content`, `set_content_path`):
  - A `.vpk`/`.zip` is extracted to `ux0/app/<TITLE_ID>` (a game, category `gd`), `ux0/addcont/<TITLE_ID>/…` (DLC, `ac`), or `ux0/patch/<TITLE_ID>` (an update, `gp`). An update is then **merged into `ux0/app/<TITLE_ID>`** (`copy_path`, https://github.com/Vita3K/Vita3K/blob/master/vita3k/io/src/io.cpp).
  - NoNpDrm: a `.vpk`/`.zip`/folder containing `sce_sys/package/work.bin` is decrypted during install (`is_nonpdrm` → `decrypt_install_nonpdrm`). Vitamin dumps (`steroid.suprx`) are rejected.
  - A `.pkg` needs its **zRIF** string: `--pkg <file> --zrif <base64>` (each flag requires the other) installs it and quits.
  - A loose `.rif` or `work.bin` passed on its own just installs a license (`copy_license`).
  - `.vci` (GcToolKit cartridge image) installs through the GUI's archive installer (`install_archive`). The CLI positional argument only treats `.vpk`/`.zip` as archives, so it **rejects `.vci`** ("not a supported content type"). https://github.com/Vita3K/Vita3K/blob/master/vita3k/main.cpp
- **Where things live on macOS** (`init_paths`, https://github.com/Vita3K/Vita3K/blob/master/vita3k/app/src/app_init.cpp):
  - `config.yml`, `config/`, `cache/`, `patch/` and logs: `SDL_GetPrefPath("Vita3K","Vita3K")`, "typically `~/Library/Application Support/Vita3K/Vita3K/`" (a source comment). An older `config.yml` inside the app bundle is still honoured.
  - Emulated filesystem (`vita_fs`, which holds `ux0/app`, `ux0/user/00/savedata`, `vs0`, `sa0`): `…/Vita3K/Vita3K/fs/`, unless an older `…/Vita3K/Vita3K/ux0` already exists. It can be moved with the `pref-path` config key.
  - A `portable/` folder next to `Vita3K.app` redirects all of the above.
  - The website says `~/Library/Application Support/Vita3K` for macOS. That disagrees with the source.

## CLI (from the parser)

The parser is CLI11 in `init_config`, https://github.com/Vita3K/Vita3K/blob/master/vita3k/config/src/config.cpp:

- Positional `content-path`: "Path to the app with a .vpk/.zip extension or folder of content to install & run". `main.cpp` installs it **every time** (it deletes and re-extracts `ux0/app/<TITLE_ID>`, with no reinstall prompt on the CLI path), then sets `run_app_path` and auto-boots it. https://github.com/Vita3K/Vita3K/blob/master/vita3k/main.cpp
- `--installed-path, -r <TITLE_ID>`: "Path to the installed app to run". Despite the name, the value is a **title ID**, checked with `CLI::IsMember` against the folder names in `<vita_fs>/ux0/app`. Anything else is a parse error and Vita3K exits with `InitConfigFailed`. `MainWindow` then calls `boot_game(title_id)` straight after it opens. https://github.com/Vita3K/Vita3K/blob/master/vita3k/gui-qt/src/main_window.cpp
- `--self, -S <path>` (default `eboot.bin`), `--app-args, -Z`.
- Install-and-quit flags: `--firmware <pup>`, `--pkg <file> --zrif <zrif>`, `--deleted-id, -d <TITLE_ID>` (removes the app, its DLC, savedata and shader cache).
- Config flags:
  - `--config-location, -c <file.yml|dir>`.
  - `!--keep-config, -w`: "Do not modify the configuration file after loading". It sets `overwrite_config = false`.
  - `--load-config, -f`.
  - `--backend-renderer, -B OpenGL|Vulkan` (ignored on macOS, which forces Vulkan).
  - `--lle-modules, -m`, `--log-level, -l 0–6`, `--archive-log, -A`, and debug flags (`-C`, `-U`, `--log-active-shaders`).
- `--fullscreen, -F` is parsed into `cfg.fullscreen`, but **nothing in the current source reads it**. The Qt frontend uses `boot-apps-full-screen` (`boot_game_once`). It was presumably left over from the older frontend (**unverified**).
- `--console, -z` only changes logging and SDL init. The Qt `MainWindow` is still created, so there's no headless mode.
- **No `--no-gui` and no quit-after-game flag.** `on_game_closed` just deletes the game window and brings the main window back. #2884 "Quit emulator after closing game" is open, and PRs #3971 (`--exit-on-game-close`) and #4007 (`--no-gui`) were both closed unmerged in June 2026. https://github.com/Vita3K/Vita3K/issues/2884, https://github.com/Vita3K/Vita3K/pull/3971, https://github.com/Vita3K/Vita3K/pull/4007

### Config, and passing settings for one launch
- At startup `init_config` loads the user's `config.yml` and then, by default, **writes it back** with the CLI values merged in (`if (cfg.overwrite_config || …) serialize_config(cfg, cfg.config_path)`). `-w` stops that write.
- With `-c <temp.yml>`, `cfg.config_path` becomes the temp file, so the startup write and later saves from the controls and user dialogs (`serialize_config(emuenv.cfg, emuenv.cfg.config_path)`) go to the temp copy. That matches the DuckStation/PPSSPP pattern. Two quirks:
  1. **Only non-default values in the temp file win.** `merge()` copies a key only if `rhs.member != option_default` (unless the whole file equals defaults). A temp file can't put a key *back* to its default over a user's non-default value (e.g. force `v-sync: true` when the user turned it off).
  2. **The Settings dialog ignores `-c`.** `commit_settings` saves through `save_current_config(…, emuenv.config_path, …)`, which is the real config folder. So changes made there during a Ludeum Play land in the user's real `config.yml` (or the per-game XML). https://github.com/Vita3K/Vita3K/blob/master/vita3k/app/src/app_init.cpp
- **Per-game config:** `<config dir>/config/config_<TITLE_ID>.xml` holds the `CurrentConfig` subset (renderer, resolution multiplier, `v-sync`, `high-accuracy`, `fps-hack`, modules, language and so on). It's loaded over the global values when the app boots, so it beats anything in a `-c` file for those keys. https://github.com/Vita3K/Vita3K/blob/master/vita3k/config/src/settings.cpp, https://github.com/Vita3K/Vita3K/blob/master/vita3k/config/include/config/state.h

## How Ludeum would launch it

**What the ROM is.** Ludeum keeps the user's dump as the ROM: a `.vpk`/`.zip` (including NoNpDrm zips), a `.pkg` (which also needs its zRIF), or a decrypted folder. Vita3K never reads that file at Play time. It boots its own installed copy in `ux0/app/<TITLE_ID>`. So Ludeum also needs:

1. **The title ID.** Read `TITLE_ID` from `sce_sys/param.sfo` inside the dump. The compatibility feed also gives a `titleId` for each entry.
2. **An Install step**, once per Game, when it's added or on its first Play:
   - `.pkg`: `Vita3K --pkg <file> --zrif <zrif>`. This installs and quits, with no window.
   - `.vpk`/`.zip`/folder: no install-only flag. `Vita3K <file>` installs and then boots the game. Copying a *decrypted* folder into `ux0/app/<TITLE_ID>` works too, but NoNpDrm needs Vita3K's decryption.
   - Don't pass the `.vpk` on every Play. It re-extracts the whole game each time and wipes any update merged into `ux0/app`.
3. **Play:**

```
# No per-Game settings for Vita yet:
/Applications/Vita3K.app/Contents/MacOS/Vita3K -r PCSE00000

# If settings are ever needed: a copy of the user's config.yml with Ludeum's keys written over it
#   ~/Library/Application Support/Vita3K/Vita3K/config.yml  ->  <Ludeum folder>/Vita3K config.yml
#   boot-apps-full-screen: true      # the only way to get fullscreen; -F does nothing
#   v-sync: false                    # non-default, so it does override
/Applications/Vita3K.app/Contents/MacOS/Vita3K -c "<Ludeum folder>/Vita3K config.yml" -w -r PCSE00000
```

`Emulator(name: "Vita3K", bundleIdentifier: "com.github.Vita3K.Vita3K")`. The process **stays running after the game closes**, so "Play ended" means the user quitting Vita3K.

## Open questions
- Should the Install step happen when the ROM is added or on its first Play? Should Ludeum track installed title IDs (by listing `<vita_fs>/ux0/app`) and offer Uninstall (`-d <TITLE_ID>`)? Installing doubles the disk use.
- Would symlinking `ux0/app/<TITLE_ID>` to a decrypted folder in Ludeum's library avoid the copy? `get_file_set` uses `is_directory`, which follows symlinks, but this is **unverified** end to end.
- How fast is it on Apple Silicon, and what does the Apple-only "Disabled" memory mapping cost? No first-party numbers. This needs a hands-on test.
- How much does #4109 (programmable blending under MoltenVK) affect the Games the user actually owns?
- Does Gatekeeper block the ad-hoc-signed app until the user approves it in System Settings?
- A Vita Platform has no run-ahead and no Game Boy model, so should Ludeum's per-Game settings sheet just be hidden for it?
