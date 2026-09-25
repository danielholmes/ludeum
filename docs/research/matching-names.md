# What ROM names and IGDB records offer for matching

Research for issue #4, which feeds Fog item 4 ("Matching rules in detail") in [`docs/spec.md`](../spec.md). Vocabulary follows [`CONTEXT.md`](../../CONTEXT.md). Researched 2026-09-26.

The question: what the No-Intro and Redump naming conventions encode (regions, languages, revisions, Discs, translations, hacks, dev status), and what IGDB's `game_type`, `alternative_names`, `game_localizations`, `version_parent`, `parent_game`, `bundles` and `collections` hold, including how well they are filled in for retro games.

## Sources

| Key | Source | Trust |
|---|---|---|
| **NI** | No-Intro wiki, [Naming Convention](https://wiki.no-intro.org/index.php?title=Naming_Convention) (rev. 13456, edited 2023-10-06). The wiki says it's "based on the last official version of the convention, which was last updated on 2007-10-30". | Primary |
| **NI-2007** | [The Official No-Intro Convention (2007-10-30)](https://datomatic.no-intro.org/stuff/The%20Official%20No-Intro%20Convention%20(20071030).pdf), PDF from DAT-o-MATIC | Primary |
| **RF** | Redump forum, ["No-Intro naming"](http://forum.redump.org/topic/4771/nointro-naming/), a 2009 announcement by Redump administrators | Primary (project announcement) |
| **RD** | Redump's own PlayStation DAT, `Sony - PlayStation - Datfile (10914) (2026-06-15 11-55-46).dat`, downloaded from <http://redump.org/datfile/psx/> | Primary data |
| **RDP** | Redump disc page for *Resident Evil 2: Dual Shock Ver. (Disc 1)*, <http://redump.org/disc/344/> | Primary data |
| **LR** | No-Intro DATs for GB, GBC, GBA, NES, SNES and Mega Drive as mirrored in [libretro-database](https://github.com/libretro/libretro-database/tree/master/metadat/no-intro) (DAT version 2026.08.01) | Secondary mirror. Used only to count tags. It seems to drop `(Unl)`, so its counts are indicative |
| **GC** | `GoodCodes.txt`, the code list shipped with Cowering's GoodTools ([archive.org copy](https://archive.org/download/SegaGameGearCollectionByGhostware/GoodCodes.txt)) | Primary (tool documentation) |
| **IGDB** | [IGDB API docs](https://api-docs.igdb.com/): the Game, Alternative Name, Game Localization, Game Type, Game Version, Collection and Region endpoints, plus the "Examples" section | Primary |
| **IGDB-live** | Read-only queries against `api.igdb.com/v4` on 2026-09-26, throttled below 3 requests a second | Primary data |
| **DR** | The local first-Import dry-run report (`prototype-output/first-import-report.md`, gitignored) and the prototype code on branch `prototype/first-import` | Our data |

The Redump wiki (`wiki.redump.org`) returned 404 for every page on 2026-09-26, so Redump's naming practice below is taken from RF and the live DAT (RD). I found no separate Redump naming guideline to cite.

## 1. No-Intro names (cartridge systems)

### Grammar

NI gives the order of the elements:

```
[BIOS flag] Title (Region) (Languages) (Version) (Devstatus) (Additional) (Special) (License) [Status]
```

"The only mandatory elements are Title and Region." Every flag except `[b]` and `[BIOS]` sits in round brackets.

| Element | Rule (NI) | Seen in practice (LR, DR) |
|---|---|---|
| **Title** | 7-bit ASCII only. Accents and umlauts are replaced by the closest ASCII. The characters `\ / : * ? " < > \|` and backtick are forbidden. | `Pokemon`, not `Pokémon`. `Battletoads-Double Dragon` for IGDB's *Battletoads / Double Dragon*. |
| Title: article | A leading article moves to the end after a comma: `Legend of Zelda, The`. An article that starts a *subtitle* stays put. | `Legend of Zelda, The - A Link to the Past`, `Lost World, The - Jurassic Park` |
| Title: subtitle | "Subtitles and pretitles are always separated from the main title by a hyphen ` - `". Colons and `~ Subtitle ~` styles are converted. | IGDB's `:` turns into ` - `, but a `-` inside a title stays (`Codename - RoboCod`) |
| Title: trademark | "Trademark reminders such as 'Disney's' are not included in the title usually." | `Toy Story (Europe)` against IGDB's *Disney's Toy Story* (DR) |
| Title: choice | A single title, chosen from the box. For a release with different regional titles the order of preference is US English, then Europe English, then Japanese. **Each regional release is named by its own title.** | `Super Star Wars - Jedi no Fukushuu (Japan)`, `Starwing (Europe)`, `Double Dragon III - The Rosetta Stone (Japan)`, `Mario Tennis GB (Japan)` |
| Title: Japanese | Hepburn romanisation, ASCII only. Loan words keep their original spelling. | NI's own example: `Looney Tunes - Bugs Bunny to Yukai na Nakama-tachi` |
| **Region** | Full country names. Multi-region releases are joined with `, `: `(USA, Europe)`, `(Japan, USA)`. `(World)` means Japan, USA and Europe together. `(Europe)` includes Australia. | Also `(USA, Australia)`, `(Japan, Korea)`, `(Asia)`, `(Brazil)` |
| **Languages** | ISO 639-1 codes, capitalised as `En`, joined by commas with no space: `(En,Fr,De)`. NI-2007 says the flag is added only when there is more than one language. | Single languages do appear, e.g. `(Japan) (En)`, and so do region subtags: `(En,Pt-BR)` |
| **Version** | `(vX.XX)` or `(Rev X)`, "only added if the version/revision is greater than the initial release". | `(Rev 1)`, `(Rev A)`, `(v1.1)` all occur |
| **Devstatus** | `(Beta)`, `(Proto)`, `(Sample)`, numbered when there are several (`(Beta 2)`). A build date may go in Additional as `(YYYY-MM-DD)`. | Also `(Demo)`, `(Kiosk)`, `(Possible Proto)` |
| **Additional** | Only when it is needed to tell releases apart, e.g. `(Rumble Version)`. | `(Virtual Console)`, `(Switch Online)`, `(Evercade)`, `(Retro-Bit)`, `(Alt)` |
| **Special** | `(ST)`, `(MB)`, `(NP)`, … | `(SGB Enhanced)`, `(GB Compatible)`, `(NP)` |
| **License** | `(Unl)` for unlicensed games. | `(Pirate)` (1,204 names in LR) |
| **Status** | `[b]` for dumps that are "bad and/or hacked". | Rare in current DATs |

The ten most common flags across the 22,336 distinct names in the six LR DATs were Japan, USA, World, Europe, a single language, Beta, a language list, Pirate, `(USA, Europe)` and Proto. `(Rev N)` and `(vX.Y)` each appeared a little over 900 times.

**Translations and hacks:** the No-Intro convention defines no tags for fan translations or ROM hacks. The only related flag is `[b]`. A translated or patched ROM therefore never has a No-Intro name.

**Multiple titles in one name:** a few entries join alternate titles with ` ~ `. LR has `Sonic The Hedgehog 2 (World) (Rev B) (Sonic Compilation ~ Sonic Classics)`. DR has `QuackShot Starring Donald Duck ~ QuackShot - I Love Donald Duck - Guruzia Ou no Hihou (World) (v1.1)`, a name from an older DAT, since today's name in LR is just `QuackShot Starring Donald Duck (World) (En,Ja) (Rev A)`.

## 2. Redump names (disc systems)

- **Redump adopted No-Intro's convention in July 2009** (RF, admin post: "we've switched the naming to No-Intro's convention"). Region, languages, version, devstatus, additional and `(Unl)` work as in section 1, and DAT names follow the same ASCII rules (e.g. `Resident Evil 2 - Dual Shock Ver. (USA) (Disc 1)`).
- **The website shows different titles from the DAT.** Redump's site shows the full title with colons plus a second title line, often in native script (Metal Gear Solid shows *メタル・ギア・ソリッド*). For example, it shows *Resident Evil 2: Dual Shock Ver. (Disc 1)* with the second line *Resident Evil 2: Dual Shock Edition* (RDP). Only the DAT name reaches a ROM's file name.
- **`(Disc N)`** marks one disc of a set. In RD it comes **after Languages and before Version and Devstatus**: `Metal Gear Solid (USA) (Disc 1) (Rev 1)`, `Gran Turismo 2 (Europe) (En,Fr,De,Es,It) (Disc 1) (Arcade Mode) (Beta) (1999-12-22)`. 1,488 of the 10,914 PlayStation entries carry `(Disc N)`.
- **A disc label** is a parenthesised flag straight after `(Disc N)`: `(Disc 1) (Leon)`, `(Disc 1) (Ichi)` / `(Disc 2) (Ni)`, `(Disc 1) (Arcade Mode)`. Its text is free-form.
- **Not every disc set uses `(Disc N)`.** `Gran Turismo 2 (USA) (Arcade Mode)` and `Gran Turismo 2 (USA) (Simulation Mode)` are the two discs of one release with no disc number (RD). Bonus media are separate entries with their own flag: `(Bonus Disc)`, `(Special Disc)`, `(Premium Disc)`.
- **Versions on discs:** RD mostly uses `(Rev N)` (367 entries) and occasionally `(vX.Y)` (15). Other tags that tell dumps apart include `(EDC)`, `(Alt)`, serials such as `(SCUS-94496)`, and editions such as `(Shokai Genteiban)` and `(PlayStation the Best)`.
- **Names change between DAT releases.** DR contains older Redump names that today's DAT has replaced: `Metal Gear Solid (USA) (Disc 1) (v1.1)` is now `(Disc 1) (Rev 1)`; `Resident Evil 2 - Dual Shock Ver. (USA) (Disc 1) (Leon)` is now `… (Disc 1)` with no label; `Gran Turismo 2 (Europe) (Disc 1) (Arcade Mode Disc)` is now `(Arcade Mode)`. A ROM keeps whatever name it had when it was downloaded.
- The DAT also has a `<category>` element (Games, Demos, …) that no file name carries.

## 3. What actually reaches the journal: OpenEmu names

The prototype reads `ZGAME.ZNAME` ("usually the No-Intro style file name") and `ZGAME.ZGAMETITLE` (from OpenVGDB) (DR, `PROTOTYPE_FirstImport.swift`). The dry run shows that the ROM names in a real library are a **mix of conventions**, not clean No-Intro or Redump:

| Convention | Examples from DR | Notes |
|---|---|---|
| No-Intro / Redump | `Bomberman GB (USA, Europe) (SGB Enhanced)`, `Fear Effect 2 - Retro Helix (Europe) (En,Fr,De) (Disc 1)` | As in sections 1 and 2 |
| **GoodTools** | `Super Star Wars (E) (V1.1) [!]`, `Mario Tennis GB (J) [C][!]`, `Choplifter (J) [hM03]`, `Mission Impossible - Operation Surma (U) (M3) [!]`, `Daffy Duck - The Marvin Missions (UE) [!]` | GC: one-letter countries (`(U)`, `(E)`, `(J)`, `(UE)`, `(B)` non-USA on Genesis, `(4)` USA and Brazil), `(M#)` for the number of languages, `[!]` verified good dump, `[a]` alternate, `[b]` bad dump, `[f]` fixed, `[h]` hack, `[o]` overdump, `[p]` pirate, `[t]` trainer, `[T+]`/`[T-]` newer/older translation, `[C]` GB Color, `[S]` Super GB, `(Unl)` |
| Scene releases (NDS/GBA) | `(US)(M5)(XenoPhobia)`, `(E)(Patience)`, `Batman_The_Brave_and_the_Bold_USA_NDS-SUXXORS` | Group names in brackets, underscores |
| Fan translations and patches | `Sweet Home (English v1.0)[Gaijin Productions]`, `Akumajou Dracula X - Chi No Rondo (English v1.01)`, `Super Famicom Wars (Japan) (NP) - English Patched.sav`, `Castlevania - The Adventure (USA) - bofner patch`, `Undead_Line_J_TEng1.0-20070903_MIJET` | No standard at all |
| Bare titles (mostly PSX) | `Final Fantasy VII (Disc 1)`, `Fear Effect`, `CTR - Crash Team Racing`, `Tony Hawks Pro Skater`, `SCUS94240` | No region; sometimes only a serial |
| File artefacts | `.nkit`, trailing ` 2` (`Battalion Wars (USA) 2`), `# GBA`, `[SLUS-00481] [U] [bin+cue]`, `-redump` | Copy suffixes from the file system and from tools |
| Homebrew | `Feed_IT_Souls_v1.4`, `grimacebday v.1.7`, `elden ring gb v1.0` | A version with no brackets |

**Discs in DR:** Disc names appear in both the Redump form (`… (USA) (Disc 1)`) and the bare form (`Parasite Eve (Disc 1)`). Several games also have a disc-less entry next to their `(Disc N)` entries (`Fear Effect`, `Final Fantasy VII`, `Heart of Darkness`, `Syphon Filter 2`). The dry run doesn't show what that entry is (a playlist or cue for the whole set is a guess), but it's worth checking before the Disc rule is written.

## 4. IGDB `game_type` (and the deprecated `category`)

`game_type` is a reference to the `game_types` endpoint (IGDB: "The type of game"). The live values (IGDB-live) match the deprecated `category` enum listed in the docs one for one:

| id | `game_types.type` | old `category` name | For a Match |
|---|---|---|---|
| 0 | Main Game | main_game | Candidate |
| 1 | DLC | dlc_addon | Not a playable ROM |
| 2 | Expansion | expansion | Not a playable ROM on its own |
| **3** | **Bundle** | bundle | **The bundle type.** See the caveats below |
| 4 | Standalone Expansion | standalone_expansion | Candidate (e.g. *Metal Gear Solid: VR Missions*) |
| 5 | Mod | mod | Fan work. It pollutes name search (below) |
| 6 | Episode | episode | Rare for retro |
| 7 | Season | season | Not a ROM |
| 8 | Remake | remake | Candidate (its own Game) |
| 9 | Remaster | remaster | Candidate (its own Game) |
| 10 | Expanded Game | expanded_game | Candidate: IGDB's usual type for an **enhanced re-release** |
| 11 | Port | port | Candidate: a separate IGDB record per platform |
| 12 | Fork | fork | Rare |
| 13 | Pack / Addon | pack | Not a ROM (e.g. *Mario Tennis: Wario*, an add-on whose `parent_game` is the GBC *Mario Tennis*) |
| 14 | Update | update | Not a ROM |

- **`category` is dead in the data.** `where category != null` counts 0 games; `where game_type != null` counts 376,287. A record fetched with `fields category` doesn't return the field at all. Only `game_type` is usable.
- **"Compilation" isn't a type.** Compilations are typed Bundle (3), e.g. *Konami GB Collection Vol. 4* and *2 Games in 1 Double Pack: Scooby-Doo and the Cyber Chase + Scooby-Doo! Mystery Mayhem*.
- **Bundle also covers single cartridges that contain more than one game.** *Super Mario World: Super Mario Advance 2* (GBA, id 16617) and *Super Mario Advance* are game_type 3. So are *Konami GB Collection* Vol. 1–4, which really are single cartridges. Under the glossary's rule that "a Match is never made to an IGDB bundle", these ROMs can never have an IGDB link. The prototype for "Matching rules in detail" has to decide whether that's acceptable.
- **The type isn't always right.** *The Legend of Zelda: The Wind Waker - Limited Edition* is typed Bundle and also has a `version_parent`. *Holy Diver Collector's Edition* is Main Game with a `version_parent`. *Choplifter III: Rescue Survive* (Game Gear) is a Remake whose `parent_game` is *Choplifter II*.
- **Mods crowd name search.** DR's top suggestions included *Super Smash Bros. Melee: 20XX Edition*, *The Legend of Zelda: The Wind Waker Multiplayer*, *Mega Man X2: Ultimate Armor* and *Super Smash Bros. Sonic*. IGDB-live confirms the first three are Mods (5) with the real game as `parent_game`. SNES alone has 892 Mod records against 1,085 main/remake/remaster/expanded/port records (IGDB-live).

## 5. IGDB relationship fields

From the Game endpoint in IGDB, with what IGDB-live shows for retro games:

| Field | IGDB's definition | What it holds in practice |
|---|---|---|
| `parent_game` | "If a DLC, expansion or part of a bundle, this is the main game or bundle" | Used much more widely than that. For a **Port** it points to the original (*Daffy Duck: The Marvin Missions* GB → the SNES game; *Wario Blast* GB → *Bomberman GB*). For an **Expanded Game** it points to the base game (*Resident Evil 2: Dual Shock Ver.* → *Resident Evil 2*; *Final Fantasy VI Advance* → *Final Fantasy III*, which is the SNES game's US name). Mods, Packs and Remasters also set it. |
| `version_parent` / `version_title` | "If a version, this is the main game" / "Title of this version (i.e Gold edition)" | Boxed or collector's **editions**, and rare on retro platforms: 7 SNES, 19 PlayStation and 1 Game Boy games set it (e.g. *Tomb Raider II: Collector's Edition*, *Super Turrican 2: Special Edition*). The docs' example for excluding editions from a search is `where version_parent = null`. It is **not** how IGDB marks regional releases or enhanced re-releases. |
| `bundles` | "The bundles this game is a part of" | The compilations and mini consoles that include the game: *Star Fox* → Super NES Classic Edition; *Super Star Wars* → "Legends Core Plus". Useful for spotting that a checksum's IGDB game is a bundle, but it says nothing about the ROM. |
| `collections` | "The collections that this game is in" (replaces the deprecated `collection`) | A **series** grouping. `collection_types` has one value, "Series". Memberships are "Member" or "Spin-off". It's for Lists and "later enrichments", not for matching. |
| `ports`, `remakes`, `remasters`, `expanded_games`, `forks`, `standalone_expansions`, `dlcs`, `expansions` | The inverse lists | Let a checksum hit on the original be checked against its re-releases when the names disagree. |

**Consequences for Games:** CONTEXT.md says "an enhanced re-release that IGDB lists separately" is a different Game. In IGDB that usually means an **Expanded Game (10)** or **Remaster (9)** record with `parent_game` set. DR has one such case already. Hasheous linked `Resident Evil 2 - Dual Shock Ver. (USA) (Disc 1) (Leon)` to *Resident Evil 2* (880), but IGDB has *Resident Evil 2: Dual Shock Ver.* (213875, Expanded Game). The bare-named `Resident Evil 2` went the other way and got the Dual Shock record as its name suggestion. *Metal Gear Solid* and *Metal Gear Solid: Integral* (41037, Expanded Game) are in the same position.

## 6. `alternative_names` and `game_localizations`

**What they hold (IGDB):**

- `alternative_names`: `name` (string) plus `comment`, "a description of what kind of alternative name it is (Acronym, Working title, Japanese title etc)". The comment is **free text** with a de facto vocabulary. The most common comments on SNES were "Alternative title" (413), "Japanese title - romanization" (215), "Alternative spelling" (199), "Abbreviation" (110), "Japanese title - translated" (94), "Acronym" (64), "Stylized title", "Other", "Working title", "Portuguese title", "Windows Executable", "European title" and "Cancelled North American title". PlayStation is similar. 13 SNES and 47 PlayStation names have no comment (IGDB-live).
- `game_localizations`: `name`, `region` and `cover`. "A region can have at most one game localization for a given game." The `regions` endpoint has only **three** regions: Korea (`ko-KR`), Japan (`ja-JP`) and Europe (`EU`). Japanese and Korean localizations are in **native script** (`ダブルドラゴン III ザ・ロゼッタストーン`). Europe localizations often have **no name**, just a cover: 31 of 95 on SNES, and 161 of 348 among the first 2,500 PlayStation localizations fetched.

**Which one matters for matching No-Intro names:** the romanised regional titles that No-Intro uses are in `alternative_names`, not `game_localizations`. Examples from IGDB-live that line up with DR or LR names:

| ROM name (DR / LR) | IGDB name | Where the ROM's title is |
|---|---|---|
| `Double Dragon III - The Rosetta Stone (Japan)` | Double Dragon III: The Sacred Stones | alt "Double Dragon III: The Rosetta Stone" [Japanese title - romanization] |
| `Super Star Wars - Jedi no Fukushuu (Japan)` | Super Star Wars: Return of the Jedi | alt [Japanese title - romanization] |
| `Looney Tunes Series - Daffy Duck (Japan)` | Daffy Duck: The Marvin Missions | alt [Japanese title - translated] |
| `Mario Tennis GB (J)` | Mario Tennis | alt [Japanese title - romanization] |
| `Overboard! (Europe)` | Shipwreckers! | alt [European title] **and** localization [Europe] |
| `Starwing (Europe)` | Star Fox | localization "Starwing" [Europe]. The alt name is "Star Wing" (with a space) |
| `Akumajou Dracula X - Chi No Rondo` | Castlevania: Rondo of Blood | alt [Japanese title - romanization] |
| `Final Fantasy 6 Advance` | Final Fantasy VI Advance | alt "Final Fantasy 6 Advance" [Alternative spelling] |
| `Road Rash 2` | Road Rash II | alt "Road Rash 2" [Other] |
| `Einhander` | Einhänder | alt "Einhander" |

**Gaps and traps:**

- Well-known games can have none at all. *Super Star Wars* (SNES, 20031) has no alternative names or localizations. That's harmless here, because its Japanese release has the same title, but it shows that an empty field doesn't prove the regional titles are identical.
- Port records are often bare. *Sonic the Hedgehog: Spinball* (SMS port) and *Army Men: Air Combat* (GBC port) have neither field, so a checksum or name match on a port can't fall back on regional titles.
- Alternative names can **cross-link records.** *Konami GB Collection Vol. 4* (Europe) has the Japanese alt name "Vol. 3", and *Vol. 2* has the Japanese alt name "Vol. 4". Matching a Europe ROM against every alt name would hit two records. The comment says which region an alt name belongs to ("Japanese title - …", "European title"), so it can be matched against the ROM's region.
- Noise values: acronyms ("MGS", "RE2", "X2"), "Windows Executable" names (`ArmyMen2.exe`), Chinese, Russian and other titles. Acronyms are dangerous for "names agree": "TMNT" is a real GBA title.

**How often they are filled in (IGDB-live, 2026-09-26).** Counted over records of game_type 0, 8, 9, 10 and 11 on each platform. "Well known" means `total_rating_count >= 5`:

| Platform | All: records | with alt names | with localizations | with either | Well known: records | with alt names | with localizations | with either |
|---|---|---|---|---|---|---|---|---|
| NES | 1,376 | 42% | 23% | 46% | 426 | 65% | 52% | 72% |
| SNES | 1,085 | 56% | 33% | 61% | 483 | 70% | 49% | 76% |
| Game Boy | 1,412 | 37% | 26% | 45% | 103 | 78% | 64% | 83% |
| Game Boy Color | 1,336 | 35% | 17% | 41% | n/a | | | |
| GBA | 1,786 | 40% | 23% | 45% | 239 | 80% | 63% | 86% |
| Mega Drive/Genesis | 1,445 | 46% | 27% | 52% | 478 | 66% | 42% | 73% |
| Master System | 495 | 45% | 19% | 51% | n/a | | | |
| PlayStation | 3,739 | 53% | 47% | 64% | 770 | 71% | 53% | 76% |
| GameCube | 767 | 58% | 31% | 62% | n/a | | | |

So roughly **a quarter of well-known retro games, and about half of all retro records, have no alternative name or localization at all.** Most are games whose title didn't change between regions, which is where they matter least. But a missing regional title can't be assumed to mean there wasn't one.

**IGDB search doesn't reliably find alternative names.** `search "Rockman World"`, `"Biohazard 2"`, `"Overboard!"`, `"Star Wing"` and `"Mario Tennis GB"` found the right game. `search "Starwing"`, `"Akumajou Dracula X: Chi no Rondo"` (on PC Engine CD), `"Einhander"` and `"Einhänder"` found **nothing**, although those strings are in the records' `alternative_names` or `game_localizations`. That explains `Einhander` and `Starwing (V1.1) (E) [!]` landing in DR's "no suggestion" list. Names need to be compared locally, against the fetched record's `name`, `alternative_names[].name` and `game_localizations[].name`, not left to `search`.

## 7. Where names disagree in the dry run

DR's 46 "Automatic matches whose names differ" already compared the ROM's name and OpenVGDB title with IGDB's `name`, `alternative_names` and `game_localizations`, using the prototype's normalisation. That normalisation strips every bracketed group, moves `, The/A/An` to the front, turns ` - ` into `: `, lowercases, turns `&` into `and`, and keeps only letters and digits. What still differs falls into two groups.

**Correct matches that better normalisation would accept:**

| Difference | DR example |
|---|---|
| Roman numerals against digits | `Oddworld Adventures II` / *Oddworld Adventures 2*; `Baseball Stars II` / *Baseball Stars 2*; `James Pond II - Codename - Robocod` / *James Pond 2: Codename - RoboCod* |
| Diacritics (No-Intro is ASCII-only) | `Asterix and the Power of the Gods` / *Astérix …* (the prototype keeps `é` because it's a letter) |
| Dropped trademark or franchise prefix (per NI) | `Toy Story` / *Disney's Toy Story*; `007 - The World Is Not Enough` / *James Bond 007: …* |
| Dropped leading article | `King of Dragons (USA)` / *The King of Dragons* (LR itself has `King of Dragons (USA)` but `King of Dragons, The (Japan)`) |
| `&` dropped instead of spelled out | `Choplifter II - Rescue & Survive` / *Choplifter II: Rescue Survive* |
| Title and subtitle swapped | `Super Mario Advance 2 - Super Mario World` / *Super Mario World: Super Mario Advance 2* |
| Several titles joined with `~` | `QuackShot Starring Donald Duck ~ QuackShot - I Love Donald Duck - …` |
| Homebrew name and version formats | `Feed_IT_Souls_v1.4`, `grimacebday v.1.7`, `Hermano_1.1_jam` |

**Wrong matches that equality has to keep out:** in nearly all of them the IGDB name is a **strict prefix** of the ROM's title. `Gradius - The Interstellar Assault` → *Gradius*, `Army Men - Air Combat` → *Army Men*, `Mickey Mouse - Magic Wand` → *Mickey Mouse*, `Medal of Honor - Heroes` → *Medal of Honor*, `Looney Tunes - Twouble!` → *Looney Tunes*, `Battletoads-Double Dragon` → *Battletoads*, `Teenage Mutant Ninja Turtles - Tournament Fighters` → *Teenage Mutant Ninja Turtles*, `Super Star Wars - Return of the Jedi` → *Super Star Wars*. The rest are bundles (Scooby-Doo double pack; *Prince of Persia … & Lara Croft Tomb Raider: The Prophecy*), editions (`Holy Diver (Japan)` → *Holy Diver Collector's Edition*, which has a `version_parent`) and plain sequel errors (`Lilo & Stitch` → *Lilo & Stitch 2*). "Names agree" has to mean equality after normalisation. Prefix or containment tests would let every one of these through.

**Other name characters to account for:** IGDB titles use characters No-Intro forbids: `?` (*Scooby-Doo! Who's Watching Who?*), `/` (*Battletoads / Double Dragon*), `:`. IGDB also has spacing and punctuation variants: `Ghosts'n Goblins` / *Ghosts 'n Goblins*, `Buckeroos!` / *Buckeroo$!*, `SOCOM - U S Navy SEALs` / *SOCOM: U.S. Navy SEALs*.

## 8. Platform note

IGDB keeps the Japanese consoles as separate platforms: **Super Famicom (58)** alongside SNES (19), and **Family Computer (99)** and **Family Computer Disk System (51)** alongside NES (18). The Japan-only *Super Famicom Wars* is on Super Famicom (plus Wii and Wii U), not SNES, so a name search restricted to SNES can't find it. A Japanese ROM in OpenEmu's `snes` or `nes` system may belong to either IGDB platform.

## Facts the "Matching rules in detail" prototype needs

1. **Parse by convention, not by one grammar.** Real names mix No-Intro, Redump, GoodTools, scene and ad-hoc forms (section 3). A Version parser has to recognise, at least: No-Intro regions (full names, comma-joined) and GoodTools regions (`U`, `E`, `J`, `UE`, `JU`, …); `(En,Fr)` and `(M#)`; `(Rev N|X)`, `(vX.Y)` and GoodTools `(V1.1)`; `(Beta N)`, `(Proto N)`, `(Demo)`, `(Sample)` and dates; `(Unl)` and `(Pirate)`; GoodTools `[!]`, `[a]`, `[b]`, `[h…]`, `[t]`, `[f]`, `[T+…]` and `[C]`; and free-text translation and patch suffixes.
2. **Discs:** `(Disc N)` comes after Languages and before Version, Devstatus and label. A disc label is the free-form parenthesised flag right after it. Some disc sets have **no** `(Disc N)` (`Gran Turismo 2 (USA) (Arcade Mode)` / `(Simulation Mode)`), and older DATs use different labels and versions for the same disc, so grouping Discs by "same name apart from `(Disc N)` and its label" misses those cases.
3. **Regional titles differ by design.** No-Intro names each regional release by its own title, so a Japan or Europe ROM often won't equal IGDB's `name`. The romanised title is usually in `alternative_names` (comment "Japanese title - romanization" or "European title"), and sometimes only in a Europe `game_localizations` name. Japanese and Korean localizations are in native script and don't help with ASCII names.
4. **Normalise at least:** the moved article (`X, The`) and any leading article; ` - ` against `:`; `-` against `/`; `&` against `and` (and `&` dropped altogether); roman numerals against digits; diacritics folded to ASCII; the `Disney's` and `James Bond` type of prefix; `'n` spacing; punctuation (`!`, `?`, `.`, `$`) removed. Then **require equality**, never prefix or containment.
5. **Compare locally, not through `search`.** IGDB search misses some alternative names and diacritic titles. Use the fetched record's `name`, `alternative_names[].name` and named `game_localizations`. Consider restricting "Japanese title …" alt names to Japan ROMs, because alt names can cross-link records (Konami GB Collection Vol. 2/3/4).
6. **`game_type` is the only usable type field** (`category` is empty). Bundle is **3**. Mods (5), DLC (1), Expansion (2), Season (7), Pack/Addon (13) and Update (14) are never Games for a ROM and should be filtered out of suggestions. Mods especially crowd search results. Main Game (0), Standalone Expansion (4), Remake (8), Remaster (9), Expanded Game (10) and Port (11) are candidates.
7. **Bundle needs a decision.** Single-cartridge collections (*Super Mario Advance 2*, *Konami GB Collection*) are typed Bundle, so "never Match to a bundle" leaves those ROMs with no IGDB link possible.
8. **Enhanced re-releases** are Expanded Game or Remaster records with `parent_game` set. **Editions** are `version_parent` records, which are rare on retro platforms. When a checksum hit and the ROM's name disagree, the checksum game's `ports`, `expanded_games` and `remasters` (or its `parent_game`) are the obvious place to look for the right record (e.g. *RE2 Dual Shock Ver.*, *MGS Integral*).
9. **Coverage is partial.** About 72–86% of well-known retro games on the main platforms have at least one alternative name or localization, and about 41–64% of all retro records do. Ports are often bare.
10. **Platforms:** a SNES or NES ROM may map to IGDB's Super Famicom (58), Famicom (99) or Famicom Disk System (51).
