# libretro-thumbnails coverage of my library

Research for #42 (map: #40). Measured 2026-10-05 against the `master` tree of each libretro-thumbnails system repo, the OpenEmu library DB, and the journal DB (1,052 non-missing ROMs; 781 Games that have at least one matched ROM).

## Headline

| Lookup strategy (cumulative) | ROMs hit | % of 1,052 |
|---|---|---|
| Exact: file name minus extension, libretro substitutions | 516 | 49.0% |
| + GoodTools → No-Intro tag rewrite | 632 | 60.1% |
| + fuzzy title match on the file name (title before first `(`/`[`, normalised) | 964 | 91.6% |
| + fuzzy title match on OpenEmu `ZGAMETITLE` / `ZNAME` / IGDB name | 1,002 | **95.2%** |
| Miss | 50 | 4.8% |

Per Game (a Game counts as hit if any of its ROMs hits): **444/781 (56.9%) exact, 758/781 (97.1%) with all fallbacks.**

The first two rows assume Game Boy ROMs are also looked up in the Game Boy Color repo — OpenEmu files GB and GBC games together under `openemu.system.gb`, and 92 of 119 "GB" misses were GBC titles. If you only check `Nintendo_-_Game_Boy`, exact drops to 461 (43.8%) and the all-fallbacks rate drops to 85%.

**Checksum route (best option for cartridge systems):** looking up the OpenEmu ROM MD5 in libretro-database's No-Intro DATs gives the canonical name, and that name has a box art in **629 of 832** cartridge ROMs tested (SNES 143/146, GB+GBC 234/254, GBA 101/107, N64 23/32, DS 41/59, MD 86/105). The big exception is NES (1/129), because OpenEmu hashes the file with its iNES header and No-Intro hashes it without.

## Method

Scripts are in the session scratchpad and not committed. Here is what they did:

