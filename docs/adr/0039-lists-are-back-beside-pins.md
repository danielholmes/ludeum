# Lists are back, beside pins

Reverses `v34 no lists`, which had no ADR of its own. That migration dropped Lists because themes, franchises, series and companies pinned to the sidebar took their place. They do for a group that something about its Games already says. They don't for one only I can say, such as games to play with my daughter: no IGDB fact finds those, and a Pin can only name a fact.

So:

- **A List is a named group of Games I put together by hand.** I create, rename and delete Lists, and put a Game in or take it out from its page. A List has no order of its own.
- **A List shows as the Library scoped to it, as a Platform does.** Selecting one in the sidebar opens the Library with a fixed `LibraryFilter.listId`, so its filters, sorts and views all work. The sidebar counts its Games, showing an empty List's 0.
- **Any Game can be in one, on any Platform, Owned or not, Expansions included. A Bundle can't.** A Bundle isn't a Game and is never a Library row (ADR 0016), so a List could never show it. Its Games can each go in.
- **`v44 lists` makes new, empty tables.** It doesn't bring back the 48 Lists `v34` dropped, which were first filled from OpenEmu's collections. I didn't want them, so their export, `Lists.md` in the Data folder, was deleted on 2026-11-05.

## Considered Options

- **A List filter in the Add filter menu of every Library-shaped screen**, as before `v34`: left out. Top-rated, What to play next and Year in review would each have to apply it, and a List's own screen is what was asked for. Nothing stops it being added later.
- **Show a Bundle in a List as a Library row, only there**: rejected. Every row's Play, Rating and Intent assume a Game, which ADR 0016 is careful to keep a Bundle from being.

## Consequences

- Lists and Pins both sit in the sidebar, and they're different things: a Pin follows IGDB's facts and a List only changes when I change it.
- Deleting a List takes a backup and asks first, like deleting anything else. Its Games stay. Taking a Game out of a List does neither, as it's one click to put back.
- Deleting a Game takes it out of its Lists, and its confirmation says how many.
