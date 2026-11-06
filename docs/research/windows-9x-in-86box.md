# Windows 9x games in 86Box

Tried 2026-11-05 and 2026-11-06 on an M3 Max running macOS 26 (Darwin 25.5), with Daniel at the keyboard and playing, as the shell can't send input to an emulator's window. The question: is real Windows in an emulated PC a better way to play Windows 9x games than Wine, and which emulator? The decision is [ADR 0041](../adr/0041-windows-games-are-played-in-86box-from-a-game-disk-over-one-windows-base.md). Where this says "felt" or "seemed", it's Daniel's impression and wasn't measured.

## Sources

- 86Box v6.0 source, read at the tag: `src/config.c`, `src/disk/hdd_image.c`, `src/cpu/cpu_table.c`, `src/machine/machine_table.c`, `src/video/vid_table.c`, `src/video/vid_voodoo_banshee.c`, `src/include/86box/cdrom.h`. https://github.com/86Box/86Box/tree/v6.0
- 86Box's ROM set: https://github.com/86Box/roms/tree/v6.0
- DOSBox-X's wiki, "Guide: Installing Windows 95". https://github.com/joncampbell123/dosbox-x/wiki
- 86Box developers on faster CPUs, 2022: "Why Not Pentium III?". https://86box.net/2022/03/21/why-not-p3
- Voodoo3 driver release notes and download. https://3dfx.retropc.se/voodoo3.html
- UTM's site, on 3D for Windows. https://mac.getutm.app/
- QEMU's report of Windows 98 SE not booting on Apple Silicon (not checked for a fix). https://gitlab.com/qemu-project/qemu/-/issues/2987

## Pins, as downloaded

| File | SHA-256 |
|---|---|
| `86Box-macOS-x86_64+arm64-b9001.zip` (release v6.0) | `fc66fc97225012af20145ae04193911bbf689fc75f89590774a904483140a5a9` |
| 86Box/roms `archive/refs/tags/v6.0.tar.gz` | `38fccaf4a7b48e581ccdfee2dc3cc0545e7d3a778bc25611e902a117eec571e6` |
| `dosbox-x-macosx-arm64-2026.10.01.zip` | `8514ab856e8ac2611fbdac7adf334c34085c1e00d700a88711f842adec50240f` |
| `voodoo3-10700.zip` | `781eb6cbc7eedcf45de5b6433666368db42044ee2dfbfe30e6328e5ae635ec0b` |

A GitHub tarball isn't promised to stay byte-identical, so if Install's checksum of the ROM set fails, it may be GitHub's packing that changed rather than the ROMs. Install, Choose Base and Play's exact command line were rehearsed together against these downloads and the real base, in a scratch Ludeum folder whose paths had spaces, parentheses and `&`: 86Box made a differencing game disk, Windows wrote 31 MB to it in 90 seconds, and the base's checksum held.

## Results

| Game | How it got in | Emulator and machine | Result |
|---|---|---|---|
| Age of Empires v1.0 (1997) | Its own installer, from disc | DOSBox-X, Windows 95 | Plays at 1024×768 with CD music once tuned to 70,000 cycles |
| Age of Empires | Its own installer | 86Box, Pentium MMX 200, Windows 95 | Plays at 1024×768; asked once for the Windows CD |
| Age of Empires | Its own installer | 86Box, Pentium MMX 200, Windows 98 SE, differencing disk | Installed with no prompts; played; saved and reloaded |
| Age of Empires | Its own installer | 86Box, final machine and base | Installed, played, saved and reloaded; busiest thread about 86% of a core |
| Z (1996), unpatched | Its own installer, then DirectX from the disc | 86Box, Windows 95 | Played smoothly, menu picture shown, saved and reloaded |
| Z | The same | DOSBox-X, Windows 95, 70,000 cycles | Compatible, with slight slowdown in play; saving not tried |
| Tiberian Sun 2.03 | EA's free installed folder, copied into a raw disk image from macOS | 86Box, Pentium MMX 200, Windows 95 | 100% through about 5 minutes; slight mouse flicker on the main menu; videos and saves not seen |
| Red Alert 2 | Out of The First Decade's archives | 86Box, final machine | 100% through videos and several minutes of play; options saved; saved and reloaded |
| Renegade (2002) | Out of The First Decade's archives | 86Box, final machine | Runs after `WWCONFIG.EXE`. 800×600, tutorial: high 80s to mid 90s, speech skipping. 1280×1024, campaign: mid 60s to mid 70s, very laggy. 800×600, lowest detail, DMA on, campaign: mostly 90–100%, still laggy in action with broken audio; crashed once |

Not tried: Z or Tiberian Sun on the final base.

What limits it, measured per thread with `ps -M` during play. Age of Empires: main thread about 86%, next about 44%. Renegade: main thread 80–100%, the four Voodoo render threads 2–37% each. So at the top of the range the emulated CPU is what runs out, and 3D drawing is paid for on separate Mac threads with room to spare. 86Box's fastest Pentium II is 450 MHz; its 500 and 550 MHz entries are a Socket 370 Celeron (to 533) and the Cyrix III.

Windows' start and dxdiag's opening each dipped into the 85–90% range for a few seconds on the 450 MHz machine, with the startup sound jittering. Taking the startup sound and items away seemed to help.

## What each game needed

