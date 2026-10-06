import AppKit
import LudeumCore
import SwiftUI

/// Each installed Emulator's version, checked once per launch in the background: Play is refused
/// for one older than Ludeum expects, and warns (once per launch) about a newer major version or
/// one that couldn't be read.
@Observable @MainActor final class EmulatorVersionChecks {
    /// By bundle identifier; an Emulator that isn't installed, or isn't checked yet, has none.
    private(set) var results: [String: VersionCheck] = [:]
    /// The installed version each check found, when it could be read.
    private(set) var installed: [String: String] = [:]
    /// Emulators the launch check found aren't installed.
    private(set) var notInstalled: Set<String> = []
    /// The launch check has been through every Emulator.
    private(set) var finished = false
    /// Emulators already warned about this launch.
    private var warned: Set<String> = []

    func result(_ emulator: Emulator) -> VersionCheck? { results[emulator.bundleIdentifier] }

    func checkAll() async {
        for emulator in Emulator.all {
            let id = emulator.bundleIdentifier
            guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else {
                notInstalled.insert(id)
                continue
            }
            let found = await Task.detached(priority: .utility) { EmulatorVersions.check(emulator, app: app) }.value
            results[id] = found?.check
            installed[id] = found?.installed
        }
        finished = true
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

/// Every Emulator Ludeum plays Games in, with what the launch check found: whether it's installed,
/// the version Ludeum needs against the one installed, and the Platforms it plays.
struct EmulatorsSheet: View {
    let services: Services
    @Environment(\.dismiss) private var dismiss
    @State private var platforms: [PlatformCount] = []

    private var checks: EmulatorVersionChecks { services.versions }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Emulators").font(.title2.bold())
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                GridRow {
                    Text("Emulator")
                    Text("Status")
                    Text("Needs")
                    Text("Installed")
                    Text("Plays")
                }
                .font(.callout.bold()).foregroundStyle(.secondary)
                Divider()
                ForEach(Emulator.all, id: \.bundleIdentifier) { emulator in
                    GridRow {
                        Text(emulator.name).bold()
                        status(emulator)
                        Text(emulator.expectedVersion ?? "–").monospacedDigit()
                        Text(checks.installed[emulator.bundleIdentifier] ?? "–").monospacedDigit()
                        Text(plays(emulator)).foregroundStyle(.secondary).lineLimit(2)
                            .frame(maxWidth: 260, alignment: .leading)
                    }
                }
            }
            Text(
                "Checked when Ludeum opens. An Emulator older than it needs can't Play; "
                    + "a newer major version, or one whose version can't be read, gets a warning the first time it Plays."
            )
            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 680)
        .task { platforms = (try? services.journal?.platformCounts()) ?? [] }
    }

    @ViewBuilder private func status(_ emulator: Emulator) -> some View {
        let id = emulator.bundleIdentifier
        if checks.notInstalled.contains(id) {
            Label("Not installed", systemImage: "minus.circle").foregroundStyle(.secondary)
        } else {
            switch checks.result(emulator) {
            case .ok: Label("OK", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            case .tooOld: Label("Too old: can't Play", systemImage: "xmark.octagon.fill").foregroundStyle(.red)
            case .newerMajor: Label("Newer major version", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            case .unreadable: Label("Version unreadable", systemImage: "questionmark.circle.fill").foregroundStyle(.orange)
            case nil:
                if checks.finished {
                    Label("Not checked", systemImage: "minus.circle").foregroundStyle(.secondary)
                } else {
                    Label("Checking…", systemImage: "hourglass").foregroundStyle(.secondary)
                }
            }
        }
    }

    /// The Library's Platforms it plays, e.g. "SNES, Game Boy".
    private func plays(_ emulator: Emulator) -> String {
        let names = platforms.filter { Emulator.of(platformId: $0.id) == emulator }.map(\.name)
        return names.isEmpty ? "–" : names.joined(separator: ", ")
    }
}
