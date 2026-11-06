# Wine as Ludeum's Windows Emulator

Wine was dropped later the same day; see [ADR 0040](../adr/0040-windows-games-are-played-in-wine-from-a-clone-of-the-roms-prepared-game.md) and [ADR 0041](../adr/0041-windows-games-are-played-in-86box-from-a-game-disk-over-one-windows-base.md). This is kept for what it found.

Researched 2026-11-05. The question: Windows Games are to be Played through Wine as a managed Emulator in [ADR 0038](../adr/0038-emulators-are-whole-apps-ludeum-installs-not-cores.md)'s sense, a pinned release Ludeum fetches, checks and keeps in the Ludeum folder and starts with settings it writes, with a Windows ROM a subfolder holding a prepared game folder and a small launch file (which exe, DLL overrides, locale, registry values). Which Wine build can be managed that way on an Apple Silicon Mac, how long will it last, what does a Wine prefix need, and how does the ROM stay untouched when the game writes into its own folder? This note gives the facts; the decision is an ADR still to be written. DOS Games in DOSBox ([#53](https://github.com/danielholmes/ludeum/issues/53)) ask the same "a folder plus a file saying what to run" question and are out of scope here.

Sources:

- **The two worked examples** on this Mac, `~/Applications/Z95.app` and `~/Applications/Age of Empires.app`, built by hand on 2026-11-05: their launchers, `recipe/` folders, prefixes and `ddraw.ini` files, read without changing or launching anything.
- **Wine's source** at tag `wine-10.0`, read from the GitHub mirror of `gitlab.winehq.org/wine/wine`. `W/dlls/mcicda/mcicda.c` means `https://github.com/wine-mirror/wine/blob/wine-10.0/dlls/mcicda/mcicda.c`. Its release notes are `ANNOUNCE.md` at `wine-9.0`, `wine-10.0` and `wine-11.0` on the same mirror.
- **WineHQ's wiki**, fetched through GitLab's API. `Wiki/FAQ` means `https://gitlab.winehq.org/wine/wine/-/wikis/FAQ`.
- **The GitHub REST API** for releases, assets, digests and repository metadata, and **Homebrew's cask API** (`https://formulae.brew.sh/api/cask/wine-stable.json` and its two siblings).
- **Two release assets**, `WS12WineSikarugir10.0_6.tar.xz` and `wine-stable-11.0_1-osx64.tar.xz`, downloaded into the session scratchpad, checked against the API's digests, unpacked and inspected with `file`, `otool`, `codesign` and `spctl`. **Neither was run**, not even for `--version`, which this session's permissions refused for a downloaded binary.
- **Apple's documentation**: the Rosetta page, support article 102527, About Apple File System, the `clonefile(2)`, `copyfile(3)` and `cp(1)` man pages on this Mac (macOS 26.5.2, M3 Max), `LSFileQuarantineEnabled`, the Platform Security guide's Gatekeeper page and the Game Porting Toolkit page. The toolkit's licence and read-me were read from the copies in Sikarugir's repository, as Apple's download is behind a sign-in.
- **cnc-ddraw's** README, LICENSE, release list and source at `v7.1.0.0`, and the `ddraw.ini` it ships.
- **Lutris's** `docs/installers.rst`, **Bottles'** docs, **Heroic's** wiki and **CrossOver's** Mac user guide (CrossOver 26).
- **Ludeum's code** on `main` at `1e1c227`.

URLs are at the end. Anything not checked against one of these is marked **unverified**. What was run: `stat`, `df`, `ls -lO` and `xattr` on the Ludeum folder and Data folder; `cp -c`, `cp -R` and `clonefile(2)` into the scratchpad; `sysctl` natively and under `arch -x86_64`. No game and no Wine was started.

## Answer

**Wine fits the managed model, and nothing found here blocks it. It has one known horizon, Rosetta 2, and one thing only a Play can settle: which of two builds to pin.** That was settled the same day, for Sikarugir's: see [Tried afterwards](#tried-afterwards).

1. **Two builds can be pinned, both made by the same maintainer, both x86_64 under Rosetta 2 with 32-bit programs in Wine's new wow64 mode, both published as GitHub release assets whose SHA-256 the API gives** (§1). Sikarugir's engine is the one both games Played on, but it is two artefacts (the engine has no libraries of its own) and no source for its patches was found. Gcenx's `wine-stable`, the package WineHQ's download page names, is one artefact holding the same 94 libraries by name; it hasn't Played either game, and its old releases don't stay listed.
2. **Neither is notarised, and their binaries are signed ad hoc at most, which doesn't matter here**: a file Ludeum fetches gets no quarantine attribute, as its six installed Emulators show (§1).
3. **Rosetta 2 is available through macOS 27.** From macOS 28 Apple keeps it "only for certain older, unmaintained games that rely on Intel-based frameworks", and hasn't said whether Wine counts. Wine itself has no arm64 build for macOS (§2).
4. **A prefix is cheap to make again**: Wine builds one in about 20 seconds, updates it by itself when the Wine build changes, and documents that one can be copied, moved and deleted like any folder. Its registry is three text files, and both games keep their options there (§3).
5. **An APFS clone gives a working copy for nearly nothing**: Z95's 361 MB game folder cloned in 0.13 seconds for under 1 MB, and the Ludeum folder and Data folder are on the same volume on this Mac, where `clonefile(2)` from the Data folder succeeds. `FileManager.copyItem` clones by itself. But most ROMs here are kept online-only by Dropbox, and cloning one of those was not tried (§5).
6. **cnc-ddraw is MIT-licensed, says it supports Wine on macOS, and lists Command & Conquer, Red Alert, Tiberian Sun, Warcraft II, Z and Age of Empires** (§4).
7. **CD audio doesn't work in Wine on macOS**, by WineHQ's own FAQ and by its source. The usual wrapper, ogg-winmm, has a README and no word on Wine (§6).