- **Z:** `DirectX\DXSETUP.EXE` on Windows 95, which lacked `DINPUT.DLL` (reported as `INPUT.DLL`). Its CD check wants the volume label `Z95VOLUME`, which `Z Expansion.iso` has and the re-packed `Z95.iso` hasn't. That disc's autorun is a VB6 program that raised an `OLEAUT32.DLL` error over the game when inserted, on Windows 95 with autorun on.
- **Red Alert 2:** `RA2.EXE`. Run directly, `GAME.EXE` quits silently, as it looks for its launcher. The `mscoree.dll` in `Ra2.exe` is only Microsoft's C runtime, not .NET.
- **Renegade:** `WWCONFIG.EXE` first. Without it the game's Direct3D device isn't created, and it crashes at `0057306d` calling `SetRenderState(D3DRS_SOFTWAREVERTEXPROCESSING)` on a null device. Then `RENEGADE.EXE`. Its code turns off multitexturing on Voodoo3 and render-to-texture.
- **Anything copied from a CD image:** read-only, so options won't save until `command /c attrib -r C:\GAME\*.* /s`.
- **The First Decade's disc:** InstallShield 11 archives. `brew install unshield`, then `unshield -g "Red Alert 2" -d <dir> x data1.hdr`; its groups include `Tiberian Sun`, `Red Alert 2`, `Yuri`, `Renegade`, `Generals` and `Zero Hour`, and `directx/dxsetup.exe` on the disc is DirectX 9.0c.

## How the base was prepared

The base as frozen is `ludeum-win98se-base.7z` in `Dropbox/games/Old Machines/Windows 98 SE/Emulator bases`: the VHD, whose SHA-256 starts `e6affc4eb4e13e474527`, with its `86box.cfg`, BIOS settings, boot floppy, answer file and `vhd-geometry.pl`.

1. **A blank disk.** `IMGMAKE hdd.img -t hd -size 32000 -fat 32` in DOSBox-X with `ver=7.1`, `XCOPY D:\WIN98 C:\WIN98 /I /E`, then the answer file. It's padded with `truncate` to 65016×16×63 sectors, the geometry given to 86Box.
2. **A boot floppy.** The CD's `[BOOT]/Boot-1.44M.img`, with `CONFIG.SYS` cut to HIMEM and an `AUTOEXEC.BAT` that runs `SETUP MSBATCH.INF /IS` unless `C:\WINDOWS\WIN.COM` exists. macOS can write it: `hdiutil attach -imagekey diskimage-class=CRawDiskImage -nobrowse -nomount`, `mount -t msdos`, then delete `.fseventsd` and any `._` file before unmounting.
3. **Setup.** The answer file fills the name, product key and autorun off (`NoDriveTypeAutoRun`), but Setup still stops at each screen. A new board needs F1 for its first CMOS error and Boot Sequence A,C. Say no to a startup disk: it would overwrite the floppy. Take the floppy out for the first boot from the disk.
4. **The card.** Set `gfxcard = voodoo3_3500_agp`, cancel Windows' own wizard, run `Voodoo3-10700.exe` from a CD image, then `C:\WINDOWS\TEMP\SETUP.EXE`, pointing its file prompt at `C:\WINDOWS\TEMP\DRIVER9X`. Its INF lists 86Box's `SUBSYS_0060121A`.
5. **DirectX 9.0c,** from The First Decade's disc. dxdiag's DirectDraw and Direct3D tests passed on the Voodoo3 3500.
6. **Tidying.** 1024×768 at 16-bit; DMA on; Effects off; no wallpaper, Active Desktop, sounds, screen saver or Welcome screen; `msconfig` startup down to ScanRegistry and SystemTray; `BootDelay=0` and `Logo=0` in `MSDOS.SYS`. Close every folder before the last shutdown: one left open is reopened at every boot of every game, with an error if it was on a CD.
7. **Freezing.** `qemu-img convert -f raw -O vpc -o subformat=dynamic,force_size`, then set the real geometry with `vhd-geometry.pl`: that option writes 65535/16/255 into both footer copies, and 86Box takes geometry from the footer. Confirm with `qemu-img compare -f raw -F vpc`, then make it read-only.

## 86Box behaviour worth knowing

- Given `hdd_01_fn` naming a `.vhd` that doesn't exist and `hdd_01_vhd_parent`, it makes a differencing disk. **If the parent is missing it silently makes an ordinary dynamic disk instead,** so check for footer type 4 (bytes 60–63 of the last 512).
- A differencing disk stores its parent as a full path (`W2ku`) and a bare file name (`W2ru`). With the original renamed away: side by side in a new folder, the copy ran, and Windows wrote 21,248 differing bytes to it, though its window didn't repaint for the screenshot. With the base in another folder, 86Box stopped with `parent VHD image not found`. Modification times on the copies weren't otherwise checked.
- A DVD-size image in a CD-only drive is ignored with a message. `cdrom_01_type = 86dvd` takes both.
- `86Box` ignores SIGTERM on this Mac, and `--missing` opens its window rather than printing and exiting. It writes `~/Library/Preferences/86Box` unless given `-O`. It returned exit code 1 once with nothing wrong that could be found.
- Its own fullscreen command leaves the picture small when the window is fixed-size. `vid_resize = 1` and `force_43 = 1` with the Mac's green button give 4:3 filling the height.
- The saved BIOS settings didn't reliably keep the boot order from one machine folder to another. A base boots from its disk, so this only matters during Setup.
