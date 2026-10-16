import AppKit
import LudeumCore
import SwiftUI

/// For now, while it's decided whether Box art needs both libretro and LaunchBox: Game detail's Cover, labelled with
/// where it came from, then each source's own Box art for the Game (`Covers.boxArt(for:from:)`), so a box the Cover
/// order hides can be seen. The Library still shows only the Cover.
struct CoverComparison: View {
    let services: Services
    let game: GameID
    let name: String
    @State private var coverOrigin: String?
    @State private var boxArt: [BoxArtSource: SourceBoxArt] = [:]

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            column(["Cover", coverOrigin].compactMap { $0 }.joined(separator: " · ")) {
                CoverView(services: services, game: game, name: name, fitsImage: true)
            }
            ForEach(BoxArtSource.allCases, id: \.self) { source in
                column(source.rawValue) { SourceBoxArtView(state: boxArt[source] ?? .loading, name: "\(name), \(source.rawValue)") }
            }
        }
        .task(id: CoverKey(game: game, revision: services.changes.coverRevision, pixels: CoverTileSize.pixels)) {
            boxArt = [:]
            coverOrigin = (try? await services.covers?.cover(for: game))?.origin
            // Each on its own, so one that can't be read doesn't hide the other.
            for source in BoxArtSource.allCases { boxArt[source] = await load(source) }
        }
    }

    private func column(_ label: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(spacing: 4) {
            content().frame(width: 150).frame(maxHeight: 200, alignment: .top)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func load(_ source: BoxArtSource) async -> SourceBoxArt {
        guard let covers = services.covers else { return .none }
        do {
            guard let found = try await covers.boxArt(for: game, from: source) else { return .none }
            guard let image = await decodeImage(found, pixels: CoverTileSize.pixels) else { return .failed }
            return .found(found, image)
        } catch {
            return .failed
        }
    }
}

/// One source's Box art for a Game, as far as it's been looked up.
private enum SourceBoxArt {
    case loading
    /// The source has no box for the Game.
    case none
    /// It couldn't be downloaded or read: not the same as having none.
    case failed
    case found(CoverSource, NSImage)
}

/// A source's box at tile size, opening full size when clicked, or what stands in for it.
private struct SourceBoxArtView: View {
    let state: SourceBoxArt
    let name: String
    @State private var enlarged = false

    var body: some View {
        switch state {
        case .found(let boxArt, let image):
            Image(nsImage: image).resizable().interpolation(.high).antialiased(true).scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .onTapGesture { enlarged = true }
                .help(boxArt.location.map { "\($0) (click to show full size)" } ?? "Show full size")
                .sheet(isPresented: $enlarged) {
                    EnlargedImage(name: name, tileSized: image) { await decodeImage(boxArt, pixels: nil) }
                }
        case .loading: placeholder { ProgressView().controlSize(.small) }
        case .none: placeholder { Text("No box").font(.caption).foregroundStyle(.secondary) }
        case .failed: placeholder { Text("Couldn't load").font(.caption).foregroundStyle(.red) }
        }
    }

    private func placeholder(@ViewBuilder _ content: () -> some View) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(.quaternary)
            content()
        }
        .frame(width: 150, height: 200)
    }
}
