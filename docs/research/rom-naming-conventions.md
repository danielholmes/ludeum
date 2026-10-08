# ROM file naming conventions

Researched 2026-10-08. Question: what established standard should Ludeum's Rename follow when it names a ROM after its Game and puts the ROM's Regions in the name? Sources are the conventions' own documents. Where a document is silent, the answer comes from the groups' published DATs: 108,529 No-Intro and 56,223 Redump game names in `libretro-database` `metadat/no-intro` and `metadat/redump` at commit `fbeefcb` (2026-10-05). Those numbers are marked **(DATs)**. The two `Microsoft - Xbox 360*` files in `metadat/no-intro` are left out, because they're Redump or libretro-made, not No-Intro.

## Summary

- **Follow No-Intro for cartridge and digital Platforms, and Redump for disc Platforms.** They share one grammar, since Redump adopted No-Intro's convention in 2009: `Title (Region) (Languages) (Version) (Devstatus) (Additional) …`. RetroArch and libretro-thumbnails name games this way, and RetroAchievements prefers these sets. TOSEC and GoodTools use different formats (country codes, `[!]` flags) and should only be read, never written.
- **Region tag:** full English names, comma and space between them. If a game came out in Japan, the USA *and* Europe, the tag is `(World)`. The convention fixes only the order of the big three: **Japan, USA, Europe**. The DATs add a pattern: after those three come the other regions, apparently in alphabetical order. No precedence list is published anywhere. Redump uses a different, fixed set of combinations that writes **`USA, Japan`**.
- **Languages tag:** `(En,Fr,De)`, ISO 639-1 codes, comma with no space, in a fixed No-Intro order that is not alphabetical (En, Ja, Fr, De, Es, It, Nl, Pt, Sv, No, Da, Fi, Zh, Ko, Pl, …). The convention says to include it only when the game has more than one language. In today's DATs it is effectively left out only when the region already implies the language, e.g. `(USA)` for English.
- **Title:** a leading article moves to the end (`Legend of Zelda, The - Spirit Tracks`). A subtitle follows `" - "`. Only 7-bit ASCII is allowed, so accents are stripped and Japanese is romanised as ASCII Hepburn. `\ / : * ? " < > | `` ` `` are forbidden and are dropped or rewritten, never replaced with `_`. libretro-thumbnails then replaces ``&*/:`<>?\|"`` with `_`, and in practice only `&` is affected.

## 1. No-Intro: tag order

Sources: the No-Intro wiki's [Naming Convention](https://wiki.no-intro.org/index.php?title=Naming_Convention) page (last edited 2023-10-06, revision 13456) and the latest official document it is based on, [The Official No-Intro Convention (2007-10-30)](https://datomatic.no-intro.org/stuff/The%20Official%20No-Intro%20Convention%20(20071030).pdf). The wiki page says it "is based on the last official version of the convention, which was last updated on 2007-10-30". No later dated convention exists.

- §3.1 Overview: "The following elements can be part of a ROM title. They are also appended in this order."
  ```
  [BIOS flag] Title (Region) (Languages) (Version) (Devstatus) (Additional) (Special) (License) [Status]
  ```
  "The only mandatory elements are Title and Region. All other elements are optional."
- **Version:** "(vX.XX) or revision (Rev X) … Revision is used instead of version when applicable … only added if the version/revision is greater than the initial release."
- **Devstatus:** `(Beta)`, `(Proto)`, `(Sample)`, numbered when there are several, e.g. `(Beta 1)` (the wiki's spelling; the PDF has `(Beta1)`). The wiki adds: "if there is build date information available … the build date should be written in the 'Additional' field in YYYY-MM-DD format".
- **Additional:** "only added if it is required to differentiate between multiple releases (ex. Rumble Version, Doritos Promo)".
- **Special:** e.g. `(ST)`, `(MB)`, `(NP)`. **License:** `(Unl)`. **Status:** `[b]`. **BIOS:** `[BIOS]`.
- Real names put several tags after Version, e.g. `Legend of Zelda, The - Spirit Tracks (Europe) (En,Fr,De,Es,It) (Rev 1) (Wii U Virtual Console)` **(DATs)**.

## 2. No-Intro: regions

**What the convention says** (wiki §3.4 "Region", same text as PDF §3.3):

- "This flag is the region of the game. It is put in parentheses. Full country names are used. The flag represents the primary region. Secondary regions are omitted (ex. USA and Canada are often the same; Canada will be omitted)."
- Single region codes, "(not exhaustive)": Australia ("Don't use with Europe"), Brazil, Canada ("Don't use with USA"), China, France, Germany, Hong Kong, Italy, Japan, Korea, Netherlands, Spain, Sweden, USA ("Includes Canada").
- "If a game is released in all 3 major territories (Japan, USA, Europe) the flag (World) will be used. If a game is only released in 2 major territories, then be both will be listed and separated by a comma and a space."
- "If a game is released in 2 or more European countries the flag (Europe) will be used. The flag (Asia) will be only used if the target regions are multiple Asian countries and the game is different from the Japanese release."
- Multi-region codes: `(World)`, `(Europe)` ("Includes Australia"), `(Asia)`, `(Japan, USA)`, `(Japan, Europe)`, `(USA, Europe)`.
- The wiki adds: "This is basically used as a summary of regions specified in the sources' Region fields". Each source (a physical copy) has its own region, and the archive's name summarises them.

**Ordering multiple regions: there is no published precedence list.** Neither the convention nor any No-Intro wiki page gives one. I checked every page listed by the wiki's `allpages` API that looked relevant, including Naming Convention, General dat notes, Source Convention and Database Navigation Guide. DAT-o-MATIC's public pages show no region list either. The only documented order is the three examples above. They imply **Japan before USA before Europe**.

**What the DATs show (DATs):** 4,325 multi-region names in 34 distinct combinations, with **no pair ever written in both orders**. The combinations, with counts:

| Combination | Names |
|---|---|
| USA, Europe | 3,102 |
| Japan, USA | 391 |
| Europe, Australia | 191 |
| USA, Europe, Brazil | 174 |
| Japan, Europe | 166 |
| Europe, Brazil | 151 |
| USA, Brazil | 79 |
| USA, Australia | 69 |
| Europe, Asia | 43 |
| Japan, Korea | 39 |
| USA, Europe, Korea; USA, Korea | 19; 16 |
| Japan, Europe, Australia, New Zealand | 16 |
| Japan, Australia | 13 |
| USA, United Kingdom | 7 |
| United Kingdom, Sweden | 5 |
| USA, Asia; Japan, Brazil | 3 each |
| USA, Europe, Asia; Europe, Hong Kong; Brazil, Spain; Japan, USA, Brazil; Japan, Europe, Brazil; Europe, Korea; Japan, Europe, Korea; Japan, New Zealand; Japan, France | 2 each |
| Australia, Greece; Brazil, Portugal; USA, Taiwan; Japan, USA, Korea; Japan, Australia, New Zealand; Japan, Europe, Australia; Asia, Korea | 1 each |

Every pair fits this order: **Japan → USA → Europe → every other region in alphabetical order**. Pairs that support the alphabetical part: Asia < Korea, Australia < Greece, Australia < New Zealand, Brazil < Portugal, Brazil < Spain, Europe < Hong Kong, USA < Taiwan. There's **one exception**: `(United Kingdom, Sweden)`, 5 Sega PICO names. In full, as inferred:

> **Japan, USA, Europe**, then Argentina, Asia, Australia, Austria, Brazil, Canada, China, Denmark, Finland, France, Germany, Greece, Hong Kong, India, Italy, Korea, Mexico, Netherlands, New Zealand, Norway, Poland, Portugal, Russia, Scandinavia, Spain, Sweden, Taiwan, United Kingdom, … (alphabetical)

This is an **inference**, not a published rule. Most single regions are never combined at all, so their relative order is untested.

**How the rules are used in practice (DATs):**

- `(World)` is never combined with another region. No name lists `Japan, USA, Europe`, so the World rule is applied consistently.
- The "Australia: don't use with Europe" rule has drifted: `(Europe, Australia)` appears 191 times and `(USA, Australia)` 69 times. Today's names say `Australia` when an Australian source was recorded.
- No-Intro spells it **`United Kingdom`** (119 names). Redump spells it **`UK`**.
- **Unknown region:** `(Unknown)`, e.g. `Monkey Music (Unknown) (Proto)`, 257 names. Region is mandatory, so an unknown one is written out. The wiki also has "Nintendo 3DS Unknown undumped" lists.
- Other single regions in use beyond the convention's list: Taiwan, Russia, United Kingdom, Denmark, New Zealand, Poland, Portugal, Norway, Greece, Argentina, Mexico, Finland, Austria, India, Scandinavia, Bulgaria, Hungary.

## 3. No-Intro: languages

**What the convention says** (wiki §3.5, same as PDF §3.4):

- "ISO 639-1 codes are used … The flag is only added if more than one language is available in the game. First letter of each language code is always uppercased, second letter is always lowercased. All codes are separated by comma without space. Language variations are merged and not listed twice (ex. US English, UK English)."
- List: "En English, Ja Japanese, Fr French, De German, Es Spanish, It Italian, Nl Dutch, Pt Portuguese, Sv Swedish, No Norwegian, Da Danish, Fi Finish, Zh Chinese, Ko Korean, Pl Polish. **This order is to be respected.** Example: Super Metroid (Japan, USA) (En,Ja)".
- The wiki's archive fields include "Show lang … Default is 'auto' ('2'), other option is 'always'". So whether the tag appears is decided by DAT-o-MATIC per entry, not by the datter writing it.
- [General dat notes](https://wiki.no-intro.org/index.php?title=General_dat_notes): "Some 'two games in one cart' entries have languages set like 'Es,It+En,Es,It,Sv,Da'. The '+' is the game separator".

**What the DATs show:** the tag is left out when the region implies the language, and is written, **even for a single language**, when it doesn't:

| Region | No tag | One language | Several |
|---|---|---|---|
| USA | 23,370 | 49 (Es, Fr, De…) | 2,644 |
| Japan | 26,656 | 1,373 (1,369 are `(En)`) | 233 |
| Europe | 17,323 | 96 | 6,088 |
| USA, Europe | 2,878 | 0 | 141 |
| Japan, USA | 1 | 325 (all `(En)`) | 11 |
| Germany | 1,087 | 27 (26 `(En)`) | 53 |

So it's `Super Mario World (USA)` but `Q-bert (Japan, USA) (En)` and `Boxen (Germany) (En)`. This matches "auto" and the 2007 example `Super Metroid (Japan, USA) (En,Ja)`. The exact "implied language" rule in DAT-o-MATIC isn't documented. It appears to be: USA, Europe, World, Australia and United Kingdom imply English; every other single country implies its own language.

**Order in today's DATs:** no pair ever appears in both orders. The order runs in a continuous chain of attested pairs: **En, Ja, Fr, De, Es, It, Nl, Pt, Sv, No, Da, Fi, Zh, Ko, Pl, Ru, El, Tr, Cs, Hu**, then (sparsely attested) Th, Hr, Hi, Ar, He, Sl, Ro. That's the 2007 order with more languages added after Pl. Example: `Final Fantasy VII - Advent Children (Europe) (En,Ja,Fr,Es,It,Nl,Pt,Sv,No,Da,Fi,Zh,Ko,Pl,Ru,El,Tr,Cs,Hu,Th,Hr,Hi,Ar,He,Sl,Ro)`. Script subtags appear too: `Zh-Hans`, `Zh-Hant`.

## 4. No-Intro: titles

All from wiki §2.1, the same as PDF §2.1 except where marked:

- **Characters:** "Only 7 Bit ASCII (Low ASCII) characters are allowed for titles. Accents, Umlauts, High ASCII, Double byte characters are converted to the best comparable Low ASCII characters." Allowed: ``a-z A-Z 0-9 SPACE $ ! # % ' ( ) + , - . ; = @ [ ] ^ _ { } ~``. NOT allowed: ``\ / : * ? " < > | ` ``. "A filename is not allowed to start or end with a SPACE or DOT character." Artistic characters (leet speak) "should be converted to their real meaning".
  - `&` is in neither list but is used freely: 2,795 names, e.g. `Adventures of Batman & Robin, The` **(DATs)**.
  - Forbidden characters are **dropped or reworded, not substituted**. `?` appears in 0 names (`Where in the World is Carmen Sandiego (USA)`), and Q\*bert is `Q-bert` **(DATs)**. Every name is pure ASCII: 0 non-ASCII names in either the No-Intro or the Redump set. Ōkami is `Okami HD`, Pokémon is `Pokemon - Ruby Version` **(DATs)**.
