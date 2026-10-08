# Ludeum

A personal record of the games I play across every platform (retro via per-Platform emulators, PC, Xbox, and others): what I thought of them, when I played them, and what I want to play next. The journal, not any emulator library, is the source of truth for this data.

## Language

### Games

**Game**:
A title as played on one Platform. Regional releases, revisions and fan translations of that title on the same Platform are the same Game. A port to a different Platform is a different Game, and so is an enhanced re-release that IGDB lists separately (e.g. Link's Awakening vs Link's Awakening DX).
_Avoid_: Title, entry, ROM

**Platform**:
The hardware or ecosystem a Game was made for, e.g. SNES, Game Boy, PC, Xbox 360. It is never the device or service the Game was actually played on. The Platforms are exactly IGDB's platforms. Every Game has one, including a Game with no IGDB link.
_Avoid_: System, console

**Version**:
One specific edition of a Game, e.g. a region, a revision, or a fan translation ("Europe Rev 1", "Japan + English translation").
_Avoid_: Release, revision, dump

**ROM**:
A game file in a ROM folder, and a Copy of the Game it's Matched to. A ROM identifies a Version of a Game, and is linked to its Game automatically or by hand; its Copy details (Regions, where and when it was acquired) belong to the ROM and go with it through any change of Match, so an unmatched ROM is a Copy of no Game. Removing or replacing the file loses nothing: the ROM is kept as missing, with its details, until I put a file back or Delete it. Deleting a ROM is the only way it leaves the journal: by hand (or by Keeping only another Version of its Game), which sends any files it still has to the Trash; the move from OpenEmu, and the recovery of its renamed files after it, also deleted a ROM found to duplicate a playlist's disc. Nothing deletes a ROM on its own, and a Game can't be deleted while it has any Copy.
_Avoid_: File, image

**ROM folder**:
The folder of one Platform's ROMs, which the journal reads directly. Every Platform with ROMs has exactly one, named for the Platform, in the Data folder's `ROMs/`, and the folder alone gives a ROM its Platform. A ROM is known by its name within its Platform's folder: a file's without the extension, or a subfolder's when the subfolder holds the game (one image, a cue sheet with its tracks, or a playlist with its Discs, alongside anything else). Disc Platforms' ROMs (PS1, Sega CD, Saturn, PC Engine CD) each have a subfolder. So Unarchiving `Okami (USA).7z` into `Okami (USA)/`, or Archiving it again, is the same ROM changing state, and so is Compacting `Tetris (World).gb` into `Tetris (World).7z`. A ROM is never kept in both forms at once (a Compacted `.7z` alone is one form): when it is, it waits in the Review queue.
_Avoid_: Library folder, watch folder

