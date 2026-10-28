# A multi-disc ROM starts on the Disc it last started on

Amends [0024](0024-ludeum-installs-duckstation-and-says-where-it-keeps-things.md) (a Standing setting points DuckStation's game list at the PlayStation ROM folder) and the glossary's Play, which no longer leaves journal data untouched.

Gran Turismo 2's Discs aren't played in order: Disc 1 is Arcade Mode and Disc 2 Gran Turismo Mode, and which one I want is the choice of what to play. Resident Evil 2's Leon and Claire Discs are the same. Play opened a multi-disc ROM's playlist, which DuckStation always boots at Disc 1, so getting to Disc 2 meant booting Disc 1 and swapping. So Game detail's Play is now a split button: a click boots the ROM's last Disc, and its menu lists every Disc by number and Disc label ("Disc 2 · Gran Turismo Mode"), for every multi-disc ROM. Play says which Disc it boots whenever the ROM has more than one, and so does the Library Cover's tooltip, since a double-click boots the same Disc.

DuckStation has no command-line argument for which playlist entry to boot (`media_playlist_index` exists in `SystemBootParameters` but no frontend sets it), as of build 12442. So Disc 1 boots through the playlist, as before, and any other Disc boots as its own `.cue`. A lone disc of a set DuckStation's database knows still swaps: its Change Disc menu and Next/Previous Disc hotkeys list the set's other discs from DuckStation's game list by Serial, so a Standing setting puts the PlayStation ROM folder in the game list. Booting a later Disc changes nothing else: DuckStation reads a set's per-game settings from Disc 1's file (unless `UseSeparateConfigForDiscSet`), as Ludeum already writes it, and names its memory card after the set, however it was booted. A Save state records the file it was booted from and its playlist position, and DuckStation boots that rather than the path it's given, so Play from a state made on Disc 2 comes back on Disc 2.

The Disc a Play started on is kept on the ROM, and nothing else about it: not when, nor how often. That keeps to [0007](0007-no-activity.md), which dropped play statistics: this is a remembered choice, not a record of play. Play from a Save state counts as starting on the state's Disc. A ROM whose last Disc it no longer has starts on Disc 1.

## Considered Options

- **A reordered playlist, Disc 2 first, for each later Disc**: rejected. It swaps for any set, known to DuckStation's database or not, but a Save state records the playlist's path and position, so it would have to stay at the same path in the same order for good, in the Data folder so another Mac finds it, and Rename and Archive would have a second playlist to keep up with.
- **Remembering the Disc DuckStation last ran**, from its play-time file by Serial: rejected. It would catch a swap made inside DuckStation, but leans on a private file that isn't in the Data folder. Choosing Arcade or Gran Turismo Mode happens in Ludeum, which is what this is for.
- **The last Disc per Game**: rejected. A Disc belongs to one Version's ROM, and Versions order their Discs differently.
- **A setting marking the Games whose Discs are played separately**, with a Play button per Disc only for them: rejected. A menu on Play costs nothing for FF7 and needs nothing set by hand.

## Consequences

- A lone disc of a set DuckStation's database doesn't know (a fan translation, say) can't be swapped from its Change Disc menu; From File still works.
- DuckStation's own window lists the PlayStation ROMs that aren't Archived.
- A Disc label is the free-form tag right after `(Disc N)`, never a Version's (`v1.1`, a revision, languages): Metal Gear Solid's `(Disc 1) (v1.1)` has none.
- Built for PlayStation only. GameCube's multi-disc ROMs, each Disc its own ROM, are all Archived.
