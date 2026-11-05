# Preparing a Windows ROM

Getting a Windows game to run under Wine is hand work done outside Ludeum, and differs in kind from game to game ([ADR 0040](../adr/0040-windows-games-are-played-in-wine-from-a-clone-of-the-roms-prepared-game.md)). What Ludeum takes is the result: a **prepared game**, a folder that Add ROM puts into `ROMs/Windows/` as it is. This says what that folder has to be, and how to try one before it's Added.

## The folder

Named for the ROM, e.g. `Age of Empires (USA)`:

```
Age of Empires (USA)/
  launch.json   the Launch file: the one file a Play opens
  Game/         the game's folder as it has to be to run (cnc-ddraw's ddraw.dll and ddraw.ini beside the exe, if it needs them)
  Prefix/       what the Launch file lays into the prefix: a registry file, codecs, fonts
  Disc/         the disc image it was prepared from, and whatever did the preparing (scripts, notes). A Play never reads it.
```

Only `launch.json` and `Game/` have to be there. A Play never runs or writes to any of it: `Game/` is cloned into the ROM's own prefix each time, and whatever the game then wrote is kept apart as its Game save.

## launch.json

Paths are written with `/` and stay inside the folder they're read from. Only `exe` is required.

```json
{
  "exe": "EMPIRES.EXE",
  "installedAt": "Games/AoE",
  "dllOverrides": { "ddraw": "n,b" },
  "locale": "en_US.UTF-8",
  "registryFile": "aoe.reg",
  "drives": [{ "letter": "d", "kind": "cdrom", "label": "AOE" }],
  "windowsFiles": { "syswow64": "syswow64", "Fonts": "Fonts" },
  "registryKeys": ["HKEY_CURRENT_USER\\Software\\Microsoft\\Games\\Age of Empires\\1.00"]
}
```

| Entry | What it says |
| --- | --- |
| `exe` | The exe to start, in `Game/`. |
| `startsIn` | The folder it starts in, in `Game/`. Left out: the exe's own. |
| `arguments` | What follows the exe on its command line. |
| `installedAt` | Where `Game/` is on the C: drive: `Games/AoE` is `C:\Games\AoE`. Left out: `Game`. It has to be where the game's registry values say it's installed, and it can't be `windows`, `users` or `Program Files` itself. |
| `dllOverrides` | DLLs taken from the game's folder ahead of Wine's own (`"n,b"`), or turned off (`""`). `mscoree` and `mshtml` are always off unless named here. |
| `locale` | `LC_ALL` for the game. A game whose English resources are tagged en-GB needs `en_GB.UTF-8` to find them. |
| `registryFile` | A `.reg` file in `Prefix/`, imported when the prefix is made: install paths, codec registrations, and the options the game starts with. |
| `drives` | Drives beside C:. Each is an empty folder that says its `kind` (`cdrom`, `hd`, `floppy`, `network`, `ramdisk`) and `label`, which is all a disc check that looks at those two needs. `letter` is D to Y. |
| `windowsFiles` | Files and folders in `Prefix/`, each with where it goes in the prefix's `windows` folder. A folder is laid over the one there. 32-bit DLLs go in `syswow64`. |
| `registryKeys` | The keys that are the game's own, which go into its Game save. Named as a 64-bit Windows does: a 32-bit game's `HKEY_LOCAL_MACHINE\Software\X` is `HKEY_LOCAL_MACHINE\Software\Wow6432Node\X`, while its `HKEY_CURRENT_USER\Software\X` is as written. |

Anything the game writes in its own folder is kept without being named. Only registry keys have to be named: leave one out and the options under it are lost whenever the prefix is made again.

## Trying it

Ludeum's Wine is `~/Library/Application Support/Ludeum/Emulators/Wine/` once it's installed from Ludeum ▸ Emulators…: Sikarugir's `WS12WineSikarugir10.0_6` with its Template's libraries. Use that build and no other, as it's the one every Windows ROM is Played on: Z's v1.5 exe starts on it and dies on plain Wine 11.0.

Work in a scratch prefix, never one under `Emulators/Wine Prefixes/`, which are Ludeum's:

```sh
W="$HOME/Library/Application Support/Ludeum/Emulators/Wine/bin"
export WINEPREFIX=/path/to/scratch/prefix WINEDLLOVERRIDES="ddraw=n,b;mscoree,mshtml=" WINEDEBUG=-all LC_ALL=en_US.UTF-8
"$W/wine" wineboot --init && "$W/wineserver" -w        # about twenty seconds
cp -cR "The Game/Game" "$WINEPREFIX/drive_c/Games/TheGame"   # a clone: the original stays as it is
(cd "$WINEPREFIX/drive_c/Games/TheGame" && "$W/wine" 'C:\Games\TheGame\GAME.EXE')
"$W/wineserver" -k                                       # ends everything in the prefix
```

- **Use `reg`, not `regedit`**, for anything unattended: `wine reg import C:\file.reg`, `wine reg export "HKEY_…" C:\file.reg /y`. `regedit` puts up a window and waits when a key isn't there.
- **A DirectDraw game needs cnc-ddraw** beside its exe (`renderer=gdi`, `fullscreen=true`, `windowed=true`, `maintas=true`): macOS has no 640x480 256-colour mode for Wine to switch to. Set `fullscreen=false` in the scratch copy while trying it, so it opens in a window.
- **A window can be captured with no Accessibility**: its id from `CGWindowListCopyWindowInfo`, then `screencapture -x -o -l<id>`.
- **Input can't be sent from the shell.** A tiny Windows exe run in the same prefix can post keys and clicks; `Disc/recipe/mkpoke.py` in the Z ROM builds one. Some screens only take a real click.
- **Wine plays no CD audio on macOS**, and can't mount a disc image as a drive.

The two worked examples are the Z and Age of Empires ROMs: each one's `Disc/How it was prepared.txt` says what it needed.

## Adding it

In Ludeum: Add ROM, pick the prepared folder, and Match it by hand (nothing knows a folder's checksum). Add ROM refuses a folder whose Launch file names something that isn't there. A later change to `launch.json` in the ROM folder is picked up at the next Play, which makes the prefix again.

The Game it's Matched to has to be on PC (Microsoft Windows), IGDB platform 6. A Game journalled on DOS is another Platform's.
