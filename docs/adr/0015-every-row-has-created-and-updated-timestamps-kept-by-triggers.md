# Every row has created and updated timestamps, kept by triggers

Every journal table has `createdAt` and `updatedAt`, so I can always tell when a Game, a Copy or anything else came in or last changed (for example, which Games I added in one sitting). They're for looking into the journal, not shown in the app.

SQLite triggers keep them, not the code that writes. An insert sets both to now. An update sets `updatedAt` only when another column really changes, because Import re-writes every ROM's row each time it runs, and an `updatedAt` that moved with it would mean nothing. An update that sets `updatedAt` itself keeps the value it sets. Rows from before `v31 row timestamps` all take 00:00 on 2026-10-15, Sydney time, the day timestamps came in.

The update trigger names the columns it watches, so a migration that adds a column or a table calls `LudeumSchema.keepTimestamps` for that table again. A test fails if a table has no timestamps or if its trigger misses a column. Writes have to keep rows rather than replace them: `INSERT OR REPLACE`, or deleting rows and inserting them again, would reset `createdAt`, so saving a Cover is an upsert and a Playthrough's Players are changed one by one.

## Considered Options

- **Setting the timestamps in Swift on each write**: rejected. The journal is written with raw SQL in dozens of places, and every new one would have to remember.
- **An update trigger that fires on any update**: rejected, for the reason above about Import.
- **Rebuilding every table so `createdAt` defaults to now**: rejected. `ALTER TABLE ADD COLUMN` can't take a default that isn't constant, and the triggers are needed for `updatedAt` anyway.
