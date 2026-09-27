# Games Journal

A personal record of the games I play across every platform (retro via OpenEmu, PC, Xbox, and others): what I thought of them, when I played them, and what I want to play next. The journal, not any emulator library, is the source of truth for this data.

## Language

### Games

**Game**:
A title as played on one Platform. Regional releases, revisions and fan translations of that title on the same Platform are the same Game. A port to a different Platform is a different Game, and so is an enhanced re-release that IGDB lists separately (e.g. Link's Awakening vs Link's Awakening DX).
_Avoid_: Title, entry, ROM

**Platform**:
The hardware or ecosystem a Game was made for, e.g. SNES, Game Boy, PC, Xbox 360. It is never the device or service the Game was actually played on.
_Avoid_: System, console

**Version**:
One specific edition of a Game, e.g. a region, a revision, or a fan translation ("Europe Rev 1", "Japan + English translation").
_Avoid_: Release, revision, dump

**ROM**:
A game file in an emulator library. A ROM identifies a Version of a Game, and is linked to its Game automatically or by hand. Journal data never belongs to a ROM, so removing or replacing the file loses nothing. A ROM that has gone from the library is kept as missing, not forgotten. It is forgotten only when its Game is deleted, and a Game can't be deleted while it has a present ROM.
_Avoid_: File, image

**Disc**:
One of several ROMs that together make up a single Version of a multi-disc game, e.g. "Resident Evil 2 (Disc 1) (Leon)" and "(Disc 2) (Claire)". A playlist ROM that loads the Discs belongs to the same Version.
_Avoid_: Part, volume, CD

**IGDB link**:
An optional reference from a Game to one IGDB game and platform, used for metadata, the Game's name and its Cover. A Game has at most one.
_Avoid_: Anchor, source game

**Match**:
The link between a ROM and its Game, together with how it was made and when. It is Automatic (the checksum identifies the game *and* the names agree), Confirmed (I accepted a suggestion from the Review queue), or Manual (I searched IGDB myself).
_Avoid_: Mapping, association

### Journal data

**Rating**:
My score for a Game, from 0.0 to 10.0 in steps of 0.1. A Game with no Rating is unrated, which is different from a Rating of 0.0. It is the latest entry in the Game's Rating history.
_Avoid_: Stars, score

**Rating history**:
Every Rating a Game has had, each with the date it was set, including being cleared back to unrated. There is at most one entry per day: changing a Rating again that day replaces the day's entry. Ratings brought over from OpenEmu stars are marked as imported and approximate, and are never replaced.
_Avoid_: Rating log, previous ratings

**Playthrough**:
One time I played a Game. Every field is optional: start date, end date, Outcome, notes, and the Version I played. A Game can have any number.
_Avoid_: Completion, run, session

**Outcome**:
How a Playthrough ended: Finished or Dropped. A Playthrough with no Outcome is still in progress.
_Avoid_: Status, result

**Partial date**:
A date known only to the day, month or year, e.g. "2024-03-17", "2024-03" or "1996". Best guesses are recorded the same way.
_Avoid_: Approximate date, fuzzy date

**Intent**:
What I plan to do with a Game next: Backlog or Up next, or nothing. Intent doesn't depend on Playthroughs, so a finished Game can still be Up next.
_Avoid_: Status, queue, TODO

**Childhood**:
A flag on a Game meaning I played it as a child, at some unknown time.
_Avoid_: Childhood Played

**List**:
A named, unordered group of Games that I curate, e.g. "Castlevania" or "Light Gun Games". A Game can be in many Lists.
_Avoid_: Collection, tag

**Activity**:
Play statistics recorded automatically by an emulator (play count, last played, total play time), totalled across a Game's ROMs. Read-only. The journal saves a snapshot of it at each Import so play time can be credited to the year it happened. Time from before tracking began has no year.
_Avoid_: Stats, history

**Cover**:
The box art shown for a Game. It comes from the Game's IGDB link. If IGDB has none, it's an image I supplied myself, or the box art OpenEmu already had.
_Avoid_: Artwork, box image, thumbnail

### Working with OpenEmu

**Import**:
Reading ROMs and Activity from OpenEmu into the journal. Import never changes OpenEmu.
_Avoid_: Scan, pull

**Sync**:
Writing the journal's data into OpenEmu: Ratings as stars, Lists plus Intent and Playthrough state as collections, and Covers for games that have no box art in OpenEmu. The journal owns the stars and the regular collections, and replaces whatever OpenEmu had.
_Avoid_: Push, export

**Review queue**:
Things the journal won't decide on its own and waits for me to resolve: ROMs with no match, suggested matches (by name, or from a checksum whose names don't agree), and Duplicate Versions.
_Avoid_: Inbox, conflicts

**Duplicate Versions**:
Two or more present ROMs that belong to one Game but aren't Discs of the same Version. Missing ROMs never count. The only way to resolve it is to remove ROMs until one Version is left.
_Avoid_: Duplicates, merge
