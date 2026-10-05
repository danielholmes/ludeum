import JournalCore
import SwiftUI
import UniformTypeIdentifiers

/// A Game's Cover: my upload, else Box art, else IGDB's Cover art (downloaded on demand), else a
/// placeholder with the Game's name.
struct CoverView: View {
    let services: Services
    let game: GameID
    let name: String
    /// Takes the image's own shape (no tile around it) once there is one; Game detail uses this.
    var fitsImage = false
    @State private var image: NSImage?

    init(services: Services, game: GameID, name: String, fitsImage: Bool = false) {
        self.services = services
        self.game = game
        self.name = name
        self.fitsImage = fitsImage
        // Already loaded: show it at once, with no placeholder flash.
        _image = State(initialValue: services.memory.cover(game, revision: services.changes.coverRevision) ?? nil)
    }

    var body: some View {
        Group {
            if fitsImage, let image {
                Image(nsImage: image).resizable().interpolation(.high).antialiased(true).scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                tile
            }
        }
        .task(id: CoverKey(game: game, revision: services.changes.coverRevision)) {
            image = await loadCover(services, game)
        }
    }

    private var tile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(.quaternary)
            if let image {
                // Fit, not fill: box scans come in every shape (SNES boxes are landscape), and a
                // filled image grows past the tile. High-quality interpolation keeps downscaling smooth.
                Image(nsImage: image).resizable().interpolation(.high).antialiased(true).scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text(name).font(.caption).foregroundStyle(.secondary).padding(6).multilineTextAlignment(.center)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private struct CoverKey: Equatable {
        let game: GameID
        let revision: Int
    }
}

/// The Cover's image, or nil for the placeholder (including when it couldn't be fetched).
@MainActor func loadCover(_ services: Services, _ game: GameID) async -> NSImage? {
    let revision = services.changes.coverRevision
    if let cached = services.memory.cover(game, revision: revision) { return cached }
    guard let source = try? await services.covers?.cover(for: game) else { return nil }  // a failed download: try again later
    // Decode off the main thread.
    let image = await Task.detached(priority: .userInitiated) { () -> NSImage? in
        let image: NSImage? =
            switch source {
            case .upload(let cover): NSImage(data: cover.jpeg)
            case .libretro(let file, _), .openEmu(let file, _), .igdb(let file, _): NSImage(contentsOf: file)
            case .placeholder: nil
            }
        // Force the decode now rather than at first draw.
        _ = image?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        return image
    }.value
    services.memory.store(cover: image, for: game, revision: revision)
    return image
}

/// Game detail's Cover, with Upload, Replace and Remove (by picker or drag-and-drop) on any Game.
struct CoverEditor: View {
    let services: Services
    let game: GameID
    let name: String
    @State private var hasUpload = false
    @State private var choosing = false
    @State private var dropTargeted = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CoverView(services: services, game: game, name: name)
                .frame(width: 150, height: 200)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.accentColor, lineWidth: dropTargeted ? 3 : 0))
                .onDrop(of: [.image, .fileURL], isTargeted: $dropTargeted, perform: drop)
            HStack {
                Button(hasUpload ? "Replace…" : "Upload…") { choosing = true }
                if hasUpload { Button("Remove") { change { try $0.remove(for: game) } } }
            }
            .controlSize(.small)
            Text("Or drop an image on the Cover.").font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .fileImporter(isPresented: $choosing, allowedContentTypes: [.image]) { result in
            guard case .success(let url) = result else { return }
            upload(url)
        }
        .task(id: services.changes.revision) { hasUpload = (try? services.journal?.uploadedCover(game)) != nil }
    }

    private func drop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                Task { @MainActor in
                    if let url, url.isFileURL { upload(url) } else { error = "Couldn't read that file." }
                }
            }
        } else {
            // An image dragged from a browser or another app arrives as image data.
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                Task { @MainActor in
                    if let data { change { try $0.upload(data, for: game) } } else { error = "Couldn't read that image." }
                }
            }
        }
        return true
    }

    /// Reads and normalises off the main thread.
    private func upload(_ url: URL) {
        change { covers in
            let data = try await Task.detached(priority: .userInitiated) {
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                return try Data(contentsOf: url)
            }.value
            try covers.upload(data, for: game)
        }
    }

    private func change(_ action: @escaping @Sendable (Covers) async throws -> Void) {
        guard let covers = services.covers else { return }
        Task {
            do {
                try await action(covers)
                error = nil
                services.changes.coverChanged()
            } catch CoverError.notAnImage {
                error = "That isn't an image macOS can read."
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
