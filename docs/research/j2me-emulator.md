# Java phone (J2ME) emulator for Ludeum

Researched 2026-11-12 for [#100](https://github.com/danielholmes/ludeum/issues/100). What was decided is [ADR 0044](../adr/0044-java-phone-games-are-played-in-kemulator-which-ludeum-installs-with-a-java-runtime.md): Ludeum makes KEmulator into an app of its own at Install, rather than launching `java` itself. The question: which emulator should Ludeum install and launch as a whole app ([ADR 0038](../adr/0038-emulators-are-whole-apps-ludeum-installs-not-cores.md)) to Play Java ME (J2ME, MIDP) phone games on an Apple Silicon Mac, starting with **Resident Evil: Genesis** and **Resident Evil: Confidential Report**? The issue quotes a suggestion of KEmulator. The library already has these Games on IGDB's Legacy Mobile Device platform, with their jars kept as Attachments, so candidates are weighed by how well Ludeum can manage them: a pinned fetch, a launch straight into a jar, Game saves sent into the Data folder, and settings for one launch.

Most of this is desk research: claims come from each project's source at its default branch on 2026-11-12, its GitHub releases and issues, and its README. The jars were read where they sit in the Data folder: their manifests, and the names of the API packages their classes refer to. Afterwards KEmulator nnmod alone was run, from the scratchpad; see [What was run](#what-was-run).

## What was run

On 2026-11-12, with Daniel's go-ahead, `kemnnx64.v2.22.zip` and Temurin `OpenJDK21U-jre_aarch64_mac_hotspot_21.0.13_9.tar.gz` were downloaded from their GitHub releases. Both matched the SHA-256s below. They were unpacked into the scratchpad, and copies of two of the jars were launched by `java` directly, with `kemulator.sh`'s flags, `-Xdock:name=KEmulator`, `-jar <rom> -s`, and a `property.txt` written first with `RMSFolder=file\:///…/Game Saves`, `AutoUpdate=1` and `ShowAppSettingsOnStart=false`:

- **It runs on macOS 26.5.2, arm64, on Java 21.0.13** ("KEmulator nnx64 2.22 Running on Mac OS X aarch64"). Gatekeeper raised nothing: the downloads came through `gh`, so they had no quarantine flag. Ludeum's own installs of the other Emulators carry none either.
- **Resident Evil: Genesis** booted straight into its title menu (New Game, Load Game, Options…) in a 176×220 screen, the default preset's.
- **Resident Evil: Degeneration** (the "Degeneracion By Gamaliel" jar) booted at `-screen 240x320` to its language menu, laid out for 240×320. Its 3D comes after the menus, and no input could be sent, so it wasn't reached.
- **Game saves went where `RMSFolder` said**, a path with a space included. Genesis wrote `Game Saves/Q2FwY29tIEludGVyYWN0aXZlLCBJbmMuX1Jlc2lkZW50IEV2aWw=/b3B0aW9ucy5kYXQ=/1.rms`, i.e. `base64("Capcom Interactive, Inc._Resident Evil")/base64("options.dat")/<record>.rms`, as the source reads.
- **No game controller on arm64.** JInput's `libjinput-osx.dylib` is ppc/i386/x86_64 only, so its OS X plugin fails to load (logged, not fatal). Only the keyboard plays.
- **A SIGTERM empties `property.txt`.** Stopping the process that way left a zero-byte file, so Ludeum must write its Standing settings before every Play, not just once.
- **No `midlets.ini` was written**, as `ShowAppSettingsOnStart=false` meant no per-game settings were saved.
- Not tested, as nothing could be clicked or typed: closing the window, a save surviving a relaunch, the keypad mapping, and the settings dialogs (#236).

## Recommendation

**KEmulator nnmod** ([shinovon/KEmulator](https://github.com/shinovon/KEmulator)), its "multi-platform" build (`kemnnx64.v2.22.zip`), run on a **Java 21 runtime that Ludeum installs beside it** (e.g. Temurin 21 JRE, aarch64). Ludeum launches `java` itself with KEmulator's own JVM flags and `-s`, rather than through its `kemulator.sh`:

- It's the live KEmulator. Its last release is v2.22 (2026-09-19), its last commit was 2026-11-06, and there have been six releases in 2026. Its README lists "macOS 11 Big Sur (aarch64)", and the build loads `swt-macosx-aarch64.jar` and LWJGL's `macos-arm64` natives on an arm64 JVM.
- It **starts straight into a jar**: `-jar <file.jar>` or `-jad <file.jad>`, `-screen WxH` for one launch, and `-s` so it doesn't relaunch itself.
- **Game saves can be put in the Data folder.** Its RMS folder is the `RMSFolder` key in `property.txt`. On macOS that key needs a `file://` prefix to be absolute (see below).
- **Saves are keyed by the MIDlet, not the file.** The key is `base64(MIDlet-Vendor + "_" + MIDlet-Name)`, so renaming a jar keeps its saves.
- **Per-game settings are KEmulator's own.** Phone model, screen size and keys live in `midlets.ini`, keyed by the jar's SHA-256. That's the ADR 0038 split: set in the Emulator, during a Play, and lasting.
- **M3G (JSR-184) runs on hardware OpenGL via LWJGL.** It also has Nokia UI, Sony Ericsson, Siemens, Samsung and Mascot Capsule APIs. Neither Resident Evil game needs any of these (see [The two games](#the-two-resident-evil-games)).

What complicates it:

- **There's no `.app` and no signed build.** The release is a zip with a jar and native libraries, and it brings no Java runtime. Ludeum would need to install and pin a JRE as part of the Emulator.
- **macOS is a second-class platform.** Settings-dialog text is invisible on macOS ([#236](https://github.com/shinovon/KEmulator/issues/236), open). A packager reports that its bundled JInput doesn't work on aarch64, so controllers may not ([#230](https://github.com/shinovon/KEmulator/issues/230)). SWT is held at 4.20 for Java 8's sake.
- **It has no licence.** It's a decompile of the closed-source KEmulator 1.0.3 with GPLv3 code from FreeJ2ME mixed in. Ludeum fetching the author's release for this Mac is fine. Ludeum shipping a copy is not clearly allowed.
- **It has no Save states.** No J2ME emulator here has any.

**FreeJ2ME-Plus** is the fallback if KEmulator's SWT misbehaves on this Mac. It's GPLv3, a pure AWT jar with no natives, and everything it writes goes under its working directory, which is easy for Ludeum to redirect. Against it: its macOS GUI has had regressions this autumn ([#256](https://github.com/TASEmulators/freej2me-plus/issues/256)), it has no gamepad on macOS (the reader is a stub), its last stable release (1.52) is from December 2025, and its saves are keyed by the MIDlet's display name.

Everything else is out. J2ME Loader and JL-Mod are Android-only. MicroEmulator is archived and last released in 2010. Oracle's Java ME SDK targets Windows and Linux x86. SquirrelJME's only release is from 2018. Running the libretro cores inside Ludeum is ruled out by ADR 0038.

## Comparison

| | KEmulator nnmod v2.22 | FreeJ2ME-Plus 1.52 / nightly | FreeJ2ME (hex007) | J2ME Loader / JL-Mod | MicroEmulator 2.0.4 | SquirrelJME |
|---|---|---|---|---|---|---|
| Latest release | 2026-09-19 | 1.52 2025-12-24; nightly jar 2026-11-11 | None | 1.8.2 2024-08 / continuous 2026-11-02; JL-Mod continuous 2026-04-11 | 2010-01-14 | 0.2.0, 2018-12-25 |
| Last commit | 2026-11-06 | 2026-11-11 | 2026-10-04 | 2026-11-08 / 2026-04-11 | 2023-03-28 (archived) | 2026-11-11 |
| macOS arm64 | Yes: listed; SWT + LWJGL arm64 natives in the zip | Yes: pure Java; nightly has a jlinked `macos-arm64` runtime | Pure Java | **No: Android only** | Pure Java (Swing), unmaintained | Not a usable player yet |
| Runtime | Java 8, or OpenJDK 17–21 | Java 8+ (README badge: VM 5) | Java | Android | Java | — |
| Licence | **None stated** (decompiled KEmulator + GPLv3 code) | GPLv3 | GPLv3 | Apache-2.0 | LGPL | MPL-2.0 |
| Start into a jar | `-jar`, `-jad`, `-midlet`, `-screen WxH`, `-s` | Positional: `file:///…jar [sp=…] fullscreen w h scale keyLayout fps doja` | Positional | — | — | — |
| Game saves (RMS) | `RMSFolder` in `property.txt` (`file://` for absolute); keyed by Vendor+Name | `<cwd>/rms/<MIDlet-1 name>/` | `<cwd>/rms/<jar name>/` | — | — | — |
| Settings file | `property.txt` (global), `midlets.ini` (per jar SHA-256), both beside `KEmulator.jar`; rewritten on exit | `<cwd>/freej2me_system/freej2me.conf`, `<cwd>/config/<MIDlet-1 name>/game.conf` | `<cwd>/config/…` | — | — | — |
| Save states | No | No | No | No | No | No |
| M3G 3D | Yes, LWJGL OpenGL (Swerve on Windows only) | Yes, its own software M3G | Partial | Yes | No | — |
| Gamepad on macOS | JInput, aarch64 doubtful | No (stub) | No | — | — | — |

## Candidates

### KEmulator nnmod (shinovon)

- **What it is.** The README says: "Cross-platform J2ME emulator, based on decompiled KEmulator 1.0.3". It lists the main changes as "Cross-platform", "Hardware accelerated 3D engine", "Freely resizable window and fullscreen mode", "Mascot Capsule and SoftBank MEXA support", "Implemented NokiaUI 1.4", "Support of obscure OEM APIs" ([README](https://github.com/shinovon/KEmulator/blob/main/README.md)). Its webpage is [nnproject.cc/kem](https://nnproject.cc/kem).
- **Activity.** v2.22 came out 2026-09-19 and v2.21.4 on 2026-04-17. There were v2.21.x releases in January, February and March 2026. The last commit, "Update MascotME", was 2026-11-06 (`gh api repos/shinovon/KEmulator/{releases,commits}`).
- **Release assets** ([v2.22](https://github.com/shinovon/KEmulator/releases/tag/v2.22)):
  - `kemnnmod.v2.22.nojre.zip`: Windows 32-bit. 10.8 MB, `sha256:c506ca12…e1d2`.
  - `kemnnx64.v2.22.zip`: "Multi-platform". 33.1 MB, `sha256:f9a5a442…8e5e`.

  The webpage labels them "Windows 32-bit" and "Multi-platform" and says which to use on macOS only by those labels ([nnproject.cc/kem](https://nnproject.cc/kem)). What's inside the multi-platform zip wasn't checked, as nothing was downloaded. The repo's `home/` folder, which the build packages, holds `KEmulator.jar`'s natives:
  - `swt-macosx-aarch64.jar` and `swt-macosx-x86_64.jar`
  - LWJGL 3.3.6 `lwjgl-*-natives-macos-arm64.jar`
  - `lwjgl3-swt-macos-arm64.jar`
  - `libjinput-osx.jnilib`
  - `kemulator.sh`
- **Requirements.** The README lists "Java 8 by Oracle" or "OpenJDK 17-21 (Will run on 22+, but debug tools work is not guaranteed)", "macOS 11 Big Sur (aarch64)" and "OpenGL 1.3 support". It uses SWT 4.20 / 4.7, LWJGL 3.3.6, JNA 5.7.0, JInput 2.0.5 and vlcj 4.7.3.
- **No JRE, no `.app`.** The multi-platform zip has no runtime; `kemulator.sh` uses `$KEM_DIR/jre/bin/java` if present, else `java` on `PATH` ([home/kemulator.sh](https://github.com/shinovon/KEmulator/blob/main/home/kemulator.sh)). An outside packager, [rwv/KEmulator-nnmod-macos](https://github.com/rwv/KEmulator-nnmod-macos), built `.app`s with `jpackage` for v2.20 in September 2025 and hasn't released since. The maintainer replied that newer SWT won't be used, to keep Java 8 support ([#230](https://github.com/shinovon/KEmulator/issues/230)).
- **Apple Silicon is real in the source.**
  - The x64 build's `EmulatorPlatform.loadSWTLibrary` maps `os.name` "mac" + `os.arch` "aarch64" to `swt-macosx-aarch64.jar`.
  - `getLwjglNatives` maps the same to `lwjgl-…-macos-arm64.jar` ([x64/src/main/emulator/EmulatorPlatform.java](https://github.com/shinovon/KEmulator/blob/main/x64/src/main/emulator/EmulatorPlatform.java)).
  - The 32-bit Windows build refuses anything but x86 Windows: "Can't run this version of KEmulator nnmod on this architecture … Try multi-platform version instead" (`Emulator.main`).
  - In the x64 build, M3G is forced to LWJGL (`if (platform.isX64()) Settings.g3d = 1`). The Windows DLL engines (Swerve `jsr184client.dll`, Mascot `micro3d_v3_32.dll`) are the old KEmulator's and only matter on 32-bit Windows. Mascot Capsule defaults to its GL engine on x64 (`Micro3D_Engine`, `GL`).
- **macOS problems on record.**
  - [#236](https://github.com/shinovon/KEmulator/issues/236) "Invisible settings UI on macOS" (open, 2025-10-09, Sonoma, Temurin 21/25). The maintainer added in May 2026 that the app-settings dialog has the same problem.
  - The `.app` packager says he had to update SWT "to fix UI text rendering issues on Apple Silicon", and update JInput to `osx-plugin-2.0.10` "which enables input device support on macOS aarch64" ([#230](https://github.com/shinovon/KEmulator/issues/230)). The repo still ships JInput 2.0.5's `libjinput-osx.jnilib`, so **controllers on arm64 are doubtful**. The keyboard doesn't need JInput.
- **It relaunches itself unless given `-s`.** In `main`, `if (!(forked || AppSettings.uei) && (librariesException != null || Utils.macos || Utils.isJava9())) { loadGame(null, false); return; }`. On macOS, `loadGame` starts a new `java` with `-XstartOnFirstThread`, the `--add-opens` list and `-javaagent`, then the first process exits. `-s` sets `forked` and skips this. `kemulator.sh` always passes `-s` and the flags itself ([Emulator.java](https://github.com/shinovon/KEmulator/blob/main/src/main/emulator/Emulator.java)). For Ludeum this matters: without `-s`, the process Ludeum started ends at once, and the Play would look over.

#### Command line (`Emulator.parseLaunchArgs`)

A bare `.jar`, `.jad` or `.jam` argument is the game. Each `-key value` is optional:

| Flag | Effect |
|---|---|
| `-jar <path>` | The MIDlet jar, made canonical |
| `-jad <path>` | A descriptor; the jar comes from its `MIDlet-Jar-URL` (`getMidletJarUrl`) |
| `-midlet <class>` | The MIDlet class, when there's no usable `MIDlet-1` |
| `-cp <path>` | A classpath instead of a jar |
| `-screen WxH` | The screen size **for this launch**; also sets resize mode to Fit |
| `-key a=b;c=d` | Key overrides for this launch (`KeyMapping.keyArg`) |
| `-fontname`, `-fontsmall/medium/large <n>` | Fonts |
| `-rec <file>` | Record or play back keys |
| `-s` | "Forked": don't relaunch |
| `-log` | Open the log window |
| `-lwj` / `-swerve`, `-mascotgl` / `-mascotsw` / `-mascotdll` | 3D engines |
| `-uei`, `-bridge`, `-xray`, `-hide` | IDE integration and debug views |

**There's no flag for fullscreen or for the phone model.** Fullscreen is `FullscreenWindow=true` in `property.txt`: at start, `shell.setFullScreen(true)` with resize mode Fit, and F11 toggles it ([EmulatorScreen.java](https://github.com/shinovon/KEmulator/blob/main/src/main/emulator/ui/swt/EmulatorScreen.java)). The phone model is `DevicePreset` in the game's `midlets.ini` section.

**The screen size is chosen in this order** (`AppSettings.load`):

1. `-screen`
2. The jar's `MIDxlet-ScreenSize`, `SEMC-Screen-Size` or `Nokia-MIDlet-Original-Display-Size`
3. The jar's file name containing `128x160`, `176x208`, `240x320` and so on
4. `ScreenWidth`/`ScreenHeight` saved in `midlets.ini`
5. The preset's own size

#### Where it keeps things

- **Its "user path" is the folder holding `KEmulator.jar`**, unless it's "installed" (Linux `/usr`, `/opt` or `~/.local`; Windows `%APPDATA%` or a registry key). On macOS it's always portable: "non-".app" program management on macOS is messy so doing nothing" (`checkIsPortable`, `getUserPath`). Nothing in the source moves it: no environment variable, no system property.
- **`property.txt`** is the global settings, a `java.util.Properties` file in the user path. It's read at start (`Property.loadProperties`) and **written back whole** on exit (`Emulator.notifyDestroyed` → `saveProperties`, called from the window's `widgetDisposed`). Keys that matter to Ludeum ([Property.java](https://github.com/shinovon/KEmulator/blob/main/src/main/emulator/ui/swt/Property.java)):
  - `RMSFolder` (default `./rms`)
  - `AutoUpdate`: 0 = not asked, so a dialog asks; 1 = manual; 2 = automatic. Automatic downloads from `https://nnproject.cc/kem/releases/` and swaps the jar ([Updater.java](https://github.com/shinovon/KEmulator/blob/main/src/main/emulator/Updater.java)).
  - `ShowAppSettingsOnStart` (default `true`): opens the per-game settings dialog the first time a jar is seen.
  - `GlobalSettings`: one settings section for every game.
  - `FullscreenWindow`, `ResizeMode`
  - `MAP_KEY_NUM_0` … `MAP_KEY_RSOFT`: the keyboard map
  - `ControllerMap.*`
  - `SecurityEnabled` and `Security.*`: MIDP permission prompts
  - `NetworkNotAvailable`
  - `JVMHeap`
  - `PresetsPath`
- **`RMSFolder` and absolute paths.** `getRmsFolderPath` puts the user path in front of any value starting with `.` **or with `/`**. So on macOS `RMSFolder=/Users/…` becomes `<KEmulator folder>/Users/…`. A value starting `file://` skips that test and then has the prefix stripped, so **`RMSFolder=file:///Users/…/rms` is how to give it an absolute path**. This is from reading the code; it hasn't been run. In `property.txt` the colons need escaping (`file\:///…`), as `java.util.Properties` reads them.
- **The Game save layout** ([RecordStore.java](https://github.com/shinovon/KEmulator/blob/main/src/midp/javax/microedition/rms/RecordStore.java)):

  ```
  <RMSFolder>/<base64(MIDlet-Vendor + "_" + MIDlet-Name)>/<base64(storeName)>/idx
                                                         .../<recordId>.rms
  ```

  Base64 has `/` replaced by `-`. A `legacy/` subfolder is read as a fallback for the old KEmulator's flat `.<name>/<name>.idx` files. So a Game's saves are found from the jar's manifest, and **a renamed jar keeps them**. Two builds of one game with the same Vendor and Name share them.
- **`midlets.ini`** holds the per-game settings, in the user path. Its sections are named `[<sha256 of the jar>:<jar path>]`, and a section matches on **either** the hash or the path. It holds `DevicePreset`, `ScreenWidth`/`ScreenHeight`, the soft-key and direction key codes, fonts, locale, encoding, frame rate and more (`AppSettings.load`/`save`). It's saved through `midlets.ini.tmp` and `Files.move(…, REPLACE_EXISTING)`, which **replaces a symlink with a plain file**. So it can't be kept in the Data folder by symlinking it.
- **No Save states.** The source has no snapshot code; the only "state" files are API classes.

#### Input and compatibility

- **Keyboard.** The keypad (0–9, `*`, `#`, the arrows, select, both soft keys) is mapped to Mac keys in its settings, or with `-key` for one launch. Gamepads go through JInput (`ControllerMap.*`), which is doubtful on arm64 (above).
- **APIs.** The source tree has MIDP 2.0 LCDUI ("Full lcdui implementation"), MMAPI with MIDI (selectable SoundFont), M3G, Nokia UI 1.4, Mascot Capsule v3, Sony Ericsson, Siemens, Samsung, LG, Motorola and others, DoJa (limited) and JSR-75/82 ([src tree](https://github.com/shinovon/KEmulator/tree/main/src)). There's no public compatibility list. The tracker has no reports on Resident Evil (searched "Resident Evil", "Resident" and "Capcom").

### FreeJ2ME-Plus (TASEmulators)

- **What it is.** "A J2ME emulator with libretro and AWT frontends, it aims to run on basically anything that can run a Java VM". It's maintained by AShiningRay, under GPLv3 ([README](https://github.com/TASEmulators/freej2me-plus/blob/devel/README.md), [LICENSE](https://github.com/TASEmulators/freej2me-plus/blob/devel/LICENSE)).
- **Activity.**
  - Stable [1.52](https://github.com/TASEmulators/freej2me-plus/releases/tag/1.52) came out 2025-12-24: `freej2me-v1.52.zip`, `freej2me_libretro-v1.52.zip`.
  - The [nightlies](https://github.com/TASEmulators/freej2me-plus/releases/tag/nightlies) tag carries `freej2me_plus-nightly.zip` (2026-11-11) and `freej2me_plus_runtime_macos-arm64.tar.gz` (33 MB, 2026-10-17).
  - The last commit was 2026-11-11.
  - The nightly assets are re-uploaded with `--clobber` ([libretro.yml](https://github.com/TASEmulators/freej2me-plus/blob/devel/.github/workflows/libretro.yml)), so a nightly URL is no pin.
- **Runtime.** The nightly runtime is `ant build-runtime`: jlink of `java.base` + `java.desktop` from Temurin 21, built on `macos-latest` for arm64. It's meant for the libretro core, but it's a plain JRE. The standalone jar is AWT only, with no natives, so any Java 8+ runs it.
- **Command line.** `java -jar freej2me.jar 'file:///path/to/midlet.jar' ['sp=…'] fullscreen width height scale keyLayout framerate dojaversion`. All are positional, and to set a later one every earlier one must be given ([README](https://github.com/TASEmulators/freej2me-plus/blob/devel/README.md); `FreeJ2ME(String[])` in [FreeJ2ME.java](https://github.com/TASEmulators/freej2me-plus/blob/devel/src/org/recompile/freej2me/FreeJ2ME.java)). `keyLayout` goes 0 Default, 1 LG, 2 Motorola/Softbank/Sharp … 6 Nokia Keyboard, 8 Siemens, 10 KDDI.
  - The README says "any settings specified at the config file take precedence over the values passed via command-line". But the code puts the arguments into `Mobile.config.settings` after the jar has loaded its config. Which wins needs a run.
  - Launching from the command line has had a window-size bug, on macOS among others ([#257](https://github.com/TASEmulators/freej2me-plus/issues/257)).
- **Where it keeps things: the working directory.** `dataPath` is `""`, so everything is relative to it:
  - `./rms/<suite>/<store>.rms`
  - `./config/<suite>/game.conf`, per game: resolution, phone, FPS, compat hacks, M3G options
  - `./freej2me_system/freej2me.conf` (system: key and gamepad maps, log level) and `FreeJ2ME.log`

  `<suite>` is the first `MIDlet-1` name with `:` removed, or the jar's file name if there's no manifest name ([Config.java](https://github.com/TASEmulators/freej2me-plus/blob/devel/src/org/recompile/freej2me/Config.java), [RecordStore.java](https://github.com/TASEmulators/freej2me-plus/blob/devel/src/javax/microedition/rms/RecordStore.java), [MIDletLoader.java](https://github.com/TASEmulators/freej2me-plus/blob/devel/src/org/recompile/mobile/MIDletLoader.java)). The vendor isn't part of the key. Saves aren't compatible with the original FreeJ2ME's (README).
- **macOS state.** [#256](https://github.com/TASEmulators/freej2me-plus/issues/256) (closed 2026-09) reported, on macOS 15 and 26:
  - forms cut off
  - an invisible menu bar
  - "No title screen"
  - a later regression with an `AquaMenuPainter` NullPointerException

  The gamepad reader for macOS is "a complete stub at the moment" ([MacGamepadReader.java](https://github.com/TASEmulators/freej2me-plus/blob/devel/src/org/recompile/freej2me/gamepad/MacGamepadReader.java)).
- **Compatibility list.** [docs/compat_data/FreeJ2ME Compatibility.md](https://github.com/TASEmulators/freej2me-plus/blob/webpage/docs/compat_data/FreeJ2ME%20Compatibility.md), on the `webpage` branch, last changed 2026-09-19. It has Resident Evil Degeneration (240x320) and Resident Evil Uprising (320x240) as "No Issues". **Neither Genesis nor Confidential Report is listed.**
- No Save states.

### FreeJ2ME (hex007)

FreeJ2ME-Plus's parent ([hex007/freej2me](https://github.com/hex007/freej2me)), GPLv3. It has no GitHub releases. Its last commit was a merge on 2026-10-04 ("bundled-jre"). It keys saves by the jar's file name, so a renamed jar loses them (`MIDletLoader` before Plus changed it). Nothing it has beats Plus.

### The original KEmulator (Wu.Liang)

Closed-source freeware, 0.9.8 and 1.0.3, for 32-bit Windows. Nnmod's README names it as the source it decompiled. Its 3D and Mascot engines are Windows DLLs (`jsr184client.dll`, `micro3d_v3_32.dll` in nnmod's `home/`). It doesn't run on macOS, and nnmod replaces it.

### J2ME Loader and JL-Mod

**Android only.** "A J2ME emulator for Android" ([nikita36078/J2ME-Loader](https://github.com/nikita36078/J2ME-Loader); continuous `.apk` 2026-11-02). JL-Mod is "J2ME emulator for Android (unofficial fork of … J2ME-Loader)" ([woesss/JL-Mod](https://github.com/woesss/JL-Mod); `.apk`s, continuous 2026-04-11). Both are Apache-2.0, and KEmulator nnmod borrows code from both.

- J2ME Loader's tested list rates "Resident Evil - Degeneration 240x320" as P ([#108](https://github.com/nikita36078/J2ME-Loader/issues/108)).
- JL-Mod's list rates Degeneration 3D and The Missions 3D as "Excellent" ([JL-Mod #68](https://github.com/woesss/JL-Mod/issues/68)).
- Neither list has Genesis or Confidential Report.

### MicroEmulator

Pure Java (Swing), LGPL ([microemulator/pom.xml](https://github.com/barteo/microemu/blob/master/microemulator/pom.xml)). Its last release, 2.0.4, was 2010-01-14 ([tag](https://github.com/barteo/microemu/tree/microemulator_2_0_4); Maven Central `lastUpdated 20100114160129`), and the [repo](https://github.com/barteo/microemu) is archived. It has no M3G. Out.

### Oracle Java ME SDK and the Wireless Toolkit

The current Java ME SDK 8.3 supports "Microsoft Windows 7 or Windows 10 64-bit … ; Linux/x86 (Ubuntu 15.10 Unity 64 bit)", needs JDK 8 and NetBeans or Eclipse, and is built around Java ME Embedded 8.3 ([release notes](https://docs.oracle.com/javame/8.3/release-notes-sdk/toc.htm)). It's a developer IDE kit, not a player. Oracle's download and archive pages refused automated fetches (HTTP 403), so the old MIDP-era WTK 2.5.2 and ME SDK 3.x platforms weren't checked from the source. Out.

### SquirrelJME

A clean-room Java ME 8 VM "for the Software Preservation of mobile Java ME devices", MPL-2.0, with a libretro frontend in progress ([README](https://github.com/SquirrelJME/SquirrelJME)). Its only release is 0.2.0 (2018-12-25). The roadmap put 0.4.0 at "206 of 317 (64%)" of its goals on 2026-06-28 ([route.mkd](https://github.com/SquirrelJME/SquirrelJME/blob/trunk/route.mkd)). It's active but not a player yet. Worth another look when 0.4.0 ships.

### libretro cores

FreeJ2ME-Plus and FreeJ2ME have libretro cores; SquirrelJME is building one. Ludeum runs whole apps, not cores (ADR 0038), and both programs above also run standalone, so the cores add nothing here.

## The two Resident Evil games

**IGDB.** Both are on **platform 55, "Legacy Mobile Device"** (abbreviation "Mobile"), and only there. That's from the platform list and game records Ludeum cached from IGDB's API, `igdb:platforms:all` (220 platforms) and `igdb:game:<id>`.

- [Resident Evil: Genesis](https://www.igdb.com/games/resident-evil-genesis) is IGDB 165142, 2008, Capcom / Capcom Interactive Canada.
- [Resident Evil: Confidential Report](https://www.igdb.com/games/resident-evil-confidential-report) is IGDB 251364. Release dates are 2003-02-13 and twice 2006. IGDB's summary: "a turn-based strategy game series by Capcom released for the mobile phone in 2006 … four titles released separately: … File #1 … File #4".

**IGDB doesn't split J2ME from other legacy mobile platforms.** There's no J2ME, BREW, i-mode or DoJa platform among the 220. Those games all go under 55. N-Gage (42), BlackBerry OS (73), Windows Mobile (405), Windows Phone (74), Palm OS (417) and Zeebo (240) are separate platforms. So a Legacy Mobile Device Game isn't necessarily a J2ME jar, and Ludeum can't tell from the Platform alone.

**The jars in the library**, read from `Data/Attachments/Legacy Mobile Device/` (manifest and class constant pools only):

| Attachment | MD5 | MIDlet-Name / Vendor / Version | Profile |
|---|---|---|---|
| `Resident Evil - Genesis/residentev_asvd7ay4.jar` | `425e7855…cd87c` | Resident Evil / Capcom Interactive, Inc. / 1.0.4 | CLDC-1.1, MIDP-2.0 |
| `… Confidential Report (File 1).jar` | `6a49c462…99c14` | Resident Evil Confidential Report 1 / CAPCOM / 1.0.2 | CLDC-1.0, MIDP-2.0 |
| `… (File 2).jar` | `32603b67…2cd890` | Resident Evil CR 2 / CAPCOM/BiNPDA / 1.0.0 | CLDC-1.0, MIDP-2.0 |
| `… (File 3).jar` | `2a62b577…21db83` | RE Confidential Report 3 / CAPCOM/BiNPDA / 1.0.0 | CLDC-1.0, MIDP-2.0 |
| `… (File 4).jar` | `b85e5cfb…dadf7662` | Resident Evil CR 4 / mob.ua / 1.0.0 | CLDC-1.0, MIDP-2.0 |

- **No game in the set needs 3D or a vendor API.** All five refer only to `javax.microedition.lcdui` (and `lcdui.game`), `media` (and `media.control` in Confidential Report), `midlet` and `rms`. They don't use M3G, Mascot Capsule, Nokia or Sony Ericsson APIs, or `io`. Genesis carries five `.mid` files, and each Confidential Report file carries 3 to 9 MIDI tracks. Any working MIDP 2.0 implementation with MIDI should run them. That they do is **unverified**.
- **No screen size is declared.** None of the jars has a `Nokia-MIDlet-Original-Display-Size`-style key, and the file names carry none, so KEmulator falls back to its phone preset's size. Genesis's widest picture (`images/jill.png`) is 254 px, which suggests a screen wider than 240. Its build size needs a run to find.
- **The vendors are odd.** "BiNPDA" and "mob.ua" in Files 2–4 suggest those jars passed through download sites that repackaged them.
- **Confidential Report is four separate MIDlets with four different names**, so each File keeps its own saves in either emulator. Its own text offers "Save to FILE" at typewriters and "Unable to connect to network", but it has no `io` classes.
- The original jar names (`residentev_asvd7ay4.jar`) are opaque, so **a jar is identified by its manifest and hash**, not its name.

## ROMs: what a J2ME game is, and who catalogues it

- **A J2ME game is a MIDlet suite.** That's a `.jar` (classes, resources, `META-INF/MANIFEST.MF` with `MIDlet-1`, `MIDlet-Name`, `MIDlet-Vendor` and `MIDlet-Version`), sometimes with a `.jad` descriptor beside it. The `.jad` repeats the manifest keys and adds `MIDlet-Jar-URL` and `MIDlet-Jar-Size`. A jar alone is enough for both recommended emulators. KEmulator also takes a `.jad` (`-jad`) and reads the jar from its URL. There are also DoJa (`.jam` + `.jar`) and KDDI (`.kjx`) Japanese formats, which nnmod and FreeJ2ME-Plus take in part.
- **No-Intro.** libretro-database carries `metadat/no-intro/Mobile - J2ME.dat`: version 2026.10.07, 207 games, named like `007 - Quantum of Solace (Unknown) (En,Fr,…) (LG KE970, 240x304) (v1.0.3).jar` ([libretro-database](https://github.com/libretro/libretro-database/blob/master/metadat/no-intro/Mobile%20-%20J2ME.dat)). That points to a No-Intro J2ME set, but DAT-o-MATIC itself sits behind a terms-acceptance gate, so it wasn't confirmed there. No Resident Evil is in it.
- **The "New J2ME Software Archive".** libretro-database's `dat/Mobile - J2ME.dat` is "The New J2ME Software Archive Lite", by "2s", 2026.02, 198,184 entries. It names each jar `<MIDlet-Name> (<Vendor>) (<Version>) (<Configuration>, <Profile>) (<CRC32>).jar` ([libretro-database](https://github.com/libretro/libretro-database/blob/master/dat/Mobile%20-%20J2ME.dat)).
  - It has Confidential Report Files 1 and 3 by MD5.
  - It has several "Resident Evil (Capcom Interactive, Inc.) (1.0.4)" builds, but not this Genesis jar's MD5.
  - Its naming is exactly what a Standard name for a jar could be built from.
- **Archives** (named only):
  - The [J2ME Preservation](https://github.com/j2me-preservation/j2me-preservation) project: a list of emulators and docs, last pushed 2021.
  - Internet Archive collections, largest first ([advanced search](https://archive.org/advancedsearch.php?q=title%3A%28J2ME%29+AND+mediatype%3Asoftware&fl%5B%5D=identifier&fl%5B%5D=title&fl%5B%5D=item_size&sort%5B%5D=item_size+desc&rows=8&output=json)):
    - "J2ME Software archives - May 2020" (`J2MEarchivesMay2020`, ~517 GB)
    - "Largest J2ME and Symbian Software Collection" (2024)
    - "Phoneky/DownloadWAP … scrape"
    - "The 'New' J2ME software archive" (`96x65pixels_j2me`, ~108 GB, 2023)
    - "Unified archive of J2ME software (2019-09)"

## How Ludeum would launch it

**What the Emulator is.** Two pinned downloads, checked by SHA-256 and kept in the Ludeum folder's `Emulators/`:

1. `kemnnx64.v2.22.zip` from the [v2.22 release](https://github.com/shinovon/KEmulator/releases/tag/v2.22) (`sha256:f9a5a442014d43f1d9d2c51243795680d99fd91e49c300712ac6bd0823ed8e5e`), unpacked to e.g. `Emulators/KEmulator/`.
2. A Java 21 runtime, e.g. Temurin `OpenJDK21U-jre_aarch64_mac_hotspot_21.0.13_9.tar.gz` (`sha256:225bab0a…ec09a`, [jdk-21.0.13+9](https://github.com/adoptium/temurin21-binaries/releases/tag/jdk-21.0.13%2B9), 2026-10-22). Either beside the zip, or as `Emulators/KEmulator/jre/`, where `kemulator.sh` would also look.

Neither is a `.app`. KEmulator is "the Emulator", and the JRE is something Ludeum installs for it, as it installs DOSBox Staging's SoundFont.

**What the ROM is.** A `.jar` (with its `.jad` if there is one) in a Legacy Mobile Device ROM folder, not an Attachment. A Game of several MIDlets, like Confidential Report's four Files, is one ROM folder of jars, and Play's menu offers each one the way it offers a Disc. That's a design choice for the ADR, not something this research settles.

**Standing settings.** Before each Play, Ludeum writes only its own keys into `Emulators/KEmulator/property.txt`, keeping the rest. KEmulator rewrites the whole file when it closes.

```properties
# Game saves into the Data folder; file:// is what makes the path absolute (see above)
RMSFolder=file\:///Users/daniel/Library/Application Support/Ludeum/Data/Emulators/KEmulator/Game Saves
# Manual updates: no first-run dialog, and it never swaps its own jar
AutoUpdate=1
# No per-game settings dialog on a new jar's first Play
ShowAppSettingsOnStart=false
```

(`java.util.Properties` has no comments at the end of a line, so each comment needs its own line.)

Possibly also `SecurityEnabled=false` and `NetworkNotAvailable=true`, so a game's network or file access doesn't stop on a permission prompt. Whether the two Resident Evil games ask needs a run.

**Play.** Run `java` directly, with the flags `kemulator.sh` adds on macOS for Java 9+, the working directory set to the KEmulator folder, and `-s`:

```
cd "<Ludeum folder>/Emulators/KEmulator"
"<…>/jre/Contents/Home/bin/java" \
  -Xmx512M -Djna.nosys=true -Djava.library.path="$PWD" -Dfile.encoding=UTF-8 \
  -Dswt.autoScale=false -javaagent:"$PWD/KEmulator.jar" -XX:+IgnoreUnrecognizedVMOptions \
  -XstartOnFirstThread \
  --add-opens java.base/java.lang=ALL-UNNAMED --add-opens java.base/java.lang.reflect=ALL-UNNAMED \
  --add-opens java.base/java.lang.ref=ALL-UNNAMED --add-opens java.base/java.io=ALL-UNNAMED \
  --add-opens java.base/java.nio=ALL-UNNAMED --add-opens java.base/java.util=ALL-UNNAMED \
  --add-opens jdk.unsupported/sun.misc=ALL-UNNAMED \
  --add-opens java.desktop/com.sun.media.sound=ALL-UNNAMED \
  --add-opens java.desktop/javax.sound.midi=ALL-UNNAMED \
  --enable-native-access=ALL-UNNAMED -XX:+UseZGC \
  -jar "$PWD/KEmulator.jar" -jar "<ROM folder>/Legacy Mobile Device/<ROM>.jar" -s [-screen 240x320]
```

`-Xdock:name=KEmulator` would stop the Dock calling it "java". With `-s` the process Ludeum starts is the one that runs the game, and the Play ends when it exits: closing the window disposes the shell and the process exits.

**Emulator settings.** The only per-launch one is `-screen WxH`, for a game whose jar doesn't declare its size. The phone model, keys and the rest are KEmulator's own, set in its per-game settings during a Play and kept in `midlets.ini` by the jar's hash. That's the DuckStation shape, except that `midlets.ini` sits in the Emulators folder, not the Data folder, and can't be symlinked there.

**Game saves.** A Game's are `<RMSFolder>/<base64(Vendor + "_" + Name)>/`, one subfolder per record store. Ludeum can list them by computing that name from the jar's manifest. Deleting the folder deletes them. There are no Save states, so no Resume.

**For FreeJ2ME-Plus instead.** Set the working directory to `Data/Emulators/FreeJ2ME-Plus/`, so `rms/`, `config/` and `freej2me_system/` all land in the Data folder, then run `java -jar freej2me.jar 'file:///…/<ROM>.jar' 1 240 320 1`, which starts fullscreen at 240x320.

## Open questions (only a hand test settles these)

- **Does KEmulator nnmod v2.22 run on this Mac** (macOS 26, arm64) on Temurin 21? Is its window usable, is the settings UI readable (#236), and does Gatekeeper or library validation object to the SWT and LWJGL `.dylib`s it unpacks from jars that Ludeum downloaded?
- **Do both Resident Evil games run**, with MIDI, and at what screen size? What's Genesis's native size, and which phone preset suits it? Does Confidential Report try the network?
- **Does `RMSFolder=file:///…` work as read**, including a path with spaces (`Application Support`) and the Data folder being a symlink into Dropbox?
- **Does a save survive** quitting and relaunching? Does closing the window always flush the record stores, and is the process gone afterwards?
- **Do a game controller and a laptop keyboard** cover the keypad well enough? What do the two games use beyond the arrows, 5 and the soft keys?
- **Does FreeJ2ME-Plus 1.52 or a current nightly** do better or worse on this Mac (#256, #257)? It's the fallback.
- **Licence.** Is fetching nnmod's GitHub release at a pinned version acceptable, given no licence file? Should its `midlets.ini` (per-game settings) count as Data-folder material that Ludeum can't move?
- **Platform.** Should Ludeum offer Play only for Legacy Mobile Device ROMs that are jars, since IGDB's platform 55 also holds BREW, i-mode and other games?

## Sources

- KEmulator nnmod:
  - [README](https://github.com/shinovon/KEmulator/blob/main/README.md)
  - [releases](https://github.com/shinovon/KEmulator/releases), [v2.22](https://github.com/shinovon/KEmulator/releases/tag/v2.22)
  - [Emulator.java](https://github.com/shinovon/KEmulator/blob/main/src/main/emulator/Emulator.java)
  - [AppSettings.java](https://github.com/shinovon/KEmulator/blob/main/src/main/emulator/AppSettings.java)
  - [Settings.java](https://github.com/shinovon/KEmulator/blob/main/src/main/emulator/Settings.java)
  - [KeyMapping.java](https://github.com/shinovon/KEmulator/blob/main/src/main/emulator/KeyMapping.java)
  - [Updater.java](https://github.com/shinovon/KEmulator/blob/main/src/main/emulator/Updater.java)
  - [Property.java](https://github.com/shinovon/KEmulator/blob/main/src/main/emulator/ui/swt/Property.java)
  - [EmulatorScreen.java](https://github.com/shinovon/KEmulator/blob/main/src/main/emulator/ui/swt/EmulatorScreen.java)
  - [RecordStore.java](https://github.com/shinovon/KEmulator/blob/main/src/midp/javax/microedition/rms/RecordStore.java)
  - [x64 EmulatorPlatform.java](https://github.com/shinovon/KEmulator/blob/main/x64/src/main/emulator/EmulatorPlatform.java)
  - [home/kemulator.sh](https://github.com/shinovon/KEmulator/blob/main/home/kemulator.sh), [home/](https://github.com/shinovon/KEmulator/tree/main/home)
  - issues [#236](https://github.com/shinovon/KEmulator/issues/236), [#230](https://github.com/shinovon/KEmulator/issues/230), [#31](https://github.com/shinovon/KEmulator/issues/31)
  - [nnproject.cc/kem](https://nnproject.cc/kem)
  - [rwv/KEmulator-nnmod-macos](https://github.com/rwv/KEmulator-nnmod-macos)
- FreeJ2ME-Plus:
  - [README](https://github.com/TASEmulators/freej2me-plus/blob/devel/README.md)
  - [releases](https://github.com/TASEmulators/freej2me-plus/releases), [nightlies](https://github.com/TASEmulators/freej2me-plus/releases/tag/nightlies)
  - [libretro.yml](https://github.com/TASEmulators/freej2me-plus/blob/devel/.github/workflows/libretro.yml)
  - [FreeJ2ME.java](https://github.com/TASEmulators/freej2me-plus/blob/devel/src/org/recompile/freej2me/FreeJ2ME.java)
  - [Config.java](https://github.com/TASEmulators/freej2me-plus/blob/devel/src/org/recompile/freej2me/Config.java)
  - [RecordStore.java](https://github.com/TASEmulators/freej2me-plus/blob/devel/src/javax/microedition/rms/RecordStore.java)
  - [MIDletLoader.java](https://github.com/TASEmulators/freej2me-plus/blob/devel/src/org/recompile/mobile/MIDletLoader.java)
  - [MacGamepadReader.java](https://github.com/TASEmulators/freej2me-plus/blob/devel/src/org/recompile/freej2me/gamepad/MacGamepadReader.java)
  - [compatibility list](https://github.com/TASEmulators/freej2me-plus/blob/webpage/docs/compat_data/FreeJ2ME%20Compatibility.md)
  - issues [#256](https://github.com/TASEmulators/freej2me-plus/issues/256), [#257](https://github.com/TASEmulators/freej2me-plus/issues/257)
- [hex007/freej2me](https://github.com/hex007/freej2me)
- [nikita36078/J2ME-Loader](https://github.com/nikita36078/J2ME-Loader) (issues [#108](https://github.com/nikita36078/J2ME-Loader/issues/108), [#509](https://github.com/nikita36078/J2ME-Loader/issues/509)); [woesss/JL-Mod](https://github.com/woesss/JL-Mod) (issues [#68](https://github.com/woesss/JL-Mod/issues/68), [#32](https://github.com/woesss/JL-Mod/issues/32))
- [barteo/microemu](https://github.com/barteo/microemu); [Maven Central metadata](https://repo1.maven.org/maven2/org/microemu/microemulator/maven-metadata.xml)
- [Oracle Java ME SDK 8.3 release notes](https://docs.oracle.com/javame/8.3/release-notes-sdk/toc.htm)
- [SquirrelJME](https://github.com/SquirrelJME/SquirrelJME), [route.mkd](https://github.com/SquirrelJME/SquirrelJME/blob/trunk/route.mkd)
- [Adoptium temurin21-binaries](https://github.com/adoptium/temurin21-binaries/releases)
- IGDB: [Resident Evil: Genesis](https://www.igdb.com/games/resident-evil-genesis), [Resident Evil: Confidential Report](https://www.igdb.com/games/resident-evil-confidential-report); platform data from Ludeum's IGDB cache (igdb.com's pages refused automated fetches)
- [libretro-database](https://github.com/libretro/libretro-database): `metadat/no-intro/Mobile - J2ME.dat`, `dat/Mobile - J2ME.dat`
- [J2ME Preservation](https://github.com/j2me-preservation/j2me-preservation); [Internet Archive search](https://archive.org/advancedsearch.php?q=title%3A%28J2ME%29+AND+mediatype%3Asoftware&fl%5B%5D=identifier&fl%5B%5D=title&fl%5B%5D=item_size&sort%5B%5D=item_size+desc&rows=8&output=json)
