import AppKit
import LudeumCore
import SwiftUI

/// Each installed Emulator's version, checked once per launch in the background: Play is refused
/// for one older than Ludeum expects, and warns (once per launch) about a newer major version or
/// one that couldn't be read.
@Observable @MainActor final class EmulatorVersionChecks {
    /// By bundle identifier; an Emulator that isn't installed, or isn't checked yet, has none.
    private(set) var results: [String: VersionCheck] = [:]
    /// Emulators already warned about this launch.
    private var warned: Set<String> = []

    func result(_ emulator: Emulator) -> VersionCheck? { results[emulator.bundleIdentifier] }

    func checkAll() async {
        for emulator in Emulator.all {
            guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: emulator.bundleIdentifier) else { continue }
            results[emulator.bundleIdentifier] = await Task.detached(priority: .utility) {
                EmulatorVersions.check(emulator, app: app)
            }.value
        }
    }

    /// Why Play is refused, when the installed version is too old.
    func tooOldMessage(_ emulator: Emulator) -> String? {
        guard case .tooOld(let found) = result(emulator), let expected = emulator.expectedVersion else { return nil }
        return "\(emulator.name) \(found) is older than \(expected), which Ludeum needs. Update \(emulator.name) to Play."
    }

    /// The warning to show before this Play, the first time only.
    func warningOnce(_ emulator: Emulator) -> String? {
        guard let result = result(emulator), !warned.contains(emulator.bundleIdentifier) else { return nil }
        let text: String? =
            switch result {
            case .newerMajor(let found):
                "\(emulator.name) \(found) is a newer major version than \(emulator.expectedVersion ?? ""), which Ludeum was made for. "
                    + "Play may not pass it the right settings."
            case .unreadable: "Couldn't check \(emulator.name)'s version. Ludeum expects \(emulator.expectedVersion ?? "") or later."
            case .ok, .tooOld: nil
            }
        if text != nil { warned.insert(emulator.bundleIdentifier) }
        return text
    }
}

/// Checks the Emulators' versions once per launch, not for every new main window.
struct EmulatorVersionsOnLaunch: ViewModifier {
    let services: Services
    @MainActor private static var started = false

    func body(content: Content) -> some View {
        content.task {
            guard !Self.started else { return }
            Self.started = true
            Task { await services.versions.checkAll() }
        }
    }
}
