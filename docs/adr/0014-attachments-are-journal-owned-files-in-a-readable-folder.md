# Attachments are the journal's, kept as files in a readable folder

An Attachment (a manual, a map, any file about a Game) belongs to its Game because the journal says so, not because of where its file sits. That is the opposite of ROMs, whose ROM folder is the source of truth (ADR 0009): a ROM identifies itself by checksum and name, so a file dropped into its folder can be Matched, but a PDF says nothing about which Game it's for. If the folder carried that, renaming or re-linking a Game would orphan its files.

The files still live in the Data folder, under `Attachments/<Platform>/<Game name>/`, keeping their own names, so they're in Dropbox and can be read without the journal. Ludeum moves a Game's folder when its name changes, and the journal records each file's path, so a move that fails loses nothing.

## Considered Options

- **The folder as source of truth, read by Import as ROMs are**: rejected, for the reason above.
- **Files named by Game id or by content hash**: rejected. Nothing would ever move, but a folder that only the journal can explain is useless if the journal is lost.
- **Files stored inside the journal, as uploaded Covers are**: rejected. Manuals run to hundreds of MB, which would bloat the live journal and every Backup.
