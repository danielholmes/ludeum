# OpenEmu's PlayStation saves into DuckStation's memory cards

Researched 2026-10-27 for issue #76. The question: are the PlayStation battery saves that `migrate-openemu` archived from OpenEmu compatible with the memory cards Ludeum now keeps for DuckStation (`Emulators/DuckStation/Memory Cards/<Disc 1's Serial>.mcd` in the Data folder, ADR 0023)? If not, can they be converted, and what would Ludeum need to do it?

OpenEmu's PlayStation core is its Mednafen core, cited at OpenEmu/Mednafen-Core `a02bb7b1ad8a79ca0abf3a888ef51c0e3c45a4bd` (master, last pushed 2024-04-09), which vendors Mednafen's source under `mednafen/`. DuckStation is cited at the installed build 12442 (`0.1-12442-gdd4a0eb77`, commit `dd4a0eb779296a525f8b10b6d9a45911ad6d088f`), as in `duckstation-io-speedups.md`. "On this Mac" was read without changing anything; the cards were parsed by a throwaway script in the session scratchpad.

## Outcome (2026-10-28)

The 13 games' saves were brought across by hand rather than by a command, each tested in DuckStation (Buzz Lightyear and Toy Story Racer weren't), and Gex 3's and Mat Hoffman's were deleted. ADR 0024 superseded ADR 0023 the same day, so the targets below are no longer right: a card is now `Emulators/DuckStation/Memory Cards/<DuckStation's title for the disc>_1.mcd`, the title from its game database (`Bugs Bunny - Lost in Time (USA) (En,Fr,Es)_1.mcd`), a disc set's save name for every Disc in it (`Gran Turismo 2 (Europe) (En,Fr,De,Es,It)_1.mcd`), and nothing is copied in at first Play. The archived and OpenEmu copies of those games' cards, and OpenEmu's backups of them in `BIOS/b/`, have gone. The rest below is as researched.

## Answer

