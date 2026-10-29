import AppKit
import LudeumCore
import SwiftUI

/// Each installed Emulator's version, checked once per launch in the background: Play is refused
/// for one older than Ludeum expects, and warns (once per launch) about a newer major version or
/// one that couldn't be read. DuckStation (ADR 0024), MesenCE (ADR 0027) and ares (ADR 0028) are copies Ludeum
/// installs, checked again after each Install: Play is refused until each is there, Ludeum's own and the pinned build.
@Observable @MainActor final class EmulatorVersionChecks {
    /// By bundle identifier; an Emulator that isn't installed, or isn't checked yet, has none.
    private(set) var results: [String: VersionCheck] = [:]
    /// The installed version each check found, when it could be read.
    private(set) var installed: [String: String] = [:]
    /// Emulators the launch check found aren't installed.
    private(set) var notInstalled: Set<String> = []
    /// The launch check has been through every Emulator.
    private(set) var finished = false
    /// Emulators Ludeum installs whose copy in the Ludeum folder isn't the one it installed: one that isn't portable, or
    /// a MesenCE with no record of its release.
    private(set) var notLudeums: Set<String> = []
    /// Emulators already warned about this launch.
    private var warned: Set<String> = []
    @ObservationIgnored private let folder: LudeumFolder

    init(folder: LudeumFolder) {
        self.folder = folder
    }

    func result(_ emulator: Emulator) -> VersionCheck? { results[emulator.bundleIdentifier] }