- **Priority:** "Titles should be primary named after the publisher's released title (box title) … If box and screen titles are totally different, the box title is preferred." If a ROM has several regional titles, "the priority is in this order: US English title, Europe English title, Japanese title and rest."
  - Not in the convention, but common in practice: different titles for the same ROM are joined with `" ~ "`, e.g. `Air-Sea Battle ~ Target Fun (Japan, USA) (En)` and `Suske en Wiske - De Tijdtemmers ~ Bob et Bobette - Les Dompteurs du Temps (Europe)` **(DATs)**.
- **Capitalisation:** "all common names, adjectives and verbs should be uppercased. Articles and link words should be lowercased except when first word." Intentional styling is kept ("RoboCop"; "Sonic The Hedgehog … 'The' is his middle name"). All-caps titles are avoided unless the title is an acronym.
- **Ordering (articles):** "If the first word is a common article then it will be moved to the end of the main title and separated with a comma. This includes non English common articles too." Examples: `Legend of Zelda, The`, `Man Born in Hell, A`. The DATs also have `Ente und der Wolf, Die`, `Manoir de Mortevielle, Le` and `Game of Concentration, A`.
- **Subtitles:** "Subtitles and pretitles are always separated from the main title by a hyphen ' - '. Titles that use a different separation style (ex. colon or '~ Subtitle ~') will be converted to a hyphen style. If the first word of a subtitle is a common article it will NOT be moved to the end." Example: `Legend of Zelda, The - A Link to the Past`. So the article moves **within the main title only**, before the `" - "`.
- **Punctuation:** dots kept as on the title ("vs", "Dr", "Mr" with or without a dot "as it appears on the title").
- **Trademark reminders:** "'Disney's' are not included in the title usually … original artists or authors are not removed (ex. 'Mary Shelley's Dracula')".
- **Japanese romanisation:** the PDF says "Hepburn". The wiki says "an ASCII-compatible form of the Hepburn convention": を → o, へ → e as particles, "Long vowels are transcribed as in Wapuro romaji" (ou, uu), "Loan words are spelled in their original language (e.g. 'Pocket Monsters' not 'Poketto Monsutaa')", suffixes hyphenated (`Nakama-tachi`), particles lowercase. Chinese and Korean romanisation are "TO DO".
- Worked example (DATs): IGDB "The Legend of Zelda: Spirit Tracks" → `Legend of Zelda, The - Spirit Tracks (USA, Australia) (En,Fr,Es)`.

