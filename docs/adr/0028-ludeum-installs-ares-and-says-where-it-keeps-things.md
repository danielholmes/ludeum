# Ludeum installs ares and says where it keeps things

Amends [0012](0012-rename-writes-no-intro-names.md) (Rename of an ares ROM moves its saves).

I want ares's Save states and Game saves in the Data folder's `Emulators/`, as DuckStation's (0024) and MesenCE's (0027) are, and the ares Ludeum plays with to be Ludeum's own. The research is [ares-under-ludeums-management.md](../research/ares-under-ludeums-management.md). ares fits more easily than either:

- **Its releases are versioned tags** with a SHA-256 in GitHub's API, and the macOS zip holds a Developer ID–signed, notarised, self-contained universal app. It needs nothing from Homebrew and no quarantine trick, and `--version` says which release it is.
- **A `settings.bml` beside `ares.app` makes it portable.** ares looks for its settings in the app's folder before Application Support, so nothing inside the bundle changes.
- **One setting says where it keeps everything.** Its Saves path takes Save states and Game saves alike, and ares makes a folder for each of its systems under it (`Mega Drive/`, `Nintendo 64/`, and `Mega CD/` for the Sega CD's shared backup RAM). So there are no clashes across Platforms to split, as MesenCE had. Left empty, as it was here, ares saves beside the ROM.
- **A Play can start from a Save state in one go**, with `--save-state <slot>`.

Two things are worse. A Save state loads only in the build that saved it: each core checks a version string, which has changed in most releases. And a state has no screenshot in it.

So:

- **Ludeum installs ares.** Install in the Emulators sheet, a Background task, fetches `ares-macos-universal.zip` for the pinned tag (`v148`) from `ares-emulator/ares`, checks it against the SHA-256 pinned in code, unpacks it without quarantine, confirms it's v148 with `--version`, and puts it in `Emulators/ares/ares.app` in the Ludeum folder. The check runs with a throwaway `settings.bml` beside the download, as ares writes one whenever it starts, so it writes none of mine. The `settings.bml` beside the installed app is the replaced copy's, else a copy of the one ares kept in `~/Library/Application Support/ares/` (my controls). ares is no longer looked up by bundle ID, and any other version is a wrong build to install again. A bump is the version and digest in code.
- **A bump costs the Save states.** The next release will refuse every state v148 saved. Game saves are kept. A bump is rare and deliberate, so nothing warns or keeps the old build.
- **Standing settings** are written into that `settings.bml` before every Play and after Install, changing only Ludeum's keys:
  - `Paths/Saves` is `Data/Emulators/ares/Saves/`.
  - `Paths/Screenshots` is `Data/Emulators/ares/Screenshots/`.
  - `General/AutoSaveMemory` is on, so Game saves are written every 30 seconds of play, not only when the game closes.

  Run-ahead stays a `--setting` for the launch (0008). ares puts that back when it quits.
- **Play is refused while any ares is open**, Ludeum's or another, as for DuckStation. ares rewrites its whole `settings.bml` when it starts and quits, and nothing stops a second copy opening.
- **Game detail** lists an ares Game's Save states, slots 1 to 9, each with when it was saved, to Play from or delete. It also lists its Game saves (`.ram`, `.eeprom`, `.flash`, `.rtc`, an N64 Controller Pak's `.pak`), each with when it was last written, which with the auto-save means when it was last played. There's no backup, restore or delete of a Game save, as for DuckStation and MesenCE. The Sega CD's backup RAM is every Sega CD Game's, so no one Game's Game save.
- **Rename moves the saves.** ares names everything by the ROM file's name without its extension (a `.zip`'s own, whatever's inside), so Rename moves a ROM's Save states, Game saves and screenshots to its new name. It's refused when a file under the new name is already there. A disc ROM's cue sheet keeps its name, as before, and so do its saves.

## Considered Options

- **Saves beside the ROMs**, ares's default: rejected. It needs no settings and is in Dropbox already, but it mixes saves into the ROM folders, and a disc ROM's states would land in its subfolder and be packed into its `.7z` by Archive.
- **Keep using `/Applications/ares.app`, with `--setting Paths/Saves=…` on every Play**: rejected. It writes nothing, but a copy of my own is what DuckStation and MesenCE are, keeps its `settings.bml` apart from any other ares, and pins the build whose Save states it keeps.
- **Warn before a bump which Games have Save states**, or keep the old build for them: rejected as tooling for a yearly event.
- **Screenshots for Save states**, taken by Ludeum: rejected. ares can't be asked for one with a state.
- **The Sega CD in this**: split out (#92). It has no BIOS on this Mac, and ares opens only `.cue` and `.chd`. What it writes is covered already.

## Consequences

- Moving over is by hand, once: the one Game save ares has made, The Curse of Illmoore Bay's `.ram` beside its ROM, moves into `Saves/Mega Drive/`. `/Applications/ares.app` and `~/Library/Application Support/ares/` are mine to delete.
- A new Mac downloads ares once, from the Emulators sheet.
- ares writes its settings and saves in place rather than under a temporary name, so a crash mid-write can leave half a file. One Mac writes the Data folder at a time, as 0024 says.
