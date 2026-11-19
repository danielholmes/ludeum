# A ROM with no region tag takes its Regions from Hasheous

Amended by [0025](0025-a-playstation-roms-serials-say-its-regions-before-hasheous.md): a PlayStation ROM's Serials say its Regions before Hasheous is asked.

**Amended 2026-11-19:** Add ROM worked out a ROM's Standard name before it was in, from its name's tags alone, and asked Hasheous only once it was, as Hasheous is asked by checksum and a large disc image takes seconds to read; so a ROM with no region tag went in as `Tetris` and was given Japan a moment later, leaving a Rename to `Tetris (Japan)`. A ROM Add ROM gives its Standard name is now renamed straight after, as a Rename would, when its Serials or Hasheous give it Regions, unless another ROM has that name, which leaves the Rename offered as before. The checksum is still read from the ROM once it's in place, so a game's size doesn't hold up the confirmation.

Amends [0011](0011-roms-are-copies.md)'s rule that a ROM's Regions are read from its name when it first appears and never touched again.

A ROM's Regions decide which region's box LaunchBox shows for its Game ([0018](0018-launchbox-box-art-after-libretros.md)), and with no Regions it falls back to North America's. 210 of my 1,239 ROMs had none, as their names had no region tag (`Crash Bandicoot`, `Castlevania - Aria of Sorrow # GBA`). Hasheous already answers each ROM's checksum at its Import, and its answer names the DAT entry the checksum is: its name (`Castlevania - Aria of Sorrow (USA).gba`) and the countries it's for. So a ROM with no Regions now takes them from that, once, at the next Import, which also fills in the ones already in the journal, or straight away when Add ROM puts it in.

The entry's name comes first, read as a ROM's name is: the countries Hasheous lists can leave a region out (`Medal of Honor - Infiltrator (USA, Europe)` is listed as the United States alone). The countries cover names in TOSEC's form (`(EU-US)`, `(JP)`), which the name reader doesn't read. Matched against my journal, Hasheous knows 118 of the 203 with a checksum, and gives Regions for 88. It knows few of my PS1 discs (6 of 74), as their checksums are mostly of cue sheets; a disc's serial would say its region for certain, but isn't read yet.

Each ROM is looked up once, known to Hasheous or not, so an unknown one isn't asked about at every Import; one whose lookup couldn't run is asked again at the next, and after three failures in a row the rest wait for it too. Editing a ROM's Copy details by hand stops it being looked up, so Regions I clear stay cleared. `v37` first reads again the name of each ROM with no Regions, as two of mine had tags `v22` couldn't read and the name reader now can (`Urban Strike (UEJ) [!]`); there's no telling those from Regions I cleared, and I hadn't cleared any. The step runs after the Import's write step, while the journal can be edited, so it only fills in Regions a ROM still hasn't got.

## Consequences

- For homebrew in TOSEC, the country is where its developer is (Chainbreak is Spain's), not a release region. Those games have no retail box, so it changes no Cover, but it shows as their Regions.
- A ROM's name and its Regions can now disagree: `Gods.sfc` has USA. Rename writes the Regions as the region tag (ADR 0012), so it now offers `Gods (USA).sfc`.
- The first Import after `v37` looks up every such ROM not already in the cache, at Hasheous's one request a second: a few minutes, once.
