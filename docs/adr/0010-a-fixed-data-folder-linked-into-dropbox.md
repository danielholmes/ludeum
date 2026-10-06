# A fixed Data folder, linked into Dropbox by hand

Everything Ludeum owns lives in one fixed place, the Ludeum folder (`~/Library/Application Support/Ludeum/`): the live journal, and beside it a `Data/` folder holding everything that must survive losing this Mac (the ROM folders under `ROMs/`, `Backups/`, and the battery saves archived from OpenEmu). There are no settings for any of these locations. I keep the Data folder safe by replacing it with a symlink into `~/Dropbox/Ludeum`, so the whole of it is one link. The live journal stays outside it and is kept through its Backups, and the cache moves out to `~/Library/Caches/Ludeum/`, since it can always be rebuilt. If the Data folder can't be found, nothing works: the app is blocked by a sheet that says how to fix it and checks again, and `ludeum-import` refuses with the same words. There's no local fallback for Backups, since it would sit at the same missing path.

## Considered Options

- **A setting for each location** (as before: the ROM folders root, PS2's folder, the backup folder): rejected. Settings raise questions a symlink doesn't, such as what to do with the files when a setting changes, and the ROM folders follow Ludeum's own naming, so they belong under Ludeum rather than in a generic folder.
- **One setting for a single root**: rejected for the same reason; the OS already offers a symlink.
- **A symlink per Data subfolder** (ROMs and Backups separately): rejected. It would let the ROMs sit somewhere other than the Backups, but I want both in Dropbox, and one link is less to forget.
- **The live journal in Dropbox**: rejected. A SQLite file that's open and written to can be synced torn or as a conflicted copy; dated Backups, written under a temporary name and then renamed, are safe to sync.
