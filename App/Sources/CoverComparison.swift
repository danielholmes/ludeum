import AppKit
import LudeumCore
import SwiftUI

/// For now, while it's decided whether Box art needs both libretro and LaunchBox: Game detail's Cover, then each
/// source's own Box art for the Game (`Covers.boxArtBySource`), labelled, so a box the Cover order hides can be seen.
/// The Library still shows only the Cover.
struct CoverComparison: View {
    let services: Services
    let game: GameID
    let name: String
    /// Each source's box, once looked up; nil until then.
    @State private var boxes: [SourceBox]?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            column("Cover") { CoverView(services: services, game: game, name: name, fitsImage: true) }
            ForEach(boxes ?? SourceBox.loading) { box in
                column(box.source) { SourceBoxView(box: box, loading: boxes == nil, name: name) }
            }
        }
        .task(id: LoadKey(game: game, revision: services.changes.coverRevision, pixels: CoverTileSize.pixels)) {
            boxes = nil
            boxes = await load()
        }
    }

    private struct LoadKey: Equatable {
        let game: GameID
        let revision: Int
        let pixels: Int
    }

    private func column(_ label: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(spacing: 4) {
            content().frame(width: 150).frame(maxHeight: 200, alignment: .top)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func load() async -> [SourceBox] {
        // A source that couldn't be read (a failed download) shows as having none, as the Cover's placeholder does.
        let boxArt = try? await services.covers?.boxArtBySource(for: game)
        var boxes: [SourceBox] = []
        for (source, found) in [("libretro", boxArt?.libretro), ("LaunchBox", boxArt?.launchBox)] {
            let image: NSImage? = if let found { await decodeCover(found, pixels: CoverTileSize.pixels) } else { nil }
            boxes.append(SourceBox(source: source, cover: found, image: image))
        }
        return boxes
    }
}

/// One source's Box art for a Game, or none.
private struct SourceBox: Identifiable {
    let source: String
    let cover: CoverSource?
    let image: NSImage?

    var id: String { source }

    static let loading = ["libretro", "LaunchBox"].map { SourceBox(source: $0, cover: nil, image: nil) }

    /// Where it came from: libretro's path, or LaunchBox's file name.
    var detail: String? {
        switch cover {
        case .libretro(_, let path): path
        case .launchBox(_, let file): file
        default: nil
        }
    }
}

/// A source's box at tile size, opening full size when clicked, or a note that it has none.
private struct SourceBoxView: View {
    let box: SourceBox
    let loading: Bool
    let name: String
    @State private var enlarged = false
    @State private var full: NSImage?

    var body: some View {
        if let image = box.image {
            Image(nsImage: image).resizable().interpolation(.high).antialiased(true).scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .onTapGesture { enlarged = true }
                .help(box.detail ?? "")
                .sheet(isPresented: $enlarged) {
                    let screen = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1200, height: 900)
                    Image(nsImage: full ?? image).resizable().interpolation(.high).antialiased(true).scaledToFit()
                        .frame(maxWidth: screen.width * 0.9, maxHeight: screen.height * 0.9)
                        .accessibilityLabel("\(name), \(box.source)")
                        .contentShape(Rectangle())
                        .onTapGesture { enlarged = false }
                        .onExitCommand { enlarged = false }
                        .task {
                            if let cover = box.cover { full = await decodeCover(cover, pixels: nil) }
                        }
                }
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(.quaternary)
                if loading {
                    ProgressView().controlSize(.small)
                } else {
                    Text("No box").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(width: 150, height: 200)
        }
    }
}
