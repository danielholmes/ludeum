import AppKit
import LudeumCore
import SwiftUI

/// Each installed Emulator's version, checked once per launch in the background: Play is refused
/// for one older than Ludeum expects, and warns (once per launch) about a newer major version or
/// one that couldn't be read. DuckStation is the copy Ludeum installs (ADR 0024), checked again after each Install:
/// Play is refused until it's there, portable and the pinned build.
@Observable @MainActor final class EmulatorVersionChecks {
    /// By bundle identifier; an Emulator that isn't installed, or isn't checked yet, has none.
    private(set) var results: [String: VersionCheck] = [:]
    /// The installed version each check found, when it could be read.
    private(set) var installed: [String: String] = [:]
    /// Emulators the launch check found aren't installed.
    private(set) var notInstalled: Set<String> = []
    /// The launch check has been through every Emulator.
    private(set) var finished = false
    /// The DuckStation in the Ludeum folder isn't portable, so it isn't the copy Ludeum installed.
    private(set) var duckStationNotPortable = false
    /// Emulators already warned about this launch.
    private var warned: Set<String> = []
    @ObservationIgnored private let folder: LudeumFolder

    init(folder: LudeumFolder) {
        self.folder = folder
    }

    func result(_ emulator: Emulator) -> VersionCheck? { results[emulator.bundleIdentifier] }