**Yes, they're compatible.** A Mednafen `.mcr` and a DuckStation `.mcd` are the same thing: the raw 128 KiB card image, `MC` header, directory frames, 15 blocks. There's nothing to convert. **Bringing one across is a copy and a rename**: OpenEmu's `<ROM name>.<md5>.0.mcr` becomes `Emulators/DuckStation/Memory Cards/<Disc 1's Serial>.mcd`. DuckStation reads a card file as raw bytes and checks only its size. Its own importer treats `.mcr` and `.mcd` as one format.

- **Only card 0 matters.** Mednafen's `.0.mcr` is the card in port 1, the port DuckStation's card 1 (the only one Ludeum points) is in. Every archived `.1`, `.2`, `.3` and `.4` card is blank.
- **13 Ludeum ROMs have saves to bring across.** Each has one Card save, whose name gives the same Serial as the ROM's Disc 1. Every other archived card (51 of 67) is blank.
- **No conflicts.** None of the 13 targets is in the Data folder yet, and DuckStation has no card of its own for any of them. The only card in the Data folder now (`SLUS-00551.mcd`, Resident Evil: Director's Cut) matches an archived card that's blank. So today it's 13 plain copies, with no merge.
- **When both sides have saves, it's a merge of Card saves, not a copy.** That doesn't happen today, but a general tool would need it. DuckStation's Memory Card Editor can do the merge by hand: open both cards, Copy File each save across, Save. It refuses a save whose name is already on the target card, or one that doesn't fit. Its "Import Entire Memory Card…" replaces the whole card, so it can't merge.
- **What Ludeum needs:** a one-off `ludeum-import` command, not an Import step. Put each card in place before the ROM's first Play. Ludeum's first-Play copy-in then leaves it alone, since it copies DuckStation's card only when the Data folder has none.

## How OpenEmu's Mednafen core names and writes cards

- **Folder.** The core sets Mednafen's `filesys.path_sav` to OpenEmu's battery saves folder (`<Application Support>/OpenEmu/Mednafen/Battery Saves/`). It sets the base directory to OpenEmu's BIOS folder (`MDFNI_InitFinalize(biosPath)`). `MednafenGameCore.mm` `-initializeMednafen`, lines 106–119. https://github.com/OpenEmu/Mednafen-Core/blob/a02bb7b1ad8a79ca0abf3a888ef51c0e3c45a4bd/MednafenGameCore.mm#L106-L119
- **Name.** `filesys.fname_sav` defaults to `%f.%M%x`. `mednafen/mednafen.cpp` line 128. https://github.com/OpenEmu/Mednafen-Core/blob/a02bb7b1ad8a79ca0abf3a888ef51c0e3c45a4bd/mednafen/mednafen.cpp#L128
  - `%f` is the loaded file's base name.
  - `%M` is empty if a file without it already exists, else the game's MD5 and a period.
  - `%x` is the caller's extension.
  - `MDFN_MakeFName`, `mednafen/general.cpp` lines 120–219, the `%M` fallback at 211–218. https://github.com/OpenEmu/Mednafen-Core/blob/a02bb7b1ad8a79ca0abf3a888ef51c0e3c45a4bd/mednafen/general.cpp#L120-L219
- **The MD5 isn't the ROM file's.** For a CD it's a "layout MD5" of the disc's TOC (first and last track, each track's LBA and control bit). So it never equals Ludeum's `rom.md5`, and matching has to go by name or Serial. `CalcDiscsLayoutMD5`, `mednafen/mednafen.cpp` lines 833–859, used at 1222–1225. https://github.com/OpenEmu/Mednafen-Core/blob/a02bb7b1ad8a79ca0abf3a888ef51c0e3c45a4bd/mednafen/mednafen.cpp#L833-L859
- **One file per virtual port.** The PlayStation module loads and saves eight cards, `"%d.mcr"` for i = 0…7. So the files are `<name>.<md5>.0.mcr` to `.7.mcr`. A dirty card is written about two seconds after the game's last write to it, and every card is written at close. `mednafen/psx/psx.cpp` lines 1195–1228 (save on idle), 1810–1817 (load), 2163–2170 (close). https://github.com/OpenEmu/Mednafen-Core/blob/a02bb7b1ad8a79ca0abf3a888ef51c0e3c45a4bd/mednafen/psx/psx.cpp#L1195-L1228
- **Which port is which.** With no multitap, virtual port 0 is physical port 1 and virtual port 1 is physical port 2. With a multitap on port 1 only, ports 0–3 are the multitap's A–D and port 4 is physical port 2's card. That's why the multitap games (CTR, Crash Bash, FIFA 98, Jonah Lomu, Overboard!) have `.0` and `.4`. In both cases `.0` is port 1's card. `EP_to_MP`, `EP_to_SP`, `FrontIO::MapDevicesToPorts`, `mednafen/psx/frontio.cpp` lines 197–255. https://github.com/OpenEmu/Mednafen-Core/blob/a02bb7b1ad8a79ca0abf3a888ef51c0e3c45a4bd/mednafen/psx/frontio.cpp#L197-L255
  - OpenEmu turns the multitap on for the games in its own list, and turns port 2's card off for others. `MednafenGameCore.mm` lines 2963–2982. https://github.com/OpenEmu/Mednafen-Core/blob/a02bb7b1ad8a79ca0abf3a888ef51c0e3c45a4bd/MednafenGameCore.mm#L2963-L2982
- **Format.** Raw bytes, exactly the card's size. The card's memory is `uint8 card_data[1 << 17]`, 128 KiB. A fresh card is formatted with `MC` and free directory frames (`0xA0`, next block `0xFFFF`). `mednafen/psx/input/memcard.cpp` lines 63 and 94–117. https://github.com/OpenEmu/Mednafen-Core/blob/a02bb7b1ad8a79ca0abf3a888ef51c0e3c45a4bd/mednafen/psx/input/memcard.cpp#L94-L117
  - `FrontIO::LoadMemcard` refuses a file of any other size. `FrontIO::SaveMemcard` writes the buffer as it is, with no header or compression. `mednafen/psx/frontio.cpp` lines 847–889. https://github.com/OpenEmu/Mednafen-Core/blob/a02bb7b1ad8a79ca0abf3a888ef51c0e3c45a4bd/mednafen/psx/frontio.cpp#L847-L889
- **Backups in `OpenEmu/BIOS/b/`.** These explain the "unexplained `.mcr` files" that #58 found. Before loading each card, Mednafen keeps up to five gzipped earlier versions, plus a one-byte counter `C.<n>.mcr`. They go in `filesys.path_savbackup` (default `b`, relative to the base directory, which OpenEmu set to its BIOS folder), named `%f.%m%z%p.%x`, i.e. `b/<name>.<md5>/<0–4>.<n>.mcr`. `MDFN_BackupSavFile(5, ext)`, `mednafen/file.cpp` lines 298–347, called at `psx.cpp` 1815; settings at `mednafen.cpp` lines 118 and 129. https://github.com/OpenEmu/Mednafen-Core/blob/a02bb7b1ad8a79ca0abf3a888ef51c0e3c45a4bd/mednafen/file.cpp#L298-L347
  - I decompressed one (`Spyro the Dragon…/4.0.mcr`). It's an ordinary 128 KiB card holding an older Spyro save. These are only older versions, and `migrate-openemu` didn't archive them (it copies `<Core>/Battery Saves/` only, `OpenEmuMigration.batterySaveFolders`, `Sources/LudeumCore/Migration/OpenEmuMigration.swift` ~165–182).

## What DuckStation reads

- **Size only.** At boot DuckStation opens card 1's path with `MemoryCard::Open`. A missing file gives a freshly formatted card. A file that fails `MemoryCardImage::LoadFromFile` gives a formatted card in memory, the OSD message "Memory Card 1 could not be read … The memory card will NOT be saved", and its path cleared, so nothing the game saves is kept. `src/core/memory_card.cpp` lines 336–361. https://github.com/stenzek/duckstation/blob/dd4a0eb779296a525f8b10b6d9a45911ad6d088f/src/core/memory_card.cpp#L336-L361
  - `LoadFromFile` checks only that the file is exactly `DATA_SIZE` (128 × 1024) bytes, then reads it raw. It ignores the extension and doesn't check the `MC` header. `src/core/memory_card_image.cpp` lines 100–124; `DATA_SIZE`, `BLOCK_SIZE = 8192`, `FRAME_SIZE = 128` in `memory_card_image.h` lines 17–22. https://github.com/stenzek/duckstation/blob/dd4a0eb779296a525f8b10b6d9a45911ad6d088f/src/core/memory_card_image.cpp#L100-L124
- **Writes.** DuckStation writes the card whole with `FileSystem::WriteAtomicRenamedFile`. `SaveToFile`, `memory_card_image.cpp` lines 126–138.
- **`ImportCard`, the editor's "Import Entire Memory Card…".** It goes by extension:
  - `mcd`, `mcr`, `mc`, `srm`, `psm`, `ps` and `ddf` are all raw cards (`ImportCardMCD`: exactly 128 KiB, `memcpy`).
  - `gme` is DexDrive (a header, then the card; a bare 128 KiB `.gme` is taken as raw).
  - `mem` and `vgs` are VGS (a 64-byte header).
  - `psx` is a 256-byte header.
  - Anything else is "Unknown extension". `memory_card_image.cpp` lines 512–523 and 627–660. https://github.com/stenzek/duckstation/blob/dd4a0eb779296a525f8b10b6d9a45911ad6d088f/src/core/memory_card_image.cpp#L627-L660
  - So DuckStation itself treats Mednafen's `.mcr` as the same format as its `.mcd`.
- **Memory Card Editor.** Two panes, each "New Card…" or "Open Card…" from any path (`MemoryCardEditorWindow::newCard` and `openCard`, `src/duckstation-qt/memorycardeditorwindow.cpp` lines 520–580). The card in the Data folder isn't in the editor's list (ADR 0023), but Open Card… can reach it.
  - **Copy File** reads a Card save off one card and writes it into the other's free blocks (`MemoryCardImage::ReadFile` and `WriteFile`). It refuses if the target already has a save of that name ("Please delete this file from the destination memory card before copying"), or if there aren't enough free blocks. `doCopyFile`, lines 615–670. https://github.com/stenzek/duckstation/blob/dd4a0eb779296a525f8b10b6d9a45911ad6d088f/src/duckstation-qt/memorycardeditorwindow.cpp#L615-L670
  - **Import Entire Memory Card…** replaces the pane's whole card (`card->data = *temp`), so it's no use for merging. `importCard`, lines 852–880.

## Copy, transform or merge

- **No byte transform.** I compared both sides directly. Every archived card is 131,072 bytes and starts `MC`. All 16 directory frames' XOR checksums are valid, and the layout is the one `Sources/LudeumCore/MemoryCards.swift` `MemoryCard.saves(in:)` parses (state `0x51` for a save's first block, `SC` title header). DuckStation's own cards here have the same layout.
  - The archived blank cards come in two variants that differ only in frame 63, the write-test frame the BIOS writes to (`cmp`). Both are just empty.
- **Copy and rename** when the target has no card yet, and DuckStation has none of its own (or only a blank one). The source is `<ROM name>.<md5>.0.mcr` and the target is `DuckStationMemoryCards.card(of: <Disc 1's Serial>)`.
- **Merge** when the target, or DuckStation's own card that the first Play would copy in, already has Card saves. Card 1 is the ROM's only card in Ludeum (ADR 0023), and Ludeum leaves card 2 as DuckStation has it. So two cards can't both be kept, and the saves must go onto one. Merging means copying each Card save's blocks into the target's free blocks, then rewriting the directory frames, next-block links and checksums. That's what DuckStation's `WriteFile` does. A save already on the target under the same file name is a real conflict: keep the newer card's (by modification time), or ask.

## What Ludeum would need

A **one-off command**, `ludeum-import import-openemu-memory-cards` (name illustrative), shaped like `migrate-openemu`: a `--dry-run` that prints the plan, then a run. The archive is a fixed, finished set: OpenEmu isn't used any more, so no new archived saves will appear. An Import step would re-check the same 67 files on every Import forever, and would need to remember what it had already brought across, so a save deleted in DuckStation didn't come back. A one-off command is enough.

1. **Read** each `Mednafen/Battery Saves/*.mcr` in `LudeumFolder.batterySaveArchive`. Keep port 0 only (`.0.mcr`, or `.0 - N.mcr`, see below). Skip a card `MemoryCard.saves(in:)` can't read or finds no saves on.
2. **Match** each card to a PlayStation ROM (platformId 7). Match by the file's base name (the part before `.<32 hex>.`) against `rom.name` or `rom.folderName`. Confirm by the Card saves' Serials (`BASLUS-01144…` gives `SLUS-01144`) against `rom.serials`. If those disagree, or several ROMs share the Serial, report it rather than guess.
   - A save's Serial can be a later Disc's: Gran Turismo 2's save was made from Disc 2 but names `SCES-02380`, Disc 1's. So match it against any of the ROM's Serials, and always write to Disc 1's card.
3. **Where there are duplicates** (`.0 - 1.mcr` and `.0 - 2.mcr`), take the newest by modification time. Here that's always `- 1`, which is byte-identical to the card OpenEmu still has.
4. **Target** `DuckStationMemoryCards.card(of: serials[0])`. Before writing, check DuckStation's own card too (`duckStationsCard(serial:rom:resources:)`). A Play would otherwise have copied that card in, and once a card is in the Data folder, `copyIn` silently skips DuckStation's (`MemoryCards.swift` `copyIn`, ~116–122; called from `DuckStationSettings.arguments`, `Sources/LudeumCore/Emulators.swift` ~118–127).
   - Neither has saves: copy with `FileManager.copyIntoDataFolder` (partial file, then rename, keeping the modification time, so Game detail's "saved" shows when it was last saved in OpenEmu).
   - Either has saves: merge the archive's Card saves into it (port `ReadFile` and `WriteFile`), or report it for a merge by hand in DuckStation's editor. Never overwrite.
5. **Leave the archive as it is**, as ADR 0009 keeps it.

Risks:
- **DuckStation running the game.** It holds the card in memory and writes it whole, which would overwrite a card put in during the session. Refuse while DuckStation is running, or say to quit it.
- **A wrong-size file at the target.** DuckStation plays with a blank card it never saves ("will NOT be saved"). Write only cards that are exactly 128 KiB and start `MC`.
- **The wrong duplicate.** `- 1` and `- 2` hold different versions of the same save, and only one can be kept. The newest is right here, but a dry run should show both dates.
- **Saves on a card other than port 0.** A multitap game's `.4` (port 2) or any `.1` card with saves would have to be merged onto card 1, since Ludeum keeps one card per ROM. None has saves today.
- **Region and Serial.** A disc reads only its own region's and game's saves. A card from another dump of the game (e.g. `Gran Turismo 2 (Simulation Mode) (v1.2)`, a US disc) wouldn't be seen by the European ROM. It's blank anyway.
- **The Data folder missing.** It's a Dropbox symlink. Refuse, as Play does (`LudeumFolder.checkData`).

## On this Mac

Read 2026-10-27, read-only. Ludeum's Data folder (`~/Library/Application Support/Ludeum/Data`, linked to `~/Dropbox/games/Ludeum`) has `OpenEmu Battery Saves archive/Mednafen/Battery Saves/` with 67 `.mcr` files for 31 games. The rest of that folder is Saturn's `.bkr`, `.bcr` and `.smpc`.

- **51 cards are blank** (no directory entry in use).
- **16 hold one Card save each**, for 13 games: three games have two copies of `.0`, `.0 - 1.mcr` and `.0 - 2.mcr`.
  - **Where the duplicates came from is unexplained.** The archive's Mednafen folder was changed at 2026-10-06 17:28, after the 16:59 migration (`Backups/2026-10-06T1659-before-migration.*`). It holds far more than the 11 files OpenEmu's own `Mednafen/Battery Saves/` has now. Each `- 1` is byte-identical (MD5) to OpenEmu's current `.0.mcr`, and each `- 2` is older.
- **Targets.** The Data folder's `Emulators/DuckStation/Memory Cards/` has only `SLUS-00551.mcd`. DuckStation's `memcards/` has only `Metal Gear Solid (USA)_1.mcd` (blank) and `Resident Evil - Director's Cut (USA)_1.mcd` (byte-identical to `SLUS-00551.mcd`). DuckStation's `gamesettings/` has only `SLUS-00551.ini`, so none of the 13 has been Played in DuckStation.

Cards with saves. Each target is in the Data folder's `Emulators/DuckStation/Memory Cards/`; none exists, and DuckStation has no card of its own for any.

| Archived card (`.0`) | Saved | Card save (file name, title, blocks) | Ludeum ROM (id) | Disc 1 Serial | Target |
|---|---|---|---|---|---|
| `Bugs Bunny & Taz - Time Busters…0 - 1.mcr` (newer; `- 2` is 2024-03-31) | 2025-03-30 | `BASLUS-01144 B & T`, "Bugs & Taz: Time Busters", 1 | Bugs Bunny & Taz - Time Busters (1083) | SLUS-01144 | `SLUS-01144.mcd` |
| `Bugs Bunny - Lost in Time…0.mcr` | 2023-05-27 | `BASLUS-00838 BBLIT`, "Bugs Bunny Lost in Time", 1 | Bugs Bunny - Lost in Time (965) | SLUS-00838 | `SLUS-00838.mcd` |
| `Crash Bandicoot 2 - Cortex Strikes Back…0.mcr` | 2022-05-01 | `BASCUS-9415400355531`, "Crash Bandicoot 2", 1 | Crash Bandicoot 2 - Cortex Strikes Back (914) | SCUS-94154 | `SCUS-94154.mcd` |
| `Crash Bandicoot…0.mcr` | 2019-08-11 | `BASCUS-9490000748929`, "Crash (2%)", 1 | Crash Bandicoot (1) | SCUS-94900 | `SCUS-94900.mcd` |
| `Crash Bash…0.mcr` | 2023-01-28 | `BASCUS-94570`, "CRASH BASH %016 %000 %000 %000", 1 | Crash Bash (917) | SCUS-94570 | `SCUS-94570.mcd` |
| `Disney-Pixar's Buzz Lightyear of Star Command…0.mcr` | 2023-04-15 | `BASLUS-0119203:00`, "BUZZ LIGHTYEAR:MEDALS03:00", 1 | Disney-Pixar's Buzz Lightyear of Star Command (1109) | SLUS-01192 | `SLUS-01192.mcd` |
| `Disney-Pixar's Toy Story Racer…0.mcr` | 2022-11-06 | `BASLUS-01214`, "TOY STORY RACER", 1 | Disney-Pixar's Toy Story Racer (1108) | SLUS-01214 | `SLUS-01214.mcd` |
| `Gex 3 - Deep Cover Gecko (USA)…0.mcr` | 2022-05-01 | `BASLUS-00806`, "Gex 3: Deep Cover Gecko", 1 | Gex 3 - Deep Cover Gecko (USA) (460) | SLUS-00806 | `SLUS-00806.mcd` |
| `Gran Turismo 2 (Europe) (En,Fr,De,Es,It) (Disc 2) (Gran Turismo Mode)…0 - 1.mcr` (newer; `- 2` is 2023-11-29) | 2026-03-27 | `BESCES-02380GAME`, "GT2 Game File", 4 | Gran Turismo 2 (Europe) (1121), Discs SCES-02380, SCES-12380 | SCES-02380 | `SCES-02380.mcd` |
| `Mat Hoffman's Pro BMX…0.mcr` | 2019-05-01 | `BASLUS-01113MHPBG0J`, "MHPB CAREER ー NIKHIL D", 1 | Mat Hoffman's Pro BMX (935) | SLUS-01113 | `SLUS-01113.mcd` |
| `Metal Gear Solid - VR Missions…0.mcr` | 2019-05-01 | `BASLUS-00957VDF@@@@A`, "MGS_VR VR TRAINING 21.3%", 1 | Metal Gear Solid - VR Missions (922) | SLUS-00957 | `SLUS-00957.mcd` |
| `Spyro the Dragon…0 - 1.mcr` (newer; `- 2` is 2024-06-22) | 2026-09-19 | `BASCUS-94228SPYRO`, "SPYRO THE DRAGON", 1 | Spyro the Dragon (1070) | SCUS-94228 | `SCUS-94228.mcd` |
| `Tony Hawks Pro Skater…0.mcr` | 2024-02-21 | `BASLUS-00860THPSG2L`, "THPS CAREER ー CAREER A", 1 | Tony Hawks Pro Skater (931) | SLUS-00860 | `SLUS-00860.mcd` |

Each Card save's Serial matches its ROM's Disc 1 Serial, and each card's name matches the ROM's `name` once the `.<md5>.<n>.mcr` is taken off. The Gran Turismo 2 card was saved from Disc 2 and is the one exception to matching by name, since the ROM is one two-disc ROM.

Archived cards that are blank on every port, so there's nothing to bring across:
- Broken Sword, CTR, Dave Mirra Freestyle BMX: Maximum Remix, Toy Story 2, Duke Nukem: Time to Kill, FIFA: Road to World Cup 98, Jonah Lomu Rugby, Looney Tunes Racing, Metal Slug X, Overboard!, Resident Evil: Director's Cut, Star Wars: Jedi Power Battles, Time Crisis, Tom and Jerry in House Trap, Tomb Raider, Tony Hawk's Pro Skater 2.
- Gran Turismo 2 (Simulation Mode) (v1.2) and Scooby-Doo and the Cyber Chase, which have no Ludeum ROM.

Of #76's important games:
- Gran Turismo 2, Spyro, Bugs Bunny: Lost in Time, Bugs Bunny & Taz: Time Busters and THPS (Tony Hawk's Pro Skater) all have a save to bring across.
- Tony Hawk's Pro Skater 2's archived cards are blank.
- Metal Gear Solid has no archived card at all. `OpenEmu/BIOS/b/Metal Gear Solid…/` holds only empty backup counters.

## Not verified

- I didn't boot DuckStation with a copied card. Its compatibility rests on the source above and on both sides parsing the same.
- I didn't trace how DuckStation places cards when a game enables its multitap, i.e. whether card 1 is still multitap 1A. The multitap games' saves here are all on `.0` anyway (Crash Bash's only).
