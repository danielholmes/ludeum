import AppKit
import LudeumCore
import SwiftUI

/// Keeps the backup of DuckStation's save states up to date (ADR 0022): it backs up every Game's states when Ludeum
/// opens and whenever it becomes active again, and while it's open, each time DuckStation's folder changes. Game detail
/// re-reads a Game's states when `revision` changes.
@Observable @MainActor final class SaveStateBackup {
    /// Bumped after every look at DuckStation's folder, whether or not anything was copied: a state may have gone.
    private(set) var revision = 0
    /// Why the last backup failed, if it did.
    private(set) var error: String?
    @ObservationIgnored private let journal: LudeumStore?
    @ObservationIgnored private let ludeum: LudeumFolder
    @ObservationIgnored private var watching: (folder: URL, source: DispatchSourceFileSystemObject)?
    @ObservationIgnored private var running = false
    @ObservationIgnored private var again = false
    @ObservationIgnored private var pending: Task<Void, Never>?

    init(journal: LudeumStore?, ludeum: LudeumFolder) {
        self.journal = journal
        self.ludeum = ludeum
    }

    /// DuckStation's states as its settings place them now.
    var states: DuckStationSaveStates { DuckStationSaveStates(ludeum: ludeum) }

    /// Backs up every Game's states, and watches DuckStation's folder: again if its settings moved it, or it's only
    /// now been made.
    func backUp() {
        watch(states.folder)
        guard let journal else { return }
        if running {
            again = true
            return
        }
        running = true
        let states = states
        Task {
            defer { running = false }
            repeat {
                again = false
                do {
                    _ = try await Task.detached(priority: .utility) { try states.backUp(journal.gameSerials()) }.value
                    error = nil
                } catch {
                    self.error = "Couldn't back up DuckStation's save states: \(error.localizedDescription)"
                }
                revision += 1
            } while again
        }
    }

    /// Backs up a second after DuckStation's folder last changed: it writes a state under another name and renames it
    /// into place, so one save is a few changes.
    private func watch(_ folder: URL) {
        guard watching?.folder != folder else { return }
        watching?.source.cancel()
        watching = nil
        let descriptor = open(folder.path(percentEncoded: false), O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .delete, .rename], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                // The folder itself went or moved: look for it again at the next backup.
                if source.data.contains(.delete) || source.data.contains(.rename) {
                    self.watching?.source.cancel()
                    self.watching = nil
                }
                self.pending?.cancel()
                self.pending = Task {
                    try? await Task.sleep(for: .seconds(1))
                    if !Task.isCancelled { self.backUp() }
                }
            }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        watching = (folder, source)
    }
}

/// Game detail's Save states: a PlayStation Game's DuckStation save states by Disc, then Resume, then slot, each with its
/// screenshot and when it was saved, to Play from, Restore when only the backup has it, or delete (ADR 0022). They're
/// made and managed in DuckStation; this is what's in its folder and in the backup. Opening it backs up first, as a
/// Serial may only just have been read.
struct SaveStatesSection: View {
    let services: Services
    /// The Serials of the ROMs Play opens, in Disc order.
    let serials: [String]
    /// Why Play can't open it, if it can't.
    let refusal: String?
    let play: (SaveState) -> Void

    @State private var states: [SaveState] = []
    @State private var screenshots: [String: NSImage] = [:]
    @State private var deleting: SaveState?
    @State private var error: String?

    var body: some View {
        Section("Save states") {
            if states.isEmpty {
                Text("No save states. Save one in DuckStation and it shows here, backed up to the Data folder.")
                    .foregroundStyle(.secondary)
            }
            ForEach(states) { row($0) }
            if let error = error ?? services.saveStates.error { Text(error).foregroundStyle(.red) }
        }
        .task(id: serials) { services.saveStates.backUp() }
        .task(id: Key(serials: serials, revision: services.saveStates.revision)) { await load() }
        .confirmationDialog(
            deleting.map { "Delete \($0.title)?" } ?? "",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            presenting: deleting
        ) { state in
            Button("Delete Save State", role: .destructive) { delete(state) }
        } message: { state in
            Text(
                state.inDuckStation
                    ? "It goes to the Trash from DuckStation's folder and from the backup."
                    : "Its backup goes to the Trash. DuckStation hasn't got it any more.")
        }
    }

    private struct Key: Equatable {
        let serials: [String]
        let revision: Int
    }

    private func row(_ state: SaveState) -> some View {
        HStack(spacing: 12) {
            // A PlayStation picture is 4:3 on screen, whatever its pixels.
            Group {
                if let image = screenshots[imageKey(state)] {
                    Image(nsImage: image).resizable().interpolation(.medium)
                } else {
                    Rectangle().fill(.quaternary)
                }
            }
            .frame(width: 96, height: 72).clipShape(.rect(cornerRadius: 4))
            VStack(alignment: .leading, spacing: 2) {
                Text(serials.count > 1 ? "\(state.title) · Disc \((serials.firstIndex(of: state.serial) ?? 0) + 1)" : state.title)
                Text(state.saved.formatted(date: .abbreviated, time: .shortened)).font(.callout).foregroundStyle(.secondary)
                if !state.inDuckStation {
                    Text("Not in DuckStation: only the backup has it").font(.callout).foregroundStyle(.orange)
                } else if !state.backedUp {
                    Text("Not backed up yet").font(.callout).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if !state.inDuckStation {
                Button("Restore") { restore(state) }.help("Copy it back into DuckStation's folder, where its menus see it")
            }
            Button("Play", systemImage: "play.fill") { play(state) }
                .labelStyle(.iconOnly).buttonStyle(.hover).disabled(refusal != nil)
                .help(refusal ?? "Play from this state in DuckStation")
            Menu {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([state.file]) }
                Divider()
                Button("Delete…", role: .destructive) { deleting = state }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("More")
        }
    }

    /// A screenshot is read again when its state's saved again.
    private func imageKey(_ state: SaveState) -> String { "\(state.file.path(percentEncoded: false))@\(state.saved.timeIntervalSince1970)" }

    private func load() async {
        let saveStates = services.saveStates.states
        let serials = serials
        states = await Task.detached(priority: .utility) { saveStates.states(of: serials) }.value
        for state in states where screenshots[imageKey(state)] == nil {
            let file = state.file
            if let shot = await Task.detached(priority: .utility, operation: { DuckStationSaveStates.screenshot(of: file) }).value {
                screenshots[imageKey(state)] = shot.image
            }
            if Task.isCancelled { return }
        }
    }

    private func restore(_ state: SaveState) {
        run { try $0.restore(state) }
    }

    private func delete(_ state: SaveState) {
        run { try $0.delete(state) }
    }

    /// Runs a change to the states, then reads them again.
    private func run(_ change: (DuckStationSaveStates) throws -> Void) {
        do {
            try change(services.saveStates.states)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        services.saveStates.backUp()
    }
}

extension SaveStateScreenshot {
    /// Its pixels as an image, their alpha ignored.
    var image: NSImage? {
        guard let provider = CGDataProvider(data: rgba as CFData),
            let image = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: width, height: height))
    }
}
