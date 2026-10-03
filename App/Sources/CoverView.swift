import JournalCore
import SwiftUI
import UniformTypeIdentifiers

/// A Game's Cover: IGDB's (downloaded on demand), else the journal's own, else a placeholder
/// with the Game's name.
struct CoverView: View {
    let services: Services
    let game: GameID
    let name: String
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(.quaternary)
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Text(name).font(.caption).foregroundStyle(.secondary).padding(6).multilineTextAlignment(.center)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .task(id: CoverKey(game: game, revision: services.changes.revision)) {
            image = await loadCover(services, game)
        }
    }

    private struct CoverKey: Equatable {
        let game: GameID
        let revision: Int
    }
}

/// The Cover's image, or nil for the placeholder (including when it couldn't be fetched).
@MainActor func loadCover(_ services: Services, _ game: GameID) async -> NSImage? {
    switch try? await services.covers?.cover(for: game) {
    case .igdb(let file): NSImage(contentsOf: file)
    case .journal(let cover): NSImage(data: cover.image.jpeg)
    case .placeholder, nil: nil
    }
}

/// Game detail's Cover, with Upload, Replace and Remove (by picker or drag-and-drop) while IGDB has none.
struct CoverEditor: View {
    let services: Services
    let game: GameID
    let name: String
    @State private var canUpload = false
    @State private var hasJournalCover = false
    @State private var choosing = false
    @State private var dropTargeted = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CoverView(services: services, game: game, name: name)
                .frame(width: 150, height: 200)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.accentColor, lineWidth: dropTargeted ? 3 : 0))
                .onDrop(of: [.image, .fileURL], isTargeted: $dropTargeted, perform: drop)
            if canUpload {
                HStack {
                    Button(hasJournalCover ? "Replace…" : "Upload…") { choosing = true }
                    if hasJournalCover { Button("Remove") { change { try await $0.remove(for: game) } } }
                }
                .controlSize(.small)
                Text("Or drop an image on the Cover.").font(.caption).foregroundStyle(.secondary)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .fileImporter(isPresented: $choosing, allowedContentTypes: [.image]) { result in
            guard case .success(let url) = result else { return }
            upload(url)
        }
        .task(id: services.changes.revision) { await refresh() }
    }

    private func refresh() async {
        guard let covers = services.covers else { return }
        canUpload = (try? await covers.canUpload(for: game)) ?? false
        hasJournalCover = (try? services.journal?.journalCover(game)) != nil
    }

    private func drop(_ providers: [NSItemProvider]) -> Bool {
        guard canUpload, let provider = providers.first else { return false }
        if provider.canLoadObject(ofClass: URL.self) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { Task { @MainActor in upload(url) } }
            }
        } else {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                if let data { Task { @MainActor in change { try await $0.upload(data, for: game) } } }
            }
        }
        return true
    }

    private func upload(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            error = "Couldn't read that file."
            return
        }
        change { try await $0.upload(data, for: game) }
    }

    private func change(_ action: @escaping (Covers) async throws -> Void) {
        guard let covers = services.covers else { return }
        Task {
            do {
                try await action(covers)
                error = nil
                services.changes.changed()
            } catch CoverError.notAnImage {
                error = "That isn't an image macOS can read."
            } catch CoverError.igdbHasACover {
                error = "IGDB has a cover for this Game, so it can't be replaced."
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
