# The journal owns the data; OpenEmu only receives a one-way Sync

Ratings, Playthroughs, Intent, Lists and Covers live in the journal, a separate app. OpenEmu's library is read for ROMs and Activity (Import) and written to only by a one-way Sync that runs by hand while OpenEmu is closed and after a backup. The journal owns everything it writes: it overwrites stars and the collections it manages, and deletes other regular collections once I confirm. Changes made inside OpenEmu to those things are expected to be lost.

## Considered Options

- **Fork OpenEmu**: rejected. It means maintaining an Obj-C/Swift app, its cores and signing myself, and OpenEmu would still tie data to ROM files, the very problem I'm trying to get away from.
- **Store extra data inside OpenEmu's Core Data store**: rejected. The schema has nowhere for it to go, and data would still be keyed to ROMs.
- **Two-way sync**: rejected. A 1-5 star rating can't be turned back into a /10 rating to one decimal place without losing information, and a two-way sync would need rules for resolving conflicts.
