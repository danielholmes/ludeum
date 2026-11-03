# Play resumes from the Resume state when there is one

Amends [0026](0026-a-multi-disc-rom-starts-on-the-disc-it-last-started-on.md): the Resume state comes before the Disc a multi-disc ROM last started on. Amends the glossary's Play, which now starts from a Save state of its own accord.

DuckStation and PCSX2 save a Resume state when a game is closed (`SaveStateOnExit`, `SaveStateOnShutdown`), and MesenCE one every minute of play (its automatic slot, 11), each as its Standing settings say ([0024](0024-ludeum-installs-duckstation-and-says-where-it-keeps-things.md), [0027](0027-ludeum-installs-mesence-with-a-folder-per-platform.md), [0032](0032-ludeum-installs-pcsx2-and-says-where-it-keeps-things.md)). Picking up where I left off is what a Play usually is: I close DuckStation mid-race and come back the next evening. Until now Play booted the ROM fresh, or its last Disc, and resuming meant scrolling to the Save states section and pressing Play on its Resume row, while a double-click on the Cover couldn't resume at all.

So what a Play starts from is decided before the press, and shown: the Game's Resume state when its Emulator keeps one for the ROM, else the Disc a multi-disc ROM last started on, else just the ROM. Game detail's Play is the split button 0026 made it, now for every Game with more than one way to start: its label says what a click does ("Resume", "Play · Gran Turismo Mode", "Play") and its menu lists every way ("Resume", then "Play", or "Play Disc 1 · Arcade Mode Disc", "Play Disc 2 · Gran Turismo Mode"). A double-click on a Library Cover does what the button's label says, as it already did for the last Disc, and its tooltip says so.

The Resume state comes before the last Disc because it holds both: a state records the Disc it was running, and DuckStation boots that ([0026](0026-a-multi-disc-rom-starts-on-the-disc-it-last-started-on.md)); the last Disc is a choice for a fresh boot. Where a multi-disc ROM has a Resume state for more than one Disc's Serial, the latest saved is the one, as that's where I left off. A slot, and the Previous one of a Resume state (`.bak`), are never resumed from: the Resume state is the Emulator's own idea of where the game was, and the rest are mine to choose from the Save states section. Nothing new is kept: the default is read from the Emulator's state folder each time it's needed (when Game detail opens, when the ROMs change, when a state is deleted in Ludeum, whenever Ludeum becomes active, and on hovering a Cover), so Play still changes no journal data but the last Disc ([0007](0007-no-activity.md)).

## Considered Options

- **Resuming only from the Save states section**, as before: rejected. Two clicks and a scroll for the commonest Play, and no way to resume from the Library.
- **Always resuming, with no menu**: rejected. A fresh boot, for a new game or another Disc, must stay a click away, and a Game with no Resume state would have nothing to say.
- **Remembering which way was last chosen**: rejected. The default follows what's on disk, so it needs nothing kept in the journal and is right on another Mac.
- **The Resume state of the last Disc rather than the latest saved**: rejected. Starting Disc 2 and closing it saves Disc 2's Resume state and makes Disc 2 the last Disc, so they agree in practice; where they don't (a Resume state deleted in DuckStation), the latest saved is still where I left off.

## Consequences

- Resume shows only once a PlayStation or PlayStation 2 ROM's Serials are read, and for a MesenCE ROM whose name can be read (an archive 7-Zip can list). ares keeps no Resume state, and Dolphin, melonDS, Ymir, PPSSPP and xemu keep none Ludeum reads, so their Play is as before.
- A Resume state saved by an Emulator still open isn't seen until Ludeum becomes active again; deleting the Resume state in the Emulator puts Play back to the last Disc at the next read.
- A Play from the Resume state counts as starting on the state's Disc, which is remembered as 0026 says.
- The Review queue's Play on a Duplicate Versions item starts fresh, as it did.
