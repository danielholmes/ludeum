import AppKit
import JournalCore
import SwiftUI

/// Searching IGDB to add Games: results in the middle column, the selected one in full beside it.
/// "Add by hand" at the foot is for Games IGDB doesn't have.
struct IGDBScreen: View {
    let services: Services
    @Binding var query: String
    /// The result shown in the detail column.
    @Binding var shown: GameSearchResult?
    /// A Game added by hand, to open.
    let open: (GameID) -> Void
    @State private var platforms: [IGDBPlatform] = []
    @State private var used: Set<Int64> = []
    @State private var byHand = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let search = services.gameSearch {
                IGDBSearchView(
                    search: search, platforms: platforms, usedPlatforms: used, query: $query, browse: { shown = $0 }, choose: { _, _ in })
            } else {
                ContentUnavailableView(
                    "IGDB isn't set up", systemImage: "key", description: Text("Add IGDB credentials in Settings to search."))
            }
            if let error { Text(error).foregroundStyle(.red) }
            Button("Add by hand…") { byHand = true }.disabled(services.journal == nil || services.work.journalLocked)
        }
        .padding()
        .navigationTitle("IGDB")
        .task {
            used = (try? services.journal?.usedPlatformIDs()) ?? []
            do {
                platforms = try await services.igdb?.platforms() ?? []
            } catch {
                self.error = "Couldn't load IGDB's platforms: \(error.localizedDescription)"
            }
        }
        .sheet(isPresented: $byHand) {
            if let journal = services.journal {
                AddByHandSheet(journal: journal, platforms: platforms, used: used, name: query) { id in
                    byHand = false
                    if let id {
                        services.changes.changed()
                        open(id)
                    }
                }
            }
        }
    }
}

/// An IGDB game in full: its platforms, each added to the Library with a click or marked "In Library"
/// (click to open that Game), then IGDB's facts and screenshots.
struct IGDBGameDetailView: View {
    let services: Services
    let result: GameSearchResult
    let browse: (LibraryFilter) -> Void
    let open: (GameID) -> Void
    @State private var chips: [PlatformChip] = []
    @State private var facts = GameFacts.none
    @State private var cover: NSImage?
    @State private var platforms: [IGDBPlatform] = []
    @State private var used: Set<Int64> = []
    @State private var choosingPlatform = false
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: 16) {
                    Group {
                        if let cover {
                            Image(nsImage: cover).resizable().scaledToFit()
                        } else {
                            RoundedRectangle(cornerRadius: 6).fill(.quaternary).aspectRatio(3 / 4, contentMode: .fit)
                        }
                    }
                    .frame(width: 150).frame(maxHeight: 200, alignment: .top)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(result.name).font(.title).bold()
                        HStack(spacing: 6) {
                            if let year = result.year { Text(String(year)).foregroundStyle(.secondary) }
                            if let type = result.gameType {
                                Text(type).font(.caption).padding(.horizontal, 4).background(.quaternary, in: .capsule)
                            }
                        }
                        FlowLayout(spacing: 6) {
                            ForEach(chips, id: \.platform.id) { chip in
                                if let game = chip.game {
                                    Button { open(game) } label: { Label("\(chip.platform.name) · In Library", systemImage: "checkmark") }
                                        .buttonStyle(.bordered).tint(.green).help("Open this Game")
                                } else {
                                    Button { add(on: chip.platform) } label: { Label(chip.platform.name, systemImage: "plus") }
                                        .buttonStyle(.bordered).help("Add to Library on \(chip.platform.name)")
                                        .disabled(services.work.journalLocked)
                                }
                            }
                            Button("Different platform…") { choosingPlatform = true }.buttonStyle(.hover)
                                .disabled(services.work.journalLocked)
                        }
                        .controlSize(.small)
                        if let error { Text(error).foregroundStyle(.red) }
                        IGDBFactsRows(services: services, facts: facts, browse: browse)
                    }
                }
            }
            if !facts.screenshots.isEmpty, let igdb = services.igdb {
                ScreenshotsSection(igdb: igdb, screenshots: facts.screenshots)
            }
        }
        .formStyle(.grouped)
        .task(id: services.changes.revision) {
            chips = (try? services.gameSearch?.currentChips(for: result)) ?? result.chips
            used = (try? services.journal?.usedPlatformIDs()) ?? []
        }
        .task(id: result.id) {
            if let search = services.gameSearch, let url = try? await search.cover(for: result) { cover = NSImage(contentsOf: url) }
            if let igdb = services.igdb { facts = (try? await igdb.facts(igdbGameId: result.igdbGameId)) ?? .none }
        }
        .sheet(isPresented: $choosingPlatform) {
            PlatformPickerSheet(platforms: platforms, used: used) { choice in
                choosingPlatform = false
                if case .platform(let platform) = choice { add(on: platform) }
            }
            .task { platforms = (try? await services.igdb?.platforms()) ?? [] }
        }
    }

    /// Adds the game to the Library on `platform`, staying here: its chip turns "In Library".
    private func add(on platform: IGDBPlatform) {
        guard let search = services.gameSearch else { return }
        do {
            _ = try search.add(result, on: platform)
            error = nil
            services.changes.changed()
        } catch {
            self.error = "Couldn't add it: \(error.localizedDescription)"
        }
    }
}
