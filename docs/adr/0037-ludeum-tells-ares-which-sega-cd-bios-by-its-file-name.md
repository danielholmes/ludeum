# Ludeum tells ares which Sega CD BIOS by its file name

Amends [0028](0028-ludeum-installs-ares-and-says-where-it-keeps-things.md), which split the Sega CD out (#92).

ares won't start a Sega CD disc without the BIOS of the disc's region. It keeps an absolute path for each, `MegaCD/Firmware/BIOS.US`, `.Japan` and `.Europe` in its `settings.bml`, filled in by Settings ▸ Firmware ▸ Scan, which hashes the files in its firmware folder against a SHA-256 it knows for each region.

Scan can't be relied on, because the digest is Scan's alone. Loading a disc reads whatever file the path names and checks nothing (`mia/system/mega-cd.cpp` at v148). None of the US BIOS dumps I have matches ares's US digest, though its Japan and Europe digests are both among them. The US Model 1 v1.10 boots in ares all the same: tested on 2026-11-04 with Earthworm Jim, it reached the BIOS's "Press the START BUTTON".

So:

- **The BIOS files are in the Data folder**, `Emulators/ares/BIOS/`, as DuckStation's and PCSX2's are, with the file name saying the region: `Mega CD US.bin`, `Mega CD Japan.bin`, `Mega CD Europe.bin`. A file's contents aren't checked. Which dump is the US BIOS is my choice, and the name records it.
- **Their paths are Standing settings.** Before every Play and after Install, each file that's there goes into its region's `BIOS.<Region>`, and `Paths/Firmware` is the folder, so nothing need be Scanned, and a new Mac needs nothing more. A region with no file keeps what ares had.
- **A Sega CD Game's Play is refused with no BIOS at all**, saying where one goes. With only another region's, ares's own message names the one it needs, as only ares reads a disc's region from its boot code.
- **The Sega CD's ROM folder reads only what ares opens**, `.chd` and `.cue`. An `.iso`, a bare `.bin` or an `.m3u` is no ROM there. So there's no playlist: a multi-disc Version opens at Disc 1, and ares's menu changes Disc.

## Considered Options

- **`Paths/Firmware` and running Scan once**, as #92 first suggested: rejected. It would skip the US BIOS for not matching ares's digest, and it's a step by hand in ares's UI on every new Mac.
- **Finding a US dump that matches ares's digest**: not needed. None of the sets here has one, and the v1.10 boots.
- **Ludeum knowing each dump's digest**: rejected. It would be a table of BIOS hashes to keep for a choice the file name makes.
- **Refusing a disc whose region has no BIOS**: rejected. Ludeum would have to read the boot code as ares does, to say what ares's own message already says.

## Consequences

- The BIOS files go into the folder by hand, once. Dropbox has them from there.
- A bad dump named as a region's BIOS shows up only when it fails to boot in ares.