- **File listings:** one `gh api repos/libretro-thumbnails/<repo>/git/trees/master?recursive=1` call per system. That was 16 calls in total, none truncated, and only `Named_Boxarts/*.png` was kept. No requests were made per ROM.
- **Lookup key:** `rom.fileName` minus its extension (`.7z`, `.cue`, `.nkit.iso`, `.iso`, `.m3u`, …), with every character in ``&*/:`<>?\|"`` replaced by `_`. That list comes from the [repo README, "File & Naming Guidelines"](https://github.com/libretro-thumbnails/libretro-thumbnails#file--naming-guidelines). The README's own check command is `find . -name '*[&\*:`<>?\\|"*]*'`.
- **GoodTools rewrite:** `(U)`→`(USA)`, `(E)`→`(Europe)`, `(J)`→`(Japan)`, `(UE)`→`(USA, Europe)`, `(W)`→`(World)` and so on. `(V1.n)` becomes `(Rev n)`. `[!]`, `[C]`, `(M5)` and similar tags are dropped.
- **Title fuzzy match:** the title is the text before the first `(` or `[`. It is lowercased, `: ` becomes ` - `, `&` and the substituted `_` both become "and", a trailing `, The` moves to the front, and everything except letters and digits is stripped. When several repo files share that key, the script prefers USA, then USA/Europe, World, Europe; skips Beta/Proto/Demo; and keeps the same `(Disc N)`. A 20-row spot-check found the right game every time, though the region was sometimes different (e.g. `Rayman DS (E)` → `Rayman DS (USA)`). Regional box art is a cosmetic difference.
- **Repo for each OpenEmu system:**

| OpenEmu `ZSYSTEMIDENTIFIER` | libretro-thumbnails repo |
|---|---|
| `openemu.system.gb` | `Nintendo_-_Game_Boy` **and** `Nintendo_-_Game_Boy_Color` |
| `openemu.system.gba` | `Nintendo_-_Game_Boy_Advance` |
| `openemu.system.gc` | `Nintendo_-_GameCube` |
| `openemu.system.gg` | `Sega_-_Game_Gear` |
| `openemu.system.n64` | `Nintendo_-_Nintendo_64` |
| `openemu.system.nds` | `Nintendo_-_Nintendo_DS` |
| `openemu.system.nes` | `Nintendo_-_Nintendo_Entertainment_System` |
| `openemu.system.pcecd` | `NEC_-_PC_Engine_CD_-_TurboGrafx-CD` |
| `openemu.system.psp` | `Sony_-_PlayStation_Portable` |
| `openemu.system.psx` | `Sony_-_PlayStation` |
| `openemu.system.saturn` | `Sega_-_Saturn` |
| `openemu.system.scd` | `Sega_-_Mega-CD_-_Sega_CD` |
| `openemu.system.sg` | `Sega_-_Mega_Drive_-_Genesis` |
| `openemu.system.sms` | `Sega_-_Master_System_-_Mark_III` |
| `openemu.system.snes` | `Nintendo_-_Super_Nintendo_Entertainment_System` |

On the CDN, the repo name's `_-_` becomes ` - `, e.g. `https://thumbnails.libretro.com/Sony%20-%20PlayStation/Named_Boxarts/<name>.png`.

## By system (ROMs)

| System | ROMs | Exact | +GoodTools | +title (file) | +title (DB) | Miss | Games hit exact / any / total |
|---|---|---|---|---|---|---|---|
| gb (+gbc) | 254 | 140 | 11 | 72 | 6 | 25 | 126 / 200 / 212 |
| gba | 107 | 40 | 14 | 41 | 8 | 4 | 34 / 83 / 83 |
| gc | 29 | 26 | 0 | 3 | 0 | 0 | 4 / 5 / 5 |
| gg | 2 | 1 | 0 | 1 | 0 | 0 | 1 / 2 / 2 |
| n64 | 32 | 7 | 22 | 3 | 0 | 0 | 7 / 31 / 31 |
| nds | 59 | 5 | 4 | 46 | 4 | 0 | 5 / 40 / 40 |
| nes | 129 | 92 | 16 | 15 | 3 | 3 | 86 / 117 / 118 |
| pcecd | 1 | 0 | 0 | 1 | 0 | 0 | – |
| psp | 38 | 18 | 0 | 8 | 1 | 11 | 13 / 18 / 26 |
| psx | 123 | 33 | 0 | 86 | 3 | 1 | 24 / 29 / 29 |
| saturn | 4 | 2 | 0 | 2 | 0 | 0 | 2 / 2 / 2 |
| scd | 6 | 1 | 1 | 3 | 1 | 0 | 1 / 1 / 1 |
| sg | 105 | 67 | 5 | 25 | 3 | 5 | 65 / 92 / 94 |
| sms | 17 | 4 | 0 | 11 | 2 | 0 | 4 / 15 / 15 |
| snes | 146 | 80 | 43 | 15 | 7 | 1 | 72 / 123 / 123 |

The per-Game columns count only Games in the journal; 264 ROMs have no Game yet. PSX and DS have low exact rates because those files are mostly named without region tags (`Vagrant Story.cue`, `Ghost Trick - Phantom Detective.7z`). The title match rescues almost all of them.

## GoodTools-named ROMs

252 ROMs (24%) have GoodTools tags such as `(U)`, `(E)`, `[!]`, `[C]` or `(M5)`. **None of them hit exactly.** This is expected: the repos are keyed on No-Intro (cartridge) and Redump (disc) names. The tag rewrite rescues 116 of them (46%), and the title match handles most of the rest. The MD5 → No-Intro DAT route skips name parsing altogether for SNES, GB(C), GBA, N64 and DS.

## What the 50 misses are

- **Homebrew, jams, hacks and fan translations** (about half): `Hermano_1.1_jam`, `Feed_IT_Souls_v1.4`, `ucity`, `elden ring gb`, `Resident Evil GBC Cart 1`, `Castlevania OoS GBc build`, `Undead_Line_J_TEng…`. libretro has no art for these, so this is the floor.
- **No-Intro titles that differ from mine:** `Pokemon - Yellow Version` (No-Intro adds ` - Special Pikachu Edition`), `Ren & Stimpy …, The` (comma-article inside a subtitle), `Toejam & Earl` versus `ToeJam & Earl`, `Final Fantasy I & II`. Only a smarter fuzzy match or the MD5 route rescues these.
- **PSP:** 11 of 38 miss, mostly PSN or minis releases and `(v1.0x)` update tags (`Tomb Raider - Legend (Europe) … (v1.01)`). PSP is the weakest repo for my library.

## Multi-disc and `.m3u`

- Redump names carry `(Disc N)`. In the PSX repo, 1,427 boxart entries have `(Disc N)`, and most of them are **git symlinks** to the disc-less file. For example, `Parasite Eve II (USA) (Disc 2).png` is a 25-byte blob containing `Parasite Eve II (USA).png`.
- `thumbnails.libretro.com` resolves these links: a HEAD on the Disc 2 URL returns a 434,694-byte `image/png`. `raw.githubusercontent.com` does not; it returns the link text. **If we pull from GitHub, symlinks have to be followed by hand. The CDN handles them.** About 2,000 of the 55,600 entries listed are symlinks.
- `.m3u` files (10 in my library) have no Redump name. The approach that works is to strip `(Disc N)` and look up `<title> (<region>)`, or to look up disc 1. This is the same disc-less key the symlinks point at. One Game equals one cover, which suits the journal.

## Format, size, freshness

- PNG only. Other formats are "not support[ed] in the repository or thumbnail server" ([README](https://github.com/libretro-thumbnails/libretro-thumbnails#file--naming-guidelines)).
- The guidelines cap images at 512 px wide (example: `Super Mario Kart (USA).png` is 512×357). The median file is 150–550 KB depending on system (GB/SMS about 150 KB; MD/NES/Saturn about 520 KB). A full box-art set for my library would be roughly 400 MB.
- The CDN pulls from the repos "about once every two days on a cronjob". Contributors are told 1–2 weeks. The CDN is Apache behind Cloudflare and returns `ETag` and `Last-Modified`, so conditional GETs work. Append `?nocaches=<date>` to bust the cache ([README](https://github.com/libretro-thumbnails/libretro-thumbnails#thumbnail-server)).

## Licence and terms

- Neither the meta repo nor the system repos have a licence: the GitHub API returns `license: null` (checked on the SNES repo). The README Credits section says the images come from "many different sources" (MobyGames, Fandom, volunteers) and that "the game art itself … originates from the work of each respective game's developers and publishers."
- **There is no grant of rights.** Downloading for a personal, local journal is in line with how RetroArch uses the art. Redistributing images (e.g. bundling them, or a public gallery) is not covered.

## Rate limits and etiquette

- `thumbnails.libretro.com` publishes no rate limit or terms. RetroArch fetches one image per playlist entry when it needs one, so a polite client should do the same: fetch lazily, cache forever, use ETags, and avoid parallel bursts.
- GitHub API: a tree listing costs one request of the 5,000/h authenticated quota (60/h unauthenticated). This study used 16. Tree listings for even the largest repos (NES 13k entries, PSX 9k) were not truncated. Blob downloads via `raw.githubusercontent.com` have no API cost but do not resolve symlinks.
- The README's other option, `git clone --depth=1` of a system repo, is heavy. The SNES repo alone is about 3.2 GB because it includes Snaps and Titles.

## Checksum route

- [libretro-database](https://github.com/libretro/libretro-database) `metadat/no-intro/<System>.dat` lists CRC, MD5 and SHA-1 per ROM against the canonical No-Intro name. That name is the thumbnail key. Matching OpenEmu `ZMD5` against these DATs gave 629/832 hits for cartridge systems with art. Combined with the exact filename match, SNES reaches 144/146, GBA 101/107 and N64 30/32.
- Two caveats. NES needs a headerless MD5 (strip the 16-byte iNES header and rehash); OpenEmu's hash only matched 2 of 129. Disc systems (PSX, Saturn, SCD, GC, PSP) have OpenEmu MD5 values of the `.cue` or image container, which won't match Redump track hashes, so the name route is the only option there.
- Hasheous offers hash → No-Intro/Redump lookups as a hosted service. I did not test it here; the libretro DATs give the same mapping offline and come from the same project that names the thumbnails.

## Recommendation for #43

Use the CDN. Try these keys in order: (1) MD5 → libretro-database DAT name (cartridge systems); (2) exact file stem with substitutions; (3) GoodTools rewrite; (4) title match against the system's tree listing, with region preference, using the file title and then the IGDB/OpenEmu title. Look GB ROMs up in both the GB and GBC repos. Expect about 95% of ROMs and about 97% of Games to get box art; the rest are mostly homebrew.
