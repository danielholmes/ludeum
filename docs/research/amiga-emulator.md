# Amiga emulator for Ludeum

Researched 2026-11-04. Criteria, as for the other Platforms: run-ahead, accuracy, a live project, performance, and that Ludeum can tell it from outside what to do. Sources are each project's source at the commit named, its GitHub releases, and running Amiberry 8.5.0 on this Mac.

## Recommendation

**Amiberry.** It's the only one that opens every form these games come in and takes its disks, machine and folders on its command line. It has no run-ahead; vAmiga does, and is the one to look at again if that comes to matter.

## Comparison

| | Amiberry 8.5.0 | vAmiga 5.0 | FS-UAE 3.2.35 |
|---|---|---|---|
| Latest release | 2026-10-27 | 2026-11-01 | 2025-09-07 |
| Last push | 2026-11-03 | 2026-11-01 | 2025-09-13 |
| macOS build | Universal, signed `.dmg` | `vAmiga.app.zip` | ARM64 `.dmg`, `.tar.xz` |
| Core | WinUAE's | Its own, written for accuracy | WinUAE's |
| Run-ahead | None (`libretro.h`'s API only) | Yes, `AMIGA_RUN_AHEAD`, off by default | None in its docs |
| Disk images | ADF, ADZ, DMS, IPF, also in `.zip` or `.7z` | ADF, ADZ, DMS, EXE, IMG, ST | ADF, IPF, DMS, ADZ, `.zip` |
| WHDLoad `.lha` | One argument, `--autoload` | No | Mounted by hand |
| Launch | `-0`–`-3`, `-diskswapper=`, `--model`, `--statefile`, `-s`, `-o` | Arguments starting `-` run as RetroShell commands | A config file |
| No Kickstart | Bundled AROS | Knows AROS; bundling not checked | Bundled AROS |

Not checked: vAmiga's A1200 support (its default is ECS, and I believe it stops there).

## Amiberry, as run

At [`bcea436`](https://github.com/BlitterStudio/amiberry/tree/bcea436ddfc3db3e244775e053eec910b77cace9), with `Amiberry-8.5.0-macOS-universal.dmg` (SHA-256 `002bb71a…`, matching GitHub's digest). Its bundle ID is `com.blitterstudio.Amiberry` and its `CFBundleShortVersionString` is `8.5.0`. Its release build listens on a control socket (`$XDG_RUNTIME_DIR/amiberry.sock`, cut short at 104 characters as a Unix socket path is; `docs/ipc.md`), which is how these were observed, and which would let Ludeum drive it, though nothing does.

- **Where it keeps things.** `--dump-paths` prints them and creates nothing. `AMIBERRY_HOME_DIR` moves every content folder (ROMs, SaveStates, Configurations, Controllers, Screenshots, NVRAM, WHDBoot and the rest); `NSWorkspace.OpenConfiguration.environment` passes it. Its portable marker is disabled on macOS (`get_portable_mode_marker_path` returns nothing under `__MACH__`), and `AMIBERRY_CONFIG_DIR` isn't read there. Its settings directory is `$HOME/Library/Application Support/Amiberry`, where it writes `amiberry.ini` (window position, detected ROMs); `-o amiberry_config=` moves `amiberry.conf`. The first launch copies 14 MB into its home, mostly WHDBoot and AROS.
- **A loose disk is written in place.** Booting a test disk whose boot block writes to block 100, `Loose.adf` changed, whether or not a save image was there. `DISK_validate_filename` opens it `r+b`.
- **A disk in an archive is write-protected, with a save image beside it.** In `.zip` or `.7z`, `GET_DISK_WRITE_PROTECT` says protected, as `zfile_iscompressed` does in `disk_setwriteprotect`. Turning that off (`DISK_WRITE_PROTECT`, or the menu) makes `<name>_save.adf` in `saveimage_dir` (by default the home folder), named by `saveimagecutfilepart` from what's after the last `/`, less its last extension.
- **A save image there is used at the next launch.** Its folder can be set per launch: `-o saveimage_dir=`. With one there, the disk comes up writable. Writes changed only the save image: `Packed.7z`'s MD5 stayed `07e65a63…` while the save image's went from `998910b0…` to `073a6aa5…`, and a second boot read `LUDE…` from block 100 into `$50000`, where the first had read zeros.
- **An empty save image is the same every time**: `UAE-1ADF`, two zero bytes, a track count of 166, then for each track 12 bytes (`0`, type `1`, length `0x31F0`, bits `0`), then 166 × 12,784 zeros: 2,124,148 bytes, MD5 `998910b0…`. One written by a script was byte-identical to Amiberry's.
- **A disk can be named inside its archive.** `-0 Game.7z/Disk\ 1.adf` opens it and names its save image `Disk 1_save.adf`, not `Game_save.adf`, as `-0 Game.7z` would. `-diskswapper=` takes such paths, comma-separated, each in quotes, and so do `-s floppy0=` and `-s diskimage0=`; `DISKSWAP 2 0` then put the third in the first drive. It reads as protected for a moment, then as writable through its own save image, seconds later.
- **A disk's path can be 255 bytes, no more.** `-0` and `-diskswapper=` copy at most 255 (`cmdpath`, `parse_diskswapper`), and `-s floppy0=` fares no better: run with plain names at each length, 255 opened and 256 left the drive empty, with no message. TOSEC's brackets and parentheses in the archive's name or the disk's made no difference. A save image's path has no such limit: at over 300, its disk was still writable.
- **It boots without a Kickstart.** With nothing in `ROMs/`, `load_kickstart` falls back to `load_kickstart_replacement`, AROS. HeroQuest (one `.adf`) and HeroQuest II (three, in one `.7z`) both reached their intros. `--model A500` is OCS with 512 KB of chip and 512 KB of slow memory: HeroQuest II still showed a grey screen 25 seconds in, and its intro within the minute, where without `--model` its intro was up by then.
- **A Kickstart added later needs a rescan.** `[DetectedROMs]` in `amiberry.ini` is only made when it's missing, unless `--rescan-roms` is given. Not run with a real Kickstart, as there's none here.
- **Unchecked:** that an IPF opens (it needs `capsimg`), that a real game's save works through a save image (a boot block's write through `trackdisk.device` did), and that a real Kickstart is picked up.

## The example games

Hasheous knows them by MD5 and by CRC32, as Commodore Amiga: HeroQuest as IGDB 12142 and HeroQuest II as 12609, every disk of every variant. Their names are TOSEC's, which the rest of Ludeum's naming ([rom-naming-conventions.md](rom-naming-conventions.md)) doesn't otherwise see.

`HeroQuest-II-Legacy-of-Sorasil_Amiga_EN` holds eight zips of one disk each, all `[cr TRSi - ZNT]`:

| Set | Disks | Against the base set |
|---|---|---|
| `[cr TRSi - ZNT]` | 1, 2, 3 | |
| `[cr TRSi - ZNT][a]` | 1, 2, 3 | 17–18 bytes per disk, all in block 880, the root block |
| `(Disk 1 of 3)[t +85 HLM]` | 1 | A trainer; 103,721 bytes on 14 cylinders |
| `(Disk 1 of 3)[t +85 HLM][a]` | 1 | A trainer; 22,282 bytes on 7 cylinders from `[a]`'s Disk 1 |

## Sources

- [BlitterStudio/amiberry](https://github.com/BlitterStudio/amiberry): `src/main.cpp`, `src/disk.cpp`, `src/memory.cpp`, `src/osdep/amiberry.cpp`, `docs/ipc.md`.
- [dirkwhoffmann/vAmiga](https://github.com/dirkwhoffmann/vAmiga) at `f51a6bf`: `GUI/MyController.swift` (arguments as RetroShell), `Core/Components/Amiga.h` (run-ahead), `Resources/Info.plist` and `Core/rvlib/Images/` (what it opens).
- [FrodeSolheim/fs-uae](https://github.com/FrodeSolheim/fs-uae) at `f362278`: `docs/floppy-images.md`, `docs/options/`.
- [TOSEC Naming Convention](https://www.tosecdev.org/tosec-naming-convention).
