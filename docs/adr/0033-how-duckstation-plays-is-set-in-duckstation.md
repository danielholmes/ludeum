# How DuckStation plays is set in DuckStation

Amends [0024](0024-ludeum-installs-duckstation-and-says-where-it-keeps-things.md): fast boot and frame pacing leave the Standing settings.

Since 0021, and globally since 0024, every launch wrote four of DuckStation's settings on: fast boot (`[BIOS] PatchFastBoot` and `FastForwardBoot`) and its lowest input latency (`[Display] OptimalFramePacing` and `PreFrameSleep`). They were Ludeum's because they were for every Game and DuckStation had no flag for them, and the per-game file, then the Standing settings, were the one place for them. But they're choices about how DuckStation plays, not about where it keeps things, and I want DuckStation to be the place I make those: 0029 already moved a Game's own settings there, and a global one changed in DuckStation's settings was undone at the next Play, with nothing in Ludeum showing why.

So:

- **The Standing settings are only what Ludeum needs**: where DuckStation keeps things (0024), the PlayStation ROM folder in its game list (0026) and no self-updating. A Play writes nothing about how DuckStation plays.
- **Fast boot and frame pacing stay on**, as every Play so far wrote them into `settings.ini` and Ludeum no longer touches those keys. Turning any of them off in DuckStation's settings now lasts.

## Considered Options

- **Write them once, at Install, and never after**: rejected. A reinstall carries `settings.ini` across, so there's no first run to seed, and a default Ludeum chooses once is still Ludeum dictating it.
- **Keep them Standing but let a change in DuckStation win**: rejected. Ludeum can't tell a change from DuckStation's default without keeping a copy of what it last wrote, and the result is the same as not writing them.

## Consequences

- A fresh DuckStation, one not installed over this one, boots in full and with DuckStation's default frame pacing until set in its settings. Ludeum doesn't say so.
- PCSX2's, MesenCE's, ares's and Dolphin's latency and fast boot settings are still Ludeum's; this decision is DuckStation's alone.
