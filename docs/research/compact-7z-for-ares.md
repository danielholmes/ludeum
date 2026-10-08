# Compacting ares Platforms as `.7z`, unpacked at Play time

Researched 2026-10-08. The question: ares can't open a `.7z`, so N64 and Mega Drive are Compacted as `.zip`. Could they be Compacted as `.7z` like every other Platform, and converted for ares in a cache or temp folder when Played? How long would the conversion take, and is it worth it? Parked, not decided.

## Findings

**Converting is fast, but the space saved is small (about 43 MB, 6%).** A cache that keeps the converted files would soon use more room than it saves. The main reason to do this would be one archive format on every Compactable Platform, not disk space.

- **Only ares Platforms are affected:** Mega Drive (127 ROMs) and N64 (32). Sega CD also runs in ares, but it's a disc Platform and isn't Compacted.
- **No zip step is needed.** ares opens an unpacked ROM file. Play already passes `--system` (`Sources/LudeumCore/Emulators.swift`), and Sega CD already runs unpacked. So the whole cost of playing from a `.7z` is unpacking it. A zip with no compression is as big as the unpacked file, so it adds nothing.
- **Time per Play:** under 0.1 s for Mega Drive, and at most 1.2 s for N64 (Conker's Bad Fur Day, 64 MB unpacked).
- **A persistent cache works against the goal.** Each cached ROM takes its full unpacked size: Conker alone is 67 MB, more than the whole 43 MB saving. A temp file with a fixed name per ROM, reused while it's still there and otherwise unpacked again, fits the numbers better. macOS clears temp folders on its own. To tell whether a temp copy is still current, compare it with the `.7z`'s size and modified date, or with the CRC that `SevenZip.contents` reads from the archive's index.

## Risks and open questions

- **Where ares writes saves (unverified, check before going further).** The Saves path in ares's `settings.bml` (`~/Library/Application Support/ares/`) is empty. If ares then saves beside the game, battery saves would land in the temp folder and be lost when it's cleared. On 2026-10-08 the N64 and Mega Drive ROM folders held only zips, so either nothing had been saved yet or saves go somewhere else.
- **The temp file must keep the ROM's name**, so ares keeps matching saves and settings to the game.
- **Effect on the glossary.** Every Compactable Platform would use `.7z`. That removes the N64/Mega Drive `.zip` exception from Compact, and an Archived `.7z` there would count as Playable. The Archived, Compact and Play definitions would need updating, and probably a new ADR.
- Not checked: whether a newer ares opens `.7z` itself, which would make all of this unnecessary.

## Measurements

Taken on an M3 Max (14 threads) with 7-Zip 26.01 (`7zz`), using copies of the library's zips. The files were on local SSD and probably already in memory, so a first read from disk could be a little slower. Each `.7z` was made with `7zz a -t7z -mx=9`, the same as Compact.

### Space

| | Unpacked | Current `.zip` | `.7z` | Saved |
|---|---|---|---|---|
| Mega Drive | 186 MB | 97.7 MB | 88.8 MB | 8.9 MB |
| N64 | 726 MB | 571.0 MB | 537.1 MB | 33.9 MB |
| **Total** | 912 MB | 668.7 MB | 625.9 MB | **~43 MB (6%)** |

Most N64 ROMs barely compress in either format: Conker's Bad Fur Day is 61.1 MB as `.zip` and 60.1 MB as `.7z`.

### Time per ROM

| Step | Mega Drive median / max | N64 median / max |
|---|---|---|
| Unpack the `.7z` | 26 ms / 95 ms | 314 ms / 1.2 s |
| Then zip with no compression (`-mx=0`) | +11 ms / +14 ms | +17 ms / +35 ms |
| Then zip at fastest compression (`-mx=1`) | +29 ms / +97 ms | +306 ms / +1.1 s |
| Then zip at maximum compression (`-mx=9`, what Compact uses) | +419 ms / +2.2 s | +4.8 s / +18 s |

Unpacking and zipping without compression took about 18 s for all 159 ROMs.
