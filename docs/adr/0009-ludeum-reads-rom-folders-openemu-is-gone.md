# Ludeum reads ROM folders; OpenEmu is gone

Supersedes [0001](0001-journal-owns-data-one-way-sync-to-openemu.md) and amends [0005](0005-platforms-are-igdb-platforms.md) and [0006](0006-box-art-before-igdb-cover-art.md).

Play already opens Games in standalone per-Platform Emulators (ADR 0008), which left OpenEmu as only a source of ROMs and the target of Sync. So the journal reads ROMs straight from ROM folders, one per IGDB Platform, and a ROM is known by its Platform and its name within that folder. Sync goes, along with the tables that tracked what it wrote. OpenEmu's Box art drops out of the Cover order, which is now my upload, else libretro Box art, else IGDB's Cover art. Its cached copies are deleted rather than kept as uploads, so a Game whose only Box art was OpenEmu's falls back to IGDB's Cover art without warning, and an upload fixes any I mind. Nothing replaces OpenVGDB's titles in the libretro lookup: it uses the ROM's file name, then its name (taken from the file name), then its Game's IGDB name. A one-off `migrate-openemu` moves the ROM files out of OpenEmu's library into the ROM folders with no loss of journal data; battery saves are archived rather than placed where an Emulator would pick them up.

## Considered Options

- **Keep OpenEmu as a read-only ROM source**: rejected. A ROM would have two kinds of identity, and the journal would keep depending on an app it no longer launches.
- **Reference ROMs where they sit in OpenEmu's library**, even if only through its file-system conventions: rejected. OpenEmu lays out its library by system, not Platform, so Game Boy and Game Boy Color, or NES and Famicom, can't each have a folder. Any reference also keeps a dependency on OpenEmu and takes away our freedom to choose our own layout.
- **Copy rather than move the files**: rejected. It doubles the disk use.
