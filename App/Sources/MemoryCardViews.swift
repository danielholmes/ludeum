import AppKit
import LudeumCore
import SwiftUI

/// Game detail's Memory card: each present PlayStation ROM's card, the one Game save DuckStation keeps for it in the Data
/// folder, with the Card saves in it (ADR 0023). Before a ROM's first Play, it's DuckStation's own card, copied in then.
/// It's read again when Game detail opens and whenever Ludeum becomes active, back from DuckStation.
struct MemoryCardSection: View {
    let services: Services
    /// The ROMs Play opens, each with Disc 1's Serial, which names its card.
    let roms: [LudeumROM]

    @State private var cards: [Int64: MemoryCardFile?] = [:]

    var body: some View {
        Section(roms.count > 1 ? "Memory cards" : "Memory card") {
            ForEach(roms) { rom in
                if roms.count > 1 { Text(rom.name).font(.headline) }
                if let read = cards[rom.id] { card(read) }
            }
        }
        .task(id: roms.map(\.id)) { await load() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await load() }
        }
    }

    @ViewBuilder private func card(_ card: MemoryCardFile?) -> some View {
        if let card {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Saved \(card.saved.formatted(date: .abbreviated, time: .shortened))")
                    if !card.inDataFolder {
                        Text("DuckStation's own card: it's copied into the Data folder at the next Play").font(.callout)
                            .foregroundStyle(.orange)
                    }
                }
                Spacer()
                Button("Show in Finder", systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting([card.file]) }
                    .labelStyle(.iconOnly).buttonStyle(.hover).help("Show the card in Finder")
            }
            if let saves = card.saves {
                if saves.isEmpty { Text("No saves on it.").foregroundStyle(.secondary) }
                ForEach(saves) { save in
                    HStack(spacing: 12) {
                        CardSaveIcon(frames: save.icon)
                        Text(save.title.isEmpty ? save.fileName : save.title)
                        Spacer()
                        Text(save.blocks == 1 ? "1 block" : "\(save.blocks) blocks").foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("Couldn't read it as a memory card.").foregroundStyle(.red)
            }
        } else {
            Text("No saves yet. Save in DuckStation and its memory card shows here, kept in the Data folder.")
                .foregroundStyle(.secondary)
        }
    }

    private func load() async {
        let memoryCards = DuckStationMemoryCards(duckStation: DuckStationSettings(ludeum: services.settings.folder))
        let locator = ROMLocator(romFolders: services.settings.romFolders)
        let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Emulator.duckStation.bundleIdentifier)
        let roms = roms
        cards = await Task.detached(priority: .utility) {
            var cards: [Int64: MemoryCardFile?] = [:]
            for rom in roms {
                guard let serial = rom.serials.first else { continue }
                // The ROM's file names DuckStation's own card for a disc its game database doesn't know.
                let file = (try? locator.file(of: rom)) ?? nil
                cards[rom.id] = memoryCards.memoryCard(
                    serial: serial, rom: file ?? URL(filePath: rom.fileName), resources: app.map(DuckStationMemoryCards.resources(of:)))
            }
            return cards
        }.value
    }
}

/// A Card save's icon, 16 × 16 shown at twice its size, its frames shown in turn as the PlayStation's own menu does.
struct CardSaveIcon: View {
    let frames: [Data]
    /// How long each frame shows.
    private static let frameTime: TimeInterval = 0.27

    var body: some View {
        TimelineView(.periodic(from: .now, by: Self.frameTime)) { timeline in
            let index = frames.count > 1 ? Int(timeline.date.timeIntervalSinceReferenceDate / Self.frameTime) % frames.count : 0
            Group {
                if let image = frames.indices.contains(index) ? Self.image(frames[index]) : nil {
                    Image(nsImage: image).resizable().interpolation(.none)
                } else {
                    Rectangle().fill(.quaternary)
                }
            }
            .frame(width: 32, height: 32)
        }
    }

    /// A frame's 16 × 16 RGBA pixels as an image.
    private static func image(_ rgba: Data) -> NSImage? {
        guard rgba.count == 16 * 16 * 4, let provider = CGDataProvider(data: rgba as CFData),
            let image = CGImage(
                width: 16, height: 16, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 16 * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: 16, height: 16))
    }
}
