# Time to beat: sources besides IGDB

Researched 2026-11-03. The question: which sources besides IGDB could give a Game a time to beat (main story / main + extras / completionist), with terms that let a personal, non-commercial app fetch it automatically and cache it for months? RAWG first, then anything else. HowLongToBeat is already ruled out (issue #94: its robots.txt carries Ziff Davis's notice against any automated retrieval without written permission and disallows `/api`). I didn't scrape anything, probe any endpoint that isn't documented, or work around any access control. Where a page was blocked to an honest User-Agent (`Ludeum/1.0 (personal game journal)`), I say so and use the Wayback Machine or the project's own source instead.

The library figures below come from read-only copies of `journal.sqlite` and `cache.sqlite`: 1,535 linked IGDB games, of which 1,220 have a Wikidata item (by IGDB slug, P5794).

## Answer

**RetroAchievements is the one source worth building on.** It's the only one I found that has a real time-to-beat figure for retro console games *and* a documented API that a personal app is allowed to use and cache.

- **What it gives:** `API_GetGameProgression` returns the **median time to beat** and the **median time to master** (and to "complete", i.e. every achievement in softcore), in seconds, each with the number of players it's the median of. Beaten means every "progression" achievement plus one "win condition" achievement, so it's close to "main story". Mastered means every achievement in hardcore, so it's a completionist figure, though achievements include challenges as well as collecting things. There's no "main + extras" tier.
- **Where the figure comes from:** not submissions. RetroAchievements' emulator integration records how long each player actually spends in the game, and the server takes the median over all ranked players who beat it. So it doesn't depend on anyone remembering to submit a time, which is why IGDB has so few for old games.
- **Terms:** it needs a free RetroAchievements account's web API key. The docs ask you to be "reasonable" and say outright to cache ("Some content data, such as game data, tends to be very static"). The site's terms say "related metadata may be referenced or reused by third parties (eg: for tracking sites or community tools)". There's no stated attribution requirement and no ban on non-commercial apps.
- **Matching:** Hasheous, which Ludeum already calls, returns a RetroAchievements game id for a ROM's checksum (152 of the 228 Hasheous records in the cache have one). Wikidata has P11393 "RetroAchievements game ID", on **481 of the library's 1,535 games: 385 of the 884 pre-2000 ones**, and on **268 pre-2000 games that have no IGDB time to beat** (IGDB has one for 178 of the 884).
- **Coverage, measured:** with Daniel's key, `API_GetGameProgression` over the 481 library games with a Wikidata RetroAchievements id (one request a second) came back for all 481. **475 have a beat median from at least 5 players** (379 of the 385 pre-2000 ones, 94 of 94 from the 2000s, 2 of 2 from 2010 on), and **323 of those have no IGDB time to beat today** (265 pre-2000, 58 from the 2000s). Only one set has no achievements. See *Measured coverage* below.
- **It doesn't cover PC.** RetroAchievements is consoles and handhelds. Thief has no RetroAchievements id.

**RAWG is allowed but not worth it.** Its free plan is for "personal and hobby projects" (20,000 requests a month) if you link back to RAWG from every page that shows its data. But it has only one number, `playtime` (whole hours), and its docs never say what that number is beyond listing "Steam average playtime" as RAWG's player-activity data. That's time played, not time to beat, and there's no main/100% split. A search engine's title for RAWG's Super Metroid page reads "Average Playtime: 6 hours", though Super Metroid was never on Steam, so the figure's source is undocumented. I couldn't check coverage: every API call needs a key, and rawg.io and api.rawg.io both returned Cloudflare 522 (origin unreachable) all through this session.

**Nothing else qualifies.** The sources that have a real time to beat (HowLongToBeat, Backloggd, GameFAQs, Completionator, TrueAchievements/TrueTrophies) have no API and forbid or don't sanction automated access. The only sanctioned route to HowLongToBeat's data I found is a paid licensing listing on TollBit, which is aimed at AI companies and has no public terms. The sources with sanctioned APIs (MobyGames, Giant Bomb, TheGamesDB, ScreenScraper, LaunchBox's dump, Wikidata) have no length field. SteamSpy's playtime fields are now 0 for every game I tried, and speedrun.com's times are world records (Chrono Trigger: 6 minutes).

## Measured coverage

Run on 2026-11-03 with a personal web API key, over the 481 library games whose Wikidata item has P11393. A beat median counts when either the softcore or the hardcore one is from at least *n* players.

| Era | RetroAchievements ids | Beat, n ≥ 1 | Beat, n ≥ 5 | Beat, n ≥ 10 | Master, n ≥ 5 | Beat n ≥ 5, no IGDB time |
|---|---|---|---|---|---|---|
| pre-2000 | 385 | 381 | 379 | 379 | 379 | 265 |
| 2000s | 94 | 94 | 94 | 92 | 90 | 58 |
| 2010+ | 2 | 2 | 2 | 2 | 2 | 0 |

Some samples (softcore beat · hardcore beat · master, hours, players in brackets):

| Game | Console | Beat | Beat (hardcore) | Master |
|---|---|---|---|---|
| Super Metroid | SNES | 10.1 (2,558) | 8.4 (5,489) | 17.5 (364) |
| Chrono Trigger | SNES | 23.6 (1,136) | 23.3 (2,395) | 38.5 (708) |
| Castlevania: Symphony of the Night | PlayStation | 14.8 (4,996) | 14.9 (5,980) | 52.6 (570) |
| Super Mario 64 | Nintendo 64 | 11.5 (1,612) | 12.8 (7,971) | 24.2 (3,724) |
| Sonic the Hedgehog 2 | Mega Drive | 5.2 (91) | 5.3 (438) | 5.4 (413) |
| Sonic the Hedgehog 2 | Game Gear | 1.4 (180) | 2.0 (192) | 3.7 (140) |
| Link's Awakening | Game Boy | 10.0 (275) | 9.8 (1,159) | none (0) |
| Populous | SNES | 17.0 (1) | 13.2 (21) | 14.9 (21) |

What this shows:
- **A RetroAchievements game is one console's set**, so Sonic 2 has a Mega Drive time and a Game Gear one. A Wikidata item can carry several P11393 values, one per console; a Game must take the set for its Platform. Hasheous, matched by the ROM's checksum, gives that set directly. It also adds ids Wikidata lacks: of the 126 library games with both an IGDB and a RetroAchievements id in the cached Hasheous records, 82 have no P11393 on Wikidata, and of the 44 that have both, 38 agree.
- **The medians run longer than HowLongToBeat's main story** (Super Metroid 8–10 h), as achievement hunters dawdle and the clock counts time in the emulator, not the time to the credits.
- **A small sample can be odd** (Populous: one softcore player, 17 h). Taking whichever of softcore and hardcore has more players, and a floor on players, avoids most of it.
- **Master can be missing** when nobody has mastered a set (Link's Awakening).

## Comparison

| Source | Has a length? | What it measures | Access / key | Terms for personal use; caching | Retro coverage | Match to IGDB |
|---|---|---|---|---|---|---|
| **RetroAchievements** | **Yes**: median to beat, to complete, to master (s) + sample counts | Tracked in-emulator playtime until beaten / all achievements, median over ranked players | Documented web API; key from a free account; rate limited (no number given) | Free; caching encouraged; "metadata may be … reused by third parties (eg: for tracking sites or community tools)" | Consoles/handhelds only. Couldn't test (key needed). 385 of 884 pre-2000 library games have an RA id on Wikidata | **Hasheous** by ROM checksum (already used); **Wikidata P11393**; RA's per-console game list with hashes |
| RAWG | One integer, `playtime` (hours) | Undocumented. Docs list "Steam average playtime" | Documented API; key required | Free for personal use with an active link back from every page using it; non-commercial; 20,000 requests a month; caching not addressed | Couldn't test (key needed; site down). Super Metroid shows 6 h on its page | Wikidata P9968 (300 library games); not in IGDB `external_games`; else name search |
| HowLongToBeat | Yes: main / main+extras / completionist | User submissions | No API. Paid TollBit listing ("Request access") | robots.txt bars automated retrieval without written permission; TollBit terms not public | Good (not re-researched) | Wikidata P2816 (769 library games) |
| Backloggd | Yes: "Time Played" average / to finish / to master | Presumably its users' logs (page doesn't say) | No API (only unofficial scrapers) | "You agree to access the Website through the interface we provide" | Super Metroid: 9 h / 8 h / 14 h | Its game data is IGDB's |
| GameFAQs | User length polls (unverified: site blocked) | User submissions | No API | Couldn't read the terms (403); a third-party copy bans spidering and scraping | Unknown | Wikidata P4769 (1,039 library games) |
| Completionator | Users record completion times | User submissions | No API | robots.txt disallows `/Game` and `/Statistics` | Unknown | Name only |
| TrueAchievements / TrueTrophies | Estimated time to all achievements | Member completions / estimates | No API found | Not checked further | Xbox / PlayStation achievement-era games only | — |
| IsThereAnyDeal | HowLongToBeat main / extra / complete, by Steam appid | HowLongToBeat's | `/internal/hltb/v1` | "Internal APIs are available only for our own services" | Steam games only | Wikidata P12570 |
| SteamSpy | `average_forever`, `median_forever` (minutes) | Owners' total playtime | Keyless API, 1 request a second | No terms beyond the poll rate | Returns 0 for every game tried (Thief Gold, FF VII, Portal 2, CS:GO) | Steam appid (IGDB `external_games` source 1: 233 library games) |
| Steam Web API | Per-user playtime only | Your own playtime or a reviewer's | Key; 100,000 calls a day | Free; Steam Data to users "for their personal use" | Steam releases only | Steam appid |
| speedrun.com | Record times per category | Speedrun world records | Keyless API | CC BY-NC 4.0 | Good, but Super Metroid any% 40 min, Chrono Trigger 6 min | Wikidata P6783 (985) |
| MobyGames | No | — | Paid API (hobbyist tier), 720 requests an hour | — | — | Wikidata P11688 |
| Giant Bomb | No (only video lengths) | — | API key | — | — | IGDB `external_games` source 3 (1,127) |
| TheGamesDB | No | — | API key, monthly allowance | — | — | Wikidata P7622 |
| ScreenScraper | No | — | Developer credentials on request | — | — | Wikidata P7756 |
| LaunchBox Games DB (`Metadata.zip`) | **No**: no play-length element | — | Public dump (Ludeum already reads it) | — | — | Wikidata P7785 |
| Wikidata | No time-to-beat property; P2047 "duration" on 0 of 1,220 library items | — | SPARQL, keyless | CC0 | — | P5794 |

## RetroAchievements

### What the figure is

- **Endpoint:** `GET https://retroachievements.org/API/API_GetGameProgression.php?i=<game id>&y=<key>`, documented as retrieving "information about the average time to unlock achievements in a game". Optional `h=1` "to prefer players with more hardcore unlocks than non-hardcore unlocks". https://api-docs.retroachievements.org/v1/get-game-progression.html
- **Fields**, from the endpoint's own header comment: `MedianTimeToBeat` "median number of seconds required to beat the game", `MedianTimeToBeatHardcore` (same in hardcore), `MedianTimeToComplete` "median number of seconds required to complete the game", `MedianTimeToMaster` "median number of seconds required to master the game", each nullable, plus `TimesUsedInBeatMedian`, `TimesUsedInHardcoreBeatMedian`, `TimesUsedInCompletionMedian` and `TimesUsedInMasteryMedian` (the sample sizes), and per achievement `MedianTimeToUnlock` "from starting to play the game". https://github.com/RetroAchievements/RAWeb/blob/e1b5e65170e56b1d79356f07f254f97dd7cccf1a/public/API/API_GetGameProgression.php
- **The docs' example** (Super Mario World, id 228): `MedianTimeToBeat` 17878 (4 h 58 m, n = 4,493), `MedianTimeToBeatHardcore` 19224 (n = 8,249), `MedianTimeToComplete` 67017 (n = 155), `MedianTimeToMaster` 79744 (22 h 9 m, n = 1,091). https://api-docs.retroachievements.org/v1/get-game-progression.md
- **"Beaten":** "A game is considered beaten when all the following statements are true: All progression-typed achievements have been earned, if any are present. Any win-typed achievement has been earned, if any are present." Optional content, higher difficulties, side quests, collectibles, challenges, easter eggs and missable story aren't progression. "Typing core sets is required for set release." https://docs.retroachievements.org/guidelines/content/progression-and-win-condition-guidelines.html. The page doesn't say when that rule started, so older sets may be untyped and have no beat median.
- **"Complete" and "master":** every achievement in the core set, in softcore or in hardcore. The casual median counts only players who completed it but didn't master it. Players who previously mastered an older revision of the set aren't counted ("This only finds masters of the current set"). https://github.com/RetroAchievements/RAWeb/blob/e1b5e65170e56b1d79356f07f254f97dd7cccf1a/app/Platform/Actions/UpdateGameBeatenMetricsAction.php
- **How it's computed:** a true median (`ROW_NUMBER()` over the times, the average of the middle one or two), over players not in `unranked_users`. The casual beat median uses players who beat it in softcore only, and the hardcore one those who beat it in hardcore. It's recomputed whenever a player's beat time changes. Same file; https://github.com/RetroAchievements/RAWeb/blob/e1b5e65170e56b1d79356f07f254f97dd7cccf1a/app/Platform/Actions/UpdatePlayerGameMetricsAction.php (~193–205)
- **Each player's time** is `calculatePlaytime(start, beaten_at)` over their recorded play sessions, starting when they could first earn achievements in the set (`getAchievementEarningStartTime`). So it's time spent playing, not calendar time. https://github.com/RetroAchievements/RAWeb/blob/e1b5e65170e56b1d79356f07f254f97dd7cccf1a/app/Platform/Services/PlayerGameActivityService.php (~563–571)
- **Mapping to Ludeum's three:** beat ≈ "Rushed/Normally" (main story; there's no separate figure for main + extras), master ≈ "100%". Hardcore bars save states, so the hardcore beat time is the more like-for-like with playing on hardware. Which of the two to show is a design question.
- The RAWeb source also has an undocumented JSON:API "v2" whose game resource carries `medianTimeToBeatSeconds` (`app/Api/V2/Games/GameResource.php`). It's not in the public docs (whose index lists only v1), so I'd not build on it.

### Access and terms

- **Key:** "Retrieving data from an API endpoint requires your RetroAchievements account's API key, which can be retrieved on your account's control panel." https://api-docs.retroachievements.org/. Accounts are free. The key goes in `y`. "Store your API key as though it is a secret, like a password." https://api-docs.retroachievements.org/getting-started.html
- **Rate limit and caching:** "Rate limiting is enabled." No number is given. "Just because you can hit the API for N requests a second does not mean that you should. … it is expected of you to be reasonable about your usage and consider how often you really need to hit the site, as well as if it's possible to cache/preload data. Some content data, such as game data, tends to be very static." https://api-docs.retroachievements.org/. Ludeum would make one call per game and cache it for months, which fits.
- **Terms of use:** the rendered page (https://retroachievements.org/terms) returned 403 to curl, so I read its source in the RAWeb repo. Relevant lines: "Achievement titles, descriptions, and related metadata may be referenced or reused by third parties (eg: for tracking sites or community tools)." "Achievement trigger logic … is proprietary … and may not be reused." "Individual reproductions of a work are allowed only for private use." "We maintain API usage logs." Nothing requires attribution and nothing bans non-commercial apps. https://github.com/RetroAchievements/RAWeb/blob/e1b5e65170e56b1d79356f07f254f97dd7cccf1a/resources/js/pages/terms.tsx
- robots.txt: `User-agent: *` / `Allow: /`, with `Content-Signal: search=yes,ai-train=no,use=reference`. https://retroachievements.org/robots.txt
- The RAWeb code is GPL-3.0. The terms say that "does not extend to achievement data".

### Coverage

- **Untested.** Every endpoint needs a key and I didn't make an account. Game pages on retroachievements.org sit behind Cloudflare, and I didn't try to get past it.
- **Ids via Wikidata (P11393):** 481 of the 1,535 library games: **385 of 884 pre-2000, 94 of 461 from the 2000s, 2 of 181 from 2010 on.** **268 of the pre-2000 ones and 58 of the 2000s ones have no IGDB time to beat.** Wikidata's coverage of the property is incomplete, so this is a lower bound on games with a set. It's an upper bound on games with a beat median.
- **The sample titles:** Super Metroid 236, Chrono Trigger 319, Sonic the Hedgehog 2 2235, Link's Awakening 669, Castlevania: Symphony of the Night 11240, Super Mario 64 10003, Ecco the Dolphin 8 all have an RA id. Thief: The Dark Project doesn't (PC). Final Fantasy VII isn't in the library. For comparison, IGDB has Ecco with no time, Sonic 2 with only "normally" 2.0 h (1 submission), and Link's Awakening with "normally" 12.0 h but "completely" 8.5 h (2 submissions).

### Matching

1. **Hasheous** (Ludeum already looks ROMs up there by checksum): its record's `metadata` array has a `RetroAchievements` entry with `id` and `link` (e.g. Darius Twin → 868, Crash Bandicoot → 10434). In the cache it's `Mapped` for 152 of 228 records. `Sources/LudeumCore/HasheousClient.swift` currently reads only the IGDB entry. This matches a ROM, not a Game, so a Game with ROMs would take the id from its ROMs.
2. **Wikidata P11393** by IGDB slug (P5794), for a Game with no ROM. https://www.wikidata.org/wiki/Property:P11393
3. RA's `API_GetGameList.php?i=<console>&h=1` lists every game on a console with its hashes, one call per console. https://github.com/RetroAchievements/RAWeb/blob/e1b5e65170e56b1d79356f07f254f97dd7cccf1a/public/API/API_GetGameList.php. RA's hash is computed by its rcheevos library and isn't always the plain file MD5. I didn't check which of Ludeum's systems differ.
- IGDB's `external_games` has no RetroAchievements source: none of the library's records has one (sources seen: 14 Twitch 1,170, 3 Giant Bomb 1,127, 1 Steam 233, 20 Amazon 157, 11 Microsoft 145, 10 YouTube 131, 36 PlayStation Store 104, 5 GOG 99, and fewer of the rest).

## RAWG

- **Field:** `playtime`, "in hours", integer, on both `Game` (lists) and `GameSingle` (`GET /games/{id}`, where id may be the slug). There's no main/extras/100% split. RAWG's OpenAPI spec, archived 2026-01-29: https://web.archive.org/web/20260129010856/https://api.rawg.io/docs/?format=openapi
- **Source of the figure:** the spec's description and the API page both list "Player activity data: Steam average playtime and RAWG player counts and ratings." Nothing else says where `playtime` comes from. A search engine's title for https://rawg.io/games/super-metroid reads "Average Playtime: 6 hours", though Super Metroid has no Steam release, so the figure isn't Steam-only. I couldn't load the page.
- **Plans** (API page, archived 2026-10-21): Free, "For personal and hobby projects", "Non-commercial projects only", "up to 20,000 requests per month", "Required backlinks to RAWG from pages where the data is used". Business is $149 a month. https://web.archive.org/web/20261021210207/https://rawg.io/apidocs
- **API terms**, same page: "Free for personal use as long as you attribute RAWG as the source of the data and/or images and add an active hyperlink from every page where the data of RAWG is used." "No data redistribution. … you may use the data with your API access only for your projects." Spec: "You must include an API key with every request. … If you don't provide it, we may ban your requests." Caching isn't mentioned either way.
- **Site terms:** use "other than for private, non-commercial purposes" is not permitted, and "use any robot, spider, scraper or other automated means to access RAWG without our express permission (with the exception of accessing RSS feeds)" is forbidden. So the API is the only route. https://web.archive.org/web/20260612024750/https://rawg.io/terms (last updated 08/04/2019)
- **Availability:** rawg.io/apidocs, api.rawg.io/docs and api.rawg.io/api/* all returned HTTP 522 (Cloudflare can't reach the origin) from about 17:55 to 18:16 AEDT. robots.txt still loaded. That's one afternoon's observation, not a trend.
- **Matching:** Wikidata P9968 "RAWG game ID" is on 300 of the library's games (e.g. `chrono-trigger-1995`, `super-mario-64-1996`). It's not in IGDB's `external_games`. Otherwise it's `GET /games?search=…&search_exact=true` by name, with a year or platform filter.

## HowLongToBeat (sanctioned routes only)

- No public API. Its data is listed on TollBit's marketplace: "licensed content from HowLongToBeat" through an API, MCP, or a subdomain, with a "Request access to HowLongToBeat" button. The page gives no price, eligibility or licence terms. https://tollbit.com/marketplace/how-long-to-beat/. TollBit is a pay-per-access marketplace for AI and bot traffic. Its terms for display and caching weren't public where I looked. That, or written permission from HowLongToBeat, is the only legitimate way in.
- IsThereAnyDeal's API documents `GET /internal/hltb/v1?appid=` returning `{id, main, extra, complete}`, but "Internal APIs are available only for our own services. They are documented here for the sake of completeness." https://docs.isthereanydeal.com/. So it isn't a route, and it's keyed by Steam appid anyway.
- Wikidata P2816 "HowLongToBeat ID" is on 769 of the library's games, which would make matching easy if permission were ever given.

## Others with a length but no permitted automated route

- **Backloggd:** its game page shows "Time Played", with an average, "to finish" and "to master" (Super Metroid: 9h, 8h, 14h). The page doesn't say where these come from. https://backloggd.com/games/super-metroid/. "All game data comes from IGDB" (https://backloggd.com/about/), but these times differ from IGDB's (3.5/10.1/12.2 h), so they look like its own users' logs. It has no API. Its terms: "You agree to access the Website through the interface we provide." https://backloggd.com/about/terms-of-service/
- **GameFAQs:** no API. The site returned 403 to curl and to WebFetch, so I couldn't read its length data or its current terms. A third-party copy of older terms bans "spidering, scraping, data mining, or other automated means". https://reddit.sudovanilla.org/r/SleeplessWatchdogs/wiki/gamefaqs. Its robots.txt allows `*` but blocks AI crawlers. https://gamefaqs.gamespot.com/robots.txt. Wikidata P4769 is on 1,039 of the library's games.
- **Completionator:** users "Record your completion times to track how long it took to finish your games". https://completionator.com/. It has no API, and its robots.txt disallows `/Game`, `/Statistics` and `/Collection`. https://completionator.com/robots.txt
- **TrueAchievements / TrueTrophies:** "completion time" estimates for all achievements (e.g. https://www.trueachievements.com/game/PGR-3/completiontime). They're user-sourced, cover only Xbox and PlayStation games with achievements or trophies, and I found no API.
- **Grouvee:** returned 403 to curl and WebFetch. Not checked.

## Others with an API but nothing usable

- **SteamSpy:** `appdetails` documents `average_forever` "average playtime since March 2009. In minutes" and `median_forever`. It's keyless, "1 request per second", data "refreshed once a day". https://steamspy.com/api.php. Today it returns 0 for both on every app I asked for: Thief Gold (211600), Final Fantasy VII (39140), Portal 2 (620), Half-Life 2 (220), CS:GO (730). It measured owners' total time played anyway, not time to beat.
- **Steam Web API:** per-user playtime (your own library) and per-reviewer playtime, not a time to beat. "You are limited to one hundred thousand (100,000) calls to the Steam Web API per day", and Steam Data goes to end users "for their personal use via your Application". https://steamcommunity.com/dev/apiterms. Only Steam releases: IGDB links 233 library games to Steam, and Wikidata P1733 covers 262.
- **speedrun.com:** keyless, "all original content provided through the API is licensed under CC-BY-NC 4.0", and asks for a descriptive User-Agent. https://github.com/speedruncomorg/api. Records are speedruns: Super Metroid any% 40.4 min and 100% 72.3 min; Chrono Trigger "SNES" 6.3 min; Ecco the Dolphin any% 17.8 min; Thief any% Normal 24.2 min. Not a time to beat.
- **MobyGames:** API by subscription ("options for hobbyists as well as users with a commercial application in mind"; "Non-commercial API requests are limted to 720 per hour"). The game objects have titles, platforms, genres, attributes, ratings, `moby_score`, releases, covers and screenshots, but no length. https://web.archive.org/web/20260912233428/https://www.mobygames.com/info/api/ (the live page returned 403)
- **Giant Bomb:** the `game` resource's fields (aliases, characters, concepts, dates, deck, description, developers, franchises, genres, images, platforms, publishers, releases, dlcs and so on) have no length. `length_seconds` exists only on videos. https://web.archive.org/web/20251128200808/https://www.giantbomb.com/api/documentation/ (the live page returned 403)
- **TheGamesDB:** optional game fields are `players`, `publishers`, `genres`, `overview`, `last_updated`, `rating`, `platform`, `coop`, `youtube`, `os`, `processor`, `ram`, `hdd`, `video`, `sound`, `alternates`. No length. https://api.thegamesdb.net/spec.yaml
- **ScreenScraper:** `jeuInfos.php` needs developer credentials obtained through its forum ("contactez-nous via le forum … pour obtenir vos identifiants"). Its docs have no duration or time-played field. https://www.screenscraper.fr/webapi2.php
- **LaunchBox Games Database:** I read every element of `Metadata.zip` (2026-11-02 build, 190,224 `Game`s). The `Game` children are Name, ReleaseDate, ReleaseYear, Overview, ReleaseType, Cooperative, DatabaseID, CommunityRating, CommunityRatingCount, Platform, Genres, Developer, Publisher, MaxPlayers, VideoURL, ESRB, WikipediaURL, SteamAppId, DOS, StartupFile, StartupMD5, SetupFile, SetupMD5, StartupParameters. **No play length.** The other elements are GameImage, GameAlternateName, Platform, PlatformAlternateName, Emulator and EmulatorPlatform. https://gamesdb.launchbox-app.com/Metadata.zip
- **OpenCritic:** API on RapidAPI ("Freemium"). Its listing renders by script, so I couldn't read its fields. https://rapidapi.com/opencritic-opencritic-default/api/opencritic-api. It aggregates critics' reviews. Not checked further.
- **Kaggle and other datasets:** the time-to-beat datasets I know of are scrapes of HowLongToBeat. Whatever licence an uploader attaches, they can't grant what HowLongToBeat's terms withhold, and they're frozen snapshots. I didn't examine individual datasets.
- **PlayStation / Xbox:** no public API with a length. The achievement sites above are the closest.

## Wikidata ids for the library (method)

SPARQL against query.wikidata.org: for each of the 1,535 IGDB slugs, the item with that P5794 and its ids under each property. 1,220 slugs have an item. Counts: MobyGames P11688 1,179; Giant Bomb Wiki P14470 1,113; GameFAQs P4769 1,039; speedrun.com P6783 985; HowLongToBeat P2816 769; RetroAchievements P11393 481; RAWG P9968 300; ITAD P12570 267; Steam P1733 262; TheGamesDB P7622 242; OpenCritic P2864 142; ScreenScraper P7756 9; LaunchBox P7785 6; duration P2047 0. The era split for RetroAchievements uses IGDB's `first_release_date` from the cached record.
