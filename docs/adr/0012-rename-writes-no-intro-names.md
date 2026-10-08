# Rename writes No-Intro names (Redump's on disc Platforms), with the ROM's Regions as its region tag

A ROM's Standard name, which Rename gives it, is the name the groups that catalogue its Platform would give it: No-Intro's for cartridge and digital Platforms, Redump's for disc Platforms (PS1, PS2, PSP, GameCube, Wii, Saturn, Sega CD, PC Engine CD). The title is the Game's name written their way (a leading article moved to the end, `" - "` for a subtitle, accents stripped, forbidden characters dropped), the region tag is written from the ROM's Regions rather than kept from the old name, and the rest of the name is rewritten into their tags and order: GoodTools dump flags and scene tags go, except `[b]`, `[h]`, `[t]` and translations, which say something about the file's contents. See `docs/research/rom-naming-conventions.md`.

We chose a published convention over our own, and over TOSEC (computer-centric, needs a year and publisher) or GoodTools (abandoned, ambiguous codes), because most of the library is already No-Intro or Redump, the name parser already reads them, and libretro-thumbnails keys Box art by these names. Following the group per Platform, rather than No-Intro everywhere, is what makes disc Platforms' names match their published sets.

## Consequences

- The region order is inferred, not documented: neither group publishes a precedence list. No-Intro's names always read Japan, USA, Europe, then the rest alphabetically, with all three of the big three written `World`, Canada left out beside USA, and `United Kingdom` spelt out; Redump's read `USA, Japan`, `USA, Canada` and `UK`. That order is for the name only: the Regions keep their own display order (Europe, USA, World, …) everywhere else.
- A ROM with no Regions gets no region tag, where No-Intro would write `(Unknown)`: to the journal, no Regions means not recorded, and an `(Unknown)` tag would be read back as a Region of that name.
- Tags Rename can't recognise (a scene group or a real edition, which can't be told apart) are kept unless I untick them when I Rename. A kept one stays: the name then conforms, so Rename isn't offered again for it.
- Forbidden characters are dropped, except that one joining two words becomes a "-" (No-Intro's `Q-bert`, and `Dragon Quest I-II` rather than `Dragon Quest III`); a fraction is written as No-Intro does (`Ranma 1-2`).
- Add ROM offers the same name once the ROM is Matched (on by default). A missing ROM of that Game comes back whether the picked file has its name or would be given it, and is named from its own Regions.
- A Disc ROM's subfolder is renamed, not the Discs, tracks and playlist inside it, which keep their old names.