## 5. Redump: differences

- **Redump switched to No-Intro's convention on 2009-07-05.** F1ReB4LL (admin): "Like it or hate it - we've switched the naming to No-Intro's convention … After careful considerations and several votings we've decided to change to the No-Intro naming convention." Serials were dropped from names. http://forum.redump.org/topic/4771/nointro-naming/
- **wiki.redump.org returned 404 for every page on 2026-10-08.** The pages below were read through the Wayback Machine (2026 snapshots).
- **Regions are a fixed set of combinations, with a different order.** [Redump Search Parameters](http://wiki.redump.org/index.php?title=Redump_Search_Parameters) (last modified 2026-05-11) lists every region a disc can have:
  - **Single regions:** Argentina, Asia, Australia, Austria, Belarus, Belgium, Brazil, Bulgaria, Canada, China, Croatia, Czech, Denmark, Estonia, Europe, Export, Finland, France, Germany, Greece, Hungary, Iceland, India, Ireland, Israel, Italy, Japan, Korea, Latin America, Lithuania, Netherlands, New Zealand, Norway, Poland, Portugal, Romania, Russia, Scandinavia, Serbia, Singapore, Slovakia, South Africa, Spain, Sweden, Switzerland, Taiwan, Thailand, Turkey, United Arab Emirates, **UK**, Ukraine, USA, World.
  - **Combinations:** Australia, Germany; Australia, New Zealand; Austria, Switzerland; Belgium, Netherlands; Europe, Asia; Europe, Australia; Europe, Canada; France, Spain; Japan, Asia; Japan, Europe; Japan, Korea; Spain, Portugal; UK, Australia; USA, Asia; USA, Australia; USA, Brazil; **USA, Canada**; USA, Europe; USA, Germany; **USA, Japan**; USA, Korea.
  - **Defunct and replaced:** Asia, Europe → Europe, Asia; Asia, USA → USA, Asia; Europe, Germany → Europe; Greater China → Asia; **Japan, USA → USA, Japan**.
  - So Redump writes `(USA, Japan)` where No-Intro writes `(Japan, USA)`. Redump also allows `USA, Canada` (No-Intro omits Canada) and spells `UK`. The DATs agree: `USA < Japan` 51 times, never the reverse; `Japan, Asia` 1,293 times **(DATs)**.
- **Disc numbering**, from the [General Moderation Guide](http://wiki.redump.org/index.php?title=General_Moderation_Guide) (last modified 2026-05-16): "Disc numbers should be standardised to Arabic numerals (One, Two → 1, 2; I, II → 1, 2) … to either remove 0-padding (for sets with less than 10 discs) or to add it (for sets of 10+ discs): Disc 01-03 → Disc 1-3; Disc 1-11 → Disc 01-11". The submission form has a "Disc Number / Letter" field ("1, 2, 3, A, B, C") and a "Disc Title" ("Install Disc, Play Disc"). [Disc Dumping Guide (MPF)](http://wiki.redump.org/index.php?title=Disc_Dumping_Guide_%28MPF%29)
- **Where the disc tag goes (DATs):** after Languages and before Version: `Assassin's Creed III (Europe) (En,…) (Disc 1) (Rev 1)`. That order appears 364 times and the reverse never. The disc title follows the number: `Alien - Isolation (USA, Europe) (En,…) (Disc 1) (Installation Disc)`. Letters are used where the disc says so: `(Disc A)`.
- **Other moderation rules:** Betas get a `YYYY-MM-DD` date. "Proto is used in datname instead of Beta if the game is unreleased at retail for that system (including unreleased for a specific console region)". Compilations are separated by `/` in the database, which becomes ` + ` in names. Region is "where a disc was meant to be sold".
- The submission form keeps a separate "Foreign Title (Non-Latin)" field, so names stay romanised ASCII, as in No-Intro: 0 non-ASCII names **(DATs)**.
- **Umlauts and macrons are sometimes spelled out, not stripped:** Einhänder is `Einhaender (USA)` on PlayStation and Ōkami is `Ookami (USA)` on PlayStation 2, as libretro-thumbnails' listings name them (seen 2026-10-08), where No-Intro's Ōkami is `Okami HD`. Box art's title match tries both spellings; Rename still strips them.

## 6. TOSEC (for comparison)

Source: [TOSEC Naming Convention (2015-03-23)](https://www.tosecdev.org/tosec-naming-convention), v4.

- Format: `Title version (demo) (date)(publisher)(system)(video)(country)(language)(copyright status)(development status)(media type)(media label)[dump info flags][more info]`. "'Title (date)(publisher)' is the bare minimum". Flags sit next to each other with no spaces between them.
- Articles: "In cases where the title begins with 'The' or 'A', it should be moved to the end … This same rule applies if the title is not in English". Version has no parentheses (`Legend of TOSEC, The v1.0`).
- Country uses "ISO 3166-1 alpha-2" codes (`US`, `JP`, `DE`, `GB`, `EU` Europe, `AS` Asia…). Two countries are "alphabetised and separated by a hyphen", e.g. `(EU-US)`, `(DE-GB)`.
- Language uses ISO 639-1 in lowercase. "If a country flag is used, we assume that the software language is the official country language", so it's `(JP)` but `(JP)(en)`. Two languages are alphabetical and hyphenated (`(en-fr)`). Three or more become `(M3)`, `(M4)`. v4 removed "when you have a dual language flag English must come first". v4 also lifted the Low-ASCII-only restriction: "all Romanised names now valid".
- Forbidden: `/ \ ? : * " < > |`. Multi-disc: `(Disc 1 of 6)`. Dump flags: `[cr][f][h][m][p][t][tr][o][u][v][b][a][!]`, where `[!]` is "Verified good dump".

## 7. GoodTools (for comparison)

Source: `GoodCodes.txt`, "written by Psych0phobiA … All codes developed by Cowering for the Goodxxxx series ROM file renaming utilities" (https://www.us-lazarus.com/faq/GoodCodes.txt; [Data Crystal](https://datacrystal.tcrf.net/wiki/GoodTools) says it shipped with GoodNES). The original GoodTools readmes weren't findable.

- **Country codes:** (1) Japan & Korea, (4) USA & Brazil NTSC, (A) Australia, (B) non USA (Genesis), (C) China, (E) Europe, (F) France, (F) World (Genesis), (FC) French Canadian, (FN) Finland, (G) Germany, (GR) Greece, (HK) Hong Kong, (H) Holland, (I) Italy, (J) Japan, (K) Korea, (NL) Netherlands, (PD) Public Domain, (S) Spain, (SW) Sweden, (U) USA, (UK) England, (Unk) Unknown Country, (Unl) Unlicensed.
- **Combined codes** like `(UE)`, `(JU)`, `(JUE)` and `(W)` World appear in GoodTools-named sets, including the user's library (`Tony Hawk's Underground (UE)`). GoodCodes.txt doesn't list them, so their exact definition is **unverified**.
- **Flags:** `[a]` alternate, `[b]` bad dump, `[f]` fixed, `[h]` hack, `[o]` overdump, `[p]` pirate, `[t]` trained, `[T]` translation (GoodTools sets write `[T+Lang]` new / `[T-Lang]` old), `[!]` "Verified good dump. Thank God for these!", `(M#)` multilanguage, `(-)` unknown year, plus system-specific ones (`[C]`/`[S]` Game Boy Color/Super, `(BS)`/`(ST)`/`(NP)` SNES, `[c]`/`[x]` Genesis checksum).

## 8. libretro-thumbnails

- **It follows the database names, which are No-Intro and Redump.** The [libretro-database README](https://github.com/libretro/libretro-database) lists `metadat/no-intro` as "Bulk import from upstream No-Intro databases. Generally non-disc-based systems" and `metadat/redump` as "Bulk import from upstream Redump databases. Generally disc-based systems". TOSEC "has lower precedence in libretro and so generally serves as a secondary stopgap". The database's job includes "Game Naming. Assign a definitive and uniform display name", and thumbnails follow from that name.
- **README** (https://github.com/libretro-thumbnails/libretro-thumbnails): "If the characters ``&*/:`<>?\|"`` appear in a game name displayed in a playlist, they must be replaced with `_` in the corresponding thumbnail filename." The path is `thumbnails/Playlist Name/Named_Type/Game Name.png`, where the type is `Named_Boxarts`, `Named_Snaps`, `Named_Titles` or `Named_Logos`. New images should be named "according to the game name that RetroArch assigns in the playlist". The older README at `libretro/libretro-thumbnails` lists ``&*/:`<>?\|``, without `"`.
- Example: No-Intro's `Adventures of Batman & Robin, The (USA, Europe, Brazil) (En)` has box art at `Adventures of Batman _ Robin, The (USA, Europe, Brazil) (En) ….png` (Sega_-_Game_Gear repo).
- Because No-Intro and Redump names never contain the other characters, **`&` → `_` is the only substitution that happens in practice**.
- **Flexible matching** ([libretro docs](https://docs.libretro.com/guides/roms-playlists-thumbnails/), RetroArch 1.17.0+). RetroArch tries three matches in order:
  1. The ROM file name.
  2. The game name.
  3. The "Short game name … ignoring all text starting at the first round bracket", e.g. `Q-Bert's Qubes (USA) (1983) (Parker Brothers) [h]` matches `Q-Bert's Qubes.png`.
- The DS repo has `Legend of Zelda, The - Spirit Tracks (USA, Australia) (En,Fr,Es).png`, `… (USA) (En,Fr,Es).png` and `… (USA) (En,Fr,Es) (Rev 1).png`. An exact match needs Languages and Version as well as Region.

## 9. Which convention is most adopted

- **RetroAchievements** ([Working with the Right ROM](https://docs.retroachievements.org/guidelines/content/working-with-the-right-rom.html)): "No-Intro and Redump are the primary groups responsible for verifying clean dumps of console games … ROMs verified by these groups are preferred whenever possible, and can generally be identified by the following naming scheme: **Game Name (Region) (Available Languages if Applicable) (Current Revision if Applicable)** Example: Diddy Kong Racing (USA) (En,Fr) (Rev 1)". TOSEC is "a good fallback choice". GoodTools isn't mentioned. Its per-system table prefers No-Intro for every cartridge system and Redump for disc systems.
- **libretro / RetroArch:** No-Intro (cartridges) > TOSEC and Redump (discs) > TOSEC, per the database README's source table.
- **Redump** adopted No-Intro's convention itself (2009).
- Taken together, the sources treat **No-Intro/Redump naming as the de facto standard**. TOSEC is for computers and fallback cases. GoodTools is legacy: its last sets predate No-Intro's dominance, and none of the projects above use it.

## Implications for Ludeum

Current code, for reference: `ROMRename.newName` in `Sources/LudeumCore/ROMRename.swift` keeps the existing tags and only rewrites `:` as ` - `. `ROMName` in `Sources/LudeumCore/Matching/ROMName.swift` reads region names, including GoodTools codes.

- **Use the No-Intro grammar** `Title (Region) (Languages) (Version) (rest)` on cartridge Platforms. On disc Platforms use the same grammar, but put `(Disc N)` after Languages and before `(Rev N)`, as Redump does. This is the form libretro-thumbnails, RetroArch and RetroAchievements key on.
- **Title from the IGDB name:**
  - Move a leading article (The/A/An, and foreign articles: Die, Der, Das, Le, La, Les, El…) to the end of the *main title*, before the first `" - "`.
  - Turn `:` and other subtitle separators into `" - "`.
  - Fold accents to ASCII (Ō → O, é → e).
  - Drop ``? * " < > | \ ` ``, and turn `/` into `-` or a space.
  - Keep `&` and `'`.
  - Only the box-art lookup should apply libretro's `&` → `_`. The file name shouldn't.
- **Region tag from the Copy's Regions, ordered for the name, not for display.**
  - Japan+USA+Europe → `World`, and drop the three.
  - Otherwise put Japan, USA and Europe first, then the rest alphabetically.
  - GoodTools `(UE)` → `(USA, Europe)`, `(JUE)` → `(World)`, `(U)` → `(USA)`.
  - Ludeum's `Regions.ordered` puts Europe and USA first for display (`Copies.swift`), so it can't be reused for naming.
  - On disc Platforms, Redump writes `USA, Japan`, `USA, Canada` and `UK`. Following No-Intro order everywhere is simpler, but costs exact thumbnail matches for those few Redump names (see open questions).
- **Region spellings:** No-Intro uses `United Kingdom`, Redump uses `UK`. `ROMName.noIntroRegions` has `UK` but not `United Kingdom`, `New Zealand`, `Greece`, `Portugal` and others the DATs use (section 2).
- **Unknown region:** No-Intro writes `(Unknown)`. For an untagged ROM with no recorded Regions, Ludeum could write `(Unknown)` or leave the region out. That's a product choice; see open questions.
- **Languages:** Ludeum doesn't know a ROM's languages. Keep a languages tag the ROM already has. Otherwise leave it out, which No-Intro also does when the region implies the language. Expect exact thumbnail misses for multi-language games; libretro's short-name match is the fallback. Never invent `(En)`.
- **Keep other tags as they are** (Version, Devstatus, Additional, `(Disc N)` and its label). GoodTools dump flags (`[!]`) and scene tags (`(M5)(BAHAMUT)`) belong to no target convention. Dropping them is consistent with No-Intro, but loses information (see open questions).

## Open questions

- No-Intro's region precedence beyond Japan → USA → Europe is inferred from DATs, not documented. `(United Kingdom, Sweden)` breaks the alphabetical pattern. Does DAT-o-MATIC sort regions in code, or do datters type them? A No-Intro forum or Discord question would settle it.
- Should Rename use Redump's fixed region set and order (`USA, Japan`, `UK`) on disc Platforms, to match Redump names and their thumbnails exactly?
- Which region implies which language in DAT-o-MATIC's "auto" Show-lang mode? Inferred above, not documented.
- For an untagged ROM with no Regions, should the name get `(Unknown)` or no region tag?
- Should GoodTools `[!]`/`[a]` and scene tags survive a Rename? They're neither No-Intro nor wrong, but no target convention has them.
