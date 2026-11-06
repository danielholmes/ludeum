# Preparing the Windows base

The Windows base is done by hand, outside Ludeum, as Windows can't be shipped and its Setup needs a person ([ADR 0041](../adr/0041-windows-games-are-played-in-86box-from-a-game-disk-over-one-windows-base.md)). The current one is `ludeum-win98se-base.7z` in `Dropbox/games/Old Machines/Windows 98 SE/Emulator bases`. Choose that in Ludeum ▸ Emulators…. Only prepare another if it's lost, and remember a base can't be replaced once a game disk stands on it.

[windows-9x-in-86box.md](../research/windows-9x-in-86box.md) has why each step is there. An agent can't send input to an emulator's window, so Daniel clicks through Setup while the agent prepares the files and watches with screenshots.

## What an archive must hold

Choose Base… checks for these at the top of the `.7z`, and refuses anything else:

- `ludeum-win98se-base.vhd`, a dynamic VHD with footer geometry 65016/16/63. A game disk finds its parent by this name.
- `nvr/p3bf.nvr`, with `nvr/p3bf.bin` beside it: the machine's BIOS settings, so a new game doesn't stop at a CMOS prompt.

## The machine

Everything is in `EightySixBoxSettings.configuration`, and Windows has drivers for exactly this, so prepare on the same machine: `p3bf`, `pentium2_deschutes`, 256 MB, `voodoo3_3500_agp` with BIOS `voodoo3_3500_agp_ntsc`, `sb16_pnp`, `86dvd` drive, disk parameters `63, 16, 65016, 0, ide`.

## Steps

1. **Disk.** In DOSBox-X with `ver=7.1`: `IMGMAKE hdd.img -t hd -size 32000 -fat 32`, mount it and the Windows 98 SE CD, `XCOPY D:\WIN98 C:\WIN98 /I /E`, and copy in a `MSBATCH.INF` with the name, product key and `NoDriveTypeAutoRun`. Pad the image with `truncate` to 65016×16×63×512 bytes.
2. **Boot floppy.** The CD's `[BOOT]/Boot-1.44M.img`, with `CONFIG.SYS` cut to `himem.sys` and an `AUTOEXEC.BAT` running `SETUP MSBATCH.INF /IS` from `C:\WIN98` unless `C:\WINDOWS\WIN.COM` exists. Writing to it from macOS leaves `.fseventsd` and `._` files: delete them before unmounting.
3. **Setup.** Boot it in 86Box. On a new board, press F1 at the CMOS message and set the boot order to floppy first in the BIOS. Cancel any offer of a startup disk, which would overwrite the floppy. When Setup restarts, take the floppy out and boot from the disk.
4. **Display driver.** With the Voodoo3 in place, cancel Windows' own wizard, then from a CD image run `voodoo3-10700.exe` (`https://3dfx.retropc.se/downloads/voodoo3-10700.zip`) and `C:\WINDOWS\TEMP\SETUP.EXE`. Point its file prompts at `C:\WINDOWS\TEMP\DRIVER9X`.
5. **DirectX 9.0c.** `directx/dxsetup.exe` on The First Decade's disc. Check dxdiag's DirectDraw and Direct3D tests.
6. **Tidy.** 1024×768 at 16-bit. DMA on in Device Manager, for the disk and the DVD drive. Effects off; no wallpaper, Active Desktop, sounds, screen saver or Welcome screen. `msconfig` startup down to ScanRegistry and SystemTray. `BootDelay=0` and `Logo=0` in `MSDOS.SYS`.
7. **Last shutdown.** Close every window first: one left open reopens at every boot of every game. Then Start ▸ Shut Down.
8. **Freeze.** `qemu-img convert -f raw -O vpc -o subformat=dynamic,force_size hdd.img ludeum-win98se-base.vhd`. That option writes 65535/16/255 as the geometry, which 86Box would believe, so set the real one in both footer copies and redo their checksums. Confirm with `qemu-img compare -f raw -F vpc`.
9. **Archive.** `7zz a` the VHD and `nvr` folder at the archive's top, and check the VHD's checksum out of the archive.

## Getting a game in

A Windows ROM is its disc. A game that comes as files, or out of a compilation like The First Decade (`unshield -g "Red Alert 2" -d <dir> x data1.hdr`), is made into an ISO first (`hdiutil makehybrid -iso -joliet`), Added as a ROM, then copied to `C:\` in Windows at its first Play. Files from a CD arrive read-only, so run `command /c attrib -r C:\GAME\*.* /s` or its options won't save.

What a game needs to start isn't Ludeum's to know, so note it on the Game: Red Alert 2 runs from `RA2.EXE`, not `GAME.EXE`; Renegade needs `WWCONFIG.EXE` first; Z's CD check wants the volume label `Z95VOLUME`.
