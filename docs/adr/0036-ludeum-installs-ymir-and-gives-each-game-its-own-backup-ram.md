# Ludeum installs Ymir and gives each Game its own backup RAM

Amends [0021](0021-duckstation-settings-go-in-its-per-game-file-named-by-the-discs-serial.md) (a Saturn ROM's Serials are read too).

I want Ymir's Save states and Game saves in the Data folder's `Emulators/`, as the other Emulators' are, and the Ymir Ludeum plays with to be Ludeum's own. The research is [ymir-under-ludeums-management.md](../research/ymir-under-ludeums-management.md). On where things go, Ymir fits more simply than any so far:

- **`-p <folder>` gives it a whole profile for that launch**, with nothing in or beside its bundle to mark it, and no first-run dialog.
- **Every folder it keeps is an absolute path** in `[General.PathOverrides]` of the `Ymir.toml` at the root of that profile. It keeps its settings in memory and rewrites the whole file on quitting.
- **Save states are keyed by the disc**, a hash of its header sectors, in `savestates/<hash>/<slot>.savestate`, with a `meta.txt` beside them naming its Product Number. So they follow a ROM through Rename, Archive and a change of image form, and a newer Ymir loads every older state.
- **One setting gives each Game its own backup RAM**, named from the disc's header as `bup-int-<Title> [<Product Number>].bin`.

Three things are worse:

- **Nothing can start it from a Save state**: no flag, setting or file. A state is applied only by Ymir's hotkey or menu once the Game is running, and it makes no state of its own, so there's no Resume either. It's the first Emulator here with no way to do what ADR 0034 relies on.
- **Backup RAM is a memory-mapped file**, written by the system rather than by Ymir, with no flush in Ymir's code, and the Data folder is in Dropbox. Ymir also silently formats an image of the wrong size or with the wrong header.
- **It has one setting for what's in its first port**, for every Game, and three of my five Saturn ROMs are light gun games I play with the mouse.

So:

- **Ludeum installs Ymir.** Install in the Emulators sheet, a Background task, fetches `ymir-macos-arm64-v0.4.1.zip` from `ymir-emu/Ymir`, the most recent release, checks it against the SHA-256 pinned in code, unpacks it without quarantine, as it's ad-hoc signed and not notarised, confirms its version from its `Info.plist`, without running it, and puts it in `Emulators/Ymir/Ymir.app` in the Ludeum folder, with the zip's `gamecontrollerdb.txt` beside it. Any other version is a wrong build to install again. A bump is the version and digest in code, and keeps every Save state.
- **Standing settings** are written into `Emulators/Ymir/Ymir.toml` before every Play and after Install, changing only Ludeum's keys: `[General.PathOverrides]` `SaveStates`, `BackupMemory`, `IPLROMImages`, `ROMCartImages`, `ExportedBackups` and `Screenshots` as `Data/Emulators/Ymir/Save States`, `Backup Memory`, `BIOS`, `Cartridge ROMs`, `Exported Saves` and `Screenshots`; `[General] CheckForUpdates` off; and `[System] InternalBackupRAMPerGame` on. A new file says `ConfigVersion = 6`, as Ymir reads a file without one as older than any and skips its controller binds. The file that says the update-check question has been answered is made too, so a new profile doesn't open by asking. The rest of its profile (its GUI state, the console's language and clock) stays beside the app.
- **Each Game has its own backup RAM**, so a Game's saves are its own to show, as a shared image can't be split: a save's name is whatever the game chose (`HOUSEOFDEAD`). The cost is that a game can't read another game's save, which a few Saturn games do.
- **A Play sets its first port from the Disc.** A Disc whose header lists the Virtua Gun gets it; one that doesn't goes back to the Control Pad, if it was left on the gun. Any other peripheral chosen in Ymir stays. A Disc whose header can't be read (a `.chd`, or one Dropbox keeps online only) leaves it as it is. A left click then takes the mouse: left is the trigger, right reloads.
- **Play is refused** while any Ymir is open, as there's no single-instance guard and it writes its whole settings file on quitting, while it's being installed, until it's installed, and until there's a Saturn BIOS in `Data/Emulators/Ymir/BIOS`. Ymir can't boot without one and looks at no file there but one of 512 KiB.
- **Saturn Serials are read off the disc's first sector**, its Product Number, as `SaturnDisc` reads it, at the next Import or by Add ROM. They find the Game's Save states, through each folder's `meta.txt`, and its backup RAM, by the name of its image.
- **Game detail** lists a Saturn Game's Save states by slot, with when each was saved and the keys that load it in Ymir (`Ctrl+1` to `Ctrl+9`, `Ctrl+0` for slot 10), to delete, with the state it replaced. It lists its Game saves, the saves inside its backup RAM, each with what the game called it and when the game wrote it. There's no Play from a Save state, no Resume and no pictures, as a state holds none, and no backup, restore or delete of a Game save, as for the other Emulators.
- **The Saturn ROM folder reads what Ymir opens**: `.chd`, `.cue` and `.iso`. Ymir opens no playlist, and a Play given one would open with no disc and no message, nor a `.bin` without its cue sheet. A multi-disc ROM's folder is one ROM, opening at Disc 1's cue sheet, and its Disc is changed in Ymir.

## Considered Options

- **Start from a state by copying it into slot 1**, for the player to press `F3`: rejected. It overwrites slot 1 and still needs the keypress.
- **Send the key from Ludeum**: rejected. It needs Accessibility permission and timing against the boot.
- **Carry a patched build**: rejected. Ludeum would build and sign Ymir itself, rather than install a release. #96 is to look again, should Ymir gain a way. Upstream refuses AI-assisted work of any kind, so anything sent to it has to be mine.
- **A nightly as the pin**: not possible. Each replaces the last on one moving tag, so its digest lasts a night.
- **The whole profile in the Data folder**, one flag and no overrides: rejected. It puts GUI state and a settings file Ymir rewrites into Dropbox.
- **A marker in the bundle**, a `Ymir.toml` in `Contents/MacOS`: rejected. It writes inside an ad-hoc seal, and `-p` needs nothing.
- **Shared backup RAM**, as the console had: rejected. It can't be shown by Game, which is what #77 asks for.
- **A setting per Game for the light gun**, in the journal: rejected. The Disc already says, and it would be a column and a control to agree with it.
- **Matching state folders by computing the disc's hash**: rejected. It needs XXH3-128 and every sector read, where `meta.txt` says the Product Number.
- **A Disc menu for a multi-disc ROM, by keeping its playlist**: not for now. No Saturn ROM here is multi-disc.

## Consequences

- Whether a memory-mapped image on the Dropbox path is synced isn't known. It's the first thing to check: a real save, with the file and Dropbox's copy looked at during and after a Play. If it fails, backup RAM can't stay as it is.
- By hand, once: House of the Dead's `- 2.bkr`, from the Data folder's archive of OpenEmu's saves, goes to `Backup Memory/games/bup-int-THE HOUSE OF THE DEAD [MK-81802].bin`, as it's already Ymir's format, and `mpr-17933.bin` and `sega_101.bin` go in `BIOS`. `/Applications/ymir.app` and its old profile hold nothing and are mine to delete. `Data/Emulators/Ymir` is marked available offline in Dropbox, as Ymir reads every state of a disc on loading it and maps its backup RAM.
- The next Import reads each Saturn ROM's Serial, so Game detail can list its saves. A multi-disc ROM has only Disc 1's read, as its folder holds no playlist naming the others. A `.chd` isn't read yet, and a Saturn ROM with no region tag waits on its Serial before Hasheous is asked, as a PlayStation one does.
- Ymir writes its states, settings and clock in place, so a crash mid-write can leave half a file. A state's `-1` holds what the slot held before it. One Mac writes the Data folder at a time, as 0024 says.
- Rehearsed on 2026-11-04 with the real release, installed by this code into a scratch folder and booted on House of the Dead: Ymir kept every key Ludeum wrote through its own rewrite of the file, took `mpr-17933.bin` for a USA disc, and wrote `meta.txt` and the image under the names Ludeum looks for. Nothing was played, so the gun, a save and a state are untested, and so is `sega_101.bin`, with no Japanese disc here.
