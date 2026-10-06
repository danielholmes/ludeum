# Ludeum: spec

A native macOS app for keeping a personal journal of the games I play on every Platform: ratings, Playthroughs, what to play next. It imports from, and syncs back into, my OpenEmu library.

This file holds the decisions made so far and the open questions (fog). Vocabulary is defined in [`CONTEXT.md`](../CONTEXT.md). The reasons behind hard-to-reverse choices are in [`docs/adr/`](adr/). Where this file and those disagree, the glossary and the ADRs win, and this file needs fixing.

## Goals

- Journal data belongs to a **Game**, never to a ROM file. Removing or re-adding a ROM, or swapping it for another Version, loses nothing.
- Richer data than OpenEmu offers: a Rating out of 10 in steps of 0.1 with its history, notes, and Playthroughs with Partial dates.
- Covers every Platform (retro, PC, Xbox, …), not just emulated games.
- Existing OpenEmu data (collections, play stats) is brought across (stars are not: Ratings start fresh), and OpenEmu stays usable as the place I actually play.

## Non-goals (for now)

Phone or remote access; several Macs; a fork of OpenEmu; two-way sync; importing from Steam or Xbox; exceptions to the Duplicate Versions rule; combining Games; moving a ROM to another Game after its Match; organising Lists automatically from IGDB data; ScreenScraper media (manuals); back, cart and disc scans; showing Screenshots and Cover art (they're stored, not yet shown).

## Decisions so far

### Architecture
- SwiftUI app plus the `LudeumCore` Swift package, with GRDB/SQLite for storage ([ADR 0003](adr/0003-swiftui-not-go.md)). The `ludeum-import` CLI exists for development tasks.
- The journal owns its data. OpenEmu only receives a one-way **Sync** ([ADR 0001](adr/0001-journal-owns-data-one-way-sync-to-openemu.md)).
- One Mac. The journal database lives in `~/Library/Application Support/Ludeum/`, with automatic dated backups in Dropbox (see [Backups](#backups)). The cache is a separate file in the same folder, excluded from backups.
- Credentials live in the Keychain (see [Settings and credentials](#settings-and-credentials)). `.env` is only for the CLI and tests (see `scripts/setup-igdb.sh`).

### App skeleton
- **Project shape:** XcodeGen. A `project.yml` defines the app target, which depends on the local package's `LudeumCore`. The generated `.xcodeproj` is gitignored. The app target sets warnings as errors, CI installs XcodeGen with brew, and the `swift build -warnings-as-errors` job stays.
- **Signing:** the free Personal Team ("Apple Development"), a stable identity, so the Dropbox access prompt and Keychain access survive rebuilds. No restricted entitlements, so the 7-day profile expiry never matters. Keychain items use the file-based keychain, which needs no profile.
- **No App Sandbox.** It's a personal app that reads and writes another app's Dropbox-backed database, so the sandbox would add friction (security-scoped bookmarks or exception entitlements) without protecting anything.
- **Where work runs:** in-process. The app calls `LudeumCore` from structured tasks off the main actor. `ludeum-import` stays a dev tool over the same `LudeumCore` calls; the app never depends on it. There's no helper, so nothing runs while the app is closed.
- **When background work runs:** only while the app is open. On launch, a low-priority refresh of expired cache entries, plus the daily backup if one is due. Covers are fetched on demand. Import and Sync run only when I start them.
- **Overlap:** Import and Sync are exclusive; while one runs, the other can't start. The background refresh pauses during either, since they share the rate limiters. Editing the journal is allowed during the refresh, but not during the Import's write step.
- **Progress and interruption:**
  - Import shows phased, determinate progress (snapshot, lookups, matching, review). It can be cancelled, and nothing is written to the journal until I confirm at the end. Lookups already made survive in the cache, so a rerun is quick. Quitting mid-Import asks first.
  - Sync is a preview, then one short transaction that can't be cancelled midway.
  - The background refresh shows only a small status indicator. Its errors are logged, not shown as alerts.

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
- **The IGDB screen:** a sidebar screen (the toolbar's Add Game button opens it) with the search and its results in the middle column. Results sort by name (A–Z, the default) or release date (newest first), undated last, and a result already in the Library is marked "In Library" with its Platforms ticked. Selecting a result shows the IGDB game in full in the detail column: cover, year, type, its platforms, then Game detail's IGDB facts and Screenshots. Both pages show IGDB's summary (four lines, then More), time to beat, a Trailer link (the first video IGDB calls a trailer) and its keywords at the foot; Library search also matches keywords.
- **Choosing the Platform:** in the IGDB game's detail, clicking a platform adds the Game to the Library on that Platform. A "Different platform…" chip opens the Platform picker, for ports IGDB doesn't list, and the IGDB link then records that game on my Platform. One Game per add: playing it on another Platform means adding it again.
- **After adding:** the Game takes IGDB's name, Cover and link. The IGDB page stays open and the platform turns "In Library", so I can keep browsing. Nothing else is asked up front.
- **No duplicate IGDB links:** a chip whose IGDB game and Platform already belong to a Game is marked "In Library", and clicking it opens that Game. Platforms not listed by IGDB that a Game holds this link on (added with "Different platform…") are shown too. A later Import attaches a matching ROM to that Game rather than creating a new one.
- **Creating a Game by hand** (no IGDB link): "Add by hand" at the foot of the IGDB screen, with the name pre-filled from the search box. Name and Platform are required. A Cover upload is optional, and everything else is edited in Game detail.
- **Duplicate warning for hand-made Games:** if a Game on the same Platform has a name that *agrees* (the matching normalisation, against its display name and its IGDB names), I'm asked to **Open** it or **Add anyway**. It warns and never blocks, because two games on one platform can share a name.
- **Linking a hand-made Game later:** a Game with no IGDB link can gain one through the same search, filtered to its Platform. Its name then follows IGDB unless I've overridden it, and its Cover becomes IGDB's. If another Game already holds that link, it's refused ("Already linked to X"), since combining Games is a non-goal. An existing link can be changed (Edit → Change IGDB link…) to fix a mistaken Match, under the same rule; it's never removed.
- **One search component:** the Review queue's manual IGDB search is this same search. There, the Platform filter is pre-set to the ROM's platforms, and clicking a result Matches the ROM instead of adding a Game.
- **A hand-made Game created from a ROM** (Review queue, no suggestion): its Platform is pre-selected from the ROM's OpenEmu system. Where the system maps to several IGDB platforms (`openemu.system.gb` covers Game Boy and Game Boy Color), I choose from those, and can still pick any other Platform.

### Journal data
- **Rating:** 0.0–10.0, or unrated (different from 0.0). One per Game, with a Rating history of dated entries.
- **Rating history:** at most one entry per day (local time). Changing the Rating again the same day replaces that day's entry, and re-entering the current value does nothing. Clearing a Rating adds an "unrated" entry. Entries can be deleted but not edited, so there's no backdating. Deleting the latest entry makes the previous one the Rating.
- **Playthrough:** **a start date is required**; every other field is optional (end as a Partial date, Outcome of Finished or Dropped, notes, Version, Played via). A Playthrough with no Outcome is in progress. **The end date can't come before the start date**, compared with the Partial date sort, and a less precise date is allowed when it contains the other (start `2024-03`, end `2024` is fine; end `2023` is refused on save). Version and Played via are free text, with suggestions drawn from the Game's ROM names.
- **Intent:** none, Backlog, or Up next (a set, not ordered). It doesn't depend on Playthroughs. The date and time it was set is recorded (never edited by hand): changing the value resets it, clearing Intent drops it, and setting the same value again does nothing. Intent from the first Import is undated.
- **Partial dates sort** as if the missing parts came first: `2024` < `2024-01` < `2024-01-05`.
- **Childhood:** a flag on a Game.
- **Lists:** named, unordered, curated. A Game can be in many.
- **Cover:** my upload, else libretro Box art, else OpenEmu Box art, else IGDB's Cover art, else a placeholder. See [Covers](#covers).

### Journal database schema
GRDB over SQLite, with foreign keys on. Table and column names are as they'll appear in `LudeumCore`.

- **Conventions:** integer `INTEGER PRIMARY KEY` ids. A Partial date is one text column (`1996`, `1996-03`, `1996-03-17`, CHECKed for shape), so plain string order is the Partial date sort and "contains" is a prefix test. Timestamps are ISO-8601 UTC text (GRDB's `Date` encoding). A Rating history day is the local date as `YYYY-MM-DD` text. Ratings are integer tenths (0–100).
- **`platform`** (IGDB platform id, name): copied from IGDB so names show without the cache.
- **`game.runAheadFrames`** (nullable integer, 0–10): the Game's own Emulator setting.
- **`game.gameBoyModel`** (nullable text: `gameBoy`, `gameBoyColor`, `superGameBoy`; null is Auto): the Game Boy Model, for Game Boy and Game Boy Color Games.
- **`game`**: `platformId` (required), `igdbGameId` (nullable, `UNIQUE(igdbGameId, platformId)`, set at most once), `igdbName` (refreshed with the cache record), `name` (hand-made or cleaned No-Intro) and `nameOverride`. The display name is `nameOverride ?? igdbName ?? name`, so the database alone (a backup, a cold cache) shows every name. Also `childhood`, `intent` (backlog/upNext, or null) and `intentSetAt` (null when undated). Intent keeps no history.
- **The current Rating is derived**, never stored: it's the latest `ratingEntry`.
- **`ratingEntry`**: `gameId`, `day`, `rating` (NULL = cleared to unrated), `UNIQUE(gameId, day)`.
- **`playthrough`**: `gameId`, `start`, `end`, `outcome` (finished/dropped, or null), `notes`, `version`, `playedVia`. `start` is NOT NULL (since `v9`). End ≥ start is checked in app code.
- **`list`** (`name` UNIQUE) and **`listGame`**.
- **`cover`**: `gameId` as PK, `jpeg` BLOB, width, height, `sha256`. It holds uploads only.
- **`rom`**: one row per OpenEmu ROM: `openEmuPk` UNIQUE, `md5`, file name, OpenEmu system id, `missing`, `version` text, `discNumber`, `discLabel`. **The Match is columns on the ROM:** `gameId`, `matchKind` (automatic/confirmed/manual) and `matchedAt` are all null or all set (CHECK). An unmatched ROM is in the Review queue.
- **Review queue suggestions are stored** on the ROM when the Import commits (`suggestedIgdbGameId`, `suggestionKind` checksum/name, `checksumIgdbGameId` for the crossed-out checksum game, `namesAgree`) and cleared on matching. Opening the queue makes no IGDB calls.
- **`import`** (`startedAt`, `isFirst`). There is no Activity (ADR 0007): OpenEmu's play stats aren't read.
- **Sync bookkeeping:** `syncedCollection` holds `openEmuPk` plus either `listId` (ON DELETE SET NULL) or `special` (`_TODO`/`_TODO Next`/`_Current`/`_Completed`). A row with neither is a deleted List's collection, which the next Sync deletes without asking for its name. `syncedCover` holds `openEmuImagePk`, `romId` and `coverKey` (which image it was: the libretro or IGDB image name, the OpenEmu image's hash, or the upload's sha256). The OpenEmu store UUID sits in a one-row `openEmuLibrary` table.
- **Deleting a Game** relies on `ON DELETE CASCADE` all the way down (Rating history, Playthroughs, List memberships, Cover, ROMs → synced covers). The app refuses before that while the Game has a present ROM.
- **Migrations:** GRDB's `DatabaseMigrator`, like the cache. There's one `v1` migration, edited freely until the first real Import into the production database, then append-only, with a backup before migrating. `eraseDatabaseOnSchemaChange` is for development only.

### Deleting
- **A Game with present ROMs can't be deleted.** The UI says to remove its ROMs in OpenEmu first. There's no "ignored ROM": unwanted ROMs are removed in OpenEmu.
- **Deleting a Game** hard-deletes all its journal data (Rating history, Playthroughs, Intent, Childhood, List memberships, IGDB link, uploaded Cover) and its missing ROMs with their Matches. If one of those ROMs reappears, a later Import matches it again as new. Stars and Covers already synced stay in OpenEmu.
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
  | `_Completed` | nothing: a Playthrough needs a start date, which OpenEmu doesn't have |
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
  - **Duplicate Versions items** show the Game and one row per present ROM: its Version text, file name, OpenEmu data (stars, collections, so I see what I'd lose) and "Show in Finder". Below: remove all but one Version in OpenEmu (exceptions need a code change), and **Check again**. There's no in-app resolve.
  - **Check again** (on those items and on the Import screen) re-reads OpenEmu into the draft. Answers whose ROM (`Z_PK` + MD5) is still present are kept; answers for ROMs that have gone are dropped; new ROMs go through matching. The last re-read is the baseline committed (store UUID, stars and collections).
  - **A ROM removed before the commit** is dropped entirely: never a missing ROM, its OpenEmu data never imported. Orphaned entries (row kept, file gone) are still imported as missing and don't count towards Duplicate Versions.
  - **Confirming a suggestion or assigning a ROM to a Game** that would then have Duplicate Versions warns but doesn't block, and the result blocks the commit like any other.
  - **Discard draft** throws the draft and my answers away; the next Import starts fresh. A committed draft has no undo.
- **Orphaned OpenEmu entries** (the ROM file is missing; 150 of them, 60 holding data) are imported with the ROM marked missing.
- **Ongoing Imports:** new ROMs go through the same matching. A ROM that disappears is marked missing. A new ROM (or a Review queue answer) that gives an existing Game Duplicate Versions is still Matched; the Game gets a Duplicate Versions item in the Review queue, keeps its journal data and stays editable, but isn't synced. Each ongoing Import re-checks it.
  - **When they run:** at app launch, each time OpenEmu quits while the journal is open (so snapshots line up with play sessions), and by hand with "Import now". The journal never watches OpenEmu's database files.
  - **What I'm told:** Automatic Matches are added silently. The Review queue carries a count badge. After an Import that changed something, a dismissible in-app summary lists ROMs added, matched, sent to review and gone missing (linking to their Games). An Import that changed nothing shows nothing. No system notifications.
  - **Reappearing ROMs:** a ROM that comes back with the same OpenEmu `Z_PK` or MD5 rejoins its old Game with its old Match, without review.
  - **A changed store UUID** (library rebuilt or replaced): the Import refuses and explains why, as Sync does. Re-pointing the journal at a new library is out of v1.

### ROM folders (PS2)

- **A ROM folder** holds a Platform's ROMs for Platforms OpenEmu doesn't have. Only PS2 has one: `~/Dropbox/games/PS2` by default, changeable in Settings. Every ongoing Import reads it after OpenEmu; a folder that can't be read is skipped, leaving its ROMs alone. Hidden folders are ignored.
- **Files:** what PCSX2 opens is ready (`.iso`, `.chd`, `.cso`, `.zso`, `.gz`, `.cue`, `.bin`, `.mdf`, preferred in that order); a `.7z` is **Archived**; anything else, including `.zip` and `.rar`, is ignored. A cue sheet's `FILE` tracks belong to it. A subfolder is a ready ROM named after itself when it holds one cue sheet, or one image and no cue sheet, at any depth, whatever else is in it; a subfolder of the same name wins over a loose file.
- **Identity:** a ROM is its file name without the extension, or its subfolder's name (`rom.folderName`, unique per system), with `systemId` `ludeum.folder.ps2` standing in for an OpenEmu system. It has no `openEmuPk` or `md5`. Unarchiving or Archiving changes one ROM between archived and ready silently, keeping its Match; when both files exist the ready one is used. A ROM whose files are all gone is missing, as for OpenEmu.
- **Matching:** no checksum, so a new folder ROM always goes to the Review queue, with an IGDB name suggestion where there is one (ADR 0004 unchanged).
- **Archived:** present, so it counts against deleting its Game, but there's nothing to Play: Game detail shows "Archived: unarchive to play" with **Unarchive**.
- **Archive / Unarchive** (PS2 only), on each present ROM in Game detail, run as Background tasks with Homebrew's 7-Zip (`7zz`; without it they say to `brew install sevenzip`). Work happens in a hidden `.ludeum-work` folder inside the ROM folder (cleared at launch, so an interrupted task leaves nothing behind) and moves into place only once checked; the file it replaces goes to the **Trash**, last. A task first checks there's enough free space.
  - **Archive** packs the ROM's folder's contents (or a loose file, a cue sheet with its tracks) into `<ROM name>.7z` with `-mx=9`, runs `7zz t`, and checks the listing before trashing what it packed.
  - **Unarchive** accepts any `.7z` and unpacks all of it into `<ROM name>/`, so nothing inside needs renaming and extras (a readme) come along. It reads the listing first: an archive without one cue sheet or one image is refused. Extracted sizes are checked against the listing before the `.7z` is trashed.
  - When a task finishes, the Game's ROMs are re-read (`checkROMsAgain`).
- **Background tasks** panel at the foot of the sidebar: hidden when idle, one line while busy ("Archiving ICO · 42%", plus waiting and failed counts), and opened, each task with progress and Cancel; failures stay until dismissed. Tasks run one at a time and keep going on other screens. The launch cache refresh shows here too. Quitting while tasks are queued or running asks first.
- **Sync** skips folder ROMs. **Box art** comes from libretro's `Sony - PlayStation 2` set by file name.

### Covers
Decided on [Map: Game images](https://github.com/danielholmes/games-journal/issues/40). Why Box art comes first: [ADR 0006](adr/0006-box-art-before-igdb-cover-art.md).

- **Which image a Game shows:** my upload, else libretro Box art, else OpenEmu Box art, else IGDB's Cover art, else a placeholder. Games with no ROM (PC, Xbox) have no Box art, so they show IGDB's Cover art.
- **Which ROM's Box art:** the present Version's (a Game has at most one, by the Duplicate Versions rule). A multi-disc Version uses its disc-less libretro name ("Parasite Eve II (USA)"), and for OpenEmu Box art the playlist ROM's, else Disc 1's. Missing ROMs count only when nothing is present: then the most recently added missing ROM's. A Playthrough's Version never affects the Cover.
- **libretro-thumbnails** ([research](https://github.com/danielholmes/games-journal/blob/research/libretro-thumbnails/docs/research/libretro-thumbnails.md)): at each Import, every new ROM is looked up against the repos' file listings, in order: the file name minus its extension (with libretro's `&*/:\`<>?\|` → `_` substitutions), then the name with GoodTools tags rewritten to No-Intro ones, then a fuzzy title match on the file name, then on the OpenEmu or IGDB title. Fuzzy matches are accepted silently; a wrong one is fixed by uploading. When several regions match, the ROM's own region wins, else USA, Europe, Japan. `openemu.system.gb` looks in both Game Boy and Game Boy Color. The ROM keeps the libretro names found for `Named_Boxarts`, `Named_Snaps` and `Named_Titles`. Images come from `thumbnails.libretro.com` (raw GitHub returns symlink text for per-disc covers). This finds Box art for about 97% of my Games.
- **OpenEmu Box art** is copied from `Artwork/` into the cache at every Import, for every ROM that has it (not just at the first Import). It isn't backed up. Nothing assumes I keep or drop OpenEmu.
- **IGDB:** each linked Game's Cover art (`cover` `image_id`, `cover_big_2x`) and Screenshot ids stay on its cached record. Cover art is the last fallback above; Screenshots and Cover art are stored for showing elsewhere later.
- **Everything but uploads lives in the cache,** unbacked, downloaded the first time it's shown (a placeholder until then). A wiped cache downloads it again, and the OpenEmu copies come back at the next Import.
- **Uploads** are allowed on any Game, and win over everything. They're stored in the journal database as BLOBs (backed up, deleted with the Game), normalised on the way in: decoded, shrunk to fit a 1,200 px long edge (never enlarged), re-encoded as JPEG at quality 0.9. Anything macOS can decode, by file picker or drag-and-drop. Removing an upload falls back down the order.
- **Carried-over Covers from the first spec are deleted** when this ships: the cache copy of the same OpenEmu Box art replaces them. My journal has one.

### Sync to OpenEmu
Writes straight into OpenEmu's Core Data SQLite store (`Library.storedata`). The spike on branch `prototype/openemu-write` showed that OpenEmu 2.4.1 keeps such writes across relaunch, its own edits and its launch-time OpenVGDB lookup ([findings](https://github.com/danielholmes/games-journal/blob/research/openemu-database/docs/research/openemu-database.md)).

- Runs by hand, only while OpenEmu is closed, after backing up OpenEmu's database.
- **Stars:** the Rating ÷ 2, rounded half up (0.0–0.9 → no stars), written to `ZGAME.ZRATING` of the OpenEmu game row of each of the Game's ROMs. OpenEmu keeps one game row per ROM. Values are always 0–5, and 0 means no stars (never NULL).
- **Collections:** each List, plus `_TODO`, `_TODO Next`, `_Current` and `_Completed` built from Intent and Playthroughs, are owned by the journal and overwritten. Other regular collections are deleted after I confirm them by name. Smart collections and collection folders are left alone.
  - **The first Sync adopts by name:** an OpenEmu collection already named like a List or a special collection becomes the journal's (keeping its `Z_PK`) instead of a duplicate being created. A deleted List's collection is deleted at the next Sync without asking, since the journal owned it.
  - **Only the journal's Games:** Sync decides membership only for OpenEmu games that belong to a journal Game. ROMs still in the Review queue, and Games with Duplicate Versions, keep the memberships they have in OpenEmu.
  - **Not while importing:** Sync isn't available before the first Import is committed or while an Import runs, and Imports don't start during a Sync. OpenEmu's backup goes where the journal's backups go.
- **Covers:** written only for games that have no box art in OpenEmu and whose OpenEmu status is 0, whatever the Cover's source. OpenEmu's own box art is never overwritten, uploads included. A game still waiting for its OpenVGDB lookup (status 3) is skipped until a later Sync, because the lookup can replace its box art. Each OpenEmu game row gets its own file and `ZIMAGE` row (`ZBOX` is one-to-one). Sync downloads any Cover it needs that isn't cached yet; if that fails, the Cover is skipped for this Sync, and it isn't an error.
- **Replacing a Cover Sync wrote:** when the Game's Cover changes (e.g. IGDB Cover art replaced by libretro Box art: the 42 Covers my first Sync wrote are replaced this way), Sync replaces it, but only while the OpenEmu game's `ZBOXIMAGE` still points at the `ZIMAGE` row Sync wrote. If I've changed the box art in OpenEmu, it's left alone and the journal forgets its record. A Game whose Cover goes away leaves OpenEmu's box art as it is: Sync never deletes box art.
- A Game with unresolved Duplicate Versions isn't synced; the Sync preview lists it as skipped, and why.
- **Guards:** Sync refuses to run while OpenEmu (`org.openemu.OpenEmu`) is running, if a Dropbox "conflicted copy" sits next to the store, or if the store's UUID isn't the one Imported. It runs `PRAGMA integrity_check` before and after. There's no waiting for Dropbox: on one Mac the local files are the truth.
- **Backup:** SQLite's backup API, taken while OpenEmu is closed (the store is WAL, so copying `Library.storedata` alone can lose data).
- **Writing, the way Core Data would:**
  - All writes happen in one transaction, followed by `PRAGMA wal_checkpoint(TRUNCATE)`, so Dropbox sees a complete main file and an empty WAL.
  - Every inserted row takes `Z_MAX + 1` from its **root** entity's `Z_PRIMARYKEY` row (`AbstractCollection` for collections, `Image` for covers), and `Z_MAX` is raised in the same transaction. **This is mandatory:** in the spike, a row inserted without it was silently overwritten by OpenEmu's next insert.
  - Entity numbers (`Z_ENT`) are read from `Z_PRIMARYKEY` by name, never hard-coded. Inserted rows get `Z_OPT = 1`, and every updated row gets `Z_OPT + 1`, including both ends of a membership change (the `Z_2GAMES` join row).
  - Journal-owned collections are updated in place (name and membership), keeping their `Z_PK`. Deleting a collection deletes its join rows too, and only rows whose `Z_ENT` is `Collection`.
  - A Cover is a new UUID-named file (no extension) in `Artwork/` holding the Cover as JPEG (IGDB's and OpenEmu's bytes unchanged, the normalised upload as stored, libretro's PNG re-encoded at quality 0.9, the way OpenEmu saves its own), plus a `ZIMAGE` row (`ZFORMAT` 3, pixel width and height, `ZRELATIVEPATH` = the file name, `ZSOURCE` NULL) linked both ways (`ZGAME.ZBOXIMAGE` and `ZIMAGE.ZBOX`). The file is always new, never overwritten.
  - Replacing a Cover Sync wrote updates its `ZIMAGE` row in place (new file name, width and height, `Z_OPT + 1`), like a journal-owned collection. The old file is deleted after the commit.
  - `Z_METADATA` and the schema are never touched.
- **OpenEmu identifiers the journal keeps:** the store UUID (`Z_METADATA.Z_UUID`) of the library it Imported; each ROM's OpenEmu `Z_PK` and MD5 (Sync looks up `ZROM.ZGAME` fresh each time); the `Z_PK` of each journal-owned collection (if it's gone, Sync creates a new one); and the `ZIMAGE` `Z_PK` of each Cover Sync wrote, with which Cover it was (`coverKey`). Core Data never renumbers `Z_PK`s.

### External data and cache (built: `LudeumCore`)
- **IGDB** (Twitch app token): the full game record, with every useful sub-record expanded plus time-to-beat. Fetched in batches of 100 (halved if IGDB answers 413). One request per name search, since multiquery ignores `search`. At most 3 requests a second.
- **Hasheous:** MD5 → IGDB game and platform. "Not found" is cached. At most 1 request a second. An optional app key can be set with `HASHEOUS_API_KEY`.
- **Cache:** entries keyed as `source:kind:id`, fresh for 60 days. An expired entry is still used if refreshing it fails. Only successful answers are cached. Images never expire. Runs can be interrupted and resumed.

### Playing in an Emulator (trial)
A phased trial of replacing OpenEmu as the player (ADR 0008). OpenEmu stays the library and Import source.

- **Emulators** are hard-coded per Platform in `Emulator.of(platformId:)`, not settings: MesenCE for NES, Family Computer, SNES, Super Famicom, Game Boy, Game Boy Color, Game Boy Advance, Master System, Game Gear, PC Engine and PC Engine CD; DuckStation for PlayStation; Dolphin for GameCube and Wii; ares for Nintendo 64, Mega Drive/Genesis and Sega CD (with `--system` naming which); melonDS for Nintendo DS; PPSSPP for PlayStation Portable, from a copy of its `ppsspp.ini` with its lowest-latency display settings for every Game (`InflightFrames = 1`, `LowLatencyPresent = True`, `FrameSkip = 0`; PSP emulators have no run-ahead), passed with `--config=`. Not `--appendconfig`, which saves into PPSSPP's own file. PCSX2 for PlayStation 2, launched `-batch -fastboot -gamecfg <file> -- <rom>`, where the file is Ludeum's game settings with Optimal Frame Pacing (`[EmuCore/GS] VsyncQueueSize = 0`) for every Game. It stands in for PCSX2's own per-game settings; its main settings (controllers, BIOS, renderer) still apply. Game Boy and Game Boy Color Games have a **Game Boy Model** setting (Auto, Game Boy, Game Boy Color, Super Game Boy), passed to MesenCE as `--gameboy.model=` (Auto is `AutoFavorGbc`); every model is offered whatever the ROM supports.
- **Play** (Game detail only) opens the Game's present ROM where it is in OpenEmu's library: the multi-disc playlist, else the first present ROM. It never changes journal data. A running MesenCE gets the ROM in its open window; DuckStation, Dolphin, ares, melonDS and Ymir open another window. There's no Play in OpenEmu: a Game whose Platform has no Emulator shows "No ‹Platform› emulator yet" instead.
- **Emulator versions** are checked once per launch, in the background, for every installed Emulator (`EmulatorVersions`, `EmulatorVersionChecks`). Each has an expected (minimum) version, the one its launch code was written against, kept with its definition: MesenCE 2.2.1, DuckStation build 12070, Dolphin 2609, ares 148, melonDS 1.1, Ymir 0.3.3, PPSSPP 1.20.4, PCSX2 2.9.103. The version comes from the command line where the Emulator has a version flag and its app version isn't the real one (PCSX2 and DuckStation `-version`; PPSSPP and ares `--version`), else the app's version (melonDS, Ymir, Dolphin; Ymir's `--version` opens its window), else for MesenCE (whose app version is a placeholder) the `Version` its settings file records. DuckStation compares by build number.
  - **Older than expected:** Play is refused: its button is red, the reason shows under it, and pressing it says so in an alert.
  - **A newer major version**, or **a version that can't be read:** an alert the first time that Emulator is Played in the launch, then Play goes ahead. Dolphin (year-month), ares and DuckStation (single counts) have no meaningful major, so they're never warned about being newer. An Emulator installed or updated while Ludeum is open is checked at the next launch; until the launch check finishes, Play goes ahead unchecked.
  - **Emulators…** (app menu, under Settings…) opens a sheet listing every Emulator: whether it's installed, its status from the launch check (OK, too old, newer major, unreadable, checking), the version Ludeum needs against the one installed, and the Library's Platforms it plays.
- **Emulator settings:** run-ahead frames, 0–10, stored as `game.runAheadFrames` (null is the default, 0), and for Game Boy and Game Boy Color Games the Game Boy Model, stored as `game.gameBoyModel` (null is Auto). Every Play passes the full set, and never changes the Emulator's own saved preferences, so one Game's settings never carry into the next:
  - MesenCE: `--doNotSaveSettings --emulation.runAheadFrames=N`, plus `--gameboy.model=M` for Game Boy and Game Boy Color Games.
  - DuckStation takes settings only as a whole file, so its Play writes a copy of DuckStation's own `settings.ini` with the Game's `RunaheadFrameCount` and passes it with `-settings`.
  - ares's run-ahead is only on or off (one frame): its Games choose Off or On, stored as 0 or 1, and passed as `--setting General/RunAhead=true|false`, which ares doesn't save.
  - Dolphin has no per-Game settings: every Play turns on Rush Frame Presentation and Smooth Early Presentation for that launch (`-C`) to lower input latency, leaving Immediately Present XFB off since it breaks some Games.
  - melonDS and Ymir have no per-Game settings and no run-ahead: Play just opens the Game.

### What to play next and Top-rated
- **What to play next** is a plain view, with no ranking or suggestions. It has three sections: **Playing**, **Up next** and **Backlog**. Each Game appears once, in the first section that fits (a Game that's Playing and Up next shows under Playing).
- **Sorting:** the same filter and sort controls as the Library. Up next and Backlog default to when the Intent was set, newest first, with undated Intent after every dated one, by name. Playing defaults to the in-progress Playthrough's start date, newest first (a Game's latest start counts if several are in progress). Name order is available too. "Intent set" is also a Library sort, with Games that have no Intent last.
- **Start playing:** an action on a Game in Up next or Backlog. In one step it creates an in-progress Playthrough starting today (day precision) and clears the Game's Intent.
- **Top-rated** is one list of every rated Game, by current Rating, highest first, with no top-N cut-off. It has the same filters as the Library (Platform, List, Childhood), so "per Platform" is the Platform filter.
- **Ties share a rank** (1, 2, 2, 4) and are listed by name. There's no hidden tie-break.
- **Unrated Games never appear.** A Rating of 0.0 is a real Rating and appears. Rating history plays no part.

### Year in review
A nice-to-have: built after the rest of v1 works.

- **One year at a time**, chosen from a picker listing only years with something in them. The current year is labelled "so far". The Library's filters (Platform, List, Childhood) apply.
- **Sections:** **Finished** and **Dropped** (Playthroughs that ended that year, with the Game's Cover, Rating and Platform); **Also played** (Playthroughs active that year that didn't end in it); and **summary numbers** (Finished, Dropped and Started counts, a per-Platform breakdown). Rating history and Childhood play no part.
- **Which years a Playthrough counts for:** every year from its start year to its end year (to the current year while in progress). It's under Finished or Dropped in its end year and under Also played in each year before that. Every Partial date has a year, so precision doesn't matter here.
- **Missing end date:** an ended Playthrough with no end date counts in its start year under Finished or Dropped, marked "end date unknown".

### Backups
- **When:** before every Import, Sync, and deletion of a Game, List or Playthrough, and otherwise at most once a day (on launch, or the first change of the day). There's no undo, so the backup just before a destructive step is the one that matters. "Back up now" is in Settings.
- **How:** SQLite's backup API, written under a temporary name and then renamed, so Dropbox never syncs a half-written file. The cache isn't backed up.
- **Where:** straight into a Dropbox folder, by default `~/Dropbox/Ludeum Backups/`, changeable in Settings. There's no extra local copy. If the folder isn't there, backups go to `Backups/` in the app's folder and the app shows a warning.
- **Names:** dated, plus the operation that triggered them, e.g. `2026-10-02T1430-before-sync.sqlite`.
- **How many are kept:** every backup from the last 7 days, then one a day for 30 days, then one a month forever. The database is a few MB, so this costs little and still covers a mistake noticed weeks later.
- **Restore:** "Restore from backup…" in Settings lists the backups. It backs up the current state first, copies the backup into the journal with the backup API (rather than swapping files under an open WAL database) and relaunches. Only the journal changes. Its OpenEmu bookkeeping (store UUID, `Z_PK`s) may now be stale, which the next Sync's guards and preview catch. Nothing is written to OpenEmu.

### Settings and credentials
- **Settings screen:** IGDB credentials (client ID and secret) with a "Test connection" button (the same check as `ludeum-import check`), an optional Hasheous key, the backup folder with "Back up now" and "Restore from backup…", and the OpenEmu library location.
- **IGDB credentials** are kept in the Keychain, along with the cached Twitch app token. If there are none at launch, Settings opens with a link to the Twitch developer console. This depends on a stable signing identity: without one, every rebuild asks for Keychain access again (see the packaging research).
- **Hasheous key: not requested.** Hash lookups don't need one. The key unlocks Hasheous's metadata proxy, which we don't use, and its rate limits aren't published. There's an optional field (Keychain) in case anonymous lookups get throttled. `HASHEOUS_API_KEY` stays for the CLI.

### Review queue
- **Layout: three panes, Mail-style** (chosen from three variants on `prototype/review-queue`). A sidebar lists the item kinds with counts: Names agree, Checksum suggestions, Name suggestions, No suggestion, Duplicate Versions. The middle column lists that kind's items (ROM name, then the suggestion), and the right pane shows the selected item with its actions.
- **Bulk confirm:** a "Confirm all N" button at the top of the Names agree list, covering name suggestions and related-record suggestions whose names agree. To keep one out, I answer it individually first.
- **An item's detail:** the ROM name, its Platform and why it's here, then the suggestion with its cover, `game_type` and whether the names agree. For a related-record suggestion, the checksum's own game is shown crossed out above it.
- **Actions on a ROM item:** Confirm (when there's a suggestion), Search IGDB… (the shared search from Adding Games), Assign to Game… (an existing Game, e.g. a fan translation; warns about Duplicate Versions) and Make by hand… (Platform pre-selected from the ROM's system).
- **Duplicate Versions items** sit in the same three panes, with the detail and Check again described under First Import.

### Import and Sync screens
- **One page each, shown in the main window's middle area (see Version 1 screens), not a sheet or wizard** (chosen from three variants on `prototype/import-sync`).
- **Import page:** the left column holds the phase timeline (snapshot, lookups, matching, review), with each phase marked done, running or blocking, plus "Discard draft…". While the phases run, the main area shows determinate progress and Cancel. After that it shows a **"Before you can commit"** checklist of expandable cards:
  - *Start dates for `_Current`*: a table of the Games, with OpenEmu's last-played date as a hint. Each one takes "Started on…" with a Partial date, or "Not playing".
  - *Duplicate Versions*: the items described under First Import, with Check again.
  
  Below, under **"Not blocking"**, come the Review queue counts (answer now or after committing; they carry over) and a summary of what will be imported.
- **Commit bar:** a sticky "Commit Import" button. While it's disabled, it says what it's waiting on ("5 start dates and 2 Duplicate Versions"). Once it's enabled, it says the commit can't be undone and a backup is taken first.
- **Sync page:** the same shape. The left column lists the guards as ticks or warnings: OpenEmu closed, no conflicted copy, same library, integrity check. In the main area, each failing guard gets a red banner saying why and what to do. Then comes the preview: stars changed, the journal-owned collections with their membership changes, covers added and covers skipped (with the reason), and Games not synced (Duplicate Versions).
- **Deleting other collections:** a card lists each OpenEmu collection the journal doesn't own, by name with its game count, each with its own "Delete" tick. An unticked collection is left alone and asked about again at the next Sync. With any ticked, the button turns destructive and names the count ("Sync and delete 2 collections"). It's disabled while a guard fails. After the write, the page shows the result and the name of OpenEmu's backup.

### Version 1 screens
Library (filter and sort by Platform, Rating, Intent, Intent set, List, Outcome, Childhood); Game detail (editing); What to play next; Year in review; Top-rated; Import, Review queue and Sync; Settings.

## After v1

Later enrichments, deliberately out of v1 and listed so they aren't lost: IGDB screenshots and artwork, series, similar games and time-to-beat on screen; ScreenScraper for manuals and box, cart and disc scans; Steam playtime; RetroAchievements; SteamGridDB for PC art.

## Fog: open questions

None. Every v1 question is decided or ruled out.

## Built so far

- `LudeumCore`: cache store, `IGDBClient` (games, search, covers, Twitch token handling), `HasheousClient`, throttling. 24 tests at the agreed boundaries. CI: lint, build with warnings as errors, tests.
- `LudeumStore` (`LudeumCore`): the journal database's `v1` migration (every table in the schema above) and the journal's rules: Partial dates, Games and IGDB links, Rating history, Playthroughs, Intent, Childhood, Lists, deleting Games. Tested at the `LudeumStore` and `PartialDate` seams.
- `Matcher` (`LudeumCore`): the first-Import matching rules (Hasheous with the NES/SNES header retry, names agree, Automatic vs suggestions, related records, excluded `game_type`s), Version text and Discs (`ROMName`), and Duplicate Versions. Tested at the `Matcher`, `namesAgree`, `ROMName` and `versions(of:)` seams.
- App skeleton: `project.yml` (XcodeGen), ad-hoc signed until the Personal Team id goes in the gitignored `App/Config/Local.xcconfig` (pending, a human step); no sandbox. The main window shell (sidebar, placeholder screens, Game detail pane) and the ⌘, Settings window. CI builds the app.
- Settings: IGDB credentials, the optional Hasheous key and the app's Twitch token in the Keychain (`KeychainSecretStore`, via `AppSettings`); OpenEmu library and backup folder locations in user defaults; "Test connection" runs `ConnectionCheck`. With no credentials at launch, Settings opens once with a link to the Twitch developer console. Credentials surviving a rebuild waits on the Personal Team id.
- Backups (`Backups`, `BackupName`, `backupsToPrune`): named by date and operation, written under a temporary name then renamed, into the Dropbox folder or `Backups/` with a warning; pruned in tiers; taken before deleting a Game, List or Playthrough and daily at launch; "Back up now" and "Restore from backup…" in Settings. The app now opens the journal. Still to hook up: before Import and Sync (with those slices), the first change of the day, and before migrating once `v1` is frozen.
- Adding Games (`GameSearch`, `IGDBClient.platforms()`, `platformPickerOrder`): the cached IGDB platforms list and the Platform picker (mine first); the one IGDB search with an optional Platform filter, add-on `game_type`s excluded in the query, Mods labelled, platform chips marked "In journal" and "Different platform…"; adding from a chip or by hand with the names-agree duplicate warning; "Link to IGDB…" for a hand-made Game, refused when the link is taken or it already has one. The app has Add Game. A Game added or linked doesn't take IGDB's Cover yet (Covers).
- Library and Game detail (`LudeumStore.library`, `roms(of:)`, `deletionSummary`): the Library as a table or covers, with a count of its Games; one bar on every Library-shaped screen reads count, the screen's fixed scope chip (a Platform, List, Pinned item, Finished or Childhood), removable filter pills and a + Filter menu (Platform, Rating, Intent, List, Genre, Theme, Played, Childhood; they combine), with the sort as a menu on the right (table headers also sort); What to play next, Top-rated and Year in review use the same bar; the toolbar holds search and the Table/Covers switch; a name search narrows any of them and sorted by name, Platform, Rating, Intent set or IGDB release year (oldest first, no year last), marking Games with no ROM in OpenEmu; Lists in the sidebar (create, rename, delete); Game detail as the editor for every journal rule (name override, Rating and its history, Intent, Childhood, Lists, Playthroughs with Version and Played via suggestions, ROMs, delete with a confirmation saying what goes with it). Each ROM in Game detail's Files section folds out to every file it's made of, with sizes ("3 files · 702 MB"): a cue sheet's tracks, a playlist's discs and their tracks (`ROMFiles`), or everything in a ROM folder ROM's subfolder, plus its `.7z`.
- Covers (`Covers`, `CoverImage.normalise`): IGDB's cover from the cached record, downloaded on demand into the cache, else the journal-owned Cover, else a placeholder. Journal-owned Covers are normalised (1,200 px long edge, never enlarged; JPEG 0.9) and stored as BLOBs. Upload, replace and remove (picker or drag-and-drop) only while IGDB has no cover; a journal-owned Cover is deleted once IGDB has one (on showing it and on linking). Carrying OpenEmu box art over comes with the first Import, and reconciling on refresh with the background refresh.
- First Import (`FirstImport`, `OpenEmuLibrary`, `ImportDraft`): the snapshot via the backup API, the saved and resumable Import draft, Check again, Discard draft, and the commit in one transaction after a backup, as described under First Import (OpenEmu's data for unmatched ROMs is held in `heldOpenEmuData` until the Review queue resolves them). The Import page (phase timeline, progress with Cancel, Before you can commit, Not blocking, the Commit bar), and quitting mid-Import asks first. `ludeum-import first-import <library> <journal folder> [--commit]` runs it into a scratch journal: on a copy of the dry run's library, 907 Automatic, 150 missing, 7 `_Current`, 35 with nothing, and Double Dragon III as Duplicate Versions.
- Review queue (`LudeumStore.reviewQueue`, `ReviewQueue`): the three panes with the five kinds and counts, and the sidebar badge. Confirm and Confirm all (Names agree) Match as confirmed; a Search IGDB result, Assign to Game and Make by hand (any Platform, the ROM's system's first) Match as manual. Every answer applies the OpenEmu data held since the first Import, and one that gives a Game Duplicate Versions warns. Duplicate Versions items list the Game's present ROMs; their Check again runs an Import.
- Ongoing Imports (`OngoingImport`): at launch, when OpenEmu quits (a trigger mid-Import runs once more afterwards) and with Import now, with phased progress and Cancel. New ROMs are matched (Automatic silently, the rest to the Review queue), ROMs that disappear are marked missing, a missing ROM that comes back with the same `Z_PK` and MD5, or the same MD5, rejoins its old Game silently, a new Version of a Game is Matched and shows as Duplicate Versions, and a changed store UUID refuses. A dismissible summary appears when ROMs were added, matched, sent to review or went missing. ROM rows keep OpenEmu's name beside the file name.
- Sync (`OpenEmuSync`, `SyncPlan`): the writer and the Sync page as described under Sync to OpenEmu. `ludeum-import sync <library copy> <journal folder> [--write]` previews or writes a Sync into a copy: on a copy of my library after a first Import, 42 Covers added, 865 skipped for box art, integrity ok, `Z_MAX` consistent, an empty WAL, and nothing left to change on a second preview. Still to check by hand: the copy surviving an OpenEmu relaunch.
- What to play next and Top-rated (`LudeumStore.whatToPlayNext`, `startPlaying`, `topRated`): Playing, Up next and Backlog with each Game once, by default by the latest in-progress start and by when the Intent was set (newest first, undated last), or by any Library sort; Start playing adds a Playthrough from today and clears the Intent. Top-rated ranks every rated Game (ties share a rank, by name) and filters by Platform, List and Childhood. Both share the Library's filter and sort menus.
- Background refresh and exclusivity (`CacheRefresh`, `WorkGate`): at launch, a background-priority refresh of every expired cache entry (IGDB games in batches, searches, platforms, Hasheous lookups), with a small toolbar indicator and errors logged; an entry that fails keeps its expired copy and is retried next launch. A refreshed record that brings an IGDB cover deletes the journal-owned Cover. Import and Sync hold the `WorkGate`, so they're exclusive and the refresh waits between steps while either runs. Journal edits (Game detail, Review queue, Add Game, Lists) are disabled from just before an Import's write step until it ends. The daily backup at launch is unchanged.
- Year in review (`LudeumStore.yearInReview`, `yearsInReview`): the year picker ("so far" for the current year) with the Library's filters; Finished, Dropped and Also played with Cover, Rating and Platform and "end date unknown"; Finished, Dropped and Started counts and a per-Platform breakdown. The "N Playthroughs have no dates" footer and its Library filter went when start dates became required. OpenEmu play time was shown here at first and removed.
- `ludeum-import check`: a live check against IGDB and Hasheous (`ConnectionCheck`, the same as "Test connection").
- `ludeum-import match-report <snapshot>`: runs the `Matcher` over an OpenEmu snapshot. On my library: 1196 ROMs, 907 Automatic, 4 related-record and 26 checksum suggestions, 222 bulk-confirmable and 2 other name suggestions, 35 with nothing, 2 Duplicate Versions.
- `scripts/setup-igdb.sh`: the IGDB credentials wizard.
- Branch `prototype/first-import`: a throwaway dry run of the first Import. Its verdict is in the commit message and folded into the decisions above.
- Branch `prototype/openemu-write`: a throwaway spike that wrote a Sync into a copy of the OpenEmu library. Its verdict is in the commit message and folded into Sync to OpenEmu above.
- Branch `prototype/review-queue`: three throwaway Review queue layouts (`prototypes/PROTOTYPE-review-queue.html`). Variant A won and is folded into Review queue above.
- Branch `prototype/matching-rules`: a throwaway measurement of the matching rules against the dry run's snapshot (`ludeum-import prototype-matching-rules`). Its verdict is in the commit message and folded into First Import above.
- Branch `prototype/import-sync`: three throwaway Import and Sync layouts (`prototypes/PROTOTYPE-import-sync.html`). Variant B won and is folded into Import and Sync screens above.
