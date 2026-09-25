# Games Journal: spec

A native macOS app for keeping a personal journal of the games I play on every Platform: ratings, Playthroughs, what to play next. It imports from, and syncs back into, my OpenEmu library.

This file holds the decisions made so far and the open questions (fog). Vocabulary is defined in [`CONTEXT.md`](../CONTEXT.md). The reasons behind hard-to-reverse choices are in [`docs/adr/`](adr/). Where this file and those disagree, the glossary and the ADRs win, and this file needs fixing.

## Goals

- Journal data belongs to a **Game**, never to a ROM file. Removing or re-adding a ROM, or swapping it for another Version, loses nothing.
- Richer data than OpenEmu offers: a Rating out of 10 in steps of 0.1 with its history, notes, and Playthroughs with Partial dates.
- Covers every Platform (retro, PC, Xbox, …), not just emulated games.
- Existing OpenEmu data (stars, collections, play stats) is brought across, and OpenEmu stays usable as the place I actually play.

## Non-goals (for now)

Phone or remote access; several Macs; a fork of OpenEmu; two-way sync; importing from Steam or Xbox; exceptions to the Duplicate Versions rule; combining Games; fixing a mistaken Match; overriding covers; organising Lists automatically from IGDB data; ScreenScraper media (manuals, better box art); downloading screenshots and artwork.

## Decisions so far

### Architecture
- SwiftUI app plus the `JournalCore` Swift package, with GRDB/SQLite for storage ([ADR 0003](adr/0003-swiftui-not-go.md)). The `journal-import` CLI exists for development tasks.
- The journal owns its data. OpenEmu only receives a one-way **Sync** ([ADR 0001](adr/0001-journal-owns-data-one-way-sync-to-openemu.md)).
- One Mac. The journal database lives in `~/Library/Application Support/GamesJournal/`, with automatic dated backups copied to Dropbox. The cache is a separate file in the same folder, excluded from backups.
- IGDB credentials: `.env` for development (see `scripts/setup-igdb.sh`). The app will later use the Keychain.

### Games and identity
- A Game is a title on one Platform. It can have one IGDB link or none ([ADR 0002](adr/0002-game-identity-is-journal-owned.md)).
- Regions, revisions and fan translations belong to the same Game. Ports, and enhanced re-releases that IGDB lists separately, are separate Games.
- Platform means the platform the Game was made for. How I played it (OpenEmu, Switch Online, Steam Deck, …) is a Playthrough's "Played via".
- Display name: IGDB's name, which I can override. Games without an IGDB link use a cleaned No-Intro name.
- Non-emulated Games (PC, Xbox) are added by searching IGDB. Games can also be created by hand with no IGDB link.

### Journal data
- **Rating:** 0.0–10.0, or unrated (different from 0.0). One per Game, with a Rating history of dated entries. Stars imported from OpenEmu become ×2 (3★ → 6.0), dated at import and marked imported/approximate.
- **Playthrough:** every field optional (start and end as Partial dates, Outcome of Finished or Dropped, notes, Version, Played via). A Playthrough with no Outcome is in progress. Version and Played via are free text, with suggestions drawn from the Game's ROM names.
- **Intent:** none, Backlog, or Up next (a set, not ordered). It doesn't depend on Playthroughs.
- **Childhood:** a flag on a Game.
- **Lists:** named, unordered, curated. A Game can be in many.
- **Activity:** read-only play stats summed across a Game's ROMs. A snapshot is saved at each Import so play time can be credited to a year.
- **Cover:** the IGDB cover. If IGDB has none, OpenEmu's existing box art is carried over once. If neither exists, I upload my own.

