# Ludeum

A personal record of the games I play across every platform (retro via OpenEmu, PC, Xbox, and others): what I thought of them, when I played them, and what I want to play next. The journal, not any emulator library, is the source of truth for this data.

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
A game file in an emulator library: OpenEmu's, or a ROM folder. A ROM identifies a Version of a Game, and is linked to its Game automatically or by hand. Journal data never belongs to a ROM, so removing or replacing the file loses nothing. A ROM that has gone from the library is kept as missing, not forgotten. It is forgotten only when its Game is deleted, and a Game can't be deleted while it has a present ROM.
_Avoid_: File, image

**ROM folder**:
A folder of a Platform's ROMs that the journal reads directly, for Platforms OpenEmu doesn't have (e.g. PS2). A ROM there is known by its name: a file's without the extension, or a subfolder's when the subfolder holds the game (one image, or a cue sheet with its tracks, alongside anything else). So Unarchiving `Okami (USA).7z` into `Okami (USA)/`, or Archiving it again, is the same ROM changing state. When both exist, the playable one is used.
_Avoid_: Library folder, watch folder

**Archived ROM**:
A ROM that is still in its library but packed in a form its Platform's Emulator can't open, so it can't be Played until I Unarchive it. It is present, not missing. Whether a ROM is archived depends on the Emulator: a `.7z` that one Emulator opens directly is an ordinary ROM there.
_Avoid_: Compressed, needs extraction (that's the fix, not the state)

**Archive / Unarchive**:
Packing a ROM folder ROM into a `.7z`, or unpacking all of it into a folder named after the ROM so it can be Played. Either way only one copy is kept: the file it replaces goes to the Trash once the new one checks out. Only PS2 ROMs can be Archived or Unarchived so far.
_Avoid_: Extract, compress, decompress

**Disc**:
One of several ROMs that together make up a single Version of a multi-disc game, e.g. "Resident Evil 2 (Disc 1) (Leon)" and "(Disc 2) (Claire)". A playlist ROM that loads the Discs belongs to the same Version.
_Avoid_: Part, volume, CD

**IGDB link**:
An optional reference from a Game to one IGDB game on the Game's Platform, used for metadata, the Game's name and its Cover. A Game has at most one, and no two Games share one. A Game with no IGDB link can gain one later, and a mistaken link can be changed to another (never removed).
_Avoid_: Anchor, source game

**Match**:
The link between a ROM and its Game, together with how it was made and when. It is Automatic (the checksum identifies the game *and* the names agree), Confirmed (I accepted a suggestion from the Review queue), or Manual (I searched IGDB myself).
_Avoid_: Mapping, association

### Journal data

**Rating**:
My score for a Game, from 0.0 to 10.0 in steps of 0.1. A Game with no Rating is unrated, which is different from a Rating of 0.0. It is the latest entry in the Game's Rating history.
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
What I plan to do with a Game next: Backlog or Up next, or nothing. Intent doesn't depend on Playthroughs, so a finished Game can still be Up next. It remembers when it was set, except Intent brought over from OpenEmu, which is undated.
_Avoid_: Status, queue, TODO

**Playing**:
A Game with a Playthrough in progress, whatever its Intent.
_Avoid_: Current, in progress (for a Game)

**Childhood**:
A flag on a Game meaning I played it as a child, at some unknown time.
_Avoid_: Childhood Played

**List**:
A named, unordered group of Games that I curate, e.g. "Castlevania" or "Light Gun Games". A Game can be in many Lists.
_Avoid_: Collection, tag

**Cover**:
The one image a Game shows. In order: an image I uploaded, else its libretro Box art, else its OpenEmu Box art, else IGDB's Cover art. A Game can have no Cover at all.
_Avoid_: Artwork, box image, thumbnail

**Box art**:
A scan of a game's retail box, with the platform's branding (the NES banner, the Game Boy stripe). It comes from libretro-thumbnails or from OpenEmu, and only exists for emulated platforms.
_Avoid_: Cover (that's what's shown, whatever its source)

**Cover art**:
IGDB's clean artwork for a game, without the box's branding. Kept for every linked Game; shown as the Cover only when there's no upload and no Box art.
_Avoid_: Box art

**Screenshot**:
An image of a game being played, or its title screen. From IGDB (several per game) and libretro-thumbnails (one gameplay shot and one title screen).

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
Opening a Game's present ROM in its Platform's Emulator. Play never changes journal data.
_Avoid_: Launch, run

**Background task**:
Long-running work the app does while I carry on, such as Archiving a ROM or refreshing the cache. Tasks queue and run one at a time, and keep running when I move to another screen.
_Avoid_: Job, operation

### Working with OpenEmu

**Import**:
Reading ROMs from OpenEmu and the ROM folders into the journal. Import never changes them.
_Avoid_: Scan, pull

**Import draft**:
The first Import before I commit it: OpenEmu's snapshot plus my answers so far, none of it journal data yet. It can't be committed while any Game has Duplicate Versions or a `_Current` Game lacks a start date, and it can be discarded.
_Avoid_: Pending import, staging

**Sync**:
Writing the journal's data into OpenEmu: Ratings as stars, Lists plus Intent and Playthrough state as collections, and Covers for games that have no box art in OpenEmu. The journal owns the stars and the regular collections, and replaces whatever OpenEmu had.
_Avoid_: Push, export

**Review queue**:
Things the journal won't decide on its own and waits for me to resolve: ROMs with no match, suggested matches (by name, or from a checksum whose names don't agree), and Duplicate Versions.
_Avoid_: Inbox, conflicts

**Duplicate Versions**:
Two or more present ROMs that belong to one Game but aren't Discs of the same Version. Missing ROMs never count. The only way to resolve it is to remove ROMs until one Version is left.
_Avoid_: Duplicates, merge

**Search**:
Finding Games by text across the whole Library, from wherever I am: on Return it opens the Library with every filter cleared and the text as its Text filter. Text matches names, companies, franchises, series and keywords.
_Avoid_: Find, global search

**Text filter**:
Narrowing the view I'm already looking at by the same kind of text a Search matches, keeping its scope and other filters.
_Avoid_: Search (that's the fresh, Library-wide one), name filter