**Archived ROM**:
A ROM that is still in its library but packed in a form its Platform's Emulator can't open, so it can't be Played until I Unarchive it (or, on N64 and Mega Drive, Compact it). It is present, not missing. Whether a ROM is archived depends on the Emulator: a `.7z` that one Emulator opens directly is a Playable ROM there.
_Avoid_: Compressed, needs extraction (that's the fix, not the state)

**Playable ROM**:
A present ROM that isn't Archived. Every present ROM is either Playable or Archived.
_Avoid_: Active, unarchived, ordinary ROM

**Archive / Unarchive**:
Packing a ROM folder ROM into a `.7z`, or unpacking all of it into a folder named after the ROM so it can be Played (a PSP, Vita, GameCube or Wii ROM, always one file, unpacks to that file, named after the ROM). Either way only one copy is kept: the file it replaces goes to the Trash once the new one checks out. Only PS2, PSP, Vita, GameCube, Wii and the Disc Platforms' (PS1, Sega CD, Saturn, PC Engine CD) ROMs can be Archived or Unarchived so far.
_Avoid_: Extract, compress, decompress

**Compact**:
Packing a ROM into the archive its Platform's Emulator opens directly, so it takes less room and still Plays: a `.7z`, or a `.zip` on N64 and Mega Drive, whose Emulator (ares) can't open a `.7z`. An Archived `.7z` there is repacked as a `.zip`. Only one copy is kept, as with Archive. Only Platforms whose Emulator opens an archive can be Compacted: the cartridge ones (NES, SNES, the Game Boys, Master System, Game Gear, N64, Mega Drive) and DS. A present ROM there that isn't Compacted waits in the Review queue.
_Avoid_: Compress, zip, Archive (that leaves it unplayable)

**Standard name**:
The name No-Intro would give a ROM (Redump, on disc Platforms): its Game's name written their way, its Regions as its region tag, and the rest of what its name says about its Version and Disc in their form, without what says nothing about them. So `Super Mario World (U) [!]` with Regions USA has the Standard name `Super Mario World (USA)`, and `The Legend of Zelda: Spirit Tracks`' ROM `Legend of Zelda, The - Spirit Tracks (…)`. A ROM with no Regions has no region tag. A tag it can't place, such as a scene group's or an edition's, is kept unless I choose to drop it.
_Avoid_: Proposed name, canonical name, No-Intro name

**Rename**:
Renaming a ROM to its Standard name in every form it's kept in: its subfolder, its file, its `.7z` and its Compacted copy, and anything else of its name beside them. It stays the same ROM, with its Match. Changing a ROM's Regions never renames it; it only makes Rename offered. A name another ROM has, present or missing, is refused.
_Avoid_: Move, retitle

**Disc**:
One of several disc images that together make up a single Version of a multi-disc game, e.g. "Resident Evil 2 (Disc 1) (Leon)" and "(Disc 2) (Claire)". A floppy set's "(Disk 1)", "(Disk 2)" are Discs too. On a disc Platform they're one ROM: a subfolder holding the Discs and a playlist that loads them. Elsewhere (GameCube) each Disc is a ROM of its own, and a playlist ROM that loads them belongs to the same Version.
_Avoid_: Part, volume, CD

**IGDB link**:
An optional reference from a Game to one IGDB game on the Game's Platform, used for metadata, the Game's name and its Cover. A Game has at most one, and no two Games share one. A Game with no IGDB link can gain one later, and a mistaken link can be changed to another (never removed).
_Avoid_: Anchor, source game

**Match**:
The link between a ROM and its Game, together with how it was made and when. It is Automatic (the checksum identifies the game *and* the names agree), Confirmed (I accepted a suggestion from the Review queue), or Manual (I searched IGDB myself).
_Avoid_: Mapping, association

### Journal data

**Rating**:
My score for how much I liked a Game, from 0.0 to 10.0 in steps of 0.1. A Game with no Rating is unrated, which is different from a Rating of 0.0. It is the latest entry in the Game's Rating history.
_Avoid_: Stars, score

**Rating history**:
Every Rating a Game has had, each with the date it was set, including being cleared back to unrated. There is at most one entry per day: changing a Rating again that day replaces the day's entry.
_Avoid_: Rating log, previous ratings

**Playthrough**:
One time I played a Game. Every Playthrough has a start date; the rest is optional (end date, Outcome, notes, and the Version I played). Its end date can't come before its start date. A Game can have any number.
_Avoid_: Completion, run, session

**Outcome**:
How a Playthrough ended: Finished or Dropped. A Playthrough with no Outcome is still in progress.
_Avoid_: Status, result

**Player**:
Someone besides me who took part in a Playthrough, whether playing or watching. I'm never a Player: I'm in every Playthrough, so one with no Players is Solo. A Playthrough can have any number of Players. Deleting a Player removes them from their Playthroughs. Each has a first and last name (both required, and no two Players share both) and a colour, and is shown as a badge of their initials in that colour.
_Avoid_: Person, companion, friend

**Solo**:
A Playthrough with no Players.

**Partial date**:
A date known only to the day, month or year, e.g. "2024-03-17", "2024-03" or "1996". Best guesses are recorded the same way. A less precise date sorts before the more precise dates within it: "2024" before "2024-01" before "2024-01-05".
_Avoid_: Approximate date, fuzzy date

**Intent**:
What I plan to do with a Game next: Backlog, Up next or Want to buy (I don't own it yet), or nothing. Intent doesn't depend on Playthroughs, so a finished Game can still be Up next. It remembers when it was set, except Intent brought over from OpenEmu, which is undated.
_Avoid_: Status, queue, TODO

**Playing**:
A Game with a Playthrough in progress, whatever its Intent.
_Avoid_: Current, in progress (for a Game)

**Childhood**:
A flag on a Game meaning I played it as a child, at some unknown time.
_Avoid_: Childhood Played

**List**:
A named, unordered group of Games that I curate, e.g. "Castlevania" or "Light Gun Games". A Game can be in many Lists.
_Avoid_: Tag

**Cover**:
The one image a Game shows. In order: an image I uploaded, else its libretro Box art, else IGDB's Cover art. A Game can have no Cover at all.
_Avoid_: Artwork, box image, thumbnail

**Box art**:
A scan of a game's retail box, with the platform's branding (the NES banner, the Game Boy stripe). It comes from libretro-thumbnails, and only exists for emulated platforms.
_Avoid_: Cover (that's what's shown, whatever its source)

**Cover art**:
IGDB's clean artwork for a game, without the box's branding. Kept for every linked Game; shown as the Cover only when there's no upload and no Box art.
_Avoid_: Box art

**Screenshot**:
An image of a game being played, or its title screen. From IGDB (several per game) and libretro-thumbnails (one gameplay shot and one title screen).

### Copies

**Copy**:
One instance of a Game that I have, or once had. A Copy is one of four Kinds: a ROM, or one I record by hand as Physical, Digital, or Physical + digital (a disc that came with a linked digital licence is one Copy, not two). A Game can have any number. Every Copy can say where, when (a Partial date) and for how much it was acquired, and which Regions it is for. A hand-recorded Copy is Owned until I mark it Gone. A ROM is a Copy with those same fields and more of its own (where its file is, whether it's Archived or Compacted), and is Owned for as long as it's in the journal, present or missing: a missing ROM is a problem to fix, never a Copy I've lost. Any Copy can be Deleted, which is different from Gone: it leaves the journal for good, and a ROM's files go to the Trash with it.
_Avoid_: Ownership (that's the Game's status), purchase, edition, licence, forget (for a ROM)

**Region**:
Where a Copy was released for, e.g. Europe, USA, World, Australia or Japan: the usual ones are offered, but any is allowed. A Copy can have any number of Regions, or none. A ROM's Regions are read from its name's tags when it first appears, and can be edited after.
_Avoid_: Territory, locale

**Gone**:
A hand-recorded Copy I no longer have, with (optionally) where it went and when, a Partial date that can't come before the Copy was acquired. A Gone Copy is kept, not deleted, and can be made Owned again. A ROM is never Gone: it leaves only by being Deleted.
_Avoid_: Sold, disposed, lost, deleted

**Owned**:
A Game with at least one Copy that isn't Gone. Since every ROM is a Copy, a Game with a ROM is Owned whether the ROM is present or missing. A Game is Owned as a ROM (it has one), Owned only as a non-ROM Copy (hand-recorded Copies but no ROM), or Not owned (no Copy that isn't Gone). A Not owned Game is in the journal because I'm interested in it or have something to record about it; nothing about it needs fixing.
_Avoid_: Have, in the collection, journal-only (for the status)

### Face-off

**Face-off**:
Checking my Ratings against each other: I'm shown two rated Games at a time, without their Ratings, and pick the one I liked more. Every rated Game takes part. My current Ratings are the starting belief, so pairs go where they're most likely wrong. I can stop at any point and still see its Disagreements.
_Avoid_: Calibration, ranking, Match (that's a ROM's link to its Game)

**Battle**:
One pick in a Face-off between two Games: one wins, or they're About the same. A skipped pair isn't a Battle. Battles are kept with the day they were fought and build up across Face-offs, but older ones count for less: half as much after a week, a quarter after two. A Game that becomes unrated keeps its Battles, and they count again if it's rated again. Deleting a Game deletes its Battles.
_Avoid_: Comparison, Match, Duel, vote

**Disagreement**:
A rated Game whose Battles consistently place it among different Ratings than the one it has, e.g. one rated 8.0 that beats Games rated up to 7.0 but loses to most rated 7.5 or more, so it belongs around 7.0–7.5. Until it has a Battle on the far side too (a win, or About the same, for one rated too high; a loss for one rated too low), it can only say which way: "belongs below 8.5". Any gap counts, however small, as long as the Battles show it consistently: so does a Game I keep preferring to one with the same Rating, since I could have called them About the same. I resolve it by changing the Rating, or by Keeping it: standing by the Rating, which sets the Disagreement aside until the Game fights another Battle. Battles outlive a Rating change, since they record what I prefer, not what I rated.
_Avoid_: Conflict, inconsistency

**Upset**:
A Battle won by the lower-rated Game, or won by either when the two share a Rating. One Upset can't say which of the two Ratings is wrong, so it isn't a Disagreement until more Battles settle it.
_Avoid_: Disagreement (that's about one Game, and needs more evidence)

### Playing

**Emulator**:
The app a Platform's Games are played in, e.g. MesenCE for NES and SNES. Each Platform has at most one.
_Avoid_: Core, player

**Emulator settings**:
The few settings of a Game's Emulator that the journal chooses on each Play, e.g. run-ahead frames. A Game without its own value gets the Emulator's default. Every Play sets all of them, so one Game's settings never carry into the next.
_Avoid_: Config, overrides

**Game Boy Model**:
An Emulator setting for Game Boy and Game Boy Color Games: the hardware the Emulator pretends to be on Play. It is Auto, Game Boy, Game Boy Color or Super Game Boy, and defaults to Auto. It never changes the Game's Platform.
_Avoid_: Forced platform, hardware mode

**Play**:
Opening a Game's present ROM in its Platform's Emulator. Play never changes journal data. A Game can't be Played while a Background task is working on one of its ROMs.
_Avoid_: Launch, run

**Background task**:
Long-running work the app does while I carry on, such as Archiving a ROM or refreshing the cache. Tasks queue and run one at a time, and keep running when I move to another screen. A task may be working on a ROM; while it is queued or running, that ROM's Game can't be Played.
_Avoid_: Job, operation

### Where things live

**Ludeum folder**:
The one place on this Mac where Ludeum keeps everything it owns: the live journal and the Data folder. The cache sits outside it, since it can always be rebuilt.
_Avoid_: App folder, library

**Data folder**:
The part of the Ludeum folder that must survive losing this Mac: the ROM folders, the Backups, and the battery saves archived from OpenEmu. Ludeum doesn't keep it safe; I do, by linking it into Dropbox. The live journal stays outside it and is kept through its Backups. Nothing works until the Data folder can be found.
_Avoid_: Kept folder, backup-worthy, Library folder

**Backup**:
A snapshot of the journal, kept in the Data folder. Taken routinely and before anything that changes the journal wholesale, such as a schema change or the move from OpenEmu.
_Avoid_: Snapshot, backed up (for the Data folder being in Dropbox)

### Working with ROMs

**Import**:
Reading the ROM folders into the journal. Import never changes them.
_Avoid_: Scan, pull

**Add ROM**:
Putting a game from elsewhere (its file, an archive of it, its folder, or its Discs) into its Platform's ROM folder in the form that Platform keeps, then Matching it by hand: to an IGDB game I choose, to a Game whose ROMs are all missing, or to a new Game I make by hand with no IGDB link, for a game IGDB doesn't have. A Compactable Platform's ROM goes in Compacted, a disc Platform's in a subfolder with a playlist for its Discs, and anything else as one Playable file; it's never left Archived. Once it's Matched it can be given its Standard name (on unless I turn it off), and a missing ROM of that Game with either name, the picked one or that one, comes back, named from its own Regions. I choose whether the picked files are copied or moved (moved ones go to the Trash once the ROM is in). Several ROMs picked at once are Added one at a time, each Matched by hand the same way; one can instead go in without a Match, for the Import that follows to Match automatically or through the Review queue.
_Avoid_: Import (that only reads the ROM folders), upload

**Review queue**:
Things the journal won't decide on its own and waits for me to resolve: ROMs with no match, suggested matches (by name, or from a checksum whose names don't agree), Duplicate Versions, Games whose ROMs are all missing, old missing ROMs of Games that still have a present one, ROMs whose Discs have no playlist, ROMs kept in both forms, and ROMs that could be Compacted but aren't.
_Avoid_: Inbox, conflicts

**Duplicate Versions**:
Two or more present ROMs that belong to one Game but aren't Discs of the same Version. Missing ROMs never count. It's resolved by leaving the Game one Version: I Keep only one Version (the others' ROMs are Deleted: their files go to the Trash), Split a Version into its own Game (its ROMs lose their Match and wait in the Review queue to be Matched again, e.g. to a re-release IGDB lists apart), or remove ROMs from the ROM folder myself.
_Avoid_: Duplicates, merge

**Search**:
Finding Games by text across the whole Library, from wherever I am: on Return it opens the Library with every filter cleared and the text as its Text filter. Text matches names, companies, franchises, series and keywords.
_Avoid_: Find, global search

**Text filter**:
Narrowing the view I'm already looking at by the same kind of text a Search matches, keeping its scope and other filters.
_Avoid_: Search (that's the fresh, Library-wide one), name filter