## The two worked examples

Both Play from a hand-built `.app` whose launcher is a short shell script. Gameplay, mouse and full screen were confirmed by hand in both, and sound and MIDI music in Age of Empires. **Saving and loading a game was tested in neither.**

**Shared between them:**

- **One engine.** Sikarugir's `WS12WineSikarugir10.0_6` (its `version` file reads `wine sikarugir 10.0 (revision 6)`), in `Z95.app/Contents/Resources/wine`. Age of Empires' launcher runs the engine inside `Z95.app`. `bin/wine` and `bin/wineserver` are x86_64 Mach-O, ad-hoc signed, and `lib/wine` holds `i386-windows`, `x86_64-windows` and `x86_64-unix` with no `i386-unix`: the new wow64 mode. It only started once 94 dylibs from Sikarugir's `Template-1.0.11.app/Contents/Frameworks` were copied into its `lib/`. As assembled it is 891 MB.
- **The same five lines of launch.** `WINEPREFIX` set to the app's prefix, `WINEDLLOVERRIDES="ddraw=n,b;mscoree,mshtml="`, `WINEDEBUG=-all`, a locale in `LC_ALL`, then `wine <exe>` with the game's folder as the working directory.
- **cnc-ddraw 7.1.0.0** beside the exe (`ddraw.dll`, `ddraw.ini`, its `Shaders` folder), with `renderer=gdi`, `fullscreen=true`, `windowed=true` and `maintas=true`. macOS offers Wine no 640x480 256-colour mode to switch to, so Wine's own DirectDraw shows black or crashes.
- **A fresh 64-bit prefix** (`#arch=win64` at the top of `system.reg`), whose `drive_c/windows` is about 317 MB and which `wineboot -i` built in about 20 seconds, with the game under `drive_c/Games/`.

**Per game:**

| | Z95 | Age of Empires |
|---|---|---|
| Exe | `z95.exe`: the Z Expansion disc's v1.5 `z9x.exe` with its UPX packing removed and an import of `ddraw.dll` added (`recipe/unscrub.py`, `addimport.py`) | `EMPIRES.EXE`, unpatched |
| Game folder | 361 MB, 804 files | 175 MB, rebuilt from the disc with long file names (`recipe/longnames.py`, `names.tsv`) |
| Locale | `en_GB.UTF-8`, as its English resources are tagged en-GB | `en_US.UTF-8` |
| `ddraw.ini` beyond the shared four | `hook=3` | `fixchilds=3` (`hook` left at its default, 4) |
| Registry it needs before it starts | No registry file in its recipe. Its key holds two paths to the game folder (`Cuts`, `War`) beside its options; who wrote them isn't recorded | `recipe/aoe.reg`: install keys under `HKLM\Software\Wow6432Node\Microsoft\Games\Age of Empires\1.00`, the codec under `Drivers32`, and `d:` as `cdrom` under `HKLM\Software\Wine\Drives` |
| Added to the prefix | nothing | the disc's Indeo 4.1 codec in `windows/syswow64`, its fonts in `windows/Fonts`, and `d:` linked to an empty `cd/` folder holding `.windows-label` (`AOE`) |
| What the game writes beside its exe | `save0.z95` to `save9.z95`, `hiscore/` | `SAVEGAME/`, and `game0.nfo` and `SCENARIO/scenario.inf` on a normal run |
| Where its options go | `HKLM\Software\Wow6432Node\Bitmap Brothers\Z\v1.0`, in `system.reg` | `HKCU\Software\Microsoft\Games\Age of Empires\1.00`, in `user.reg` |

So what a Windows ROM carries is more than a game folder and an exe's name. Age of Empires' also carries a registry file, a drive to fake, and files that go into the prefix's `windows` folder. And the two games keep their options in different registry files.

**Sizes.** Engine 891 MB, shared. Each prefix 317 MB before the game. Game folders 361 MB and 175 MB. As whole apps they are 1.5 GB and 500 MB, of which only the game folders and a few kilobytes of recipe are the game.

## 1. Which Wine build Ludeum could manage

Five were compared. Only the first two are builds Ludeum could fetch and pin.

| | Sikarugir engine | Gcenx `macOS_Wine_builds` | CrossOver source | Game Porting Toolkit | Whisky |
|---|---|---|---|---|---|
| Published | Assets of the one release `v1.0` of `Sikarugir-App/Engines`, added to since 2024-10 | A release per Wine version of `Gcenx/macOS_Wine_builds` | `crossover-sources-26.3.0.tar.gz` on CodeWeavers' media server | Apple's developer downloads; a Homebrew formula in `apple/homebrew-apple` | `Whisky.zip`, last `v2.3.5` on 2025-04-05 |
| Artefact | `WS12WineSikarugir10.0_6.tar.xz`, 166 MB, unpacking to `wswine.bundle/` (750 MB) | `wine-stable-11.0_1-osx64.tar.xz`, 185 MB, unpacking to `Wine Stable.app` (682 MB); also `wine-devel-` and `wine-staging-` | Source only, 149 MB | Source patch plus Apple's D3DMetal libraries | A 5 MB app with no Wine in it |
| Checksum | SHA-256 from GitHub's API; matched | SHA-256 from GitHub's API; matched | None on the page | Formula pins the source tarball's | Not checked |
| Self-contained | **No**: `lib/` holds only `wine/` | **Yes for these games**: 94 dylibs in `lib/`; only GStreamer and FFmpeg are absent | Needs building | Needs building | Not checked |
| Architecture | x86_64, new wow64 | x86_64, new wow64 | Not checked | x86_64 only | CrossOver 22.1.1 and the toolkit |
| Signing | Ad hoc, not notarised | Bundle unsigned, binaries ad hoc, not notarised | | | Not checked |
| Cadence | `10.0` and eight revisions of it, 2025-08 to 2026-10; `11.0` since 2026-09 | A development release every two to six weeks through 2026, the latest `11.21` on 2026-10-31; one stable, `11.0_1` | Not checked | Formula last pushed 2024-06 | **Archived** |

