# A PlayStation Game's own settings are DuckStation's

Supersedes [0021](0021-duckstation-settings-go-in-its-per-game-file-named-by-the-discs-serial.md) for a Game's own settings, and amends [0008](0008-journal-owns-per-game-emulator-settings.md): PlayStation Games have no Emulator settings in the journal.

Under 0021 a PlayStation Game's run-ahead and CD read and seek speedups were the journal's, merged into DuckStation's per-game file before every Play, so a change made in DuckStation's Game Properties lasted only until then. It makes more sense to set them in DuckStation. Its Game Properties already offers every per-game setting it has, not only the three Ludeum chose, and since 0024 its per-game files live in the Data folder (`Emulators/DuckStation/Game Settings/<Serial>.ini`), so Dropbox has them without the journal holding a copy. 0008's reason for the journal owning them doesn't apply either: a setting a DuckStation Game doesn't set falls back to DuckStation's own, so nothing carries over from the Game played before.

So:

- **A Play writes only the Standing settings.** Ludeum doesn't write DuckStation's per-game files, so what's set in Game Properties stays. It still reads them, for a Game's memory card.
- **The Game detail settings button is gone for PlayStation Games.** MesenCE's and ares's Games keep theirs.
- **A Game whose Disc 1 has no Serial is no longer refused.** Ludeum only needed the Serial to name the per-game file. Save states and memory cards still go by it.
- **`v43` drops `game.cdReadSpeedup` and `game.cdSeekSpeedup`, and clears a PlayStation Game's `runAheadFrames`.** That column stays for MesenCE's and ares's Games. On 2026-10-31 only Resident Evil: Director's Cut had any (run-ahead 6, both speedups Maximum), and its per-game file already said the same, as every Play had written it there, so nothing was moved by hand.

## Consequences

- The cleanup of what every Play wrote into the per-game files before 0024 (the Standing keys, and card 1 as the Serial-named card) goes with the writer. None of the six files in the Data folder had any of it left.
- A PlayStation Game's settings no longer show in Ludeum, and Ludeum doesn't know whether a Game has any.
