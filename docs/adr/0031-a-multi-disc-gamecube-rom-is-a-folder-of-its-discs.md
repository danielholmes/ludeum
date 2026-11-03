# A multi-disc GameCube ROM is a folder of its Discs

Amends the glossary's Disc, which kept each GameCube Disc a ROM of its own, and [0026](0026-a-multi-disc-rom-starts-on-the-disc-it-last-started-on.md)'s note that GameCube's multi-disc ROMs are each Disc its own ROM.

A ROM is a Copy ([0011](0011-roms-are-copies.md)), so Resident Evil, Resident Evil Zero and Metal Gear Solid: The Twin Snakes each showed two Copies, one per Disc, with each Disc's Regions, acquisition and notes kept apart. They were the only Games in the journal with more than one ROM. A multi-disc GameCube Version is now one ROM, kept as a PlayStation one is: a subfolder named after the Version, its Discs' name without their Disc, holding the Discs and an `.m3u` naming them in order. The GameCube ROM folder reads `.m3u` as ready, which is all it takes for a scan to read such a subfolder as one ROM opening its playlist, and one whose Discs have no playlist as waiting for one.

Dolphin boots an `.m3u` (`Boot.cpp`'s `ReadM3UFile`, and its game list scans them), and with `Main.Core.AutoDiscChange` on changes to the playlist's next Disc when the game asks for it. That setting is off by Dolphin's default, so every Play turns it on for that launch with `-C`, as it does the latency settings. Play boots Disc 1; unlike DuckStation's, a GameCube game asks for its other Disc itself, so there's no choosing a Disc to start on.

A single-disc GameCube ROM is still one loose file, and its Archive and Unarchive are unchanged. A multi-disc one's Archive packs its folder (playlist and Discs) into `<ROM name>.7z`, and its Unarchive unpacks a `.7z` holding more than one file into `<ROM name>/`, as the disc Platforms' do, refused unless it makes a ROM of its folder. A folder of Discs with no playlist still isn't Archived. Add ROM keeps picked GameCube Discs together, or an archive of them, writing the playlist; a picked folder is still read only where every ROM is kept in one.

The three Games' Discs, each an Archived `.7z`, are made one ROM by hand, once, with Ludeum closed, by `ludeum-import gamecube-discs` (a plan unless `--run`), which goes once it has run: each Disc is unarchived, the Discs move into the Version's folder with a playlist, which is Archived again, and Disc 1's row is kept as the ROM, with the Copy details every Disc agrees on and any Playthrough of another Disc moved to it; the other rows are deleted. Discs whose details disagree, or that aren't all there, are left. Its `before-gamecube-discs` backup is kept forever.

## Considered Options

- **Grouping a Version's Disc ROMs into one Copy on Game detail**, leaving the files and rows apart: rejected. Each Disc would still have its own details underneath, shown in one place and kept in two, and every Copy count (Owned, the Library) would need the same grouping.
- **Each Disc its own ROM, with a playlist ROM loading them**, as the glossary allowed: rejected. The playlist would be a third Copy, and Archive would have to keep three files in step.

## Consequences

- Loose GameCube Discs at the top of the ROM folder are still read as a ROM each, and Duplicate versions groups them as one Version; Add ROM no longer makes them.
- Archive of a multi-disc GameCube ROM recompresses both Discs at `-mx=9`, which takes minutes.
- The Unarchive help can't say which a GameCube `.7z` unpacks to without reading it, so it says either.
