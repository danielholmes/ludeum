# Building and signing a personal-use macOS SwiftUI app around a SwiftPM package

Research for [#3](https://github.com/danielholmes/games-journal/issues/3). It feeds the grilling ticket "App skeleton: project shape and where work runs" ([#13](https://github.com/danielholmes/games-journal/issues/13)). This is a comparison, not a decision.

Researched 2026-09-26, on macOS 26.5 with Xcode 26.6 (the version CI pins). Claims are cited to Apple documentation, Apple DTS forum posts (Quinn "The Eskimo!"), and the XcodeGen, Tuist and GitHub runner-image repos. Items marked **(spike)** were checked on this Mac with a throwaway build. Items marked **(inferred)** or **(unverified)** were not.

## Short answer

- **All four project shapes can produce a signed `.app` that runs on this Mac for free.** A locally built app isn't quarantined, so Gatekeeper never checks it and notarisation doesn't matter. SwiftPM alone can't make an app bundle, but a short script can wrap its executable into one **(spike)**.
- **The signing identity matters more than the project shape.** Without a stable identity (ad-hoc signing), macOS treats every rebuild as a new app. Permission prompts, such as the Dropbox one below, and keychain "Always Allow" choices don't carry over. A free Personal Team "Apple Development" identity fixes this, but only Xcode (a checked-in, XcodeGen or Tuist project) manages it automatically.
- **Keychain:** the modern data protection keychain needs a provisioning profile. A free Personal Team profile expires after 7 days; a paid account's doesn't. The legacy file-based keychain needs no entitlements and works with any signing.
- **New finding: on this Mac, all of OpenEmu's data is inside Dropbox.** `~/Library/Application Support/OpenEmu` is a symlink into `~/Library/CloudStorage/Dropbox`, and OpenEmu's `databasePath` points to `~/Dropbox/games/OpenEmu/Game Library`. Any app that reads it, sandboxed or not, gets a macOS prompt: "wants to access files managed by Dropbox" **(spike)**.
- **App Sandbox is optional** (it's required only for the Mac App Store). If used, OpenEmu and Dropbox access means a user-selected folder with a security-scoped bookmark, or temporary-exception entitlements.
- **CI:** every shape builds on the `macos-26` runner. The Xcode-based shapes can't pass `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` on the `xcodebuild` command line. That fails on GRDB **(spike)**, so the setting goes on the app target instead.

## Facts about this Mac that shape the answer

| Path | What it is |
|---|---|
| `~/Library/Application Support/OpenEmu` | symlink → `~/Dropbox/games/OpenEmu/Application Support` |
| `~/Dropbox` | symlink → `~/Library/CloudStorage/Dropbox` (Dropbox on Apple's File Provider) |
| OpenEmu `databasePath` default | `~/Dropbox/games/OpenEmu/Game Library` (holds `Library.storedata`, `-wal`, `-shm`, `Artwork/`, `roms/`) |

The `prototype/first-import` branch already reads `databasePath` from OpenEmu's defaults (`UserDefaults(suiteName: "org.openemu.OpenEmu")`). It falls back to `~/Library/Application Support/OpenEmu/Game Library`.

Dropbox on File Provider keeps its folder under `~/Library/CloudStorage` ([Dropbox Help](https://help.dropbox.com/installs/dropbox-for-macos-support); File Provider domain roots are `~/Library/CloudStorage/<domain>`, per [Apple forums](https://developer.apple.com/forums/thread/719294)).

**(spike)** An ad-hoc-signed, unsandboxed SwiftUI app that listed either OpenEmu path blocked inside TCC. macOS showed: **"“SpikePlain.app” wants to access files managed by “Dropbox”."** [Don't Allow / Allow]. So the journal app will need this permission once per code identity, both for Import/Sync and for backups to Dropbox. The Terminal-run `journal-import` CLI never hit this, because it runs under Terminal's permissions.

## Signing modes (independent of project shape)

| Mode | Cost / account | Code identity (designated requirement) | Restricted entitlements (e.g. `keychain-access-groups`) | Runs a local build? | Survives Gatekeeper if downloaded? |
|---|---|---|---|---|---|
| **Ad-hoc** (`codesign -s -`, Xcode "Sign to Run Locally") | none | tied to one build's cdhash, changes every rebuild | no (no profile) | yes | no |
| **Self-signed certificate** (Keychain Access › Certificate Assistant) | none | stable across rebuilds **(inferred)** | no (no profile) | yes | no |
| **Personal Team** (free Apple Account in Xcode) | free | stable: bundle ID + "Apple Development: …" certificate | yes, via a profile that **expires after 7 days** | yes | no (no notarisation) |
| **Developer Program** | paid | stable | yes, long-lived profiles | yes | yes, with Developer ID + notarisation |

Sources and details:

- **Apple silicon needs a signature, but ad-hoc is enough.** "the operating system enforces that any executable must be signed before it's allowed to run. There isn't a specific identity requirement for this signature: a simple ad-hoc signature is sufficient." The linker ad-hoc signs automatically. However, "binaries signed this way cannot pass through Gatekeeper" ([macOS Big Sur 11.0.1 Universal Apps release notes](https://developer.apple.com/documentation/macos-release-notes/macos-big-sur-11_0_1-universal-apps-release-notes)).
- **Gatekeeper checks quarantined apps.** "If you launch a quarantined app, the system invokes Gatekeeper." Quarantine is set by user-level apps on downloads (e.g. Safari). "Unix-y networking tools, like `curl` and `scp`, don't quarantine the files they download" ([Quinn, *Resolving Trusted Execution Problems*](https://developer.apple.com/forums/thread/706442)).
  - **(spike)** `spctl --assess` rejects the ad-hoc app, yet it launches fine from a local build.
  - Since macOS Sequoia, Control-click no longer overrides Gatekeeper. Users must go to System Settings › Privacy & Security ([Apple Developer News, 2024-08-06](https://developer.apple.com/news/?id=saqachfa)). This matters only if a CI-built app is downloaded through a browser.
- **Ad-hoc identity changes every build.** "Ad hoc signed code, called Sign to Run Locally by Xcode, has a DR but it's tied to that specific version of the code … If you tweak the code and run it again, macOS repeats that prompt" ([TN3127](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)). **(spike)** The ad-hoc app's DR was `cdhash H"…"`.
- **Apple Development identity is stable.** Its DR is `identifier "<bundle id>" and anchor apple generic and certificate leaf[subject.CN] = "Apple Development: …" …` ([TN3127](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)). It survives rebuilds, so TCC and keychain approvals persist.
- **Personal Team limits.** "You can register up to 10 App IDs, which expire after 7 days" and "3 devices, which expire after 7 days". Also, "you'll be required to reprovision your apps to a device periodically" ([Apple, Developer account overview](https://developer.apple.com/support/compare-memberships/)). Notarisation and Certificates, Identifiers & Profiles are Developer Program only (same page).
  - Apple Development certificates for a Personal Team are renewed by Xcode automatically ([Quinn](https://developer.apple.com/forums/thread/737307)).
  - Keychain sharing, App Sandbox, App Groups and Hardened Runtime are all listed as available to a free "Apple Developer" account ([Supported capabilities (macOS)](https://developer.apple.com/help/account/reference/supported-capabilities-macos)).
  - Quinn confirmed a Personal Team can build and run a Mac app "even if it uses a restricted entitlement" ([forum 787500](https://developer.apple.com/forums/thread/787500)).
- **Profiles on macOS.** "macOS doesn't require a provisioning profile to run third-party code." App Sandbox, hardened runtime, App Groups and `get-task-allow` entitlements are unrestricted. "A Mac app that uses no restricted entitlements doesn't need a provisioning profile." The profile lives at `MyApp.app/Contents/embedded.provisionprofile` ([TN3125](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles)).
  - An expired profile or certificate must be updated and the product re-signed. The most common launch failure is "the app claiming a restricted entitlement that's not authorised by a provisioning profile" ([Quinn, *Resolving Code Signing Crashes on Launch*](https://developer.apple.com/forums/thread/706427)).
  - **(inferred, unverified)** A Personal Team app that claims `keychain-access-groups` will stop launching about 7 days after it was signed, until it's rebuilt from Xcode. An app with no restricted entitlements shouldn't be affected. There's no Personal Team identity on this Mac to test either case.
- **Developer ID keeps working after expiry.** Developer ID-signed code carries a secure timestamp, "Thus, an old Developer ID-signed app will continue to run after it's certificate has expired" ([Quinn, 706427](https://developer.apple.com/forums/thread/706427)).
- **Self-signed:** Keychain Access can create self-signed certificates ([Apple Support](https://support.apple.com/guide/keychain-access/create-self-signed-certificates-kyca8916/mac)). Apple DTS generally steers people to Apple-issued identities. That its DR stays stable across rebuilds is **inferred, unverified**.

## Keychain without entitlements

- macOS has two keychain implementations: file-based and data protection. The SecItem API "defaults to targeting the file-based keychain". Setting `kSecUseDataProtectionKeychain` targets the other one. The file-based keychain "is on the road to deprecation. It's not officially deprecated" ([TN3137](https://developer.apple.com/documentation/technotes/tn3137-on-mac-keychains)).
- **Data protection keychain:** "macOS builds the list of data protection keychain access groups available to your program from its code signing entitlements … These entitlements must be authorized by a provisioning profile" ([TN3137](https://developer.apple.com/documentation/technotes/tn3137-on-mac-keychains)). The default access group is the app ID ([Sharing access to keychain items](https://developer.apple.com/documentation/security/sharing-access-to-keychain-items-among-a-collection-of-apps)). **(spike)** An ad-hoc app, sandboxed or not, gets `SecItemAdd` = `-34018` (`errSecMissingEntitlement`) with `kSecUseDataProtectionKeychain`. This needs Personal Team (7-day profile) or paid signing.
- **File-based keychain:** each item has an ACL of trusted apps. An untrusted caller gets a prompt: "Deny, Allow, or Always Allow … In the latter case, the system adds the app to the list of trusted apps" ([Access Control Lists](https://developer.apple.com/documentation/security/access-control-lists)). No entitlements are needed. Trust is tied to code identity, so **(inferred)** ad-hoc builds lose it on every rebuild. A stable identity (Personal Team, or self-signed) keeps it.

## App Sandbox vs OpenEmu and Dropbox

- **Sandbox is optional.** "To distribute a macOS app through the Mac App Store, you must enable the App Sandbox capability" ([App Sandbox](https://developer.apple.com/documentation/security/app-sandbox)). Nothing requires it for personal use. The sandbox entitlements are unrestricted ([TN3125](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles)). **(spike)** An ad-hoc-signed app with `com.apple.security.app-sandbox` and hardened runtime launches and gets its container at `~/Library/Containers/<bundle id>/Data`.
- **Sandboxed file access** ([Accessing files from the macOS App Sandbox](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox)):
  - **User-selected folder.** Pick the Game Library folder once in an open panel. "the operating system extends your app's sandbox to items within that folder, and recursively in nested folders". Persist it with a security-scoped bookmark (`bookmarkData(options: .withSecurityScope)`, then `startAccessingSecurityScopedResource()`). Picking the folder rather than `Library.storedata` covers SQLite's `-wal`/`-shm` siblings and `Artwork/`. The same works for the Dropbox backup folder.
  - **Temporary exceptions.** `com.apple.security.temporary-exception.files.home-relative-path.read-write` (and `absolute-path`) grant fixed paths without a panel. `com.apple.security.temporary-exception.shared-preference.read-only` is needed to read OpenEmu's `databasePath` from its preferences domain ([App Sandbox Temporary Exception Entitlements](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/AppSandboxTemporaryExceptionEntitlements.html)). They exist for App Store review exceptions, but nothing stops a personal app using them. **(unverified)** Because the OpenEmu paths are symlinks into `~/Library/CloudStorage/Dropbox`, an exception probably has to name the resolved path.
  - **Full Disk Access** can't be obtained by entitlement. The user grants it in System Settings (same Apple page).
- **Not sandboxed:** plain POSIX access to both locations. The Dropbox (File Provider) prompt still appears, per code identity **(spike)**.
- **Either way:** the Dropbox prompt is per code identity. With ad-hoc signing, expect it again after every rebuild **(inferred from TN3127)**.
- OpenEmu itself isn't sandboxed (its data isn't in `~/Library/Containers`). So macOS 14's "access data from other apps" container prompt doesn't apply here.

## The four project shapes

### A. Checked-in Xcode project + local package

- **Build and run:** an app target in a `.xcodeproj` (e.g. in `App/`), with the repo's package added as a local package and `JournalCore` linked. This is Apple's documented pattern ([Organizing your code with local packages](https://developer.apple.com/documentation/xcode/organizing-your-code-with-local-packages)). **(unverified)** A project nested under the package root, referencing `..`, wasn't built in this research.
- **Signing:** Xcode does it all: Sign to Run Locally, Personal Team automatic provisioning (the only practical way to get and refresh the 7-day profile), or paid. Build with Run, or Archive and copy to `/Applications`.
- **Keychain and sandbox:** capabilities, entitlements and Info.plist are edited in Xcode and stored in the project. Xcode can generate the Info.plist (`GENERATE_INFOPLIST_FILE`). Asset catalogs (app icon, accent colour) are compiled normally.
- **CI:** `xcodebuild -project … -scheme … build` with signing off or ad-hoc (`CODE_SIGN_IDENTITY=-`). Set `SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` on the app target, not on the command line. **(spike)** `xcodebuild … SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` fails with `error: Conflicting options '-warnings-as-errors' and '-suppress-warnings' (in target 'GRDB' …)`, because command-line settings reach remote package targets that Xcode compiles with `-suppress-warnings`. Keep today's `swift build -Xswiftc -warnings-as-errors` job for the package. Xcode 26.6 is on the runner ([macos-26-arm64 image](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md)).
- **Fit:** the package and `journal-import` stay unchanged, and `swift build`/`swift test` keep working. The cost is a hand-edited `project.pbxproj` in git: noisy diffs and occasional merge conflicts, though few for a one-person repo.

### B. SwiftPM only (+ a bundling script)

- **Build and run:** SwiftPM products are only library, executable and plugin ([PackageDescription `Product`](https://developer.apple.com/documentation/packagedescription/product)); there's no app product. **(spike)** An `executableTarget` with a SwiftUI `@main App` builds with `swift build -Xswiftc -warnings-as-errors`. A ~20-line script makes the `.app`:
  1. Copy the binary to `X.app/Contents/MacOS/`.
  2. Write `Contents/Info.plist` (`CFBundleExecutable`, `CFBundleIdentifier`, `CFBundlePackageType=APPL`, …).
  3. Run `codesign --force --sign - --options runtime [--entitlements …]`.

  The result launches via `open`, with a correct bundle ID, sandboxed or not. **(spike)** `swift build` doesn't compile asset catalogs ("found 1 file(s) which are unhandled"). An app icon needs `iconutil`/`actool` by hand, or none.
- **Signing:** ad-hoc or a self-signed/Apple Development certificate via `codesign`. There's no automatic Personal Team provisioning. You'd have to fetch a profile through Xcode anyway, so in practice there's no data protection keychain and no stable identity unless you sign with a real certificate.
- **Keychain and sandbox:** file-based keychain only (in practice). Entitlements are a plist passed to `codesign`.
- **CI:** closest to today. It's the same `swift build` plus the script, with no new tools.
- **Fit:** best. One manifest with `JournalCore`, `journal-import` and the app target side by side. The costs: you own the bundle layout, Info.plist, icon and signing, and running from Xcode runs the bare executable, not the bundle. Third-party bundlers exist (e.g. swift-bundler) but weren't evaluated.

### C. XcodeGen (generated project)

- **What it is:** "generates your Xcode project using your folder structure and a project spec". You check in a YAML `project.yml`, and the `.xcodeproj` can be gitignored ("no more merge conflicts") ([README](https://github.com/yonaskolb/XcodeGen)). It's active: 2.46.0 was released 2026-07-16.
- **Build and run:** local packages via `packages: { GamesJournal: { path: . } }` and `dependencies: - package: GamesJournal, product: JournalCore`. `entitlements:` and `info:` can generate those plists. Signing uses `DEVELOPMENT_TEAM`, `CODE_SIGN_IDENTITY` and `CODE_SIGN_ENTITLEMENTS` settings ([ProjectSpec](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md)).
- **Signing, keychain and sandbox:** once generated, it's an ordinary Xcode project, the same as A (Personal Team, Sign to Run Locally, capabilities). The team ID goes in the spec or a local override.
- **CI:** not on the runner image. Add `brew install xcodegen` (or Mint, or build from source) and pin a version, then `xcodegen generate && xcodebuild …`. The warnings-as-errors caveat is the same as A.
- **Fit:** the package and CLI are untouched. You add a YAML spec and one tool, and you re-run `xcodegen` when files are added.

### D. Tuist (generated project)

- **What it is:** Swift manifests (`Project.swift`) generate the Xcode project. It's installed with mise (recommended, pins a version per project) or Homebrew ([Install Tuist](https://github.com/tuist/tuist/blob/main/server/priv/docs/en/guides/install-tuist.md)). It's very active (CLI 4.211 canaries daily). Its docs position the tool around teams, "medium and large projects", and its cache/insights service.
- **Build and run:** packages via Xcode's default integration (`Project(packages: [...])` + `.package(product:)`), or Tuist's XcodeProj-based integration through `Tuist/Package.swift` ([Dependencies](https://github.com/tuist/tuist/blob/main/server/priv/docs/en/guides/features/projects/dependencies.md)).
- **Signing, keychain and sandbox:** same as A once generated.
- **CI:** not on the runner image. Install via mise/Homebrew, then `tuist generate` and `xcodebuild` (or `tuist build`). The warnings caveat is the same as A.
- **Fit:** works, but it's the heaviest option: a second manifest language layer, its own dependency model, and a fast-moving tool for a one-person app.

## Comparison

| | A. Checked-in Xcode project | B. SwiftPM only + script | C. XcodeGen | D. Tuist |
|---|---|---|---|---|
| Produces a signed `.app` | yes (Xcode) | yes, via a script **(spike)** | yes (Xcode) | yes (Xcode) |
| Ad-hoc / Sign to Run Locally | yes | yes **(spike)** | yes | yes |
| Personal Team automatic provisioning (stable identity, 7-day profile) | yes | no (manual `codesign` with a certificate; no profile management) | yes | yes |
| Paid Developer ID + notarisation | yes (Archive) | manual (`codesign` + `notarytool`) | yes | yes |
| Data protection keychain | with Personal Team (weekly re-sign) or paid | effectively no | as A | as A |
| File-based keychain (no entitlements) | yes | yes | yes | yes |
| App Sandbox + bookmarks/exceptions | yes (capabilities UI) | yes (entitlements plist) **(spike)** | yes (spec) | yes (manifest) |
| Asset catalogs / app icon | yes | no, manual **(spike)** | yes | yes |
| Extra tools on CI | none (Xcode on runner) | none | XcodeGen (not preinstalled) | Tuist via mise/brew (not preinstalled) |
| Warnings as errors on CI | app target setting; keep `swift build` job | unchanged `swift build -Xswiftc -warnings-as-errors` | as A | as A |
| Fit with `Package.swift` + `journal-import` | package untouched; separate project | one manifest for everything | package untouched; YAML spec | package untouched; Swift manifests |
| Checked-in artefact | `project.pbxproj` (noisy diffs) | `Package.swift` + script + Info.plist | `project.yml` | `Project.swift` (+ `Tuist/`) |
| Main cost | pbxproj churn | own the bundle, icon and signing; weaker Xcode run/debug | one more tool | heaviest tooling |

The trade-offs that cut across shapes:

| Question for the grilling | Options |
|---|---|
| Signing identity | ad-hoc (Dropbox and keychain prompts after every rebuild), self-signed (stable, free, manual), Personal Team (stable, free, 7-day profile if restricted entitlements), paid |
| Credentials store | file-based keychain (any signing), data protection keychain (profile), or a plain file in `~/Library/Application Support/GamesJournal/` |
| Sandbox | off (simplest: POSIX access plus one Dropbox prompt) or on (folder picker + security-scoped bookmarks, or temporary exceptions) |
| OpenEmu location | read `databasePath` from OpenEmu's defaults (needs a shared-preference exception if sandboxed) or have the user pick the folder |

## Spike notes

The throwaway code was in the session scratchpad, not the repo. It was a SwiftPM `executableTarget` with a SwiftUI `@main App` that wrote probe results to a file and quit. `bundle.sh` wrapped it into `.app`, wrote Info.plist and ran `codesign -s - --options runtime [--entitlements]`. Results:

- `codesign -v --strict`: valid; DR `cdhash H"…"`. `spctl --assess`: rejected. `open` launches it anyway (not quarantined).
- Unsandboxed: `SecItemAdd` with `kSecUseDataProtectionKeychain` → `-34018`.
- Sandboxed (`com.apple.security.app-sandbox`): launches; `NSHomeDirectory()` is the container; data protection keychain → `-34018`.
- Listing `~/Library/Application Support/OpenEmu` or `~/Library/CloudStorage/Dropbox` from the unsandboxed app blocks in TCC with the "wants to access files managed by Dropbox" prompt. It was not answered.
- `xcodebuild -scheme JournalCore … SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` on this repo fails on GRDB (conflicting `-warnings-as-errors` / `-suppress-warnings`).
- `swift build` with an `.xcassets` folder: "unhandled" warning, no compiled catalog.

## Not verified

- What an expired Personal Team profile does on macOS, with and without restricted entitlements. There's no Personal Team identity on this Mac.
- Whether a self-signed certificate's DR keeps TCC and keychain approvals across rebuilds.
- Whether sandbox temporary exceptions match the symlinked OpenEmu path or need the resolved `~/Library/CloudStorage/Dropbox/...` path.
- A real XcodeGen or Tuist generation against this repo. Building XcodeGen from source was not permitted in this session.
- Xcode behaviour with a `.xcodeproj` nested under the package root that references `..` as a local package.