**Sikarugir's engines.** The [Engines repository](https://github.com/Sikarugir-App/Engines) has one release, tagged `v1.0`, with 46 assets added over time; its `EngineList.txt` names the current ones (`WS12WineSikarugir11.0_1`, `WS12WineSikarugir10.0_8` and eight CrossOver builds), and `10.0_6` is no longer among them, though its asset is still there. The API gives `sha256:9da7ee0c…6091b2` for it, which the download matched. As shipped, the engine's Unix libraries ask for `libinotify`, `libintl`, GStreamer and FFmpeg through `@rpath`, which resolves to `lib/`, holding only `wine/`, and to a `lib/external` that isn't there. The libraries come from the wrapper, a second artefact (`Template-1.0.11.tar.xz`, 85 MB, in `Sikarugir-App/Template`, also with a digest). Neither repository has a licence file. `Sikarugir-App/wine` has no commits of its own over upstream Wine, so **the source of the engine's own changes was not found**, nor what `WS12` means.

**Gcenx's builds.** The repository calls itself "The Official Winehq macOS Packages", and [Wiki/Download](https://gitlab.winehq.org/wine/wine/-/wikis/Download) lists "WineHQ binary packages for macOS 10.15.4 and later" with its author as maintainer. Its README gives the configure options: `--enable-archs=i386,x86_64`, the new wow64 mode. Unpacked, `Contents/Resources/wine/lib` has 94 dylibs with exactly the names of those copied into `Z95.app`. Of every `@rpath` dependency of its Unix libraries, only `winegstreamer.so`'s (GStreamer, GLib) and `winedmo.so`'s (FFmpeg) are not in the bundle, and the engine in `Z95.app` lacks those too. The four it opens by name (FreeType, GnuTLS, SDL2, MoltenVK) are there. Three things count against it:

- **It hasn't Played either game.** It is Wine 11.0, where the proven engine is Wine 10.0 with Sikarugir's changes.
- **Old releases go.** The repository lists 14 releases, the oldest `11.0_1` of 2026-04-16; no 10.x is there. A pinned release can disappear, as DuckStation's rolling tags do (ADR 0024).
- **`Wine Stable.app` claims `.exe` files** in its `Info.plist`, so the OS would offer it for them. Ludeum would start `Contents/Resources/wine/bin/wine` directly.

Homebrew's three wine casks pointed at these assets and **were disabled on 2026-09-01 for `fails_gatekeeper_check`**; they also depend on a `gstreamer-runtime` cask. [Wiki/MacOS](https://gitlab.winehq.org/wine/wine/-/wikis/MacOS) still tells users to `brew install --cask --no-quarantine`. `spctl` here agrees: `rejected, source=no usable signature`.

**16-bit code.** Wine 9.0's notes list "Lack of support for 16-bit code" among the new wow64 mode's limits, and 11.0's say "16-bit applications are supported in the new WoW64 mode". So a Wine 10 engine can't run a 16-bit installer or game and a Wine 11 one may. Whether that holds on macOS is **unverified**, and why Age of Empires' `AOESETUP.EXE` failed was not established.

