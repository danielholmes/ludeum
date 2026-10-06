# Battery saves: OpenEmu vs Ludeum's standalone Emulators

Researched 2026-10-06 for issue #58. Save states are out of scope. "Local" = what is actually on this Mac under `~/Library/Application Support/OpenEmu` (listed read-only).

## Gist

- OpenEmu keeps battery saves per core in `~/Library/Application Support/OpenEmu/<Core>/Battery Saves/<ROM name>.<ext>`; Mednafen adds the ROM's MD5: `<name>.<md5>.<ext>`. Dolphin and PPSSPP keep their own full user trees under `OpenEmu/dolphin/` and `OpenEmu/PPSSPP/`.
- Most cartridge saves are raw SRAM dumps. **Copy + rename** works for NES, SNES, GB/GBC, GBA, SMS/GG (MesenCE), PS1 (DuckStation), GC (Dolphin GCI folder) and PSP (PPSSPP SAVEDATA).
- **Conversion needed** for N64 (Mupen64Plus `.mpk` holds 4 Controller Paks; `.eep` is always 2 KiB; SRAM/Flash byte-order between Mupen and ares is unverified), Mega Drive (GPGX byte layout vs ares, unverified) and DS (if the source is DeSmuME `.dsv`, strip the footer).
- **Awkward / partly infeasible**: Saturn and Sega CD internal backup RAM. Ymir (by default) and ares use **one global** internal-backup image, but OpenEmu keeps one per game. Copying one game's image overwrites the others. Merging would need a backup-RAM file-level tool (Ymir has an import/export manager in its UI).

## Per Platform

| Platform | OpenEmu core → file | Target Emulator → expected file | Verdict |
|---|---|---|---|
| NES | Nestopia → `Nestopia/Battery Saves/<rom>.sav` (raw PRG-RAM) | MesenCE → `MesenCE/Saves/<rom>.sav` | Copy (name must match the ROM file name Ludeum launches) |
| SNES | Snes9x → `SNES9x/Battery Saves/<rom>.sav` (raw SRAM) | MesenCE → `Saves/<rom>.srm` | Copy + rename extension |
| GB/GBC | Gambatte → `Gambatte/Battery Saves/<rom>.sav` (raw cart RAM; RTC is separate) | MesenCE → `Saves/<rom>.srm` (+ `.rtc` for MBC3) | Copy + rename; RTC is not carried over (clock resets) |
| GBA | mGBA → `mGBA/Battery Saves/<rom>.sav` (raw SRAM/Flash/EEPROM) | MesenCE → `Saves/<rom>.sav` | Copy; EEPROM byte order mGBA vs Mesen unverified, so test one EEPROM game |
| SMS / GG | Genesis Plus GX → `GenesisPlus/Battery Saves/<rom>.sav`/`.srm` (unverified) | MesenCE → `Saves/<rom>.sav` | Copy + rename (likely; unverified) |
| PCE-CD | Mednafen → `Mednafen/Battery Saves/<name>.<md5>.sav` (BRAM, 2 KiB) | MesenCE → `Saves/<rom>.sav` (CD BRAM, per game) | Copy + rename (format unverified; Mednafen may gzip some save files) |
| PS1 | Mednafen → `Mednafen/Battery Saves/<name>.<md5>.<slot>.mcr` (raw 128 KiB card) | DuckStation → `DuckStation/memcards/<title-or-serial>_<slot+1>.mcd` (raw 128 KiB) | Copy + rename: `.0.mcr`→`_1.mcd`, `.1.mcr`→`_2.mcd` |
| GameCube | Dolphin core → `OpenEmu/dolphin/GC/<REGION>/Card A/*.gci` (GCI folder) | Dolphin → `~/Library/Application Support/Dolphin/GC/<REGION>/Card A/*.gci` | Copy the `.gci` files (same layout) |
| N64 | Mupen64Plus → `Mupen64Plus/Battery Saves/<rom>.eep` (2 KiB), `.sra`, `.fla`, `.mpk` (4×32 KiB Controller Paks) | ares → `<rom>.eeprom` / `.ram` / `.flash` next to the ROM (Saves path is empty here), Controller Pak `save.pak` (32 KiB) per gamepad | Convert: truncate `.eep` to the game's EEPROM size (512 B for 4 Kbit); split the first 32 KiB of `.mpk`; SRAM/Flash byte-swap needs testing |
| Mega Drive | Genesis Plus GX → `GenesisPlus/Battery Saves/<rom>.srm` | ares → `<rom>.ram` / `.eeprom` | Probably conversion (GPGX keeps a byte-addressed 64 KiB buffer; ares stores the cartridge RAM only); unverified |
| Sega CD | Genesis Plus GX → `.brm` (8 KiB internal BRAM, unverified) | ares → **global** `backup.ram` in the Mega CD system pak | Copy only if one game; otherwise needs merging |
| Saturn | Mednafen → `<name>.<md5>.bkr` (32 KiB internal), `.bcr` (cart backup), `.smpc` | Ymir → **global** `StrikerX3/Ymir/state/bup-int.bin` (256 Kbit = 32 KiB), unless `InternalBackupRAMPerGame = true`; cart backup is configured separately | Raw copy plausible (same size); per-game mode makes it a copy; import through Ymir's backup manager is the safe path |
| DS | OpenEmu's DS core (DeSmuME-based, unverified): `.dsv` = raw + footer | melonDS → `<rom>.sav` raw, next to the ROM by default | Strip the DeSmuME footer, rename |
| PSP | PPSSPP core → `OpenEmu/PPSSPP/PSP/SAVEDATA/<GAMEID…>/` | PPSSPP → `<memstick>/PSP/SAVEDATA/<GAMEID…>/` | Copy the folders |

