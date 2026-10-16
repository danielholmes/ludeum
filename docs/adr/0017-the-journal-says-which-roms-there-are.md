# The journal says which ROMs there are; ROM folders only say how their files are

Amends [0009](0009-ludeum-reads-rom-folders-openemu-is-gone.md), and brings ROMs into line with Attachments ([0014](0014-attachments-are-journal-owned-files-in-a-readable-folder.md)).

Every ROM I have came in through Ludeum: Add ROM, the move from OpenEmu, or Add without a Match. So a ROM is in the journal because something recorded it there, not because a file turned up in its ROM folder. An Import no longer makes a ROM of a file it doesn't know. It lists the file as a **Stray file** in the Review queue, where I Add it as a ROM (one, or all at once) or take it out of the folder. Adding one goes through the same matching as before (ADR 0004): Automatic when the checksum and the name agree, else a suggestion in the Review queue. Add without a Match now hands the Import the ROMs it put in, so they're added and nothing else is.

What stays is the half of 0009 that keeps the journal honest about files: each Import still reads every ROM folder, and a ROM's own properties (missing, Archived, Compacted, in both forms, needing a playlist) are still what its folder says about its files now. A ROM is still known by its Platform and its name in that folder, so Unarchiving, Compacting or putting a missing file back is still the same ROM. Attachments work the same way: the journal says which there are, and an Import checks their files are still there.

Stray files are kept in the journal (`strayFile`), as the files' state is for ROMs and Attachments, so the Review queue and its count don't need the folders read again. Each Import rewrites a ROM folder's list once it has read the folder, and leaves the list of a folder it couldn't read alone.

## Considered Options

- **Keep reading new files as new ROMs** (0009 as it was): rejected. A half-copied file, a Dropbox sync caught part-way, something unpacked by hand in Finder, or a file renamed in Finder, became a ROM with a Match of its own (or an unmatched one), and its review item, without my asking.
- **Ignore files the journal doesn't know**: rejected. They would sit unseen in the Data folder, taking up room, and a ROM put in by hand, or on another Mac through Dropbox, would never be found.
- **Have Add without a Match record and match its ROMs itself**: rejected for now. It would need the Matcher in Add ROM, a second way of doing what the Import already does for a file in a ROM folder.
- **Find Stray files when the Review queue opens** instead of keeping them: rejected. The Review queue would read every ROM folder each time it loads, and its count in the sidebar would need the same.
