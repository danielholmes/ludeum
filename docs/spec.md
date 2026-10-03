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
- **Platforms are IGDB's platforms** ([ADR 0005](adr/0005-platforms-are-igdb-platforms.md)): the list comes from IGDB's `platforms` endpoint, cached like any other record. Every Game has one, including Games with no IGDB link. There are no custom Platforms.
- **An IGDB link is unique:** no two Games share the same IGDB game and Platform. Its platform is always the Game's Platform, even when IGDB doesn't list that game on it.
- Display name: IGDB's name, which I can override. Games without an IGDB link use a cleaned No-Intro name, or the name I typed.

### Adding Games
Non-emulated Games (PC, Xbox, …) and Games I don't have a ROM for yet are added by hand.

- **Platform picker:** every IGDB platform, type-to-filter, with Platforms my Games already use listed first.
- **Searching IGDB:** one search box plus an optional Platform filter, empty by default. Each result is an IGDB game with its cover, name, first release year, `game_type` (when it isn't a main game) and its platforms as chips. Results never include DLC (1), Expansion (2), Season (7), Pack/Addon (13) or Update (14). Mods (5) are shown and labelled.
- **Choosing the Platform:** clicking a platform chip adds the Game on that Platform. A "Different platform…" chip opens the Platform picker, for ports IGDB doesn't list, and the IGDB link then records that game on my Platform. One Game per add: playing it on another Platform means adding it again.
- **After adding:** the Game takes IGDB's name, Cover and link, and its Game detail opens. Nothing else is asked up front.
- **No duplicate IGDB links:** a chip whose IGDB game and Platform already belong to a Game is marked "In journal", and clicking it opens that Game. A later Import attaches a matching ROM to that Game rather than creating a new one.
- **Creating a Game by hand** (no IGDB link): "Add by hand" at the foot of the search results, with the name pre-filled from the search box. Name and Platform are required. A Cover upload is optional, and everything else is edited in Game detail.
- **Duplicate warning for hand-made Games:** if a Game on the same Platform has a name that *agrees* (the matching normalisation, against its display name and its IGDB names), I'm asked to **Open** it or **Add anyway**. It warns and never blocks, because two games on one platform can share a name.
- **Linking a hand-made Game later:** a Game with no IGDB link can gain one through the same search, filtered to its Platform. Its name then follows IGDB unless I've overridden it, and its Cover becomes IGDB's. If another Game already holds that link, it's refused ("Already linked to X"), since combining Games is a non-goal. An existing link is never changed or removed.
- **One search component:** the Review queue's manual IGDB search is this same search. There, the Platform filter is pre-set to the ROM's platforms, and clicking a result Matches the ROM instead of adding a Game.
- **A hand-made Game created from a ROM** (Review queue, no suggestion): its Platform is pre-selected from the ROM's OpenEmu system. Where the system maps to several IGDB platforms (`openemu.system.gb` covers Game Boy and Game Boy Color), I choose from those, and can still pick any other Platform.

### Journal data
- **Rating:** 0.0–10.0, or unrated (different from 0.0). One per Game, with a Rating history of dated entries. Stars imported from OpenEmu become ×2 (3★ → 6.0), dated at import and marked imported/approximate.
- **Rating history:** at most one entry per day (local time). Changing the Rating again the same day replaces that day's entry, and re-entering the current value does nothing. An imported entry is never replaced. Clearing a Rating adds an "unrated" entry. Entries can be deleted but not edited, so there's no backdating. Deleting the latest entry makes the previous one the Rating.
- **Playthrough:** every field optional (start and end as Partial dates, Outcome of Finished or Dropped, notes, Version, Played via), except that a Playthrough with no Outcome is in progress and **must have a start date**. So an in-progress Playthrough's start date can't be cleared, and removing the Outcome from a Playthrough with no start date asks for one. **The end date can't come before the start date**, compared with the Partial date sort, and a less precise date is allowed when it contains the other (start `2024-03`, end `2024` is fine; end `2023` is refused on save). Version and Played via are free text, with suggestions drawn from the Game's ROM names.
- **Intent:** none, Backlog, or Up next (a set, not ordered). It doesn't depend on Playthroughs. The date and time it was set is recorded (never edited by hand): changing the value resets it, clearing Intent drops it, and setting the same value again does nothing. Intent from the first Import is undated.
- **Partial dates sort** as if the missing parts came first: `2024` < `2024-01` < `2024-01-05`.
- **Childhood:** a flag on a Game.
- **Lists:** named, unordered, curated. A Game can be in many.
- **Activity:** read-only play stats summed across a Game's ROMs. A snapshot is saved at each Import so play time can be credited to a year.
- **Cover:** the IGDB cover. If IGDB has none, OpenEmu's existing box art carried over at the first Import, or an image I upload. See [Covers](#covers).

### Deleting
- **A Game with present ROMs can't be deleted.** The UI says to remove its ROMs in OpenEmu first. There's no "ignored ROM": unwanted ROMs are removed in OpenEmu.
- **Deleting a Game** hard-deletes all its journal data (Rating history, Playthroughs, Intent, Childhood, List memberships, Activity snapshots, IGDB link, uploaded Cover) and its missing ROMs with their Matches. If one of those ROMs reappears, a later Import matches it again as new. Stars and Covers already synced stay in OpenEmu.
- **Games whose ROMs are all missing** stay as normal Games, marked "no ROM in OpenEmu". They're never hidden or deleted automatically.
- **A single missing ROM** can't be removed from its Game.
- **Deleting a List** leaves its Games untouched. The next Sync deletes its collection without asking for the name.
- **No soft delete or undo.** Deleting a Game, List or Playthrough asks for a confirmation that says what goes with it. The automatic backups are the safety net.

### First Import from OpenEmu
- Reads a snapshot of OpenEmu's database, taken with SQLite's backup API. Safe while OpenEmu is running. Never writes to OpenEmu.
- Collections map as follows:

  | OpenEmu collection | Becomes |
  |---|---|
  | `_TODO` | Intent Backlog |
  | `_TODO Next` | Intent Up next |
  | `_Current` | a Playthrough in progress, with the start date I enter during the Import |
  | `_Completed` | a Finished Playthrough with no dates (OpenEmu's last-played date is shown as a hint) |
  | `_Childhood Played` | the Childhood flag |
  | every other collection | a List |

- **Matching** (confirmed in the dry run on the `prototype/first-import` branch; rules measured on `prototype/matching-rules`):
  1. Hasheous lookup by OpenEmu's MD5. Uncompressed or small archived NES/SNES dumps are retried with the header stripped, only if the file is already on disk. CD images are never read.
  2. It's an **Automatic** Match only when the checksum *and* the name agree ([ADR 0004](adr/0004-automatic-match-needs-checksum-and-name.md)). An IGDB Bundle (`game_type` 3) is treated like any other game: single-cartridge collections (Super Mario Advance, Kirby Super Star, Super Mario All-Stars) really are Bundle records, and the name rule already keeps out wrong multi-game packs.
  3. Everything else goes to the **Review queue**, with one suggestion or none:
     - If the checksum's names disagree, a **related record** of the checksum's game whose name agrees (`parent_game`, `version_parent`, `expanded_games`, `remasters`, `remakes`, `ports`, `standalone_expansions`, `forks`) is the suggestion, e.g. *Resident Evil 2: Dual Shock Ver.* for a checksum pointing at *Resident Evil 2*. Otherwise the checksum's own game is.
     - With no checksum game, IGDB name search on the ROM's platforms. The suggestion is the first candidate whose name agrees, else the first candidate. Candidates of `game_type` Mod (5), DLC (1), Expansion (2), Season (7), Pack/Addon (13) and Update (14) are never suggested.
     - Otherwise no suggestion (search IGDB by hand).
  4. The Review queue can bulk-confirm suggestions whose names agree.
  5. Expected load on my library: about 907 Automatic, about 223 of 224 name suggestions bulk-confirmable, about 35 with nothing. That leaves about 30 checksum suggestions (4 of them bulk-confirmable through a related record), 1 name suggestion and 35 manual searches.
- **Names agree** when any ROM-side name equals any IGDB-side name after normalising. Never prefix or containment: nearly every wrong checksum match is the IGDB name being a prefix of the ROM's title (*Super Star Wars* for *Super Star Wars: Return of the Jedi*).
  - ROM side: the ROM's name and OpenVGDB's title (`ZGAMETITLE`). Bracketed groups are removed. A ` ~ ` separates alternative titles. Title and subtitle may be swapped (`Super Mario Advance 2 - Super Mario World`). File artefacts are removed: `.nkit`, `.sav`, trailing copy numbers, `-redump`, `# GBA`, patch suffixes, leading scene release numbers, and for bracket-free homebrew names underscores and a trailing version (`Feed_IT_Souls_v1.4`).
  - IGDB side: the game's `name`, every `alternative_names[].name` (acronyms included) and every named `game_localizations[]`. An alt name whose comment starts "Japanese", "European", "Korean" or "(North) American", and a Japan, Europe or Korea localization, only count for a ROM from that region (or of unknown region), so *Lilo & Stitch 2*'s Japanese title "Lilo & Stitch" doesn't match a USA *Lilo & Stitch*.
  - Normalising: lowercase; fold diacritics; `&` → `and`; split into words on anything but letters and digits; roman numerals II–XX become digits (not I, V or X); drop `and`, every `the`, and a leading `a`/`an`; drop a leading `Disney's`, `Disney-Pixar's`, `James Bond`, `Tom Clancy's` or `Sid Meier's`; join the words.
- **Versions** aren't parsed into fields. A Version is described by the ROM name's tags as written (region, languages, revision, dev status, translation and so on), without the Disc and its label, GoodTools dump flags (`[!]`, `[a]`, `[b]`…) and file artefacts. Real names mix No-Intro, Redump, GoodTools, scene and ad-hoc forms, and a Version is only ever shown or suggested as text.
- **Discs:** the present ROMs of one Game that each carry a `(Disc N)`, with no number repeated, are the Discs of one Version, whatever else their names say (Gran Turismo 2's two Discs come from different DAT versions). An `.m3u` playlist ROM of that Game belongs to the same Version. The free-form flag straight after `(Disc N)` is the disc label.
- **Start dates for `_Current`:** an in-progress Playthrough needs a start date, so the first Import lists the `_Current` Games (7 in my library) and asks for each one's start date (a Partial date). For any of them I can choose "Not playing" instead, and no Playthrough is created. The Import draft can't be committed until every one is answered.
- **Duplicate Versions** (2 or more *present* ROMs on one Game that aren't Discs of one Version) block the first Import until I remove ROMs in OpenEmu. There's no exceptions mechanism, and the UI should say that real exceptions need a code change. With these rules my library has 2: Double Dragon III (Japan and USA) and Sweet Home (two translations).
- **The first Import is staged, as an Import draft.** Nothing becomes journal data until the draft is committed, in one step. The draft (the OpenEmu snapshot plus my answers so far) is saved, so quitting the app resumes it. While a draft exists, Sync and ongoing Imports aren't available.
  - **Committing** needs only two things: no Duplicate Versions, and every `_Current` start date answered. Unmatched ROMs and pending suggestions carry over into the journal's Review queue as ordinary items, their ROMs imported unmatched with their OpenEmu data held until they're resolved.
  - **Duplicate Versions items** show the Game and one row per present ROM: its Version text, file name, OpenEmu data (stars, collections, play time, so I see what I'd lose) and "Show in Finder". Below: remove all but one Version in OpenEmu (exceptions need a code change), and **Check again**. There's no in-app resolve.
  - **Check again** (on those items and on the Import screen) re-reads OpenEmu into the draft. Answers whose ROM (`Z_PK` + MD5) is still present are kept; answers for ROMs that have gone are dropped; new ROMs go through matching. The last re-read is the baseline committed (store UUID, Activity snapshot, stars and collections).
  - **A ROM removed before the commit** is dropped entirely: never a missing ROM, its OpenEmu data never imported. Orphaned entries (row kept, file gone) are still imported as missing and don't count towards Duplicate Versions.
  - **Confirming a suggestion or assigning a ROM to a Game** that would then have Duplicate Versions warns but doesn't block, and the result blocks the commit like any other.
  - **Discard draft** throws the draft and my answers away; the next Import starts fresh. A committed draft has no undo.
- **Orphaned OpenEmu entries** (the ROM file is missing; 150 of them, 60 holding data) are imported with the ROM marked missing.
- **Ongoing Imports:** new ROMs go through the same matching. A ROM that disappears is marked missing, and its last Activity is kept. A new ROM (or a Review queue answer) that gives an existing Game Duplicate Versions is still Matched; the Game gets a Duplicate Versions item in the Review queue, keeps its journal data and stays editable, but isn't synced. Each ongoing Import re-checks it.
  - **When they run:** at app launch, each time OpenEmu quits while the journal is open (so snapshots line up with play sessions), and by hand with "Import now". The journal never watches OpenEmu's database files.
  - **Activity snapshots:** each Import stores a snapshot row only for ROMs that are new or whose Activity changed since their last snapshot.
  - **What I'm told:** Automatic Matches are added silently. The Review queue carries a count badge. After an Import that changed something, a dismissible in-app summary lists ROMs added, matched, sent to review and gone missing (linking to their Games). An Import that changed nothing shows nothing. No system notifications.
  - **Reappearing ROMs:** a ROM that comes back with the same OpenEmu `Z_PK` or MD5 rejoins its old Game with its old Match, without review.
  - **A changed store UUID** (library rebuilt or replaced): the Import refuses and explains why, as Sync does. Re-pointing the journal at a new library is out of v1.

### Covers
- **IGDB covers stay in the cache.** The journal stores only the IGDB link. The cover comes from the cached record's `image_id` at IGDB's `cover_big_2x` size (528×748 JPEG), downloaded on demand into the cache's images folder. A Cover not yet downloaded shows a placeholder. If IGDB changes a cover, the journal follows it at the next refresh, and a wiped cache downloads it again.
- **Journal-owned Covers** (carried over or uploaded) are stored in the journal database as BLOBs, so the dated backups carry them and deleting a Game removes its Cover in the same transaction. There are few of them: in my library only 17 of 1,822 IGDB games have no cover.
- **Normalised on the way in:** decoded, shrunk to fit a 1,200 px long edge (never enlarged), and re-encoded as JPEG at quality 0.9. Uploads take anything macOS can decode (PNG, HEIC, WebP, …), by file picker or drag-and-drop.
- **Carried over at the first Import only:** every Game created from a ROM during the first Import (Automatic, confirmed in its Review queue, or hand-made from it) that has no IGDB cover at that moment takes its ROM's OpenEmu box art, read from `Artwork/` and normalised. With several ROMs, the lowest `Z_PK` wins. ROMs resolved after the first Import get nothing, and I upload instead.
- **IGDB always wins.** Upload, replace and remove are offered only while a Game has no IGDB cover. A journal-owned Cover is deleted, with no prompt, as soon as an IGDB cover exists: when a hand-made Game gains an IGDB link whose record has a cover, or when a refresh brings a cover to a linked Game's record. If IGDB later drops the cover, the Game shows a placeholder and I can upload again. So my 63 hand-picked OpenEmu images aren't imported for Games whose IGDB record has a cover, though OpenEmu keeps them, since Sync never touches existing box art (overriding covers is a non-goal).

### Sync to OpenEmu
Writes straight into OpenEmu's Core Data SQLite store (`Library.storedata`). The spike on branch `prototype/openemu-write` showed that OpenEmu 2.4.1 keeps such writes across relaunch, its own edits and its launch-time OpenVGDB lookup ([findings](https://github.com/danielholmes/games-journal/blob/research/openemu-database/docs/research/openemu-database.md)).

- Runs by hand, only while OpenEmu is closed, after backing up OpenEmu's database.
- **Stars:** the Rating ÷ 2, rounded half up (0.0–0.9 → no stars), written to `ZGAME.ZRATING` of the OpenEmu game row of each of the Game's ROMs. OpenEmu keeps one game row per ROM. Values are always 0–5, and 0 means no stars (never NULL).
- **Collections:** each List, plus `_TODO`, `_TODO Next`, `_Current` and `_Completed` built from Intent and Playthroughs, are owned by the journal and overwritten. Other regular collections are deleted after I confirm them by name. Smart collections and collection folders are left alone.
- **Covers:** written only for games that have no box art in OpenEmu and whose OpenEmu status is 0. A game still waiting for its OpenVGDB lookup (status 3) is skipped until a later Sync, because the lookup can replace its box art. Each OpenEmu game row gets its own file and `ZIMAGE` row (`ZBOX` is one-to-one). If an IGDB cover can't be downloaded, that Cover is skipped for this Sync, and it isn't an error.
- **Replacing a Cover Sync wrote:** when the Game's Cover changes (e.g. an upload replaced by IGDB's cover on linking), Sync replaces it, but only while the OpenEmu game's `ZBOXIMAGE` still points at the `ZIMAGE` row Sync wrote. If I've changed the box art in OpenEmu, it's left alone and the journal forgets its record. A Game whose Cover goes away leaves OpenEmu's box art as it is: Sync never deletes box art.
- A Game with unresolved Duplicate Versions isn't synced; the Sync preview lists it as skipped, and why.
- **Guards:** Sync refuses to run while OpenEmu (`org.openemu.OpenEmu`) is running, if a Dropbox "conflicted copy" sits next to the store, or if the store's UUID isn't the one Imported. It runs `PRAGMA integrity_check` before and after. There's no waiting for Dropbox: on one Mac the local files are the truth.
- **Backup:** SQLite's backup API, taken while OpenEmu is closed (the store is WAL, so copying `Library.storedata` alone can lose data).
- **Writing, the way Core Data would:**
  - All writes happen in one transaction, followed by `PRAGMA wal_checkpoint(TRUNCATE)`, so Dropbox sees a complete main file and an empty WAL.
  - Every inserted row takes `Z_MAX + 1` from its **root** entity's `Z_PRIMARYKEY` row (`AbstractCollection` for collections, `Image` for covers), and `Z_MAX` is raised in the same transaction. **This is mandatory:** in the spike, a row inserted without it was silently overwritten by OpenEmu's next insert.
  - Entity numbers (`Z_ENT`) are read from `Z_PRIMARYKEY` by name, never hard-coded. Inserted rows get `Z_OPT = 1`, and every updated row gets `Z_OPT + 1`, including both ends of a membership change (the `Z_2GAMES` join row).
  - Journal-owned collections are updated in place (name and membership), keeping their `Z_PK`. Deleting a collection deletes its join rows too, and only rows whose `Z_ENT` is `Collection`.
  - A Cover is a new UUID-named file (no extension) in `Artwork/` holding the Cover's JPEG bytes unchanged (IGDB's `cover_big_2x`, or the normalised journal-owned image), plus a `ZIMAGE` row (`ZFORMAT` 3, pixel width and height, `ZRELATIVEPATH` = the file name, `ZSOURCE` NULL) linked both ways (`ZGAME.ZBOXIMAGE` and `ZIMAGE.ZBOX`). The file is always new, never overwritten.
  - Replacing a Cover Sync wrote updates its `ZIMAGE` row in place (new file name, width and height, `Z_OPT + 1`), like a journal-owned collection. The old file is deleted after the commit.
  - `Z_METADATA` and the schema are never touched.
- **OpenEmu identifiers the journal keeps:** the store UUID (`Z_METADATA.Z_UUID`) of the library it Imported; each ROM's OpenEmu `Z_PK` and MD5 (Sync looks up `ZROM.ZGAME` fresh each time); the `Z_PK` of each journal-owned collection (if it's gone, Sync creates a new one); and the `ZIMAGE` `Z_PK` of each Cover Sync wrote, with which Cover it was (the IGDB `image_id`, or a hash of the journal-owned image). Core Data never renumbers `Z_PK`s.

### External data and cache (built: `JournalCore`)
- **IGDB** (Twitch app token): the full game record, with every useful sub-record expanded plus time-to-beat. Fetched in batches of 100 (halved if IGDB answers 413). One request per name search, since multiquery ignores `search`. At most 3 requests a second.
- **Hasheous:** MD5 → IGDB game and platform. "Not found" is cached. At most 1 request a second. An optional app key can be set with `HASHEOUS_API_KEY`.
- **Cache:** entries keyed as `source:kind:id`, fresh for 60 days. An expired entry is still used if refreshing it fails. Only successful answers are cached. Images never expire. Runs can be interrupted and resumed.

### What to play next and Top-rated
- **What to play next** is a plain view, with no ranking or suggestions. It has three sections: **Playing**, **Up next** and **Backlog**. Each Game appears once, in the first section that fits (a Game that's Playing and Up next shows under Playing).
- **Sorting:** the same filter and sort controls as the Library. Up next and Backlog default to when the Intent was set, newest first, with undated Intent after every dated one, by name. Playing defaults to the in-progress Playthrough's start date, newest first (a Game's latest start counts if several are in progress). Name order is available too. "Intent set" is also a Library sort, with Games that have no Intent last.
- **Start playing:** an action on a Game in Up next or Backlog. In one step it creates an in-progress Playthrough starting today (day precision) and clears the Game's Intent.
- **Top-rated** is one list of every rated Game, by current Rating, highest first, with no top-N cut-off. It has the same filters as the Library (Platform, List, Childhood), so "per Platform" is the Platform filter.
- **Ties share a rank** (1, 2, 2, 4) and are listed by name. There's no hidden tie-break.
- **Imported Ratings** are included, each marked "≈ imported". The mark disappears once I re-rate the Game.
- **Unrated Games never appear.** A Rating of 0.0 is a real Rating and appears. Rating history plays no part.

### Year in review
A nice-to-have: built after the rest of v1 works.

- **One year at a time**, chosen from a picker listing only years with something in them. The current year is labelled "so far". The Library's filters (Platform, List, Childhood) apply.
- **Sections:** **Finished** and **Dropped** (Playthroughs that ended that year, with the Game's Cover, Rating and Platform); **Also played** (Playthroughs active that year that didn't end in it); **Play time** (tracked OpenEmu play time credited to that year, per Game, most first, with a total); and **summary numbers** (Finished, Dropped and Started counts, tracked hours, a per-Platform breakdown). Rating history and Childhood play no part.
- **Which years a Playthrough counts for:** every year from its start year to its end year (to the current year while in progress). It's under Finished or Dropped in its end year and under Also played in each year before that. Every Partial date has a year, so precision doesn't matter here.
- **Missing dates:** an ended Playthrough with a start date but no end date counts in its start year under Finished or Dropped, marked "end date unknown". One with an end date but no start date counts only in its end year. One with no dates appears in no year, and the footer says "N Playthroughs have no dates", linking to a Library filter for them.
- **Crediting Activity:** per ROM, the play time added since the previous snapshot is credited to one year, and a Game's time is the sum over its ROMs.
  - Both snapshots in the same year: that year. Straddling New Year: the year of the ROM's last-played date at the later snapshot. It's a heuristic, and more frequent Imports shrink the error.
  - A ROM first seen after the first Import: all its play time is tracked (a delta from zero), since it wasn't in the library at the previous Import.
  - Play time went down (a ROM re-added, stats reset): nothing is credited, and the new value becomes the baseline.
  - A missing ROM adds nothing, and its last snapshot stays the baseline if it comes back.
- **Before tracking:** play time in the first Import's snapshot (381 h in my library) has no year and never appears here. Game detail shows it inside the total, e.g. "Play time 12 h 30 m (9 h before tracking)".
- **Non-emulated Games** have no play time. The section is labelled "OpenEmu play time", and those Games appear through their Playthroughs only. There's no hand-typed hours field.

### Version 1 screens
Library (filter and sort by Platform, Rating, Intent, Intent set, List, Outcome, Childhood); Game detail (editing); What to play next; Year in review; Top-rated; Import, Review queue and Sync.

## Fog: open questions

Roughly in the order they block work:

1. **Journal database schema:** tables for Game, ROM, Match, Rating history, Playthrough, List, Activity snapshots and Covers; migrations; how Partial dates are stored.
2. **App skeleton:** Xcode project versus SwiftPM-only; how the app hosts `JournalCore`; where Import, Sync and background work run; signing for personal use.
3. **Review queue UX:** layout for bulk confirm, the checksum-suggestion view, manual IGDB search (the shared search from Adding Games), and assigning a ROM to an existing Game (fan translations).
4. **Backups:** how often journal backups are copied to Dropbox and how many are kept.
5. **Credentials in the app:** moving from `.env` to the Keychain; a settings screen; whether to request a Hasheous app key.
6. **Later enrichments** (deliberately out of v1, listed so they aren't lost): IGDB screenshots and artwork, series, similar games and time-to-beat on screen; ScreenScraper for manuals and box, cart and disc scans; Steam playtime; RetroAchievements; SteamGridDB for PC art.

## Built so far

- `JournalCore`: cache store, `IGDBClient` (games, search, covers, Twitch token handling), `HasheousClient`, throttling. 24 tests at the agreed boundaries. CI: lint, build with warnings as errors, tests.
- `journal-import check`: a live check against IGDB and Hasheous.
- `scripts/setup-igdb.sh`: the IGDB credentials wizard.
- Branch `prototype/first-import`: a throwaway dry run of the first Import. Its verdict is in the commit message and folded into the decisions above.
- Branch `prototype/openemu-write`: a throwaway spike that wrote a Sync into a copy of the OpenEmu library. Its verdict is in the commit message and folded into Sync to OpenEmu above.
- Branch `prototype/matching-rules`: a throwaway measurement of the matching rules against the dry run's snapshot (`journal-import prototype-matching-rules`). Its verdict is in the commit message and folded into First Import above.