**CrossOver.** CodeWeavers publishes [its open-source code](https://www.codeweavers.com/crossover/source) as one tarball, under the GPL, LGPL and other licences, with no binaries and no build instructions; CrossOver itself is a paid product. Building it would be Ludeum's job. Sikarugir already does (`WS12WineCX24.0.7_7`).

**Game Porting Toolkit.** Its read-me (4.0 beta 2): "The evaluation environment for Windows games … helps game developers try out their existing Windows games right on Apple Silicon Macs running macOS 15 Sequoia or higher." The licence grants use "for the sole purpose of developing, testing, or evaluating video games for use on Apple-branded products" and distribution "solely for non-commercial purposes". Apple's formula builds CrossOver 22.1.1's source with `depends_on arch: :x86_64`. What it adds is D3DMetal, which Sikarugir's README describes as "64Bit Direct3D 11 & 12 via Metal": nothing a DirectDraw game uses.

**Whisky.** Archived on GitHub, last pushed 2025-05-11. Its README: "Whisky is no longer actively maintained. Apps and games may break at any time."

**Licence and fetching.** Wine is LGPL 2.1 or later ([`W/LICENSE`](https://github.com/wine-mirror/wine/blob/wine-10.0/LICENSE)). Nothing in either README restricts downloading a release asset, and Homebrew's casks fetched the same URLs. Ludeum would fetch the maintainer's own asset to this Mac and redistribute nothing, as with every Emulator since ADR 0024. The licences of the 94 bundled libraries were not read.

**Quarantine and Gatekeeper.** Apple documents `LSFileQuarantineEnabled` as "whether the files this app creates are quarantined by default". Ludeum doesn't set it and isn't sandboxed (`ENABLE_APP_SANDBOX: NO` in `project.yml`), and its downloads are bytes from `URLSession` written to a file it creates (`URLSessionTransport.download` in `HTTPTransport.swift`). On this Mac all six Emulators in the Ludeum folder carry `com.apple.provenance` and no `com.apple.quarantine`. `EmulatorInstall` in `DuckStationInstall.swift` removes the attribute anyway, and `PCSX2Install.swift` already unpacks a `.tar.xz`. The engine in `Z95.app` is ad-hoc signed, unquarantined, and Played both games. Apple's Platform Security guide says Gatekeeper checks software a user "downloads and opens"; that the quarantine attribute is the trigger is not spelled out on the pages read.

**Half of either engine is not needed.** `share/wine/gecko` and `share/wine/mono` are 437 MB of Sikarugir's 750 MB and 311 MB of Gcenx's 682 MB. Both launchers disable the DLLs that load them (`mscoree,mshtml=`).

## 2. Rosetta 2's future

**Apple's developer documentation:** "Rosetta was designed to make the transition to Apple silicon easier, and will be available through macOS 27 — as a general-purpose tool for Intel apps to help developers complete the migration of their apps. Beyond this timeframe, we will keep a subset of Rosetta functionality aimed at supporting older unmaintained gaming titles, that rely on Intel-based frameworks."

**Apple's support article 102527**, published 2026-09-21: "Rosetta is available for any Mac with Apple silicon using macOS 27 or earlier. Starting with macOS 28, the next major macOS release, Rosetta functionality will be available only for certain older, unmaintained games that rely on Intel-based frameworks." It adds that opening an Intel-based app may show a notice that it "will not work with a future release of macOS (macOS 28)".

**What that means for Wine.** Every build in §1 is x86_64 only, so each depends on Rosetta. This Mac runs macOS 26.5.2 with Rosetta installed; macOS 27 is the current release, and Wine keeps working there. Neither page says how a game qualifies for the subset kept from macOS 28, or whether a Windows game inside an x86_64 Wine does. That is the open risk, and it has no date beyond "the next major macOS release".

**No arm64 route in Wine itself.**

- [Wiki/MacOS-Building](https://gitlab.winehq.org/wine/wine/-/wikis/MacOS-Building): "Wine is not ready yet to be build for ARM. This means that this guide will guide you to make a build for x86 that you will run with Rosetta."
- Wine 10.0's notes: "ARM64 support requires the system page size to be 4K, since that is what the Windows ABI specifies. Running on kernels with 16K or 64K pages is not supported at this point." This Mac's page size is 16,384 bytes natively and 4,096 inside a Rosetta process.
- Wine 11.0's notes add "support for simulating a 4K page size on top of larger host pages", which "works for simple applications".
- Wine has had an interface for an x86 emulator inside an ARM64 Wine since 9.0, but "No emulation library is provided with Wine". FEX, which implements it, describes itself as for "ARM64 Linux devices", and Hangover's releases are Debian and Ubuntu arm64 packages. Neither offers a macOS build.

## 3. Wine prefix facts

- **`WINEPREFIX` is the whole Windows installation.** The `wine` man page: "the name of the directory where Wine stores its data (the default is `$HOME/.wine`)". Processes with the same prefix share one `wineserver`, registry included; different prefixes are "truly independent".
- **Wine creates it.** `setup_config_dir` in [`W/dlls/ntdll/unix/server.c`](https://github.com/wine-mirror/wine/blob/wine-10.0/dlls/ntdll/unix/server.c) makes the folder, `dosdevices/`, `drive_c/`, and the links `dosdevices/c:` to `../drive_c` and `dosdevices/z:` to `/`. It refuses a folder the user doesn't own. `wineboot --init` then fills it from `wine.inf`.
- **Wine updates it when the build changes.** `update_wineprefix` in [`W/programs/wineboot/wineboot.c`](https://github.com/wine-mirror/wine/blob/wine-10.0/programs/wineboot/wineboot.c) compares the number in the prefix's `.update-timestamp` with the modification time of the engine's `share/wine/wine.inf`, and reruns `wine.inf` when they differ. `disable` in that file turns it off. The User's Guide: "The registry is also updated automatically if `wine.inf` changes, for instance when upgrading to a newer Wine version." Both example prefixes hold `1793840362`, the time `wine.inf` was copied into `Z95.app`; in the tarball it is 2026-04-11. So an install that doesn't keep that file's time makes every prefix update at its next start, same version or not.
- **Any difference triggers it, older or newer.** Nothing in the source or docs speaks of going back to an older Wine. The FAQ: "It is also recommended that applications being run with different Wine versions be installed into separate wineprefixes."
- **Its architecture is fixed at creation.** `#arch=win64` in `system.reg`. Wine 11.0 deprecates 32-bit prefixes and doesn't support them in the new wow64 mode.
- **Drives are links in `dosdevices/`**, a letter and a colon each (User's Guide, Drive Settings). A drive's type comes from a value under `HKLM\Software\Wine\Drives` (`hd`, `floppy`, `cdrom`, `network`, `ramdisk`), and its label and serial from `.windows-label` and `.windows-serial` at the root of the folder it links to ([`W/dlls/mountmgr.sys/device.c`](https://github.com/wine-mirror/wine/blob/wine-10.0/dlls/mountmgr.sys/device.c)). That is all Age of Empires' disc check needed.
- **`WINEDLLOVERRIDES`** sets, per DLL, `n` (native), `b` (builtin), an order of the two, or nothing to disable it; entries are separated by `;`. So `ddraw=n,b` takes the `ddraw.dll` beside the game first.
- **The registry is three text files** in the prefix: `system.reg` (`HKEY_LOCAL_MACHINE`), `user.reg` (`HKEY_CURRENT_USER`) and `userdef.reg`. The User's Guide: "It is not advisable to edit these files"; use `regedit` or `reg`. `wineserver` loads them at start and saves the changed ones every 30 seconds and on exit, to a temporary file renamed into place, or straight into the file when it is a symbolic link or has more than one hard link (`save_branch` in [`W/server/registry.c`](https://github.com/wine-mirror/wine/blob/wine-10.0/server/registry.c)).
- **A 32-bit program's `HKLM\Software` is `HKLM\Software\Wow6432Node`** in a 64-bit prefix; the redirection is in `registry.c`. Both examples show it: `aoe.reg` writes there, and Z wrote its own options there. Age of Empires' `HKCU\Software` keys are not under a `Wow6432Node`. 32-bit system DLLs go in `windows/syswow64`.
- **`wineserver -k`** kills the server of the prefix `WINEPREFIX` names; **`-w`** waits until it ends. By default it stays 3 seconds after the last process (`-p`). Its socket is under `/tmp/.wine-<uid>/server-<device>-<inode>`, named from the prefix folder itself.
- **A prefix can be copied and moved.** The FAQ: "You can rename, move, copy and delete prefixes without affecting others, and each prefix has its own wineserver instance", and "To the host system, a wineprefix is just another directory". Two things inside one are absolute: `z:`, and the links Wine makes from `drive_c/users/<name>/Documents`, `Desktop`, `Downloads`, `Music`, `Pictures` and `Videos` to the real folders in `$HOME` (`create_link` in [`W/dlls/shell32/shellpath.c`](https://github.com/wine-mirror/wine/blob/wine-10.0/dlls/shell32/shellpath.c)). A game that saves in My Documents would write into `~/Documents`.

**Per game or shared.** Wine's User's Guide and FAQ give no rule in so many words. What they say leans to one each: different prefixes "simulate two Windows computers"; "If in doubt, start again installing the app in a fresh wineprefix"; and [Wiki/Winetricks](https://gitlab.winehq.org/wine/wine/-/wikis/Winetricks): "by default, winetricks installs each app into its own Wine prefix", since "the preferred way to uninstall anything in Wine is to simply install into a fresh Wine prefix".

## 4. cnc-ddraw

[`FunkyFr3sh/cnc-ddraw`](https://github.com/FunkyFr3sh/cnc-ddraw), MIT. Its description: a "GDI, OpenGL and Direct3D 9 re-implementation of the DirectDraw API for classic 2D games". The latest release is `v7.1.0.0` of 2024-12-28, the one both games use: `cnc-ddraw.zip` (2.7 MB), a Windows ME build, a `.pdb` and `proxy-dlls.zip`. **No checksums are published**, and GitHub's API has no digest for these assets, so a pin would be a digest Ludeum computes. The repository was last pushed 2026-08-30.

**On Wine and macOS**, the README says two things: it "Supports Windows ME, 2000, XP, Vista, 7, 8, 10, 11, Wine (Linux/macOS/Android) and Virtual Machines", and "Wine (Linux/macOS/Android) only: override `ddraw` in winecfg manually or run `cnc-ddraw config.exe` once." It also says "The game must be set to fullscreen" and "cnc-ddraw does not support Direct3D games".

**Supported games.** The README's list has Command & Conquer Gold, Command & Conquer: Red Alert, Command & Conquer: Tiberian Sun, Warcraft 2, Z & Z Expansion Kit, Age of Empires and Age of Empires: The Rise of Rome, and ends "There are a lot more games supported but I don't usually update the list".

**The settings the two games use**, from the comments in the shipped `ddraw.ini` and, where it has none, the source:

- **`renderer`**: "possible values: auto, opengl, openglcore, gdi, direct3d9, direct3d9on12 (auto = try direct3d9/opengl, fallback = gdi)". Default `auto`; both games set `gdi`.
- **`fullscreen`**: "Override the width/height settings shown above and always stretch to fullscreen. Note: Can be combined with 'windowed=true' to get windowed-fullscreen aka borderless mode". Default `false`.
- **`windowed`**: "Run in windowed mode rather than going fullscreen". Default `false`. With `fullscreen=true` it is the borderless mode.
- **`maintas`**: "Maintain aspect ratio". Default `false`.
- **`fixchilds`**: "Child window handling, possible values: 0 = Disabled, 1 = Display top left, 2 = Display top left + repaint, 3 = Hide, 4 = Display top left + hide. Note: Disables upscaling if a child window was detected". Default 2; Age of Empires sets 3.
- **`hook`**: no comment in the file. In `src/hook.c`, 1 patches the import table of the game's exe alone, 2 uses Microsoft Detours, and 3 and 4 patch the import tables of every loaded module in the game's folder and of a few system ones (`winmm`, `msvfw32`, `quartz`, and `mciavi32` under Wine). 4 is the default and becomes 3 by itself when the exe, or a DLL it imports, imports `ddraw.dll`; what else separates the two was not traced. Z95 sets 3 outright.

**Per-game sections.** A section named for the exe overrides `[ddraw]`, and under Wine a section `<exe>/wine` is taken first if there is one (`cfg_get_game_section` in `src/config.c`). The file ships with sections for `[empires]`, `[C&C95]`, `[ra95]`, `[game]` (Tiberian Sun) and others; none for Z. And `savesettings=1`, the default, is by its comment "Save window position/size/state on game exit", into `ddraw.ini`: one more file written beside the exe. Whether it writes in borderless full screen was not checked.

## 5. Keeping the ROM untouched while the game writes into its own folder

Both games write beside their exe and into the registry (see the table above). This is ADR 0035's problem, where Amiberry's save images kept the Amiga ROM untouched. Wine has no equivalent: no overlay or redirect for a game's folder was found in its documentation.

**What macOS offers: APFS clones.**

- Apple, About Apple File System: "A clone is a copy of a file or directory that occupies no additional space on disk. Clones let you make fast, power-efficient file copies on the same volume. The `copyItem(at:to:)` and `copyItem(atPath:toPath:)` methods of `FileManager` automatically create a clone for Apple File System volumes". And: "Modifications to the data are written elsewhere, and both files continue to share the unmodified blocks."
- `clonefile(2)`: the clone "shares its data blocks with the src file" and writes to either are "private to the file being modified (copy-on-write)". It fails with `EXDEV` when "src and dst are not on the same filesystem", and with `ENOTSUP` on a file system without it. On directories: "the use of clonefile(2) to clone directory hierarchies is strongly discouraged. Use copyfile(3) instead".
- `cp(1)`: `-c` copies "using clonefile(2)" and, across file systems or where cloning isn't supported, "will fallback to using copyfile(2)". So `cp -c` never fails for lack of cloning; it just copies.

**On this Mac.**

- **The Ludeum folder and the Data folder are on the same volume.** The Data folder is a link to `~/Dropbox/games/Ludeum` (ADR 0010), which resolves to `~/Library/CloudStorage/Dropbox/games/Ludeum`. `stat` gives the same device (`/dev/disk3s5`, `/System/Volumes/Data`, APFS) for the Ludeum folder, its `Emulators/`, the Data folder and its `ROMs/`. 122 GiB of 926 GiB is free.
- **`clonefile(2)` works out of the Data folder.** Called directly on a Backup that is on this Mac, into the scratchpad, it returned 0 in 0.2 ms and the clone was identical. The clone carried Dropbox's `com.dropbox.attrs` and `com.dropbox.internal` attributes.
- **A folder clones fast.** `cp -cR` of Z95's game folder (361 MB, 804 files) took 0.13 seconds and used 856 KB of free space; `cp -R` took 0.61 seconds and used all 361 MB. Appending to the clone's `z95.exe` and adding a file left the original's SHA-256 unchanged, and `diff -rq` showed only those two differences. A prefix's `windows` folder (317 MB, 1,731 files) cloned in 0.28 seconds for 1.4 MB.
- **Most ROMs aren't on this Mac.** 1,073 of the 1,269 entries in the top two levels of `ROMs/` have the `dataless` flag: Dropbox keeps them online only. Cloning one was **not tried**, as reading it downloads it.

**How the existing managers treat it**, from their own documentation. None of the pages read keeps an untouched original apart from the folder the game runs in: the installed game is the working copy, and saves are wherever the game puts them.

- **Lutris**: one prefix per game, with the game inside it. `docs/installers.rst`: "`prefix`: Path to the Wine prefix. For Wine games, it should be set to `$GAMEDIR`", and its example runs `$GAMEDIR/drive_c/game/bin/Game.exe`. A game's `exe`, `args`, `working_dir`, `arch` and `overrides` (`ddraw.dll: n`) are keys of its installer file, which is close to the launch file proposed here.
- **Bottles**: shared, and Linux only. Its author wanted "one or more wine prefixes as a 'container' for all my applications" and "environments that contain more applications and games and where the wine version can be updated". Its Versioning and Backups pages answered "Page Not Found" and weren't read.
- **Heroic**: a prefix chosen per game, apart from the game. "The game installation folder will contain the primary contents of the game. The prefix is equivalent to a 'virtual Windows C: Drive' and will contain any dependencies and game saves."
- **CrossOver**: a bottle holds a C: drive, a registry, settings, "One or more Windows applications" and "Saved user data". "Unless you specify otherwise, CrossOver installs each application into a new bottle", because "Keeping applications in separate bottles prevents them from interacting with or damaging one another." A bottle can be duplicated ("Creates an exact copy of the bottle") or archived.

## 6. CD audio and disc checks

**Disc checks.** A check on drive type and volume label passes on a folder, as Age of Empires' does (§3). The FAQ on anything stronger: "Copy protection uses several 'dirty' methods to detect if discs are 'real' or not. Some of these methods work in Wine but many do not". Nothing found in `mountmgr.sys` or `cdrom.c` mounts a disc image as a drive, so a `.bin` and `.cue` are of no use to Wine as they are.

**CD audio.** [Wiki/MacOS-FAQ](https://gitlab.winehq.org/wine/wine/-/wikis/MacOS-FAQ): "mcicda.dll does not work (bug #20323), so apps will not play music off CD tracks", and "CD-ROM support is incomplete". [Bug 20323](https://bugs.winehq.org/show_bug.cgi?id=20323), "MacOS mcicda does not play audio CD", was filed in 2009 and is still open and unconfirmed. The source agrees:

- [`W/dlls/mcicda/mcicda.c`](https://github.com/wine-mirror/wine/blob/wine-10.0/dlls/mcicda/mcicda.c) opens `\\.\X:` on a drive whose type is `DRIVE_CDROM` and asks it for the table of contents. It plays by reading raw audio sectors into DirectSound, or else by `IOCTL_CDROM_PLAY_AUDIO_MSF`.
- In [`W/dlls/ntdll/unix/cdrom.c`](https://github.com/wine-mirror/wine/blob/wine-10.0/dlls/ntdll/unix/cdrom.c), reading the table of contents and raw sectors is implemented under `__APPLE__` against a real disc device (`DKIOCCDREADTOC`, `DKIOCCDREAD`). Play, pause, resume and stop return `STATUS_NOT_SUPPORTED` on anything but Linux and the BSDs.

So a folder standing in for the disc has no tracks to read, and Age of Empires fell back to its MIDI files. Its disc's 13 audio tracks are not played.

**The wrapper.** ogg-winmm replaces `winmm.dll` beside the game and plays `Music/Track02.ogg` onwards in place of the disc's tracks. The original, [`hifi-unmaintained/ogg-winmm`](https://github.com/hifi-unmaintained/ogg-winmm), was last pushed in 2013 and has no README. The fork [`ayuanx/ogg-winmm`](https://github.com/ayuanx/ogg-winmm) (GPL-2.0, last release `v2025.01.16`) has one: rip the tracks to `Track02.ogg`, `Track03.ogg` and so on, put the DLL and `winmm.ini` beside the exe and the files in `Music/`. It names Windows XP or newer, and says nothing of Wine or macOS. Under Wine it would presumably need `winmm=n,b` among the overrides, as cnc-ddraw needs `ddraw`. **Not tried.**

## Recommendations

These follow from the findings; none is decided. The first was tried the same day: see [Tried afterwards](#tried-afterwards).

1. **Try Gcenx's `wine-stable-11.0_1` with both games, and pin it if they Play.** It is one artefact where Sikarugir's is two, it is the package WineHQ names, it carries the libraries that had to be borrowed for the engine in use, and Wine 11.0 is the first whose new wow64 mode takes 16-bit code. If either game doesn't Play on it, pin the Sikarugir engine with its Template, both by digest, and record that the source of the engine's changes wasn't found. Either way the ADR should say what happens when a pinned asset is gone, since Gcenx's releases don't stay.
2. **One prefix per ROM, in the Ludeum folder and outside the Data folder.** A prefix is 317 MB that the engine rebuilds, the two games keep options in it, and Age of Empires needs its own drive, codec and fonts in it. Wine's docs lean the same way. A new prefix could be a clone of one template (0.28 seconds) instead of a 20-second `wineboot`; a cloned prefix was not started here, though Wine documents copying one.
3. **Play a clone of the ROM's game folder, never the ROM.** `FileManager.copyItem` does it on this volume in a fraction of a second for almost no space. The ROM has to be on this Mac first; reading one Dropbox keeps online only downloads it.
4. **The launch file says what the two launchers and recipes say**: the exe and its working directory, the DLL overrides, the locale, a registry file to import, the drives to make (letter, type, label), and the files to put in the prefix's `windows` folder. Lutris's installer keys cover the same ground. Everything else Ludeum would fix is environment for the one start (`WINEPREFIX`, `WINEDEBUG`), so Wine has no settings file to keep in step, as with Amiberry (ADR 0035).
5. **After the game ends, wait for `wineserver -w` before reading the prefix or the working copy.** The server outlives the game by 3 seconds and writes the registry as it exits.
6. **Leave CD audio out to begin with.** Both games Play without it.
7. **Record Rosetta as the Windows Emulator's horizon**, with macOS 28 the point to look again.

## What this doesn't settle

- **Whether Wine 11.0 from Gcenx Plays the two games.** It was inspected, not run.
- **Whether saving and loading works in either game.** Neither was tested, so no Game save here is known to work.
- **Where a Windows Game's Game saves live.** What a Play changes is files in the working copy and keys in `system.reg` or `user.reg`, and none of it is in the Data folder unless something puts it there. The facts that bear on it: a clone makes the difference from the ROM cheap to find; the two games use different registry files; `wineserver` writes through a `user.reg` or `system.reg` that is a symbolic link; and `system.reg` is 3.2 MB, mostly Wine's own.
- **Whether an online-only ROM can be cloned** without downloading it first. Not tried.
- **macOS 28.** Apple hasn't said what qualifies for the Rosetta it keeps.
- **One pin for every ROM, or a pin per ROM.** Wine's FAQ expects regressions between versions and recommends a prefix per Wine version.
- **Whether a ROM keeps its disc image.** Age of Empires' `.bin` and `.cue` aren't needed once its folder is built, and Wine can't mount them.
- **Who supplies cnc-ddraw**: each ROM carrying its own copy, as now, or Ludeum fetching a pinned one with a digest it computes.
- **The user folders.** A prefix links My Documents to `~/Documents`; no game here uses it, and what to do for one that does is open.
- **Trimming the engine.** Wine's Gecko and Mono are half its size and unused by these games, but removing them makes the copy no longer the author's release.
- **Whether the launch file is the ROM's or the journal's.** The glossary's Emulator settings are the journal's, chosen on each Play (ADR 0008); a launch file inside the ROM's subfolder is not. #53 asks the same of DOS.
- **Save states.** Nothing in Wine's documentation snapshots a running program, so a Windows Game would have Game saves and no Save states or Resume state. Not looked into further.
- **Archive and Unarchive for a Windows ROM**, and how one is Matched: #53's questions, shared with DOS.

## Tried afterwards

On 2026-11-05, after this note was written, Gcenx's `wine-stable-11.0_1` was run against clones (`cp -cR`) of both games' prefixes, with their `ddraw.ini` set to a window and the games driven by injected keys and clicks, not a real mouse.

- **A clone of a prefix starts.** Wine 11.0 updated a prefix made by the Wine 10.0 engine by itself; Age of Empires' window was up 16 seconds after launch.
- **Age of Empires Plays on Gcenx's Wine 11.0**: intro video, menus, a random-map game. It saved a game (`SAVEGAME/test.gam`, about 200 KB) and loaded it back after a restart.
- **Z does not.** `z95.exe` exits as it starts, after its DLLs load, with `err:virtual:virtual_setup_exception nested exception on signal stack`. The Z Expansion disc's own `z9x.exe`, packed as shipped, dies the same way, so it isn't the unpacking or the added import. The original 1998 `winz.exe` starts and shows its window. Whether it's Wine 11.0 or the absence of Sikarugir's changes that the v1.5 patch trips on was not established: no Gcenx 10.x is listed any more, and Sikarugir's 11.0 engine wasn't tried.
- **The same save and load was then repeated on the Sikarugir 10.0_6 engine** from a fresh clone, and worked. Afterwards the clone's game folder differed from the original by `SAVEGAME/test.gam` alone; cnc-ddraw had not rewritten `ddraw.ini`. `user.reg` and `system.reg` differed in lines of Wine's own (class padding, a driver date) and in nothing of the game's, the game having been killed, not quit.

So recommendation 1 falls to its second half: the Sikarugir engine with its Template. Saving and loading in Z is still untried.

## Sources

- Wine: [source at `wine-10.0`](https://github.com/wine-mirror/wine/tree/wine-10.0); release notes for [9.0](https://github.com/wine-mirror/wine/blob/wine-9.0/ANNOUNCE.md), [10.0](https://github.com/wine-mirror/wine/blob/wine-10.0/ANNOUNCE.md) and [11.0](https://github.com/wine-mirror/wine/blob/wine-11.0/ANNOUNCE.md); wiki pages [FAQ](https://gitlab.winehq.org/wine/wine/-/wikis/FAQ), [Wine User's Guide](https://gitlab.winehq.org/wine/wine/-/wikis/Wine-User's-Guide), [MacOS](https://gitlab.winehq.org/wine/wine/-/wikis/MacOS), [MacOS-FAQ](https://gitlab.winehq.org/wine/wine/-/wikis/MacOS-FAQ), [MacOS-Building](https://gitlab.winehq.org/wine/wine/-/wikis/MacOS-Building), [Download](https://gitlab.winehq.org/wine/wine/-/wikis/Download), [Emulation](https://gitlab.winehq.org/wine/wine/-/wikis/Emulation), [Winetricks](https://gitlab.winehq.org/wine/wine/-/wikis/Winetricks), [Commands/wineboot](https://gitlab.winehq.org/wine/wine/-/wikis/Commands/wineboot), and the man pages for [wine](https://gitlab.winehq.org/wine/wine/-/wikis/Man-Pages/wine), [wineserver](https://gitlab.winehq.org/wine/wine/-/wikis/Man-Pages/wineserver) and [wineboot](https://gitlab.winehq.org/wine/wine/-/wikis/Man-Pages/wineboot).
- Sikarugir: [Engines `v1.0`](https://github.com/Sikarugir-App/Engines/releases/tag/v1.0), [Template `v1.0`](https://github.com/Sikarugir-App/Template/releases/tag/v1.0), [README](https://github.com/Sikarugir-App/Sikarugir), [`Sikarugir-App/wine`](https://github.com/Sikarugir-App/wine).
- Gcenx: [`macOS_Wine_builds`](https://github.com/Gcenx/macOS_Wine_builds), [release `11.0_1`](https://github.com/Gcenx/macOS_Wine_builds/releases/tag/11.0_1). Homebrew: [`wine-stable`](https://formulae.brew.sh/api/cask/wine-stable.json), [`wine@devel`](https://formulae.brew.sh/api/cask/wine@devel.json), [`wine@staging`](https://formulae.brew.sh/api/cask/wine@staging.json).
- CodeWeavers: [CrossOver source](https://www.codeweavers.com/crossover/source), [CrossOver Mac User Guide](https://support.codeweavers.com/user-guides/crossover-mac-user-guide).
- Apple: [About the Rosetta translation environment](https://developer.apple.com/documentation/apple-silicon/about-the-rosetta-translation-environment), [Using Intel-based apps on a Mac with Apple silicon](https://support.apple.com/en-us/102527), [About Apple File System](https://developer.apple.com/documentation/foundation/about-apple-file-system), [`LSFileQuarantineEnabled`](https://developer.apple.com/documentation/bundleresources/information-property-list/lsfilequarantineenabled), [Gatekeeper and runtime protection in macOS](https://support.apple.com/guide/security/gatekeeper-and-runtime-protection-sec5599b66df/web), [Game Porting Toolkit](https://developer.apple.com/games/game-porting-toolkit/), [`apple/homebrew-apple`](https://github.com/apple/homebrew-apple), and the toolkit's [licence](https://github.com/Sikarugir-App/Sikarugir/blob/main/D3DMetal/4.0/License.pdf) and [read-me](https://github.com/Sikarugir-App/Sikarugir/blob/main/D3DMetal/4.0/Read%20Me.pdf) as copied in Sikarugir's repository.
- [`Whisky-App/Whisky`](https://github.com/Whisky-App/Whisky). [`FEX-Emu/FEX`](https://github.com/FEX-Emu/FEX) and [`AndreRH/hangover`](https://github.com/AndreRH/hangover).
- cnc-ddraw: [README and LICENSE](https://github.com/FunkyFr3sh/cnc-ddraw), [release `v7.1.0.0`](https://github.com/FunkyFr3sh/cnc-ddraw/releases/tag/v7.1.0.0), [`src/hook.c`](https://github.com/FunkyFr3sh/cnc-ddraw/blob/v7.1.0.0/src/hook.c), [`src/config.c`](https://github.com/FunkyFr3sh/cnc-ddraw/blob/v7.1.0.0/src/config.c).
- Managers: [Lutris `docs/installers.rst`](https://github.com/lutris/lutris/blob/master/docs/installers.rst), [Bottles, Why Bottles?](https://docs.usebottles.com/faq/why-bottles), [Heroic, Linux Quick Start Guide](https://github.com/Heroic-Games-Launcher/HeroicGamesLauncher/wiki/Linux-Quick-Start-Guide).
- ogg-winmm: [`hifi-unmaintained/ogg-winmm`](https://github.com/hifi-unmaintained/ogg-winmm), [`ayuanx/ogg-winmm`](https://github.com/ayuanx/ogg-winmm).