    func checkAll() async {
        for emulator in Emulator.all {
            if emulator.isLudeums {
                await checkLudeums(emulator)
                continue
            }
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

    /// Checks an Emulator Ludeum installs: there, its own copy, and the pinned build.
    func checkLudeums(_ emulator: Emulator) async {
        let id = emulator.bundleIdentifier
        let app: URL
        let isInstalled: Bool
        let isLudeums: Bool
        if emulator == .mesenCE {
            let settings = MesenSettings(ludeum: folder)
            (app, isInstalled, isLudeums) = (settings.app, settings.isInstalled, settings.isPortable && settings.installed != nil)
        } else if emulator == .ares {
            let settings = AresSettings(ludeum: folder)
            (app, isInstalled, isLudeums) = (settings.app, settings.isInstalled, settings.isPortable)
        } else {
            let settings = DuckStationSettings(ludeum: folder)
            (app, isInstalled, isLudeums) = (settings.app, settings.isInstalled, settings.isPortable)
        }
        guard isInstalled else {
            notInstalled.insert(id)
            results[id] = nil
            installed[id] = nil
            notLudeums.remove(id)
            return
        }
        notInstalled.remove(id)
        if isLudeums { notLudeums.remove(id) } else { notLudeums.insert(id) }
        let found = await Task.detached(priority: .utility) { EmulatorVersions.check(emulator, app: app) }.value
        results[id] = found?.check
        installed[id] = found?.installed
    }

    /// Whether an Emulator Ludeum installs is being installed now.
    func isInstalling(_ emulator: Emulator, tasks: BackgroundTasks) -> Bool { tasks.isActive(.emulator(emulator)) }

    /// Installs the pinned DuckStation, MesenCE or ares as a Background task, then checks it again. Installing replaces
    /// it, so a task that gets its turn while it's open fails rather than pull the app from under it.
    func install(_ emulator: Emulator, tasks: BackgroundTasks) {
        let folder = folder
        tasks.enqueue("Installing \(emulator.name)", subject: .emulator(emulator)) { progress in
            if await emulator.isRunning { throw EmulatorRunning(emulator: emulator) }
            if emulator == .mesenCE {
                try await MesenInstaller(ludeum: folder).install(progress: progress)
            } else if emulator == .ares {
                try await AresInstaller(ludeum: folder).install(progress: progress)
            } else {
                try await DuckStationInstaller(ludeum: folder).install(progress: progress)
            }
        } ended: {
            Task { await self.checkLudeums(emulator) }
        }
    }

    /// Why Play is refused, when the installed version won't do.
    func refusalMessage(_ emulator: Emulator) -> String? {
        if notLudeums.contains(emulator.bundleIdentifier) {
            return "\(emulator.name) isn't the copy Ludeum installed. Install it again from Ludeum ▸ Emulators… to Play."
        }
        guard let expected = emulator.expectedVersion else { return nil }
        switch result(emulator) {
        case .tooOld(let found):
            return "\(emulator.name) \(found) is older than \(expected), which Ludeum needs. Update \(emulator.name) to Play."
        case .wrongBuild where emulator == .mesenCE:
            return "MesenCE isn't the \(expected) release Ludeum installs. Install it again from Ludeum ▸ Emulators… to Play."
        case .wrongBuild(let found) where emulator == .ares:
            return "ares is v\(found), and Ludeum installs v\(expected). Install it again from Ludeum ▸ Emulators… to Play."
        case .wrongBuild(let found):
            return
                "\(emulator.name) is build \(found), and Ludeum installs build \(expected). Install it again from Ludeum ▸ Emulators… to Play."
        default: return nil
        }
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
            case .ok, .tooOld, .wrongBuild: nil
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

/// Warns once per launch about each system tool that isn't installed. It's only a warning: what
/// needs the tool says so again when it's tried.
struct SystemToolsOnLaunch: ViewModifier {
    @MainActor private static var started = false
    @State private var warning: (title: String, message: String)?

    func body(content: Content) -> some View {
        content
            .task {
                guard !Self.started else { return }
                Self.started = true
                warning = SystemTool.warning(missing: SystemTool.missing())
            }
            .launchWarning($warning)
    }
}

extension View {
    /// An alert showing `warning` while there is one, cleared when it's dismissed: what a launch check found.
    func launchWarning(_ warning: Binding<(title: String, message: String)?>) -> some View {
        alert(
            warning.wrappedValue?.title ?? "",
            isPresented: Binding(get: { warning.wrappedValue != nil }, set: { if !$0 { warning.wrappedValue = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(warning.wrappedValue?.message ?? "")
        }
    }
}

/// Every Emulator Ludeum plays Games in, with what the launch check found: whether it's installed,
/// the version Ludeum needs against the one installed, and the Platforms it plays. DuckStation, MesenCE and ares are
/// installed from here. No Emulator is opened from here: its own settings are reached during a Play (ADR 0027).
struct EmulatorsSheet: View {
    let services: Services
    @Environment(\.dismiss) private var dismiss
    @State private var platforms: [PlatformCount] = []
    @State private var installError: String?

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
                    Text("")
                }
                .font(.callout.bold()).foregroundStyle(.secondary)
                Divider()
                ForEach(Emulator.all, id: \.bundleIdentifier) { emulator in
                    GridRow {
                        Text(emulator.name).bold()
                        status(emulator)
                        Text(emulator.expectedVersion ?? "–").monospacedDigit()
                        Text(checks.installed[emulator.bundleIdentifier] ?? "–").monospacedDigit()
                        Text(plays(emulator)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(width: 260, alignment: .leading)
                        if emulator.isLudeums { installButton(emulator) } else { Text("") }
                    }
                }
            }
            Text(
                "Checked when Ludeum opens. An Emulator older than it needs can't Play; "
                    + "a newer major version, or one whose version can't be read, gets a warning the first time it Plays. "
                    + "DuckStation, MesenCE and ares are Ludeum's own copies, installed here at the release Ludeum needs and kept "
                    + "in the Ludeum folder: their save states and game saves live in the Data folder, MesenCE's apart for each "
                    + "Platform and ares's for each of its systems. "
                    + "An Emulator's own settings are changed in it during a Play."
            )
            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let installError { Text(installError).font(.callout).foregroundStyle(.red) }
            ForEach(Emulator.all.filter(\.isLudeums), id: \.bundleIdentifier) { emulator in
                if let failed = services.tasks.items.first(where: { $0.subject == .emulator(emulator) }),
                    case .failed(let why) = failed.state
                {
                    Text("Installing \(emulator.name) failed: \(why)").font(.callout).foregroundStyle(.red)
                }
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 720)
        .task { platforms = (try? services.journal?.platformCounts()) ?? [] }
    }

    @ViewBuilder private func status(_ emulator: Emulator) -> some View {
        let id = emulator.bundleIdentifier
        if emulator.isLudeums, let item = services.tasks.active(.emulator(emulator)) {
            Label(item.progress.map { "Installing \(Int($0 * 100))%" } ?? "Installing…", systemImage: "arrow.down.circle")
                .foregroundStyle(.secondary)
        } else if checks.notInstalled.contains(id) {
            Label("Not installed", systemImage: "minus.circle").foregroundStyle(.secondary)
        } else if checks.notLudeums.contains(id) {
            Label("Not Ludeum's copy: install again", systemImage: "xmark.octagon.fill").foregroundStyle(.red)
        } else {
            switch checks.result(emulator) {
            case .ok: Label("OK", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            case .tooOld: Label("Too old: can't Play", systemImage: "xmark.octagon.fill").foregroundStyle(.red)
            case .wrongBuild: Label("Wrong build: install again", systemImage: "xmark.octagon.fill").foregroundStyle(.red)
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

    /// Installs the pinned DuckStation, MesenCE or ares into the Ludeum folder, or installs it again over the copy there.
    private func installButton(_ emulator: Emulator) -> some View {
        let installed = !checks.notInstalled.contains(emulator.bundleIdentifier)
        let release =
            switch emulator {
            case .mesenCE: MesenRelease.pinned.version
            case .ares: "v\(AresRelease.pinned.version)"
            default: "build \(DuckStationRelease.pinned.build)"
            }
        return Button(installed ? "Reinstall" : "Install") {
            installError = nil
            if emulator.isRunning {
                installError = EmulatorRunning(emulator: emulator).description
                return
            }
            if emulator == .mesenCE, let library = MesenRelease.pinned.needs, !library.isInstalled {
                installError = MesenInstallError.needs(library).description
                return
            }
            checks.install(emulator, tasks: services.tasks)
        }
        .disabled(checks.isInstalling(emulator, tasks: services.tasks))
        .help(installed ? "Download \(release) again and put it in place" : "Download \(emulator.name) into the Ludeum folder")
    }

    /// The Library's Platforms it plays, e.g. "SNES, Game Boy".
    private func plays(_ emulator: Emulator) -> String {
        let names = platforms.filter { Emulator.of(platformId: $0.id) == emulator }.map(\.name)
        return names.isEmpty ? "–" : names.joined(separator: ", ")
    }
}

extension Emulator {
    /// Any copy of it is open, Ludeum's or another. DuckStation and ares rewrite their settings files whole from memory,
    /// and MesenCE reads its own once, so Ludeum doesn't write them, or replace the app, meanwhile.
    @MainActor var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty }
}

/// Installing was refused because the Emulator is open.
struct EmulatorRunning: LocalizedError, CustomStringConvertible {
    let emulator: Emulator

    var description: String { "Quit \(emulator.name) first: installing replaces it." }
    var errorDescription: String? { description }
}
