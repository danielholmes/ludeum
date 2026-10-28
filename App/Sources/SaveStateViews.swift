import AppKit
import LudeumCore
import SwiftUI

/// Game detail's Save states: a PlayStation Game's DuckStation save states by Disc, then Resume, then slot, each with its
/// screenshot and when it was saved, to Play from or delete (ADR 0024). They're made and managed in DuckStation, which
/// keeps them in the Data folder; this is what's there, read again when Game detail opens and whenever Ludeum becomes
/// active, back from DuckStation.
struct SaveStatesSection: View {
    let services: Services
    /// The Serials of the ROMs Play opens, in Disc order.
    let serials: [String]
    /// The Discs of the multi-disc ROM Play opens, saying which a state was saved on with its Disc label.
    let discs: [PlayDisc]
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
                Text("No save states. Save one in DuckStation and it shows here, kept in the Data folder.")
                    .foregroundStyle(.secondary)
            }
            ForEach(states) { row($0) }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .task(id: serials) { await load() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await load() }
        }
        .confirmationDialog(
            deleting.map { "Delete \($0.title)?" } ?? "",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            presenting: deleting
        ) { state in
            Button("Delete Save State", role: .destructive) { delete(state) }
        } message: { _ in
            Text("It goes to the Trash.")
        }
    }

    private var saveStates: DuckStationSaveStates { DuckStationSaveStates(ludeum: services.settings.folder) }

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
                Text(
                    serials.count > 1
                        ? "\(state.title) · \(discs.first { $0.serial == state.serial }?.numberAndLabel ?? "Disc \((serials.firstIndex(of: state.serial) ?? 0) + 1)")"
                        : state.title)
                Text(state.saved.formatted(date: .abbreviated, time: .shortened)).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
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
        let saveStates = saveStates
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

    private func delete(_ state: SaveState) {
        do {
            try saveStates.delete(state)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        Task { await load() }
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