### First Import from OpenEmu
- Reads a snapshot of OpenEmu's database, taken with SQLite's backup API. Safe while OpenEmu is running. Never writes to OpenEmu.
- Collections map as follows:

  | OpenEmu collection | Becomes |
  |---|---|
  | `_TODO` | Intent Backlog |
  | `_TODO Next` | Intent Up next |
  | `_Current` | a Playthrough in progress |
  | `_Completed` | a Finished Playthrough with no dates (OpenEmu's last-played date is shown as a hint) |
  | `_Childhood Played` | the Childhood flag |
  | every other collection | a List |

- **Matching** (confirmed in the dry run on the `prototype/first-import` branch):
  1. Hasheous lookup by OpenEmu's MD5. Uncompressed or small archived NES/SNES dumps are retried with the header stripped, only if the file is already on disk. CD images are never read.
  2. It's an **Automatic** Match only when the checksum *and* the name agree, and never with an IGDB bundle ([ADR 0004](adr/0004-automatic-match-needs-checksum-and-name.md)).
  3. Everything else goes to the **Review queue**: suggestions from checksums whose names disagree, IGDB name-search suggestions, or no suggestion at all (search IGDB by hand).
  4. The Review queue can bulk-confirm suggestions whose names match exactly.
  5. Expected load on my library: about 937 checksum matches, about 224 name suggestions (211 exact), about 35 with nothing, so roughly 50 items to decide by hand.
- **Duplicate Versions** (2 or more *present*, non-Disc ROMs on one Game) block the first Import until I remove ROMs in OpenEmu. There's no exceptions mechanism, and the UI should say that real exceptions need a code change. The dry run found 5 real ones.
- **Discs:** ROMs differing only by `(Disc N)` or a disc label make up one Version.
- **Orphaned OpenEmu entries** (the ROM file is missing; 150 of them, 60 holding data) are imported with the ROM marked missing.
- **Ongoing Imports:** new ROMs go through the same matching. A ROM that disappears is marked missing, and its last Activity is kept.

### Sync to OpenEmu
- Runs by hand, only while OpenEmu is closed, after backing up OpenEmu's database.
- **Stars:** the Rating ÷ 2, rounded half up (0.0–0.9 → no stars), written to every ROM of the Game.
- **Collections:** each List, plus `_TODO`, `_TODO Next`, `_Current` and `_Completed` built from Intent and Playthroughs, are owned by the journal and overwritten. Other regular collections are deleted after I confirm them by name. Smart collections are left alone.
- **Covers:** written only for games that have no box art in OpenEmu.
- A Game with unresolved Duplicate Versions isn't synced.

### External data and cache (built: `JournalCore`)
- **IGDB** (Twitch app token): the full game record, with every useful sub-record expanded plus time-to-beat. Fetched in batches of 100 (halved if IGDB answers 413). One request per name search, since multiquery ignores `search`. At most 3 requests a second.
- **Hasheous:** MD5 → IGDB game and platform. "Not found" is cached. At most 1 request a second. An optional app key can be set with `HASHEOUS_API_KEY`.
- **Cache:** entries keyed as `source:kind:id`, fresh for 60 days. An expired entry is still used if refreshing it fails. Only successful answers are cached. Images never expire. Runs can be interrupted and resumed.

### Version 1 screens
Library (filter and sort by Platform, Rating, Intent, List, Outcome, Childhood); Game detail (editing); What to play next; Year in review; Top-rated; Import, Review queue and Sync.

## Fog: open questions

Roughly in the order they block work:

1. **Journal database schema:** tables for Game, ROM, Match, Rating history, Playthrough, List, Activity snapshots and Covers; migrations; how Partial dates are stored.
2. **Is writing to OpenEmu safe?** Sync writes straight into OpenEmu's Core Data SQLite store: `Z_OPT`, `Z_PRIMARYKEY`, the collection join table, `ZIMAGE` rows plus files in `Artwork/`. Does OpenEmu 2.4.1 accept these changes without corruption or losing them to a re-sync? Needs a spike against a copy of the library.
3. **App skeleton:** Xcode project versus SwiftPM-only; how the app hosts `JournalCore`; where Import, Sync and background work run; signing for personal use.
4. **Matching rules in detail:** name normalisation for "names agree" (roman numerals, `&`/`and`, subtitles, articles, IGDB alternative names and localisations); the parser for Disc and Version from No-Intro and Redump names; which IGDB `game_type` values count as bundles.
5. **Review queue UX:** layout for bulk confirm, the checksum-suggestion view, manual IGDB search, and assigning a ROM to an existing Game (fan translations).
6. **Duplicate Versions flow:** how the first Import pauses and resumes while I remove ROMs in OpenEmu.
7. **Year in review:** how Partial dates are counted (a year-only date counts for that year; a month-only date?); crediting Activity to years from snapshot differences; how "time played" is shown for non-emulated Games.
8. **Adding non-OpenEmu Games:** the IGDB search flow; which IGDB platforms to list; creating a Game by hand.
9. **Covers:** where uploaded covers are stored and in what format; how Sync writes one into `Artwork/` with a `ZIMAGE` row.
10. **Backups:** how often journal backups are copied to Dropbox and how many are kept.
11. **Credentials in the app:** moving from `.env` to the Keychain; a settings screen; whether to request a Hasheous app key.
12. **Rating history:** does re-entering the same value add an entry? Can entries be edited or deleted?
13. **Deleting things:** deleting a Game (and its ROM Matches); deleting a List; what happens to Games whose ROMs are all missing.
14. **Later enrichments** (deliberately out of v1, listed so they aren't lost): IGDB screenshots and artwork, series, similar games and time-to-beat on screen; ScreenScraper for manuals and box, cart and disc scans; Steam playtime; RetroAchievements; SteamGridDB for PC art.

## Built so far

- `JournalCore`: cache store, `IGDBClient` (games, search, covers, Twitch token handling), `HasheousClient`, throttling. 24 tests at the agreed boundaries. CI: lint, build with warnings as errors, tests.
- `journal-import check`: a live check against IGDB and Hasheous.
- `scripts/setup-igdb.sh`: the IGDB credentials wizard.
- Branch `prototype/first-import`: a throwaway dry run of the first Import. Its verdict is in the commit message and folded into the decisions above.