## Local inventory (read-only listing)

- `Gambatte/Battery Saves`: 8 `.sav` (8–32 KiB): Pokemon Yellow, Pokemon TCG, FF Adventure, Resident Evil Gaiden, Bomberman Quest, Donkey Kong, `Neighbor.sav`, `game 2.sav`.
- `mGBA/Battery Saves`: Advance Wars (64 KiB), Pokemon LeafGreen (128 KiB), Bomberman Tournament (0 bytes, empty).
- `SNES9x/Battery Saves`: Super Mario World (2 KiB), Super Mario All-Stars (8 KiB), Sensible Soccer (8 KiB), `Super Famicom Wars ... .sav.sav` (32 KiB; double extension). `Save States/SuperNES/` also holds a stray `.sav`.
- `Mupen64Plus/Battery Saves`: Mario Kart 64 `.eep` (2 KiB) + `.mpk`, Castlevania `.mpk`, Castlevania LoD `.mpk` (128 KiB each).
- `Mednafen/Battery Saves`: PS1 `.mcr` 128 KiB for Bugs Bunny & Taz, Gran Turismo 2, Jonah Lomu Rugby, Spyro (slots 0/1, one slot 4); Saturn House of the Dead `.bkr` (32 KiB), `.bcr` (570 B), `.smpc` (12 B).
- `BIOS/b/<name>.<md5>/*.mcr`: many more `.mcr` files (`C.0`–`C.7`, `0.0`, `1.0`…) for Bugs Bunny, Jonah Lomu, Metal Gear Solid discs and VR Missions. These look like multitap/extra-card files. Which core writes them is unexplained.
- `Nestopia/`, `GenesisPlus/Battery Saves`: empty. `dolphin/GC/*/Card A`: empty. `PPSSPP/PSP/SAVEDATA`: empty.
- Already on the standalone side: `DuckStation/memcards/Metal Gear Solid (USA)_1.mcd`; `MesenCE/Saves/Survival Kids (U) [C][!].srm`.

## Sources

- Mesen2 battery naming: `BatteryManager::GetBasePath` = SaveFolder + `<romName><ext>`. Extensions are `.sav` for NES (`Core/NES/BaseMapper.cpp`), GBA (`Core/GBA/Cart/GbaCart.cpp`), SMS/GG (`Core/SMS/SmsMemoryManager.cpp`) and PCE-CD (`Core/PCE/CdRom/PceCdRom.cpp`). They are `.srm` for SNES (`Core/SNES/BaseCartridge.cpp`) and GB (`Core/Gameboy/Gameboy.cpp`); GB RTC is `.rtc` (`GbMbc3Rtc.h`). https://github.com/SourMesen/Mesen2. Local settings: `MesenCE/Saves/`.
- DuckStation: `Settings::GetGameMemoryCardPath` → `memcards/{serial-or-title}_{slot+1}.mcd` (`src/core/settings.cpp`). Title vs serial is chosen in `System::GetGameMemoryCardPath` (`src/core/system.cpp`). Local `settings.ini`: `Card1Type = PerGameTitle`, `UsePlaylistTitle = true`. https://github.com/stenzek/duckstation
- ares: `Emulator::locate` saves `<rom without suffix><suffix>` next to the game when the Saves path is empty, else `<path>/<System>/<name><suffix>` (`desktop-ui/emulator/emulator.cpp`). N64 suffixes are `.ram/.eeprom/.flash/.rtc` (`mia/medium/nintendo-64.cpp`), with Controller Pak `save.pak` (`ares/n64/controller/gamepad/gamepad.cpp`). MD suffixes are `.ram/.eeprom` (`mia/medium/mega-drive.cpp`). Mega CD BRAM is `backup.ram` read from the system pak (`ares/md/mcd/mcd.cpp`). https://github.com/ares-emulator/ares
- Ymir: `kInternalBackupRAMSize = 256Kbit` (`libs/ymir-core/include/ymir/sys/memory_defs.hpp`). README lists an "integrated backup memory manager to import and export saves". Local `Ymir.toml`: `InternalBackupRAMImagePath = 'bup-int.bin'`, `InternalBackupRAMPerGame = false`. https://github.com/StrikerX3/Ymir
- OpenEmu paths and sizes: local filesystem listing (above).
- Unverified (inferred, not traced to source here): the GPGX SRAM layout, the DeSmuME `.dsv` footer and OpenEmu's DS core identity, Mupen64Plus SRAM/Flash byte order vs ares, Mednafen PCE BRAM / Saturn `.bcr` compression, and the melonDS/PPSSPP standalone default paths on macOS.