    func checkAll() async {
        for emulator in Emulator.all {
            if emulator == .duckStation {
                await checkDuckStation()
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

    /// Checks the DuckStation Ludeum installs: there, portable, and the pinned build.
    func checkDuckStation() async {
        let id = Emulator.duckStation.bundleIdentifier
        let settings = DuckStationSettings(ludeum: folder)
        guard settings.isInstalled else {
            notInstalled.insert(id)
            results[id] = nil
            installed[id] = nil
            duckStationNotPortable = false
            return
        }
        notInstalled.remove(id)
        duckStationNotPortable = !settings.isPortable
        let app = settings.app
        let found = await Task.detached(priority: .utility) { EmulatorVersions.check(.duckStation, app: app) }.value
        results[id] = found?.check
        installed[id] = found?.installed
    }

    /// Whether DuckStation is being installed now.
    func isInstalling(_ emulator: Emulator, tasks: BackgroundTasks) -> Bool { tasks.isActive(.emulator(emulator)) }

    /// Installs the pinned DuckStation as a Background task, then checks it again. Installing replaces it, so a task
    /// that gets its turn while DuckStation is open fails rather than pull the app from under it.
    func installDuckStation(tasks: BackgroundTasks) {
        let folder = folder
        tasks.enqueue("Installing DuckStation", subject: .emulator(.duckStation)) { progress in
            if await Emulator.duckStation.isRunning { throw EmulatorRunning() }
            try await DuckStationInstaller(ludeum: folder).install(progress: progress)
        } ended: {
            Task { await self.checkDuckStation() }
        }
    }

    /// Why Play is refused, when the installed version won't do.
    func refusalMessage(_ emulator: Emulator) -> String? {
        if emulator == .duckStation, duckStationNotPortable {
            return "DuckStation isn't the copy Ludeum installed (it isn't portable). Install it again from Ludeum ▸ Emulators… to Play."
        }
        guard let expected = emulator.expectedVersion else { return nil }
        switch result(emulator) {
        case .tooOld(let found):
            return "\(emulator.name) \(found) is older than \(expected), which Ludeum needs. Update \(emulator.name) to Play."
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
/// the version Ludeum needs against the one installed, and the Platforms it plays. DuckStation is installed from here.
struct EmulatorsSheet: View {
    let services: Services
    @Environment(\.dismiss) private var dismiss
    @State private var platforms: [PlatformCount] = []
    @State private var openError: String?

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
                        Text(plays(emulator)).foregroundStyle(.secondary).lineLimit(2)
                            .frame(maxWidth: 260, alignment: .leading)
                        HStack {
                            if emulator == .duckStation { installButton }
                            openButton(emulator)
                        }
                    }
                }
            }
            Text(
                "Checked when Ludeum opens. An Emulator older than it needs can't Play; "
                    + "a newer major version, or one whose version can't be read, gets a warning the first time it Plays. "
                    + "DuckStation is Ludeum's own copy, installed here at the build Ludeum needs and kept in the Ludeum folder: "
                    + "its save states, memory cards, BIOS and game settings live in the Data folder."
            )
            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let openError { Text(openError).font(.callout).foregroundStyle(.red) }
            if let failed = services.tasks.items.first(where: { $0.subject == .emulator(.duckStation) }),
                case .failed(let why) = failed.state
            {
                Text("Installing DuckStation failed: \(why)").font(.callout).foregroundStyle(.red)
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
        if emulator == .duckStation, let item = services.tasks.active(.emulator(emulator)) {
            Label(item.progress.map { "Installing \(Int($0 * 100))%" } ?? "Installing…", systemImage: "arrow.down.circle")
                .foregroundStyle(.secondary)
        } else if checks.notInstalled.contains(id) {
            Label("Not installed", systemImage: "minus.circle").foregroundStyle(.secondary)
        } else if emulator == .duckStation, checks.duckStationNotPortable {
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

    /// Installs the pinned DuckStation into the Ludeum folder, or installs it again over the copy there.
    private var installButton: some View {
        let id = Emulator.duckStation.bundleIdentifier
        let installed = !checks.notInstalled.contains(id)
        return Button(installed ? "Reinstall" : "Install") {
            openError = nil
            if Emulator.duckStation.isRunning {
                openError = EmulatorRunning().description
                return
            }
            checks.installDuckStation(tasks: services.tasks)
        }
        .disabled(checks.isInstalling(.duckStation, tasks: services.tasks))
        .help(
            installed
                ? "Download build \(DuckStationRelease.pinned.build) again and put it in place"
                : "Download DuckStation into the Ludeum folder")
    }

    /// Opens an Emulator the launch check found installed on its own, with no ROM, e.g. to change its
    /// settings or update it (even one too old to Play). DuckStation gets its Standing settings first.
    @ViewBuilder private func openButton(_ emulator: Emulator) -> some View {
        if checks.finished, !checks.notInstalled.contains(emulator.bundleIdentifier) {
            Button("Open") {
                openError = nil
                let app: URL
                if emulator == .duckStation {
                    let settings = DuckStationSettings(ludeum: services.settings.folder)
                    app = settings.app
                    if !emulator.isRunning {
                        do { try settings.writeStanding() } catch { openError = "Couldn't write DuckStation's settings: \(error)" }
                    }
                } else {
                    guard let found = NSWorkspace.shared.urlForApplication(withBundleIdentifier: emulator.bundleIdentifier) else {
                        openError = "Couldn't find \(emulator.name). Is it still installed?"
                        return
                    }
                    app = found
                }
                NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                    if let error { Task { @MainActor in openError = "Couldn't open \(emulator.name): \(error.localizedDescription)" } }
                }
            }
            .help("Open \(emulator.name) with no ROM")
        } else {
            Text("")
        }
    }

    /// The Library's Platforms it plays, e.g. "SNES, Game Boy".
    private func plays(_ emulator: Emulator) -> String {
        let names = platforms.filter { Emulator.of(platformId: $0.id) == emulator }.map(\.name)
        return names.isEmpty ? "–" : names.joined(separator: ", ")
    }
}

extension Emulator {
    /// Any copy of it is open, Ludeum's or another. DuckStation rewrites its settings file whole from memory, so Ludeum
    /// doesn't write it, or replace the app, meanwhile.
    @MainActor var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty }
}

/// Installing was refused because DuckStation is open.
struct EmulatorRunning: LocalizedError, CustomStringConvertible {
    var description: String { "Quit DuckStation first: installing replaces it." }
    var errorDescription: String? { description }
}
