# xemu under Ludeum's management

Researched 2026-11-04 for issue #89. The question: can Ludeum manage xemu as ADR 0024 manages DuckStation, 0027 MesenCE, 0028 ares and 0032 PCSX2 (install a pinned build, keep it apart from any other copy, write Standing settings that put its Save states and Game saves in the Data folder, refuse Play while it runs, list and Play from Save states in Game detail, show a Game's Game saves)? Where does xemu keep them, what does it name them by, what loses one, and do they follow a ROM through Archive, Compact and Rename? This note builds on [xbox-emulator.md](xbox-emulator.md) (2026-10-14) and the xemu row of [managing-emulators-inside-ludeum.md](managing-emulators-inside-ludeum.md), and checks what issue #89 claims. It lays out the facts and the options. It doesn't make the decision.

Sources:

- **xemu source** at tag `v0.8.139`, commit `aa54c34cae1c09410d74c69a44210a9867fe2d16` (2026-10-21), the latest versioned release. Links like `T/ui/xemu-snapshots.c#L260-L302` mean `https://github.com/xemu-project/xemu/blob/aa54c34cae1c09410d74c69a44210a9867fe2d16/ui/xemu-snapshots.c#L260-L302`.
- **xemu `master`** at `6095054b7d02dfac25fdc4a8ba9300358046e860` (2026-11-02). Nine commits past the tag, all renderer, CI or contributing changes. `ui/xemu-snapshots.c`, `ui/xui/snapshot-manager.cc`, `ui/xemu-settings.cc`, `config_spec.yml`, `migration/savevm.c`, `block/qcow2-snapshot.c`, `system/vl.c` and `ui/xemu.c` are identical there (diffed), so no `master` links are needed.
- **genconfig**, which writes `xemu.toml`, at `42f85f9a2457e61d7e32542c07723565a284fcd6`, the revision in `T/subprojects/genconfig.wrap`. Links like `G/cnode.h#L194` mean `https://github.com/mborgerson/genconfig/blob/42f85f9a2457e61d7e32542c07723565a284fcd6/cnode.h#L194`.
- **SDL** at `829a65d769d935c4852f8159e964312c0957260a`, the revision in `T/subprojects/sdl3.wrap`: `src/filesystem/cocoa/SDL_sysfilesystem.m`, as `S#L..`.
- **xemu's documentation**, `xemu-project/xemu-website` at `bb920769e1682af6293be9ba48a402a099a7bd60` (2026-11-02): `docs/docs/snapshots.md`, `faq.md`, `required-files.md`, `cli.md`, `disc-images.md`, `dashboard.md`, `ftp.md`, `xmus.md`, `troubleshooting.md`, as `D/<file>`.
- **xemu's issue tracker** where it records a known fault (#1484, #1566, #1717, #2284, #2506, #2624).
- **The GitHub REST API** for releases, tags, digests and repo metadata.
- **The release assets** `xemu-0.8.139-macos-universal.zip`, `xemu-0.8.136-macos-universal.zip` and `xbox_hdd.qcow2` (`xemu-project/xemu-dashboard` release `v20260516-0955`), downloaded into the session scratchpad, checked against the API's digests and inspected. None was run. xemu was never run.
- **xboxdevwiki** ([Hard Drive](https://xboxdevwiki.net/Hard_Drive), [Xbox Savegame System](https://xboxdevwiki.net/Xbox_Savegame_System), [Xbe](https://xboxdevwiki.net/Xbe), [XDVDFS](https://xboxdevwiki.net/XDVDFS)) for the console's own layout. It's a community wiki, not a primary source, and is named wherever it's relied on. The XDVDFS directory entry is from `antangelo/xdvdfs` at `6b05af7fba79d567ef8c9698c8702b8d782248b8`, the tool xemu's docs recommend.
- **Dropbox's** [conflicted copy](https://help.dropbox.com/organize/conflicted-copy) and [online-only](https://help.dropbox.com/sync/make-files-online-only) help pages and its [engineering post on blocks](https://dropbox.tech/infrastructure/streaming-file-synchronization).
- **This Mac**, read without changing or launching anything: `/Applications/xemu.app`, `~/Library/Application Support/xemu/xemu/`, the Ludeum folder and the Data folder, by listing and `stat`. No ROM's contents were read.
- **Ludeum's code** on `main` at commit `466e232`.

Anything not checked against one of these sources is marked **unverified**. Behaviour read from the source but not seen running says "from the source".

## Answer

**Install, isolation and settings fit, with one new wrinkle. Save states and Game saves don't fit any shape so far: every Game's of both live in one disk image of the console's, and loading a Save state rewinds that whole image.** Seven facts shape the design:

1. **Save states are QEMU internal snapshots inside the hard disk image (the issue's "check" holds).** `savevm` writes the machine's state into the qcow2 file and records a copy of its L1 table in the file's snapshot table. There's no state file to list, copy or delete. A plain (raw) image can't hold one (§3).
2. **Loading one reverts the whole disk.** It makes the snapshot's L1 table the active one, so everything written to the image since, by any Game, is gone unless another snapshot holds it. On one shared image, loading Game A's Save state from last week throws away Game B's Game saves from this week. xemu's docs warn of it only for the one game (§3).
3. **A snapshot records the DVD's path as a string, and a Rename doesn't lose it.** It's used only by xemu's own menu, which compares it with the disc in the drive and asks what to do. "No" loads the snapshot with the disc that's in, which after a Rename is the right one. "Yes" ejects the disc, fails to open the old path and doesn't load. `-loadvm` and the monitor don't look at it. So nothing is lost, but the path stays stale inside the snapshot for good (§6).
4. **`-loadvm` can't start a Play from a Save state taken with a controller bound, at this tag or `master`, from the source and a report; it wasn't tried here.** `-loadvm` runs before xemu binds its inputs, a snapshot taken with any controller bound then has a USB device the machine lacks, and the failure exits xemu (`error_fatal`). xemu's own issue #1717 says so, with a report on v0.8.136 on Windows; what controller is connected at launch doesn't come into it. The monitor's `loadvm`, sent after startup, is the known workaround, and is a race for Ludeum to win (§3).
5. **Two routes keep it apart, and only one keeps the bundle sealed.** The portable route, `xemu.toml` in `Contents/Resources`, breaks the seal: on a scratch copy `codesign --verify` says "a sealed resource is missing or invalid, file added" and `spctl` then refuses it. The stapled ticket isn't enough. `-config_path <file>` on every launch writes nothing into the bundle, and its file names every path that matters. That leaves only the shader cache in `~/Library/Application Support/xemu/xemu/`, shared with any other xemu, and a double-clicked copy doesn't get the file (§1).
6. **Listing can be done without xemu, deleting can't reasonably.** A qcow2 reader for the snapshot table, xemu's own metadata (title name, disc path, 160 × 120 PNG thumbnail, all plain at the start of the VM state) and the FATX file system is small: a 156-line throwaway reader here walked the clean image, including its compressed clusters and five FATX partitions. No real snapshot exists on this Mac to test the snapshot half against. Deleting means rewriting refcounts, which needs `qemu-img` (not in the bundle), or xemu's own menu or monitor (§4, §5).
7. **One multi-gigabyte file written in place is unlike anything in the Data folder today.** Each Save state adds up to the machine's RAM (64 MiB by default, from the source) and copy-on-write of what changes after it, the three game cache partitions can reach 2.2 GiB, nothing shrinks the file, and it's open for writing throughout a Play. Two Macs diverging means a conflicted copy of everything at once. One image per Game shrinks all of that and removes fact 2's reach beyond one Game, at the cost of a real console's shared disk (§8).

The rest:

- **Install.** Versioned tags with a `digest` per asset, none aged off since 2022, signed, notarised, stapled and universal. The bundle is `xemu.app` beside `LICENSE.txt` in the zip. `Info.plist` gives the version without a launch; **any** launch, `-version` included, rewrites the settings file at exit and opens a window first, from the source (§10).
- **Game saves** are at `E:\UDATA\<title ID>\` on the image's FATX partition (FAQ for the partition, xboxdevwiki for the folders). The key Ludeum would need is the title ID in `default.xbe`'s certificate, read through the XISO's XDVDFS. They survive Rename because no ROM file's name is involved (§5, §6).
- **Formats.** Nothing has changed: loose XISO `.iso` only. No CHD, CCI or Redump at the tag or `master`, and #2808 and #2809 are still open. Both of this Mac's Xbox ROMs are Archived `.7z`, so neither can be Played until Unarchived (§6, §12).
- **This Mac has no working xemu setup any more.** Its `xemu.toml` names an MCPX, a BIOS and an HDD in `~/Downloads/XEMU_FILES/`, and that folder is gone. So there are no Save states or Game saves to bring across, unless that folder is in the Trash, which this session can't read, and Play needs those two firmware files found again (§12).

## 0. Which repository

- **`xemu-project/xemu`**, default branch `master`, pushed 2026-11-02, 4,231 stars. The API's `license.spdx_id` is `NOASSERTION`, because `LICENSE` is QEMU's prose; it says "the QEMU emulator as a whole is released under the GNU General Public License, version 2", and the zip's `LICENSE.txt` says the binary is under GPL-2.0. The issue's GPL-2.0 holds.
- **`xemu-project/xemu-dashboard`** (MIT) builds the clean `xbox_hdd.qcow2`. **`xemu-project/xemu-website`** holds the docs.

## 1. Data root, portable mode and what it writes where

### How the base path is decided

- **`xemu_settings_get_base_path`** (`T/ui/xemu-settings.cc#L73-L92`): if a file named `xemu.toml` opens at `SDL_GetBasePath()` (`#L51-L63`), that folder is the base, else `SDL_GetPrefPath("xemu", "xemu")`.
- **On macOS `SDL_GetBasePath()` is the bundle's resource folder**, `xemu.app/Contents/Resources/`, unless `Info.plist` has `SDL_FILESYSTEM_BASE_DIR_TYPE` (`S#L34-L64`). The release's `Info.plist` doesn't, so a portable `xemu.toml` must be inside the bundle, as the FAQ says (`D/faq.md`). The app's parent folder, the route PCSX2 and ares took, isn't looked at.
- **`SDL_GetPrefPath`** is `NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory…)` + `xemu/xemu/`, created with `mkdir` on every call (`S#L88-L135`). That's `~/Library/Application Support/xemu/xemu/`, which resolves the earlier note's **unverified**, and it's what exists on this Mac.
- **`-config_path <file>` moves only the settings file** (`T/ui/xemu-settings.cc#L65-L71`, `#L94-L105`; parsed at `T/ui/xemu.c#L1373-L1382`). The base path ignores it. The issue's claim holds: the file then says where the hard disk image is. There's no flag or environment variable for the base path of xemu's own. Whether a changed `HOME` or `CFFIXED_USER_HOME` moves what `NSSearchPathForDirectoriesInDomains` returns is **unverified** (ADR 0024 rejected that family of trick).

### Every file xemu writes

| What | Where | Set by | Written |
|---|---|---|---|
| `xemu.toml` | `-config_path`, else base | flag or portable file | At exit only (§2) |
| Hard disk image | `sys.files.hdd_path` | `xemu.toml`; no default | In place, throughout a Play |
| `eeprom.bin` | `sys.files.eeprom_path`, else `<base>eeprom.bin`, the default then written back into the key | `xemu.toml` | Generated if missing (`T/system/vl.c#L2909-L2949`); written when the guest changes it (`persist`, default on, `T/hw/xbox/smbus_storage.c#L111`, `#L158`) |
| `shaders/<hash>/…`, `shader_cache_list` | Base path, **no key** | Nothing moves them; `perf.cache_shaders = false` turns the cache off | During play (`T/hw/xbox/nv2a/pgraph/gl/shaders.c#L258-L268`, `#L369-L371`) |
| Screenshots | `general.screenshot_dir`, else `.`, the working directory | `xemu.toml` | F12 (`T/ui/xui/gl-helpers.cc#L1027-L1033`). A launch through `NSWorkspace` probably has `/` as its working directory, so the default would fail: **unverified** |

Read only: the MCPX (`bootrom_path`) and flash (`flashrom_path`), the disc, `input.gamecontrollerdb_path`. Not written at all on macOS: an ImGui `.ini` (`io.IniFilename = NULL`, `T/ui/xui/main.cc#L144`) and a log (`xemu.log` is Windows only, `T/ui/xemu.c#L1351-L1358`; here it's stderr). macOS keeps file-dialog state under the `xemu.app.0` defaults domain, as for any app. `#if`-guarded updater code doesn't exist in this build (§2).

The shader cache is rebuildable and each entry is checked against `xemu_version`, the GL vendor and GL version before use (`T/hw/xbox/nv2a/pgraph/gl/shaders.c#L423-L448`), so sharing it with another copy costs nothing but rebuilds. On this Mac it's empty (§12).

### The routes

- **Portable: `xemu.toml` in `Contents/Resources`.** Everything lands inside the bundle (settings, a default EEPROM, shader cache), self-contained even when double-clicked. Tested on a scratch copy of the release, with nothing executed: untouched, `codesign --verify --deep --strict` says "valid on disk" and `spctl -a -t exec` "accepted, Notarized Developer ID"; with the file added, `codesign` says "a sealed resource is missing or invalid / file added" and `spctl` says the same and refuses. `stapler validate` still passes, as the ticket is about the cdhash. Remove the file and it's valid again. ADR 0024 accepted a broken seal for an ad-hoc-signed app that was never quarantined. Whether macOS 26 runs a hardened, Developer ID–signed bundle with a broken seal and no quarantine is **unverified** without running it. A link at that path would be a file added all the same.
- **`-config_path <file>` on every launch, the file beside the app.** E.g. `Emulators/xemu/xemu.app` with `Emulators/xemu/xemu.toml`. The bundle stays sealed and notarised, like ares's and PCSX2's. `open --args` is the FAQ's form; Ludeum's Play already passes arguments through `NSWorkspace.OpenConfiguration` (`App/Sources/GameDetailParts.swift` ~491–499). Left in the shared base: only the shader cache, with `eeprom_path` set. It holds only for launches from Ludeum: a double-clicked copy reads the global `xemu.toml`. ADR 0024 weighed that against a changed `HOME`, and ADR 0035's Amiberry launch, every setting on the command line, already depends on it.
- **Keep `/Applications/xemu.app`, `-config_path` alone.** Writes nothing and installs nothing; loses the pin (ADR 0024's objection).

## 2. Settings: `xemu.toml`

### Shape

TOML, generated from `T/config_spec.yml`. Path and first-run keys:

| Key | Default | Note |
|---|---|---|
| `general.show_welcome` | `true` | While true, the machine doesn't start and the First Boot window opens; its Settings button clears it (`T/system/vl.c#L3042-L3045`, `T/ui/xui/welcome.cc#L53-L63`) |
| `general.updates.check` | `true` | **Does nothing on macOS.** The check and `update.cc` are Windows only (`T/ui/xui/main.cc#L151-L155`, `T/ui/xui/meson.build#L28-L29`, `T/ui/xui/main-menu.cc#L56-L60`). No updater can replace the bundle. #1350 asks for one |
| `general.screenshot_dir` | empty | See §1 |
| `general.games_dir` | empty | The popup menu's list of `.iso`/`.xiso` to switch to; set from the first disc loaded through the menu when empty (`T/ui/xui/actions.cc#L53-L68`) |
| `general.skip_boot_anim` | false | `short-animation=on`, the nearest thing to fast boot (`T/system/vl.c#L3019-L3024`) |
| `general.snapshots.shortcuts.f5`…`f8` | empty | Snapshot names bound to F5–F8 (§3) |
| `general.snapshots.filter_current_game` | false | The menu's "Filter by current title" |
| `sys.files.bootrom_path`, `flashrom_path`, `eeprom_path`, `hdd_path`, `dvd_path` | empty | `T/config_spec.yml#L362-L367` |
| `sys.mem_limit` | `'64'` | `-m 64` (`T/system/vl.c#L3056-L3058`) |
| `display.window.fullscreen_on_startup`, `vsync` | false, true | `T/config_spec.yml#L244-L259` |
| `input.bindings.port1`…`port4`, `port1_driver`… | empty | A controller's SDL GUID, `keyboard`, and the driver. `input.auto_bind` (default true) binds a new controller to a free port and remembers it (`T/ui/xemu-input.c#L426-L435`) |

### When it's read and written

- **Read once, at startup** (`T/ui/xemu.c#L1384`). A file that doesn't parse is a fatal message box and exit (`#L1384-L1392`); no file means defaults (`T/ui/xemu-settings.cc#L163-L165`).
- **Written once, at exit**, by `atexit` (`T/ui/xemu.c#L1393`, the only caller in `ui/`, `system/` or `hw/`). So it isn't touched during a Play, and a write by Ludeum during one is lost at the end. A SIGKILL or crash skips the write; an `exit(1)` from a failed `-loadvm` doesn't.
- **Not atomic.** `fopen(path, "wb")`, `fprintf`, `fclose` (`T/ui/xemu-settings.cc#L209-L238`). A link at the path survives it, unlike DuckStation's and PCSX2's rename.
- **Whole file, and only what differs from the default** (`generate_delta_toml`, `G/cnode.h#L588`). A key set to its default vanishes, which is harmless.
- **Unknown keys are dropped.** At load they print "unrecognized" and are skipped (`G/cnode.h#L194-L211`), and the save writes only from the tree, so they're gone after the first exit. A key of the wrong type is skipped the same way.
- **Absolute paths and spaces work.** The on-disk form is a TOML literal string, `eeprom_path = '/Users/daniel/Library/Application Support/xemu/xemu/eeprom.bin'`, which xemu wrote itself here. Commas are doubled for QEMU's option parser (`strdup_double_commas`, `T/system/vl.c#L2538-L2552`, used for bootrom, EEPROM, HDD and DVD), which matters as Redump names carry them: `Dino Crisis 3 (Europe) (En,Fr,De,Es,It)`. How the writer quotes a path containing `'` is the toml++ formatter's choice and **unverified**, so a parser in Ludeum must take both string forms.
- **Ludeum has no TOML code today** (grepped `Sources/`, `Package.swift`). MesenCE is JSON, ares BML, DuckStation and PCSX2 INI.

### The disc path

- **`-dvd_path` isn't written back**, as the earlier note says: it's a local in `qemu_init`, and the argument is cleared before QEMU parses (`T/system/vl.c#L3076-L3095`). Re-verified.
- **But a disc loaded inside xemu is.** The Load Disc menu, and "Yes" in the snapshot prompt, call `xemu_load_disc`, which sets `sys.files.dvd_path` (`T/ui/xemu.c#L1453-L1470`), and eject clears it (`#L1437-L1451`). So Ludeum's comment in `Emulators.swift` ("The disc isn't saved into its settings") is true of the flag. A `dvd_path` left in the file is what a launch without `-dvd_path` boots.

## 3. Save states

xemu calls them snapshots. The docs: "Snapshots are saved to the hard disk image that you started xemu with… They capture the full state of the machine, including any loaded disc, attached controllers, and hard drive state" (`D/snapshots.md`), and "Snapshot data is stored on the hard drive image, and is not easily extractable" (`D/faq.md`).

### How they're made

- **`save_snapshot`** (`T/migration/savevm.c#L3203-L3315`), QEMU's own, called by `xemu_snapshots_save` (`T/ui/xemu-snapshots.c#L250-L253`). With a name, an existing one of that name is **deleted first** (`#L3235-L3240`). Then the VM stops, its state is streamed into the image, and `bdrv_all_create_snapshot` records it.
- **Named** by what's typed in the menu, or `vm-YYYYMMDDHHMMSS` when none is (`#L3277-L3282`), up to 255 bytes (`T/include/block/snapshot.h#L41`). Nothing of a Game's in the name. Names are global to the image, and Replace or a bound key overwrites by name whatever Game made it: xemu's maintainers call that intended (#1566).
- **In qcow2**, the state goes at guest offsets past the end of the virtual disk; the L1 table is then copied, every cluster's refcount raised, and the snapshot table rewritten (`T/block/qcow2-snapshot.c#L637-L757`, `T/docs/interop/qcow2.rst#L679-L752`). The VM state is then discarded from the active L1 (`#L737-L741`), so it lives only under the snapshot. Later writes to shared clusters copy-on-write.
- **Which drives count:** every inserted, writable device must support snapshots, and the state goes in the first that does (`T/block/snapshot.c#L516-L563`, `#L736-L775`). The DVD is read-only, so it's skipped. So one writable non-qcow2 image blocks them all: a raw XMU fails with "Device 'xmu_0' is writable but does not support snapshots", silently in the menu (#2284), and a raw HDD can't take one.
- **`-snapshot`** (`T/system/vl.c#L3258-L3261`) runs on a temporary overlay: anything saved in that run goes with it (from the source).

### What xemu adds

Ahead of QEMU's stream, `xemu_snapshots_save_extra_data` writes (`T/migration/savevm.c#L1816-L1818`, `T/ui/xemu-snapshots.c#L260-L302`, `T/ui/xemu-snapshots.h#L32-L36`), big-endian:

```
u32 magic 0x78656d75 ('xemu'), u32 version 1, u32 size, then:
u32 length, disc path             (the DVD's path, as qmp_query_block reports it)
u8  length, XBE title name        (UTF-8, from the certificate's 40 UTF-16 units)
u32 length, thumbnail             (PNG, 160 × 120, of the framebuffer)
```

- **The title ID isn't kept**, only the title name, so a list by Game goes by name or by disc path. The menu's filter compares names (`T/ui/xui/main-menu.cc#L1363-L1370`).
- **Loading skips it** whichever version it is (`T/ui/xemu-snapshots.c#L304-L328`), and listing shows a snapshot of another version without metadata (`#L74-L77`).

### What loading does

- **`load_snapshot`** (`T/migration/savevm.c#L3396-L3480`) calls `bdrv_all_goto_snapshot`, which in qcow2 writes the snapshot's L1 table over the active one and drops the old one's refcounts (`T/block/qcow2-snapshot.c#L828-L878`). **Everything the disk gained since then is gone**, on every partition: saves on `E:`, of every Game on that image. The docs warn: "a newly saved game will not be present if you revert to an older snapshot" (`D/snapshots.md`). Other snapshots are untouched, as they keep their own references.
- **The machine must match.** A USB device in the state that the machine lacks is "Unknown section or instance… Make sure that your current VM setup matches your saved VM setup, including any hotplugged devices" (`T/migration/savevm.c#L2634-L2636`). The docs: connect controllers as when it was saved, or an error shows and the machine pauses. A maintainer on #2624: "The configuration for loading a snapshot needs to be consistent". So a snapshot saved with a Duke controller in port 1 needs one there.
- **Disc:** §6.
- **From the menu**, `LoadSnapshotChecked` handles the disc (`T/ui/xui/snapshot-manager.cc#L59-L95`). From the monitor, nothing does: "Loading a snapshot from the monitor will not re-mount the game disc".

### Starting a Play from one

- **`-loadvm <name>` reaches `load_snapshot` with `error_fatal`** (`T/system/vl.c#L2882-L2886`), inside `qmp_x_exit_preconfig` (`#L4118`), before `qemu_init_displays` (`#L4120`), which posts the semaphore (`T/ui/xemu.c#L1226`) the main thread waits on (`#L1407`) before `xemu_input_init` (`#L1423`). So no controller or its hub exists yet (`xemu_input_bind`, `T/ui/xemu-input.c` ~L722–L769). #1717 and #1484 are open on exactly this: "we bring up input too late". A user report there on v0.8.136 on Windows: "Unknown section or instance 'pci.0:02.0/1.3/usb-hub' 0" and xemu closes; the same command worked for a snapshot taken with the controller unplugged. Not tried here. This code is identical on `master`.
- **The fix isn't simple**, by a maintainer's note on #1484: input init has to run from the main thread, as SDL requires.
- **The monitor's `loadvm`** is #1717's workaround (`sleep 2; echo loadvm snap0 | … -monitor stdio`). Extra arguments go to QEMU (`D/cli.md`), and the binary has `socket` chardevs, so `-monitor unix:<path>,server=on,wait=off` plus a `loadvm` from Ludeum is possible, from the source, with `-dvd_path` having put the disc in. A failure there leaves xemu open rather than killing it. It has to wait for controllers to be bound, a race like the one a state on MesenCE's command line lost (ADR 0027). Nothing here tried it. `info usb` or a retry could tell when it's ready: **unverified**. `-qmp` is the same with structure.
- **Left to xemu:** Ludeum starts the disc and F5–F8 or the menu load the state, Save states shown read-only in Game detail.

### Other ways in and out

- **No Resume state.** Every caller of `xemu_snapshots_save` is a user action (`T/ui/xui/actions.cc#L107`, `T/ui/xui/main-menu.cc#L1346`, `#L1496`, `T/ui/xui/menubar.cc#L101`, `T/ui/xui/popup-menu.cc#L439`). Closing the window just shuts down (`T/ui/xemu.c#L579-L586`, `#L963-L969`). ADR 0034 has nothing to read, and a monitor `savevm` on close would need Ludeum to be the thing closing it.
- **Quick slots, by binding.** Once a name is in `general.snapshots.shortcuts.f5`–`f8`, F5–F8 load it and Shift+F5–F8 save it (`D/snapshots.md`, `T/ui/xui/actions.cc#L94-L116`, `T/ui/xui/main.cc` ~L302). Saving creates it if it isn't there, from the source, so a Standing setting could give a Play four named slots (per Game, on a shared image, sidestepping #1566). Delete in the menu has no confirmation (`T/ui/xui/main-menu.cc#L1499-L1501`).
- **Across xemu versions.** There's no single version gate as PCSX2's `g_SaveVersion`, and no build check as ares's. QEMU's rule is per device: a section newer than the build's or older than its `minimum_version_id` is refused (`T/migration/vmstate.c#L142-L153`). Between v0.8.136 and v0.8.139, `git diff` of `hw/xbox` shows that kept deliberately: `nv2a` goes from version 3 to 5, `minimum_version_id` 1, with new fields versioned and a `post_load` filling them (`T/hw/xbox/nv2a/nv2a.c#L440-L453`, `#L467-L468`), and the new DSP core pads old fields with `VMSTATE_UNUSED` and puts new state in a subsection. So a newer xemu is meant to load older snapshots and an older one will refuse newer ones. It's not promised in the docs, and not tried. Devices have slipped: #2241's "Error -22" with a Controller S closed on 2026-01-15, two days after `739520523f` fixed that device's `minimum_version_id`. A bump probably doesn't cost the Save states, where ADR 0028's and 0032's can.

## 4. Listing and deleting Save states without xemu

**Reading is plain.** The steps, per `T/docs/interop/qcow2.rst`:

1. Header, big-endian: version at 4, `cluster_bits` at 20, virtual size at 24, `l1_size` at 36, `l1_table_offset` at 40, `nb_snapshots` at 60, `snapshots_offset` at 64.
2. Snapshot table at `snapshots_offset`, entries 8-byte aligned (`#L699-L752`): L1 offset (8), L1 entries (4), id length (2), name length (2), date seconds (4), nanoseconds (4), guest clock (8), VM state size (4), extra data size (4), extra data (for v3: 64-bit VM state size at 40, disk size at 48, then icount), id, name.
3. VM state lives at guest offset `l1_vm_state_index << (cluster_bits + l2_bits)` under **the snapshot's** L1 (`T/block/qcow2.h#L710-L713`, `T/block/qcow2.c#L1664`). For the 8 GiB image with 64 KiB clusters that's exactly 8 GiB (16 L1 entries of 512 MiB each). VM state isn't compressed (written through the same path as guest writes, `T/block/qcow2.c#L5449-L5471`).
4. Read §3's header there: title, disc path, PNG thumbnail.

So Game detail could list name, date, title and picture, as it does for DuckStation, from a Swift reader. **Tested here**: a 156-line Python reader of header, L1, L2, compressed clusters (raw deflate, 22 read) and FATX ran over the clean image and agrees with `qemu-img info` (qcow2 compat 1.1, 8 GiB virtual, 64 KiB clusters, 16-bit refcounts, 0 snapshots, 1.6 MiB on disk). **Not tested**: steps 2–4 against a real snapshot, as none exists on this Mac and xemu wasn't run.

- **While xemu runs,** QEMU caches metadata in memory, so a read from outside may see a stale or half-updated table. xemu's own locks are advisory and Ludeum's plain read wouldn't take one (§9). xemu's listing opens the file read-only with `BDRV_O_RO_WRITE_SHARE` for the same reason (`T/ui/xemu-snapshots.c#L156-L158`). ADR 0034's re-read "whenever Ludeum becomes active" would meet this.
- **`qemu-img snapshot -l`** lists names, dates and sizes, not xemu's metadata. It isn't in the bundle (`Contents/MacOS/xemu` and dylibs only). Homebrew's `qemu` would bring it, as ADR 0027's SDL2 came from Homebrew; on this Mac there's only the Android SDK's (`~/Library/Android/sdk/emulator/qemu-img`, 2.12), which isn't a thing to rely on.

**Deleting from outside** means rewriting the snapshot table, decrementing refcounts through all the snapshot's L2 tables and freeing clusters, in the file's own write order (`qcow2_snapshot_delete`, `T/block/qcow2-snapshot.c` ~L909–L975). A hand-written writer can corrupt every Game's saves at once on a shared image. The routes are: `qemu-img snapshot -d` with xemu closed; `delvm` over the monitor during a running xemu; or xemu's menu. Nothing shrinks the file: freed clusters are punched as holes on APFS (`pass-discard-snapshot` default on, `T/block/qcow2.c#L1219`, `T/block/file-posix.c#L2333-L2339`) and reused, its length stays.

## 5. Game saves

- **Where.** "Just like on a real Xbox, they are stored on the E partition of the virtual hard drive. The drive contents can be accessed with FTP" (`D/faq.md`). So the issue's first claim holds: the image holds every Game's saves, in one file system.
- **Layout (xboxdevwiki).** `E:\UDATA\<title ID as 8 lower-case hex digits>\` holds `TitleMeta.xbx` (text, `TitleName=…`, possibly localised), `TitleImage.xbx` (128 × 128 Xbox texture), and a folder per save, each with `SaveMeta.xbx`, optionally `SaveImage.xbx`, and the game's own files. `E:\TDATA\<title ID>\` holds downloaded content and other title data, and some games' saves. The wiki says every XBE that has run gets a folder in both, so a folder doesn't mean a save.
- **The title ID.** A 4-byte field of the XBE's certificate, usually two ASCII letters for the publisher and a 16-bit number (xboxdevwiki; its example `5553000c` is `US` 12). xemu reads it from guest memory: header at `0x10000`, `m_certificate_addr` at `+0x118`, then `m_titleid` at `+8`, `m_title_name` at `+0xC` (`T/xemu-xbe.h#L29-L41`, `#L76-L91`, `T/xemu-xbe.c#L82-L136`).
- **Ludeum could read it off the ROM.** XISO: volume descriptor at sector 32 (the header `XboxDisc` reads), root directory's sector and size at `0x14`/`0x18`, 2048-byte sectors (xboxdevwiki, xdvdfs's `volume.rs`). Directory entries are a binary tree: left and right offsets (u16), sector and size (u32), attributes and name length (u8), name (xdvdfs's `layout/`: 14 bytes before the name, `dirent_node.rs` and `disk_data.rs`). From `default.xbe`, base at `+0x104` and certificate address give the file offset. From a loose `.iso` that's a few reads. From a `.7z`, as both ROMs here are, it means streaming through 7-Zip to wherever `default.xbe` lies, which isn't fixed: `Serials` today reads only the start of a disc, for PlayStation and PS2 (`Sources/LudeumCore/Serials.swift`).
- **Is it a Serial?** The glossary's Serial is "the product code a disc is pressed with… as the disc itself says it". A title ID rendered `US-012` reads like one. That it matches the code printed on the disc or Redump's serial is **unverified**, as is how often regions of a game share one.
- **Reading them.** Fixed partitions, no table, per xboxdevwiki, and confirmed by `FATX` at each offset in the clean image:

| Partition | Offset | Size | Clean image |
|---|---|---|---|
| Config | `0x0` | 512 KiB | `RFRB` at `0x600` |
| X, game cache | `0x00080000` | 750 MiB | FATX, empty |
| Y, game cache | `0x2EE80000` | 750 MiB | FATX, empty |
| Z, game cache | `0x5DC80000` | 750 MiB | FATX, empty |
| C, system | `0x8CA80000` | 500 MiB | FATX, `xboxdash.xbe` (1,916,928 bytes, the size of the dashboard release's `default.xbe`) |
| E, data | `0xABE80000` | 4.8 GiB | FATX, empty: no `UDATA` until a game makes it |

  FATX here: 32 sectors a cluster, FAT from 4 KiB in, FAT16 below 0xFFF0 clusters and FAT32 above, 64-byte directory entries. The reader above listed it. FAT32 chains weren't exercised, E being empty. FATX timestamps give "when last written", but Ludeum's reader would be its first file-system code of this kind, reading a live disk's metadata as PCSX2's file cards would have needed (rejected in ADR 0032). With xemu closed only, as §4.
- **Other routes.** xemu-dashboard's FTP server, from inside a running machine, with NAT and a port forward set up (`D/ftp.md`): not something a Play would do. `TitleMeta.xbx` gives Ludeum a title to show. A snapshot's copy of a save can be read too, by reading through its L1, but no one would want that.
- **Signatures.** Saves are signed: the certificate carries a key "used to sign savegames" (xboxdevwiki), and "some game saves are tied to the console they were created on. Try using the EEPROM from the console they were created on" (`D/faq.md`). xemu generates a random `hdd_key` for a new EEPROM (`T/hw/xbox/eeprom_generation.c#L102-L107`). So **`eeprom.bin` belongs with the saves**: lose it and some Game saves stop loading, by the FAQ's account. It isn't needed to unlock the image: xemu's `locked=on` drive accepts any password ("XXX: Actually verify the password…", `T/hw/ide/core.c#L2559-L2563`).
- **Memory units.** XMUs are possible through the monitor only, and block snapshots (§3). None is set up here.

## 6. Through Archive, Compact and Rename

The key question. Saves and snapshots are keyed by the image, never by the ROM file. The one thing a ROM's name touches is the path string in a snapshot.

**What a snapshot does with that path** (`T/ui/xui/snapshot-manager.cc`):

- `LoadSnapshotChecked` compares `disc_path` with the drive's current path by `strcmp` (`#L75-L76`). Equal, it loads. If the snapshot was saved with no disc, it ejects what's in, and loads (`#L86-L89`).
- Different, it opens "DVD Drive Image": "The DVD drive disc image mounted when the snapshot was created does not appear to be loaded", Current and Expected, "Would you like to load it now?" (`#L121-L132`):
  - **Yes:** eject (clearing `dvd_path`), then try the recorded path. If that's gone, an error shows and **the snapshot isn't loaded**, with the drive now empty (`#L136-L148`).
  - **No:** load the snapshot with the disc that's in (`#L152-L155`).
  - **Cancel:** nothing.
- Nothing compares the disc's contents or title. The IDE device's saved state doesn't name its medium (`T/hw/ide/core.c#L3001-L3026`), and the docs agree: a load from the monitor "will not re-mount the game disc". `-loadvm` and the monitor's `loadvm` don't consult `disc_path` at all.

So:

- **Rename (ADR 0012), loose ROM.** The Game saves: unaffected. A Save state: not lost, but its recorded path is the old one for good, as there's no way to edit it short of rewriting it inside the VM state. Every load from xemu's menu of an older state then prompts, "No" is the right answer and "Yes" lands on the failure above. With `-dvd_path` (new path) and a monitor `loadvm`, there's no prompt. Whether a game running from the state then reads its disc happily should follow, as the bytes are the same: **unverified** by running.
- **The string is exact.** `~/Dropbox/games/Ludeum/ROMs/…` and `~/Library/Application Support/Ludeum/Data/ROMs/…` are different strings for the same file, as is another Mac's home folder. Anything that changes the path Ludeum passes triggers the prompt.
- **Another Game's disc.** "No" loads a Save state of Game A onto Game B's disc, and `-loadvm` would too. Nothing stops it. On a shared image Ludeum would have to pick by title or path itself.
- **A listing keyed by `disc_path`** would break at a Rename; one keyed by the title name wouldn't, but can't tell two ROMs of a title apart.
- **An image per Game or ROM** moves the question: an image named after a ROM would need moving by Rename, as ADR 0028's and 0035's saves do. One keyed by the journal wouldn't.
- **Archive and Unarchive.** xemu can't open a `.7z` (below), so an Archived ROM can't be Played, as now (`Play.swift`'s `.refused(.archived)`). Saves and states wait on the image. Unarchive restores the same file at the same path (`archiving: .singleFile`), so `disc_path` matches again.
- **Compact.** Not offered: Xbox has no `compactExtension` (`Sources/LudeumCore/Import/ROMPlatform.swift` ~143–145), and xemu opens no archive.
- **A different dump.** A new XISO of the same game, whatever its name: same title ID, so Game saves still found; states as for Rename. A redumped ISO whose files move on disc under a loaded state: **unverified**; a state's disc reads are from a guest file system that's assumed the same.

**Formats, re-verified at the tag and `master`.** `git grep` of `block/`, `hw/ide/`, `hw/xbox/`, `ui/`, `system/` finds no `chd`, `cci` or Redump format or the `0x18300000` offset. `ls block/` has no such driver. The UI's filter is `*.iso, *.xiso` (`T/ui/xui/actions.cc#L40-L43`). The FAQ still says no to Redump and CHD. PRs: #2809 (CHD), #2808 (CCI) open, last touched 2026-10-18 by a bulk update; #2915 (Redump), #2921 (CHD), #2934 (game library) closed unmerged 2026-07-16; #1659 (DVD security) open. So nothing has landed since 2026-10-12.

## 7. What else loses one

- **Loading an older Save state** loses every Game save and everything else written to that image since (§3). On a shared image this is the big one.
- **A Save state over one of the same name**: Replace, Create with a typed name, Shift+F5–F8, all delete the old first (`T/migration/savevm.c#L3235-L3240`). If the new save then fails, the old is gone. Bound keys go across Games on a shared image (#1566).
- **Replacing, restoring or converting the image.** A new `xbox_hdd.qcow2`, Dropbox's Rewind of an older one, or `qemu-img convert` (which drops internal snapshots unless asked, **unverified** here) takes everything. A Rewind can't choose one Game's save.
- **`hdd_path` changing** leaves them all behind, as the list is only ever the current image's. A raw image can't hold them.
- **Controllers.** A state whose USB devices can't be matched won't load until they are (§3). Changing input device repeatedly is reported to break old states (#2624). The state isn't gone, but it's unreachable without that set-up. `port1_driver` matters too: `usb-xbox-gamepad-s` (Controller S) is another device than the Duke default `usb-xbox-gamepad` (`T/ui/xemu-input.h#L35-L36`).
- **Memory limit.** `sys.mem_limit` changes the size of the RAM block, and a fixed block refuses a resize ("Size mismatch", `T/system/physmem.c#L2189`). From the source, not followed through the whole load and not tried.
- **Flash and MCPX.** A flash of another size changes the `xbox.bios` RAM block's length (`T/hw/xbox/xbox.c#L74-L80`, `#L112`), which from the source should fail the same way. One of the same size presumably loads, the state's RAM then overriding the BIOS's: **unverified**. Nothing compares them. PCSX2 warns; xemu doesn't.
- **`eeprom.bin`** lost or regenerated: §5.
- **`-snapshot`:** §3. **An XMU attached:** saving fails, quietly in the menu (#2284).
- **Crash during a save.** Refcounts are raised and stable before the table points to the new L1 (`T/block/qcow2-snapshot.c#L707-L733`), so a crash leaks clusters rather than breaking others, from the source. Those leaks are repaired only by `qemu-img check -r`. A metadata overlap sets the corrupt bit, and then "Image is corrupt; cannot be opened read/write" (`T/block/qcow2.c#L1546-L1552`), again needing `qemu-img`, which isn't in the bundle.
- **Unnamed-snapshot crash** in the menu is reported on old builds (#1543); `9ea91d8eba` touched that area in January 2026. Current status **unverified**.

## 8. The image and Dropbox

### How it's written

- **Clean image**: `xbox_hdd.qcow2`, qcow2 v3, 8 GiB virtual, 64 KiB clusters, 16-bit refcounts, 1,638,400 bytes, no lazy refcounts, zlib-compressed clusters for what it ships. From `xemu-dashboard` `v20260516-0955`, `sha256:00d7df7a…f6dd`. The download matched. Its contents are free of copyrighted material by the docs' account (`D/required-files.md`), and MIT by the repo's: this one required file Ludeum could fetch itself.
- **Grows, in place.** New clusters are appended at the end; L1, L2, refcount blocks and already-allocated data clusters are overwritten where they are. So a write can touch anywhere in the file.
- **What makes it grow** (from the source; none measured):
  - A Save state: VM state of up to about the guest's RAM, 64 MiB by default, plus device state and the thumbnail, plus 64 KiB per cluster written to afterwards while it holds the old copy. An L1 table too.
  - Game caches: X, Y and Z, 750 MiB each, per xboxdevwiki. Games write there at will, and xemu's troubleshooting docs treat them as real ("Some games are susceptible to cache problems", `D/troubleshooting.md`). Those clusters stay allocated, so a shared image heads towards about 2.2 GiB of cache regardless of the saves, and how much each game uses is **unverified**. How the kernel picks a cache partition is out of scope here.
  - Game saves: small on `E:`.
- **Doesn't shrink.** §4. `qemu-img convert` would compact it, and drop snapshots.

### Against Dropbox

- **Block sync.** Dropbox splits a file into 4 MB blocks and hashes each; on a commit, the server asks for those it lacks ([engineering post](https://dropbox.tech/infrastructure/streaming-file-synchronization)). So a change shouldn't re-upload the whole file; that's inferred from the design, as the post doesn't say it outright. It does mean rehashing a many-gigabyte file after a change, how often while it's open is **unverified**.
- **Open throughout a Play.** Every Emulator so far writes small files that settle. Here the file's mtime can keep moving for as long as a game runs. "A file is left open on another user's computer, which Dropbox saves as a new edit" is a named cause of conflicted copies ([help](https://help.dropbox.com/organize/conflicted-copy)).
- **Half-written uploads.** Dropbox could read the image mid-write, so what's uploaded during a Play needn't be consistent. The final version after xemu closes should be (`qemu_cleanup`, `T/ui/xemu.c#L1271`, not followed further), and it's that one which matters while one Mac writes at a time (ADR 0024). A second Mac opening a mid-Play version could see a torn image: **unverified**.
- **A conflict is total.** Two Macs both playing leaves one image and one conflicted copy, each with some Game saves and states and neither mergeable. With `.srm` files the same mistake costs one Game's.
- **Online-only.** Online-only files can be opened only "when connected to the internet" ([help](https://help.dropbox.com/sync/make-files-online-only)). `xemu_check_file` and QEMU open the image with plain file calls (`T/system/vl.c#L2527-L2535`), so an evicted image stalls as ADR 0024 describes for DuckStation, longer for its size. It would want marking available offline, as the other Emulators' folders are.
- **Version history** covers the image as a whole: a rollback is every Game's, per the point in §7.

### Options, not chosen

| Option | Save states | Game saves | Dropbox | Notes |
|---|---|---|---|---|
| **A. One shared image in the Data folder** | All Games', one table; loading rewinds all Games' saves; list needs filtering by title or path | All, one `E:`, as a console; a game reading another's saves works | One large, always-churning file | What xemu assumes. Simplest settings. Fact 2 is its cost |
| **B. One image per Game (or ROM) in the Data folder**, `hdd_path` written before each Play | That Game's only; rewinding touches only it; listing is the image's table | That Game's only, and `E:\UDATA\` needs no title ID to find them | Several smaller files; only what's played changes; a conflict is one Game's | Made by copying 1.6 MiB. Rename and two-Version Games need a naming answer (§6). Each has its own caches, so a first boot rebuilds them. Saves one title reads from another, Dashboard music and installed content aren't shared, **unverified** how much any of it matters. Dashboard update needs nothing |
| **C. Local image(s) in the Ludeum folder**, outside Dropbox, as A or B | As A or B | As A or B | None | Goes against "the Data folder must survive losing this Mac" (ADR 0010) unless backed up |
| **D. C plus a copy into the Data folder** after each Play, or a daily copy, like the journal's Backups | As A or B | As A or B | One settled upload per copy | ADR 0022's copying, which 0024 did away with. A copy after every Play may be 2 GiB+. No half-written version |
| **E. Per-Game qcow2 overlay on a shared base**, `backing_file` in the header | As B: internal snapshots belong to the overlay | As B | Small overlays, plus one base | Only saves the 1.6 MiB a copy costs. Creating one without `qemu-img` means Ludeum writing a qcow2 header. xemu's `bdrv_open` follows it, from the source. A moved base breaks every overlay |
| **F. Save states left to xemu**, on any of A–E: made and loaded in its menu, not shown in Ludeum | Unlisted | Listed or not | As A–E | As ADR 0035 leaves Amiberry's states unlisted |

## 9. Single instance

- **No guard in xemu.** `createsNewApplicationInstance = true` in Ludeum's launch would open a second one. No IPC to hand it a disc either, re-verified: no `DROP_FILE` handler in `ui/`.
- **On the same image the second fails.** QEMU takes byte-range locks on the image (`T/block/file-posix.c#L669-L692`, `auto` means `qemu_has_ofd_lock()`). The macOS SDK defines `F_OFD_SETLK` (`sys/fcntl.h` line 309), the release binary contains the probe's strings, and `fcntl(F_OFD_GETLK)` on `/dev/null`, the same probe as `T/util/osdep.c#L194-L230`, succeeds on this Mac. So the second xemu should exit at `-drive` with `Failed to get "write" lock / Is another process using the image`. From the source; not tried.
- **On different images (Option B) nothing stops it.** Both then rewrite the one settings file at exit (or their own), and share the shader cache. "Whichever closes last wins".
- **Detecting it** is as for the others: `NSRunningApplication.runningApplications(withBundleIdentifier: "xemu.app.0")`, `App/Sources/EmulatorVersionChecks.swift` line 310. Any copy has that ID. `Emulator.xemu` already has it (`Sources/LudeumCore/Emulators.swift` line 17).
- **Reasons to refuse** are the same as DuckStation's and ares's: settings rewritten at exit, the image in use. And `Rename` of a ROM wouldn't need refusing unless images are named after ROMs.
- **No quit when the game closes.** There's no `-batch`. A game returning goes to the dashboard. Closing the window or the guest powering down ends it. `-no-shutdown` is QEMU's and goes the other way.

## 10. Install

### Releases

- **Tagged releases**: 305 tags and 287 versioned releases back to v0.6.5 (2022-04-30). Nothing has aged off. Cadence has slowed: from April to December 2025 it ran at 5–20 a month; 2026 has 4 in January, then one each in February, May and June, then v0.8.137, v0.8.138 and v0.8.139 between 2026-10-16 and 2026-10-21.
- **`pre-release`** is a rolling tag, deleted and recreated (`T/.github/workflows/delete-prerelease.yml`), now `0.8.139-9-g6095054b7d`, with only `-unsigned` macOS zips: not pinnable.
- **Digest per asset** since at least 2025 (absent on v0.6.x). The API says `immutable: false` for v0.8.139, so an asset can be replaced; the pinned digest catches that.
- **The signed zip arrives after the release is built, from outside the public workflows.** CI builds only `-unsigned` zips, ad-hoc signed (`T/.github/workflows/build-macos.yml#L96-L135`), and no public workflow signs or notarises, so the Developer ID step is presumably done by hand. Upload times show the signed asset landing from under a minute (v0.8.139) to about an hour (v0.8.134) after the build, sometimes after the release is published (v0.8.137); on older tags it could be days (v0.8.130's `xemu-macos-universal-release.zip` has `updated_at` 11 days after publishing). A bump just after a release may find it not there yet.
- **Asset names**: `xemu-<ver>-macos-universal.zip` from v0.8.131, `xemu-macos-universal-release.zip` before. Candidates:

| Tag | Published | Signed zip | Bytes | SHA-256 |
|---|---|---|---|---|
| v0.8.139 | 2026-10-21 | `xemu-0.8.139-macos-universal.zip` | 21,479,533 | `9817aaa5e187a698416271a6ddc083a40d7ff5e09c3231cff32a692638c7427d` |
| v0.8.136 | 2026-06-08 | `xemu-0.8.136-macos-universal.zip` | 18,526,030 | `9b5f52240b12ff0d6ab3852b38a820dc92b99124db8a981ccf2ed2cb893f446e` |

  Both downloads matched. v0.8.136 is what Ludeum expects (`EmulatorVersionSpec(expected: "0.8.136", source: .appVersion)`, `Sources/LudeumCore/EmulatorVersions.swift`). Between them: 86 commits, the new DSP56300 APU core (JIT off by default), PTIMER and many nv2a fixes, SDL 3.4.18.

### The zip

- **Contents**: `LICENSE.txt` and `xemu.app`, 54 MB unpacked. `Contents/MacOS/xemu` (universal x86_64 and arm64), `Contents/Libraries/{arm64,x86_64}/` with SDL3, epoxy, glib, slirp, pcap, libusb, samplerate and the rest (`otool -L` shows `@executable_path/../Libraries/…` only, beyond the system's), `Resources/xemu.icns`, `Info.plist`. It needs nothing from Homebrew.
- **Signed and notarised**: `Developer ID Application: Matthew Borgerson (YB6695UN77)`, hardened runtime, ticket stapled (`stapler validate` passes, `spctl` says "Notarized Developer ID"). Entitlements: JIT, unsigned executable memory. No sandbox. So no quarantine trick is needed, as long as the bundle isn't written into (§1).
- **`Info.plist`**: `CFBundleIdentifier` `xemu.app.0`, `CFBundleShortVersionString` and `CFBundleVersion` `0.8.139`, `LSMinimumSystemVersion` 10.6 (which is wrong in practice, and harmless). Set from `XEMU_VERSION` cut at the first `-` (`T/build.sh#L69-L76`), so dev builds read as the tag they follow. A pre-release can't be told from it, which matters only if one's ever installed.
- **Confirming the build**: ares's lesson applies. `-version` prints QEMU's version, not xemu's (`T/system/vl.c#L896-L900`, `#L3374-L3377`), and by then `main` has loaded settings, registered `atexit(xemu_settings_save)` and made the SDL window (`T/ui/xemu.c#L1384-L1401`). So it rewrites the settings and flashes a window, from the source. The app's version, as `EmulatorVersions` reads now (`.appVersion`), needs no process. `exact: true` is the existing switch.
- **Homebrew**: the cask is at 0.8.139 with the same digest, and now targets `/Applications/xemu.app`. Not needed.

## 11. Required files and first run

(`D/required-files.md`, `T/system/vl.c#L2982-L3074`)

- **MCPX boot ROM**: 512 bytes or an error and it's ignored (`#L2994-L3001`); empty path, no error. Its good MD5 is in the docs: `d49c52a4102f6df7bcf8d0617ac475ed`, starting `33 C0`, ending `02 EE`. Without it the FAQ's "The guest has not initialized the display" is the likely result.
- **Flash BIOS**: file must open or there's an error and the machine stays stopped (`#L3046-L3050`); a size that's a positive multiple of 64 KiB (`T/hw/xbox/xbox.c#L77-L80`), else filled with `0xFF` (`#L100-L102`). A retail one can't boot games: "You must use either a debug BIOS or a modded retail BIOS"; "COMPLEX 4627" is the one named.
- **HDD**: a file that won't open is an error and no drive, the machine still running (`#L3062-L3065`); an empty path, no error, no drive. Snapshots then have nowhere to go.
- **EEPROM**: generated, as §1. 256 bytes exactly, else an error and no autostart.
- **`show_welcome`** true stops the machine and suppresses the flash error, to let the user set paths (`#L3042-L3045`). A file written by Ludeum with `show_welcome = false` skips that. Nothing else in first run needs a person, except a controller: bound automatically on connect (§2).
- **So Ludeum can refuse Play with a message**, as ADR 0032 does for PS2's BIOS (`Play.swift`'s `.noBIOS`): it can check MCPX size (or MD5), flash size, and the image. It can't supply the first two. It could fetch the third, at a pinned tag and digest, as Install does.
- **A retail flash with xemu-dashboard** gives a "properly signed dashboard" error (`D/dashboard.md`).

## 12. This Mac

- **`/Applications/xemu.app`** (also reached as `Xemu.app`, one folder on a case-insensitive disk): v0.8.136, dated 2026-06-08, `Contents/MacOS/xemu` SHA-256 `28887fa5…7df1b` and CDHash `28bbf63d…cafc`, both the same as the v0.8.136 release's, seal valid, `spctl` accepted. `com.apple.quarantine` still set from Chrome (`03c1;…;Chrome`).
- **`~/Library/Application Support/xemu/xemu/`**, dated 2026-10-14, the day [xbox-emulator.md](xbox-emulator.md) was researched: `eeprom.bin` (256 bytes, 13:36), `shader_cache_list` (496 bytes, 13:38), an empty `shaders/`, `xemu.toml` (585 bytes, 13:38).
- **`xemu.toml`** says: `show_welcome = false`, `last_viewed_menu_index = 6`, one gamepad (`0300bb97…`) mapped and bound to port 1 as `usb-xbox-gamepad`, and:

| Key | Path | There? |
|---|---|---|
| `bootrom_path` | `~/Downloads/XEMU_FILES/Boot ROM image/mcpx_1.0.bin` | **No** |
| `flashrom_path` | `~/Downloads/XEMU_FILES/BIOS/Complex_4627v1.03.bin` | **No** |
| `hdd_path` | `~/Downloads/XEMU_FILES/Pre-built Xbox HDD image/xbox_hdd.qcow2` | **No** |
| `eeprom_path` | `~/Library/Application Support/xemu/xemu/eeprom.bin` | Yes |

- **`~/Downloads/XEMU_FILES/` is gone.** `mdfind -name` for `xbox_hdd`, `mcpx`, `Complex_4627` found nothing; a bounded `find` of `~` (depth 4, not `Library`), `~/Dropbox/games`, `~/Downloads`, `~/Desktop` and `~/Documents` for `*.qcow2`, `*mcpx*`, `Complex_4627*` and `XEMU*` found none. `~/.Trash` can't be read by this session (`Operation not permitted`), so it may hold them. So whatever Game saves or Save states the 2026-10-14 session made went with that image, unless it's there.
- **The ROM folder**, `~/Dropbox/games/Ludeum/ROMs/Xbox` (8.2 GB): two ROMs, both Archived `.7z`, both with blocks on disk (`stat`):
  - `Brothers in Arms - Road to Hill 30 (World) (En,Fr,De,Es,It).7z`, 5,542,830,941 bytes.
  - `Dino Crisis 3 (Europe) (En,Fr,De,Es,It).7z`, 3,305,485,902 bytes. The earlier note found its loose form an XISO under a Redump name. Whether each archive's inside is an XISO or Redump image wasn't read here.
- **The Data folder's `Emulators/`** has `Amiberry/`, `DuckStation/`, `MesenCE/`, `PCSX2/` and `ares/`: nothing for xemu. **The Ludeum folder's `Emulators/`** has `Amiberry.app`, `DuckStation.app`, `MesenCE.app`, `PCSX2/`, `ares/`: nothing for xemu either.
- **No `qemu-img`** but the Android SDK's. No Homebrew `qemu`, no cask of xemu.

## 13. Renderer and latency

Little changed since [xbox-emulator.md](xbox-emulator.md).

- **Still OpenGL on macOS.** Vulkan is built only for Windows and Linux (`T/meson.build#L2387-L2394`), identical at `master`. `display.renderer` defaults to `OPENGL` (`T/config_spec.yml#L226-L230`). PR #2799, "macOS/MoltenVK: Vulkan renderer support for ARM Macs", is open.
- **VSync is still the only latency knob** (`T/ui/xemu.c#L1148`). No run-ahead. #746 is open.
- **New to note:** #2506, "[REGRESSION] macOS low in game FPS/pacing after 0.8.108", is open, last active 2026-10-26, with a maintainer declining a menu toggle that would revert the depth precision change. It's on macOS specifically and predates every candidate tag.

## 14. Mapping ADRs 0024, 0027, 0028 and 0032 onto xemu

| ADR 0024 / 0027 / 0028 / 0032 | xemu | Notes |
|---|---|---|
| Pinned versioned tag and SHA-256 in code | **Same** | §10. Signed zip is uploaded by hand shortly after the release. |
| Unpack without quarantine | **Not needed** | Notarised and stapled, if unwritten. |
| Confirm the build | **App version, as ares** | No launch: every launch rewrites settings (§10). |
| Portable: a marker in `Contents/MacOS` (0024, 0027) or beside the app (0028, 0032) | **Inside `Contents/Resources` only, or `-config_path`** | Portable breaks the notarised seal, tested. `-config_path` keeps it, leaves only the shader cache in the shared folder, and doesn't apply to a double-click (§1). |
| Standing settings written before every Play and after Install | **Same, into TOML** | Paths, `show_welcome = false`, `screenshot_dir`; Ludeum needs a TOML reader or a careful line edit, to keep controller mappings xemu wrote (§2). |
| Only while the Emulator isn't running | **Same** | Rewritten whole at exit (§2). |
| Self-update off | **Not applicable** | No updater on macOS (§2). |
| Save states and Game saves in `Data/Emulators/<Emulator>/` | **One key, `hdd_path`, for both** | Moving the image moves both, as the issue says, and is the design question (§8). Keep `eeprom_path` with it (§5). |
| A folder per Platform (0027) | **Not applicable** | One Platform. Per-Game images are the analogue. |
| Refuse Play while any copy runs | **Same** | `xemu.app.0`. A second on one image fails anyway (§9). |
| Refuse Play without BIOS (0032) | **Same, wider** | MCPX and flash, plus the image if Ludeum doesn't supply it (§11). |
| Game detail lists Save states | **By reading qcow2** | Name, date, title, thumbnail from the file, xemu closed; filter by title or disc path, or per-Game images (§4). |
| Play from a Save state | **Not cleanly** | `-loadvm` dies on a state taken with a controller bound (#1717). Monitor `loadvm` after startup is the route, a race; else xemu's own menu (§3). |
| Delete a Save state | **Not without `qemu-img` or a running xemu** | §4. |
| Resume state (0034) | **None** | Not saved on close (§3). |
| Game detail shows Game saves | **By reading FATX, or a choice** | `E:\UDATA\<title ID>`, xemu closed; a title ID off the ROM, or an image per Game. A Game's share of a shared `E:` is no file (§5). |
| Rename moves the saves (0027, 0028, 0035) | **Nothing to move for a shared image** | A state's stale path prompts in xemu's menu; "No" works (§6). Per-Game images named by ROM would move. |
| Saves keyed by Serial (0024, 0032) | **Title ID, if at all** | Needs reading `default.xbe`; whether it's a Serial is open (§5). |
| A bump costs Save states (0028, 0032) | **Probably not** | Device version rules, compatible by design between v0.8.136 and v0.8.139 (§3). |
| Writes atomic, or one Mac at a time | **One Mac at a time, more strictly** | Settings written in place, the image always in place. A conflict is all of it (§8). |
| Folders marked available offline in Dropbox | **Same need, larger** | §8. |
| Licence | **GPL-2.0** | A configured copy is fine. |
| Move over by hand once | **Nothing to move, today** | §12. |
| Architecture | **Universal** | Native arm64; TCG for the CPU. |

## Open questions for the design session

1. **Where does the hard disk image live, given Dropbox?** Data folder (one multi-GB file written in place through a Play), Ludeum folder (not surviving this Mac), or Ludeum folder with copies into the Data folder after a Play (ADR 0022's copying)? §8's options A, C and D.
2. **One shared image, or one per Game (or per ROM)?** The shared one is a console; one per Game gives other Emulators' behaviour, with loading a Save state touching only that Game's saves, smaller files and a smaller conflict, at the cost of whatever crosses titles. If per Game: named by what, so Rename and a Game's second Version do the right thing? Is a Game the unit, or a ROM?
3. **Are Save states listed at all, and how?** Ludeum reading qcow2 (a new read-only reader, xemu closed), `qemu-img` as a dependency, or left to xemu's menu as ADR 0035 leaves Amiberry's? Is a real snapshot needed first, to test §4's steps 2–4? It would take one Play by hand.
4. **Are Game saves shown, and how?** A FATX reader on top, keyed by a title ID read off `default.xbe` (from a `.7z`, by streaming how far?) or, with an image per Game, simply whatever's in its `UDATA`? Is a title ID a Serial, in the glossary's sense?
5. **Play from a Save state: the monitor race, nothing, or wait for #1717?** Does a `-monitor unix:…` launch with a retry work? It needs a spike, as ADR 0027 ran 22 launches for MesenCE. And a Resume state: no, unless Ludeum closes xemu itself?
6. **Delete from Game detail?** Only with `qemu-img` or a running xemu. Or left to xemu's menu?
7. **Portable route.** `-config_path` beside the app, sealed, with the shader cache left in Application Support and a double-clicked copy not isolated; or `Contents/Resources`, self-contained, seal broken, and only verified by running that macOS will open it? Is `perf.cache_shaders` left on?
8. **Which tag to pin?** v0.8.139, or stay at the v0.8.136 Ludeum expects? §10's changes and the digest for each are above; the v0.8.136 copy here is the one that has run on this Mac. #2506 applies to both.
9. **What happens to the existing data on this Mac?** `eeprom.bin` is the one thing of value left if any Game save returns; is `XEMU_FILES` in the Trash? Where do the MCPX and BIOS come from again, and where do they go (`Data/Emulators/xemu/BIOS`)? Who deletes `/Applications/xemu.app` and the old folder? Copying the controller's mapping from the old `xemu.toml` into the first one Ludeum writes, as ADR 0028 kept ares's controls?
10. **Does Ludeum supply the clean image?** It's MIT, 1.6 MiB and pinned by digest, so Install or a first Play could fetch it. A per-Game image would need it for each new Game.
11. **Back up, restore and delete a Game save (#77).** DuckStation, MesenCE, ares and PCSX2 went without, relying on Dropbox's history. Here that history is of a whole image, so a single Game's rollback doesn't exist on a shared image. Does that change the answer, or does an image per Game restore it? Does Ludeum say anything about loading an older state rewinding the saves?
12. **Which Standing settings beyond the paths?** `show_welcome = false`, `screenshot_dir`, `skip_boot_anim`, `filter_current_game`, `games_dir`, the F5–F8 bindings (four named slots per Game?), clearing `dvd_path`, `-full-screen` or `fullscreen_on_startup`.
13. **An Archived ROM's Save states:** are they listed while it can't be Played? They exist regardless, on the image.

### Side findings (outside #89)

- **`general.updates.check` does nothing on macOS**; xemu has no self-updater there, so there's no bundle replacement to guard against (§2).
- **Older notes.** [xbox-emulator.md](xbox-emulator.md)'s line numbers are of an older commit, and its statement that the cask installs `/Applications/Xemu.app` is now `xemu.app`. Its plan of a copy of the user's `xemu.toml`, per launch, is this note's `-config_path` route with a different owner. [managing-emulators-inside-ludeum.md](managing-emulators-inside-ludeum.md)'s "signing of the other **unverified**" is now verified: signed, notarised and stapled.
- **The issue's claims**: the image holds every Game's saves (holds, by default; XMUs aside); snapshots are inside it (holds); `-config_path` moves only the config (holds, the shader cache stays in the base path). "Moving the image moves both" holds, with `eeprom.bin` to take along and a disc path inside each snapshot that doesn't update.
- **Ludeum's `Emulators.swift` comment**, "The disc isn't saved into its settings", is true of `-dvd_path` but not of a disc loaded in xemu's menu or by the snapshot prompt's "Yes", which is saved and then boots on a launch without `-dvd_path` (§2).
- **xemu's dashboard menu has a Clear Cache**, and xemu's docs suggest it for "Dirty Disc" faults (`D/troubleshooting.md`). It's a way to shrink what a snapshot-free image holds, though not the file.
- **FATX tools exist**: `fatxfs`, a FUSE reader for Linux and macOS, per xboxdevwiki. Not looked at.
