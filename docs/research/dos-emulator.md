# DOS emulator for Ludeum

Researched 2026-11-09 for [#53](https://github.com/danielholmes/ludeum/issues/53), on an M3 Max running macOS 26 (Darwin 25.5). The question: which DOSBox should Ludeum install and launch as a whole app ([ADR 0038](../adr/0038-emulators-are-whole-apps-ludeum-installs-not-cores.md)) for DOS (IGDB platform 13), given that a ROM is never written to and a game's writes are kept apart as its Game save, as Amiberry's save images ([ADR 0035](../adr/0035-an-amiga-rom-is-one-archive-and-its-saves-are-amiberrys-save-images.md)) and 86Box's game disks ([ADR 0041](../adr/0041-windows-games-are-played-in-86box-from-a-game-disk-over-one-windows-base.md)) do. Everything was driven from the shell, which can't type into an emulator's window; screenshots were taken by window ID.

## Recommendation

**DOSBox Staging**, launched as `--noprimaryconf --nolocalconf --conf <standing> [--conf <game>] -c "mount c <ROM folder>" -c "mount c <Game save folder> -t overlay" -c … --exit`, with the ROM a plain folder. It's the only one that's a signed, notarized Universal app; its command line layers configs and settings cleanly; its overlay kept the ROM byte-identical through writes, appends, deletes and renames; and its defaults are tuned so that a game's own config can be a few lines. What it lacks: it can't mount a ZIP (and won't, per its maintainer), has no save states (closed as not planned), aborts if a game renames a directory that's in the ROM, and keeps a folder of its own in `~/Library/Preferences/DOSBox` unless `HOME` is pointed elsewhere.

**DOSBox-X** is the one to choose instead if a DOS ROM should be one archive, as an Amiga ROM is: it mounts a ZIP or 7z as a drive with an overlay over it (verified), and it has save states. Against it: an ad-hoc-signed, unnotarized zip, monthly releases, and over an archive, files that came in the archive can't be deleted or renamed.

**Plain DOSBox 0.74-3** is out: its Mac build has no arm64 (Rosetta only, which Apple is winding down), and it has no overlay mount (`Illegal type overlay`, as run), no `--set` and no save states.

**Boxer** wraps its own DOSBox build: its original repository was last pushed in 2021, and the Apple Silicon fork's last release is a 2022 beta (`AS-beta-4.1`, [MaddTheSane/Boxer](https://github.com/MaddTheSane/Boxer/releases)). **DOSBox Pure** is a libretro core, and Ludeum runs whole apps, not cores (ADR 0038).

## Comparison

| | DOSBox Staging 0.83.0 | DOSBox-X 2026.10.01 | DOSBox 0.74-3-3 |
|---|---|---|---|
| Released | 2026-08-27 | 2026-10-02 | Source 2019-06-26; Mac `-3` dmg 2020-09-22 |
| Cadence | 0.82.0 2024-10, 0.82.1 2025-04, 0.82.2 2025-06, 0.83.0 2026-08; rolling `dev-latest` | Roughly monthly: 2026.05.02, .06.02, .07.02, .08.02, .08.31, .10.01 | None since 2019 |
| macOS build | Universal (`x86_64 arm64`) `.dmg`, Developer ID (John Novak, `944SS92GAH`), notarized; macOS 14+ | `arm64` and `x86_64` zips, each with SDL1 and SDL2 apps; ad-hoc signed, `spctl` rejects it; macOS 10.15+ | `x86_64 i386 ppc7400` `.dmg`, Developer ID, notarized; no arm64 |
| Config at launch | `--conf` (repeatable), `--set key=value`, `--noprimaryconf`, `--nolocalconf`, `--working-dir` | `-conf` (repeatable), `-set "section key=value"`, `-defaultconf`, `-nopromptfolder` | `-conf` (repeatable), `-c`, `-exit` |
| Own folder on macOS | `~/Library/Preferences/DOSBox`; follows `$HOME`; portable mode can't be used in the signed app | Writes `~/Library/Preferences/DOSBox-X 2026.10.01 Preferences` if missing; follows `$HOME` | `~/Library/Preferences/DOSBox 0.74-3-3 Preferences` |
| Folder overlay | Yes, since 0.75.0 | Yes | No |
| ZIP/7z as a drive | No | Yes, read-only, overlay on top | No |
| Save states | No | Yes, 100 slots or a named file | No |
| Dynamic core on arm64 | Yes (`risc_armv8le`) | Yes, `dynamic_rec` only | No (no arm64 build) |
| MIDI out of the box on a Mac | `port` (CoreMIDI): silent with no MIDI destination | `default`, which opened `coreaudio` (Apple's synth) | Not checked |
| Quits on SIGTERM | Yes | No; stopped with SIGINT/SIGKILL | Not checked |

## Pins, as downloaded

| File | Source | SHA-256 |
|---|---|---|
| `dosbox-staging-macOS-v0.83.0.dmg` | [GitHub release v0.83.0](https://github.com/dosbox-staging/dosbox-staging/releases/download/v0.83.0/dosbox-staging-macOS-v0.83.0.dmg) | `d8a771adfb8010fa6b5f7fb5351abfba659273ad01c89f03675a92bdbdae8167` |
| `dosbox-x-macosx-arm64-2026.10.01.zip` | [GitHub release dosbox-x-v2026.10.01](https://github.com/joncampbell123/dosbox-x/releases/download/dosbox-x-v2026.10.01/dosbox-x-macosx-arm64-2026.10.01.zip) | `8514ab856e8ac2611fbdac7adf334c34085c1e00d700a88711f842adec50240f` |
| `DOSBox-0.74-3-3.dmg` | [SourceForge](https://sourceforge.net/projects/dosbox/files/dosbox/0.74-3/) | `83493d149318cb7bfe5d68d98d1cd10b003db2f0519374bf06de285dc0bb2768` |
| `dosbox-0.74-3.tar.gz` (source, read only) | SourceForge, same folder | `c0d13dd7ed2ed363b68de615475781e891cd582e8162b5c3669137502222260a` |

The first two match the `digest` GitHub's API gives for the asset. Staging's own macOS download page still shows `sha256: TODO` for 0.83.0 (`website/docs/releases/macos.md`). The DOSBox-X zip is the same file the Windows 9x trial used ([windows-9x-in-86box.md](windows-9x-in-86box.md)). Staging's app: bundle ID `io.github.dosbox-staging`, version `0.83.0-7b400`, 109 MB. DOSBox-X's: `com.dosbox-x`, `2026.10.01 Commit b6abbd5`, 112 MB, with `libfluidsynth.3.dylib` in `Contents/MacOS/arm64`. `dosbox.com` refused connections from here, so 0.74-3 came from its SourceForge folder.

## Findings

### Command line and where settings live

- **Staging layers in a fixed order**: the primary config (unless `--noprimaryconf`), then a `dosbox.conf` in the working directory (unless `--nolocalconf`), then each `--conf` in order, then each `--set`, last wins (manual, `using-dosbox-staging/configuration.md`, "Configuration layering"; `src/config/config.cpp` `ParseArguments`). `--set` takes the bare setting name, e.g. `--set cpu_cycles=5000` (manual, `command-line.md`). `-c` runs DOS commands before the `PATH` argument; `--exit` quits after the `-c` commands and `[autoexec]`, so with a game started from `-c`, Staging quits when the game does (`dosbox --help`). `--fullscreen` starts fullscreen.
- **Staging's own folder is `~/Library/Preferences/DOSBox`** (`src/misc/cross.cpp` `get_or_create_config_dir`, resolved through `$HOME`). Even with `--noprimaryconf` it creates `plugins`, `shaders`, `soundfonts`, `mt32-roms`, `soundcanvas-roms` and `webserver` there and writes `shell_history.txt` (`src/main.cpp` `maybe_create_resource_directories`; as run). Daniel already has that folder from his own Staging. With `HOME` set to a folder holding an empty `Library/Preferences`, all of it went there instead; with `HOME` set to a folder without one, Staging logged that it couldn't create the folder and ran anyway.
- **Staging's portable mode doesn't work inside the signed app.** It's a `dosbox-staging.conf` next to the executable (`src/misc/cross.cpp` `init_config_dir`), which is `Contents/MacOS`. With one there, `codesign --verify` said `a sealed resource is missing or invalid` and the process was killed at launch (exit 137) every time; taken out, it ran.
- **DOSBox-X loads only what `-conf` names**: given any `-conf`, it skips its search of the working directory, program directory and user folder (`src/gui/sdlmain.cpp`, the `config_paths` loop runs only while nothing's loaded), and `-conf`, `-set`, `-defaultconf` or `-fastlaunch` turn off its macOS prompt for a working folder. As run, a user config with `memsize = 8` was ignored, `-conf ludeum.conf` (memsize 16) then `-conf game.conf` (cycles fixed 5000) layered, and `-set "cpu cycles=fixed 9000"` won. But **it still writes a full default user config** to `~/Library/Preferences/DOSBox-X 2026.10.01 Preferences` when there isn't one, and didn't rewrite an existing one. `-fs` starts fullscreen; `-exit` quits after `AUTOEXEC.BAT`.
- **DOS command lines are short.** `-c "mount c <path>"` took paths of well over 127 characters with spaces and parentheses in both. But `config -wc <long absolute path>` in Staging wrote to a truncated name (`s`, then `saved.`), and in DOSBox-X a `/` in the path was read as a switch. A bare file name works: Staging writes it in the working directory, DOSBox-X in its user config folder.

### Mounting

- **A host folder as C:**: `mount c <folder>` in both. Staging also takes a folder as its bare argument, or a `.exe`, whose folder becomes C: and which is run, quitting when it exits (`dosbox --help`).
- **CD images:** Staging 0.83.0 merged `IMGMOUNT` into `MOUNT` (`IMGMOUNT` stays as an alias): `mount d game.cue` or `.iso`, type detected by extension; CUE/BIN carries CD-DA tracks, also as FLAC, Opus, Ogg Vorbis, MP3 or WAV; ISO can't carry audio; MDS/MDF too (release notes 0.83.0, "IMGMOUNT has been merged into MOUNT"; manual `storage.md`, `sound-devices/cd-da.md`). DOSBox-X: `imgmount d game.cue -t iso`. As run, a 900 KB ISO made with `hdiutil makehybrid` listed its file as D: in both. CD audio wasn't tried.
- **Floppy images:** `mount a disk.img` (Staging; `-t floppy` if detection's wrong; several images cycle with a hotkey; `-ro` for read-only) and `imgmount a disk.img -t floppy` (DOSBox-X). Without `-ro` a game writes into the image itself: neither overlay works over an image (Staging refuses one over anything but a local folder, `src/dos/programs/mount.cpp`; DOSBox-X over anything but a local folder or an archive). Not run.
- **Automounting** (Staging): `drives/c/`, `drives/d/…` under the working directory are mounted at start, images in them as floppies or CDs, each with an optional `c.conf` that can set `type = overlay` (manual `storage.md`, "Automounting"). It also always mounts its own utilities as Y: from `Resources/drives`.
- **ZIP/7z:** Staging can't. As run, `mount e keen1.zip` said `Can't create drive from file.` The issue asking for it was closed in 2021 in favour of a ROM-package spec, and its maintainer added in 2025: "I don't think this will happen. Kinda feature bloat for no good reason" ([dosbox-staging#314](https://github.com/dosbox-staging/dosbox-staging/issues/314)). DOSBox-X mounts ZIP and 7z through PhysFS, read-only, since 0.83.9, and since 0.83.10 `mount c <folder> -t overlay` over one gives it a write location, `<folder>/C_DRIVE` (its `CHANGELOG`; `src/dos/drive_physfs.cpp`). A ZIP can also be its bare argument, mounted as C:. PhysFS's write directory is one for the whole process (`PHYSFS_setWriteDir`), so it's one overlay for all archive drives.

### Writes: the overlay

Both forks carry the same overlay drive, from a patch GOG gave DOSBox SVN (Staging's 0.75.0 release notes, "Mount overlay support"; [#314](https://github.com/dosbox-staging/dosbox-staging/issues/314)). `mount c <ROM folder>` then `mount c <save folder> -t overlay`: changed and new files go to the save folder, whole files copied up on the first write; a deleted file leaves a marker; at the next start the two are merged. Both paths must be absolute or both relative, and different (`Overlay_Drive` constructor). Overlays don't stack: a second replaces the first (DOSBox-X `CHANGELOG`).

As run with a copy of Keen 1 (38 files) in a folder named `Keen 1 (1990)`, and the save folder `save (Keen 1)`; a tree hash of the ROM folder was `ca37090bcf16400c` before and after every run:

| | DOSBox Staging 0.83.0 | DOSBox-X 2026.10.01, folder | DOSBox-X 2026.10.01, ZIP |
|---|---|---|---|
| New file | `TEST.TXT` | `TEST.TXT` | `C_DRIVE/TEST.TXT` |
| Append to a ROM file | Copied up as `KEEN1/SCORES.CK1` | Copied up as `keen1/scores.ck1` | Copied up as `C_DRIVE/keen1/scores.ck1` |
| Delete a ROM file | Marker `KEEN1/DBOVERLAY_DEL_ORDER.FRM`; hidden from `DIR`, next run too | Marker `keen1/.DBOVERLAY_DEL_ORDER.FRM` | Silently not deleted |
| Rename a ROM file | Copy as `VENDOR.TXT` plus a delete marker | Not tried | Silently not renamed |
| New directory | `NEWDIR/Z.TXT` | Not tried | Not tried |
| Rename a ROM directory | **Aborts the emulator** (exit 134, `ABORT: Overlay: renaming base directory KEEN1 to KEEN2 not yet supported`) | Refused with access denied, emulator carries on | Not tried |
| ROM afterwards | Unchanged | Unchanged | Archive SHA-256 unchanged |

- **Case:** Staging's overlay names everything in upper case 8.3 (its design note, `src/dos/drive_overlay.cpp`); DOSBox-X keeps the ROM's own case.
- **Over an archive,** DOSBox-X's `FileUnlink` and `Rename` work only on what's already in the write directory (`PHYSFS_delete`; `physfsDrive::Rename` checks `PHYSFS_getRealDir`), hence the silent failures. Directories inside the ZIP listed with the date 01/01/2098, and a long folder name in the ZIP came up as `KEEN1(~1`.

### Save states

- **Staging has none,** closed as not planned in 2024: "it's very unlikely it will be ever implemented" ([dosbox-staging#313](https://github.com/dosbox-staging/dosbox-staging/issues/313)).
- **DOSBox-X has 100 slots** (10 a page), or a named `savefile` in `[dosbox]` used instead of slots; `saveslot` picks the default slot, `forceloadstate` skips its check of version, machine, program and memory size, `saveremark` asks for a remark (`src/dosbox.cpp`; [wiki, Saving and loading states](https://github.com/joncampbell123/dosbox-x/wiki/Guide:Saving-and-loading-states)). Slots go in `save/` under the working directory, or wherever `-savedir <path>` says (`src/misc/savestates.cpp`, `src/gui/sdlmain.cpp`). There's no command-line option or setting to load one at launch that I found; it's the menu or a hotkey. Not run.

### Performance on Apple Silicon

- **Staging:** `core = auto`, the default, is the normal core for real mode and the dynamic core for protected mode; the dynamic core has an ARMv8 back end (`src/cpu/cpu.cpp`, `src/cpu/core_dynrec/risc_armv8le.h`). Cycles default to fixed: `cpu_cycles = 3000` for real mode, `cpu_cycles_protected = 60000` for protected mode, with `cpu_throttle` off; the legacy `cycles` setting still works and switches the new ones off (`src/cpu/cpu.h`, `cpu.cpp`).
- **DOSBox-X:** `core = auto` "will switch to dynamic if available", and of the two dynamic cores only `dynamic_rec` exists on arm64, of which its help says "Windows 95 or other preemptive multitasking OSes will not work" (`src/dosbox.cpp`), as the Windows 95 trial found. `cycles = auto` switches to max cycles in protected mode (`src/cpu/cpu.cpp`).
- Not measured: neither was timed against the other.

### Sound and MIDI

- Both default to a Sound Blaster 16 at 220h, IRQ 7, DMA 1, high DMA 5, with OPL, an MPU-401 at 330h, and the Gravis Ultrasound off (`sbtype`, `oplmode`, `gus` defaults; Staging's log, as run).
- **Staging's `mididevice = port` is CoreMIDI** on macOS (`src/midi/midi.cpp`), and with no MIDI destination it sends nowhere (`src/midi/coremidi.cpp`), so General MIDI music is silent until a config sets `mididevice = coreaudio` (Apple's synth) or `fluidsynth` with a SoundFont, which isn't bundled: `soundfont = default.sf2`, looked for in `soundfont_dir` then `<config folder>/soundfonts` (manual `sound/midi.md`, `sound-devices/fluidsynth.md`). MT-32 needs ROMs it can't bundle, in `mt32-roms` (`sound-devices/roland-mt-32.md`).
- **DOSBox-X's `mididevice = default`** opened `coreaudio` as run; FluidSynth needs `fluid.soundfont` set (`src/dosbox.cpp`).
- Not heard: no sound was listened to in either.

### Per-game configuration

What a game still needs, by the projects' own word:

- **Staging** says its defaults "will give you good results for most programs", and keeps a [Game issues](https://github.com/dosbox-staging/dosbox-staging/wiki/Game-issues) page of about 140 games that need more. Those entries are mostly `cpu_cycles` or `cpu_cycles_protected`, then `cputype` (e.g. `386_prefetch` for self-modifying code), `core`, `machine` (e.g. `cga` for Contra), `memsize`, `xms`/`ems`/`umb`, and sound (`sbtype`, `gus`, `mididevice`). Its 0.83.0 release notes add `cpu_cycles_protected` values for some games and `hard_disk_speed = fast` for games that check disk speed. No table of games built into the emulator turned up in its source.
- **DOSBox-X's** [DOS games guide](https://github.com/joncampbell123/dosbox-x/wiki/Guide:DOS-games-in-DOSBox%E2%80%90X) starts from defaults and lists what to try when a game misbehaves: fixed cycles, `core = normal`, `machine = vesa_nolfb` or `vgaonly`, `ems`/`xms` off, `sbtype`, `gus`. It points to outside lists, the old DOSBox compatibility list, PCGamingWiki and Vogons, and keeps none of its own.
- **Staging's manual recommends minimal per-game files over a general one:** "you can keep your local configurations quite minimal. There's absolutely no need to specify every single setting", and to keep hardware settings out of the general file (`configuration.md`, "Configuration best practices"). Ludeum's equivalent would be a standing `--conf`, then the game's `--conf` holding only its differences, then `--set`s.

Changing settings during a Play, and keeping them:

- **Staging:** `config -set <setting>=<value>` at the DOS prompt and the hotkeys (Cmd+F11/F12 for cycles); there's no settings window. `config -wc <file>` writes the *whole* current configuration, about 96 KB as run, with the runtime change in it, not a diff; `config -l` lists which files were loaded. Its HTTP API is off by default (`webserver_enabled`).
- **DOSBox-X:** a graphical Configuration Tool (`-startgui`, the Main menu, or `SHOWTOOL`) and `config -set "section key=value"`. `config -wc -mod -norem <file>` writes only the settings that differ from the *defaults*: as run, after `config -set cpu cycles=fixed 12345` it wrote `[cpu] cycles = fixed 12345` and empty special sections. A setting that the standing config changed from its default would be written too, so neither gives "this game's differences from Ludeum's standing config" without Ludeum diffing.
- **eXoDOS** ships its 7,666 games already configured, each with a batch file that names which DOSBox it calls, and one `options.conf` for display settings ([retro-exo.com](https://www.retro-exo.com/exodos.html)). Its page says nothing about licensing, and I found no licence for its configurations.

## What was run

All in this session's scratchpad, never against `~/Dropbox`: Keen 1's game folder was copied out of `Keen 1.boxer` as test data, and zipped as `keen1.zip` (SHA-256 `b1a0ac1d…`). Every run had `HOME` pointed at a scratch folder; Daniel's own `~/Library/Preferences/DOSBox`, `DOSBox-X 2026.10.01 Preferences`, `com.dosbox-x.plist` and `DOSBox 0.74-3-3 Preferences` hashed the same before and after.

- Staging: `--noprimaryconf --nolocalconf --conf ludeum.conf -c "mount c …" -c "mount c … -t overlay" -c … -c exit`, three times for the overlay table, the third renaming a directory; then `-c "C:" -c "cd \keen1" -c "keen1" --exit`, which reached Keen's title starfield in its window (screenshot by `screencapture -l`), and SIGTERM closed it. Then the `HOME` and portable-mode runs above, `--conf` twice with `--set sbtype=sbpro2` and `config -l`, `config -wc`, and the ISO and ZIP mounts.
- DOSBox-X (SDL1 app): the same overlay commands with `-conf … -nopromptfolder -fastlaunch`; the config layering run; the ZIP with an overlay, writes, a delete and a rename; Keen 1 from the ZIP to its starfield; the ISO mount; `config -wc -mod -norem`. SIGTERM left it running for 30 seconds; SIGINT then SIGKILL ended it. An `IMGMAKE` floppy wasn't created as typed, so floppies weren't tried.
- DOSBox 0.74-3-3 under Rosetta: a mount and a write worked; `-t overlay` printed `Illegal type overlay`; it logged `Unable to obtain graphics context for NSWindow (Mojave behavior)`.

Not verified: CD audio from CUE/BIN; floppy images; any sound or music heard; speed or CPU use; a real game's own save going through the overlay (Keen 1 wasn't played to a save, only writes from the DOS prompt); fullscreen; DOSBox-X's save states; whether setting `HOME` for a launched app upsets anything else in macOS (audio, video and controllers came up as normal in Staging's log).

## Open questions

- **What a DOS ROM is:** a folder (Staging), or one archive (DOSBox-X), which matters for matching, checksums and archiving as PS2 ROMs are.
- **Games installed from a CD:** the install would go entirely into the Game save over an empty or near-empty C:. Is that acceptable as the Game save, or does an installed game become a new ROM?
- **Floppy images** are written in place; mount them `-ro`, or copy each into the Game save first as ADR 0035 does?
- **Staging's own folder:** let it share `~/Library/Preferences/DOSBox` with Daniel's own Staging, or set `HOME` for each Play to a folder Ludeum owns (untested beyond these runs)?
- **Staging's abort on a renamed ROM directory:** how many games do that? None found; nothing searched for it.
- **Where a game's settings live** (a `--conf` file next to the ROM, or the journal's Emulator settings, ADR 0008), and how changes made during a Play get back to it, since neither emulator writes a diff against a standing config.
- **Rosetta:** Apple said at WWDC 2025 that Rosetta stays as a general tool through macOS 27 ([MacRumors](https://www.macrumors.com/2025/06/10/apple-to-phase-out-rosetta-2/), not Apple's own page), which settles plain DOSBox regardless.

## Sources

- DOSBox Staging at `v0.83.0` (`7b40053`): `src/config/config.cpp`, `src/main.cpp`, `src/misc/cross.cpp`, `src/dos/drive_overlay.cpp`, `src/dos/programs/mount.cpp`, `src/dos/programs.cpp`, `src/cpu/cpu.cpp`, `src/cpu/cpu.h`, `src/midi/midi.cpp`, `src/midi/coremidi.cpp`, `src/midi/fluidsynth.cpp`; its website source, `website/docs/0.83/manual/` (`using-dosbox-staging/configuration.md`, `command-line.md`, `storage.md`, `sound/midi.md`, `sound/sound-devices/`) and `website/docs/releases/` (`macos.md`, `release-notes/0.75.0.md`, `0.83.0.md`). https://github.com/dosbox-staging/dosbox-staging/tree/v0.83.0
- DOSBox Staging releases and issues: https://github.com/dosbox-staging/dosbox-staging/releases, [#313 Save States support](https://github.com/dosbox-staging/dosbox-staging/issues/313), [#314 Zip/7z mount and launch](https://github.com/dosbox-staging/dosbox-staging/issues/314), [Game issues](https://github.com/dosbox-staging/dosbox-staging/wiki/Game-issues).
- DOSBox-X at `dosbox-x-v2026.10.01`: `CHANGELOG`, `src/dosbox.cpp`, `src/gui/sdlmain.cpp`, `src/misc/cross.cpp`, `src/misc/programs.cpp`, `src/misc/savestates.cpp`, `src/dos/dos_programs.cpp`, `src/dos/drive_overlay.cpp`, `src/dos/drive_physfs.cpp`, `src/cpu/cpu.cpp`; the zip's `README.txt`. https://github.com/joncampbell123/dosbox-x/tree/dosbox-x-v2026.10.01
- DOSBox-X wiki: [Home](https://github.com/joncampbell123/dosbox-x/wiki) (configuration file, FAQ), [Saving and loading states](https://github.com/joncampbell123/dosbox-x/wiki/Guide:Saving-and-loading-states), [DOS games in DOSBox-X](https://github.com/joncampbell123/dosbox-x/wiki/Guide:DOS-games-in-DOSBox%E2%80%90X).
- DOSBox 0.74-3 source tarball: `src/dos/dos_programs.cpp`, `src/cpu/core_dynrec/`, `src/misc/cross.cpp`, `docs/dosbox.1`. https://sourceforge.net/projects/dosbox/files/dosbox/0.74-3/
- eXoDOS: https://www.retro-exo.com/exodos.html
