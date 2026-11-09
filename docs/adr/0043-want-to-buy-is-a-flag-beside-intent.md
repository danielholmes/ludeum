# Want to buy is a flag beside Intent, not one of its values

Want to buy joined the Intents in v21, beside Backlog and Up next, as what I plan to do with a Game I don't own yet. But a Game has one Intent, so wanting to buy one and wanting to play it soon couldn't both be said: setting Up next on a Game I hadn't bought lost that I still had to buy it. One is about owning a Game, the other about playing it, and they go together as often as not.

So:

- **Want to buy is a flag on a Game**, like Childhood: on or off, set from a checkbox beside Childhood in Game detail, and with no date, as the Intent's date is for ordering What to play next, which it isn't in. **Intent is Backlog, Up next or nothing.** A Bundle has neither, as before.
- **v47 moves it:** every Game whose Intent was Want to buy has the flag and no Intent, its Intent's date dropped with it. No row's timestamps change. The `intent` column's CHECK still allows `wantToBuy`, as SQLite can only change one by rebuilding `game`, which every Copy, Playthrough and Battle references; nothing writes it.
- **What to play next goes by Intent alone,** so a Game I want to buy that's Up next or Backlog is there, buying it being the first step to playing it.
- **Copies still never change it** (as before): a Game I've since bought keeps the flag until I clear it.
- **The cart is in a Cover's ROM corner,** the bottom right, as it's about owning the Game, leaving the top right to Playing and the Intent. A missing ROM's warning wins the corner, as it's something to fix, then the cart, then Archived. The table shows the cart beside the name, as it does a ROM badge.
- **The Want to buy screen and filter** scope the Library to the flag, as Childhood's do.

## Considered Options

- **Intent as a set, Want to buy one of several values a Game can have at once**: rejected. Backlog and Up next do exclude each other, and a set would make them seem not to.
- **Clearing the flag when a Copy is added**: rejected for now, as before v47. A Copy recorded later than the buying, or a ROM of a Game I still want a boxed copy of, would clear it wrongly.
- **Keeping the date it was set**: rejected. Nothing sorts by it, and the Library's Intent set sort is the Intent's.
