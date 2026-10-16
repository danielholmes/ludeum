import AppKit
import LudeumCore
import SwiftUI

/// For now, while it's decided whether Box art needs both libretro and LaunchBox: Game detail's Cover, labelled with
/// where it came from, then each source's own Box art for the Game (`Covers.boxArt(for:from:)`) and IGDB's Cover art,
/// so an image the Cover order hides can be seen. The Library still shows only the Cover.
struct CoverComparison: View {
    let services: Services
    let game: GameID
    let name: String
    @State private var coverOrigin: String?
    @State private var images: [Source: SourceImage] = [:]

    /// What's shown beside the Cover, in the Cover order.
    private enum Source: CaseIterable {
        case libretro, launchBox, igdb

        var label: String {
            switch self {
            case .libretro: ImageSource.libretro.rawValue
            case .launchBox: ImageSource.launchBox.rawValue
            case .igdb: "IGDB"
            }
        }

        func find(_ covers: Covers, _ game: GameID) async throws -> CoverSource? {
            switch self {
            case .libretro: try await covers.boxArt(for: game, from: .libretro)
            case .launchBox: try await covers.boxArt(for: game, from: .launchBox)
            case .igdb: try await covers.coverArt(for: game)
            }
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            column(["Cover", coverOrigin].compactMap { $0 }.joined(separator: " · ")) {
                CoverView(services: services, game: game, name: name, fitsImage: true)
            }
            ForEach(Source.allCases, id: \.self) { source in
                column(source.label) { SourceImageView(state: images[source] ?? .loading, name: "\(name), \(source.label)") }
            }
        }
        .task(id: CoverKey(game: game, revision: services.changes.coverRevision, pixels: CoverTileSize.pixels)) {
            images = [:]
            coverOrigin = (try? await services.covers?.cover(for: game))?.origin
            // Each on its own, so one that can't be read doesn't hide the others.
            for source in Source.allCases { images[source] = await load(source) }
        }
    }

    private func column(_ label: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(spacing: 4) {
            // Narrower in a narrow window, rather than running off its edge.
            content().frame(maxWidth: 150).frame(maxHeight: 200, alignment: .top)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func load(_ source: Source) async -> SourceImage {
        guard let covers = services.covers else { return .none }
        do {
            guard let found = try await source.find(covers, game) else { return .none }
            guard let image = await decodeImage(found, pixels: CoverTileSize.pixels) else { return .failed }
            return .found(found, image)
        } catch {
            return .failed
        }
    }
}

/// One source's image for a Game, as far as it's been looked up.
private enum SourceImage {
    case loading
    /// The source has none for the Game.
    case none
    /// It couldn't be downloaded or read: not the same as having none.
    case failed
    case found(CoverSource, NSImage)
}

/// A source's image at tile size, opening full size when clicked, or what stands in for it.
private struct SourceImageView: View {
    let state: SourceImage
    let name: String
    @State private var enlarged = false

    var body: some View {
        switch state {
        case .found(let found, let image):
            Image(nsImage: image).resizable().interpolation(.high).antialiased(true).scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .onTapGesture { enlarged = true }
                .help(found.location.map { "\($0) (click to show full size)" } ?? "Show full size")
                .sheet(isPresented: $enlarged) {
                    EnlargedImage(name: name, tileSized: image) { await decodeImage(found, pixels: nil) }
                }
        case .loading: placeholder { ProgressView().controlSize(.small) }
        case .none: placeholder { Text("None").font(.caption).foregroundStyle(.secondary) }
        case .failed: placeholder { Text("Couldn't load").font(.caption).foregroundStyle(.red) }
        }
    }

    private func placeholder(@ViewBuilder _ content: () -> some View) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(.quaternary)
            content()
        }
        .frame(maxWidth: 150).frame(height: 200)
    }
}

/// For now, beside IGDB's: one source's Screenshots for the Game (`Covers.screenshots(for:from:)`), title screens
/// first, each whole in a 4:3 tile and full size when clicked, to compare the sources while it's decided whether both
/// are needed.
struct SourceScreenshotsSection: View {
    let services: Services
    let game: GameID
    let source: ImageSource
    @State private var screenshots: [String]?
    @State private var failed = false

    var body: some View {
        Section("\(source.rawValue) Screenshots") {
            if let screenshots, !screenshots.isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                    ForEach(screenshots, id: \.self) { reference in
                        SourceScreenshotTile(services: services, source: source, reference: reference)
                    }
                }
            } else if failed {
                Text("Couldn't load").foregroundStyle(.red)
            } else if screenshots == nil {
                ProgressView().controlSize(.small)
            } else {
                Text("None").foregroundStyle(.secondary)
            }
        }
        .task(id: CoverKey(game: game, revision: services.changes.coverRevision, pixels: 0)) {
            screenshots = nil
            failed = false
            do {
                screenshots = try await services.covers?.screenshots(for: game, from: source) ?? []
            } catch {
                failed = true
            }
        }
    }
}

/// One of a source's Screenshots, whole in a 4:3 tile, downloaded on first view; full size when clicked.
private struct SourceScreenshotTile: View {
    let services: Services
    let source: ImageSource
    let reference: String
    @State private var image: SourceImage = .loading
    @State private var enlarged = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4).fill(.quaternary)
            switch image {
            case .found(let found, let tile):
                Image(nsImage: tile).resizable().interpolation(.high).antialiased(true).scaledToFit()
                    .onTapGesture { enlarged = true }
                    .help("\(reference) (click to show full size)")
                    .sheet(isPresented: $enlarged) {
                        EnlargedImage(name: "\(source.rawValue) Screenshot", tileSized: tile) { await decodeImage(found, pixels: nil) }
                    }
            case .loading: ProgressView().controlSize(.small)
            case .none: EmptyView()
            case .failed: Text("Couldn't load").font(.caption).foregroundStyle(.red)
            }
        }
        .aspectRatio(4 / 3, contentMode: .fit)
        .frame(minWidth: 0)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .task(id: reference) { image = await load() }
    }

    private func load() async -> SourceImage {
        guard let file = try? await services.covers?.screenshot(reference, from: source) else { return .failed }
        let found: CoverSource =
            switch source {
            case .libretro: .libretro(file, path: reference)
            case .launchBox: .launchBox(file, file: reference)
            }
        guard let tile = await decodeImage(found, pixels: 600) else { return .failed }
        return .found(found, tile)
    }
}
