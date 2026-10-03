import AppKit
import JournalCore
import SwiftUI

/// The Review queue, Mail-style: item kinds with counts, that kind's items, and the selected item.
struct ReviewQueueScreen: View {
    let services: Services

    enum Kind: String, CaseIterable, Identifiable {
        case namesAgree = "Names agree"
        case checksum = "Checksum suggestions"
        case name = "Name suggestions"
        case noSuggestion = "No suggestion"
        case duplicateVersions = "Duplicate Versions"
        var id: Self { self }
    }

    @State private var items = ReviewQueueItems()
    @State private var kind: Kind? = .namesAgree
    @State private var selection: Int64?
    @State private var error: String?
    @State private var confirmingAll = false
    /// Suggested IGDB games' names, for the middle column.
    @State private var suggestionNames: [Int64: String] = [:]

    var body: some View {
        HSplitView {
            List(Kind.allCases, selection: $kind) { kind in
                Text(kind.rawValue).badge(count(kind)).tag(kind)
            }
            .frame(minWidth: 170, idealWidth: 190, maxWidth: 240)

            VStack(alignment: .leading, spacing: 0) {
                if kind == .namesAgree, !items.namesAgree.isEmpty {
                    Button("Confirm all \(items.namesAgree.count)") { confirmingAll = true }.padding(8)
                }
                List(selection: $selection) {
                    if kind == .duplicateVersions {
                        ForEach(items.duplicateVersions) { d in
                            VStack(alignment: .leading) {
                                Text(d.game.name)
                                Text("\(d.roms.count) present ROMs").font(.caption).foregroundStyle(.secondary)
                            }
                            .tag(d.id)
                        }
                    } else {
                        ForEach(romItems) { item in
                            VStack(alignment: .leading) {
                                Text(item.romName)
                                Text(item.suggestedIgdbGameId.map { suggestionNames[$0] ?? "IGDB #\($0)" } ?? "Search IGDB by hand")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            .tag(item.romId)
                        }
                    }
                }
            }
            .frame(minWidth: 240, idealWidth: 300)

            Group {
                if kind == .duplicateVersions, let d = items.duplicateVersions.first(where: { $0.id == selection }) {
                    DuplicateVersionsDetail(item: d) { reload() }
                } else if let item = romItems.first(where: { $0.romId == selection }) {
                    ReviewItemDetail(services: services, item: item) { error = $0 }
                } else {
                    ContentUnavailableView(items.count == 0 ? "Nothing to review" : "Choose an item", systemImage: "tray")
                }
            }
            .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Review queue")
        .overlay(alignment: .bottom) {
            if let error { Text(error).foregroundStyle(.white).padding(8).background(.red, in: .rect(cornerRadius: 6)).padding() }
        }
        .task(id: services.changes.revision) {
            reload()
            await loadSuggestionNames()
        }
        .onChange(of: kind) { selection = nil }
        .confirmationDialog("Confirm all \(items.namesAgree.count) suggestions whose names agree?", isPresented: $confirmingAll) {
            Button("Confirm all") { confirmAll() }
        } message: {
            Text("Each ROM is Matched to its suggestion. To keep one out, answer it on its own first.")
        }
    }

    private var romItems: [ReviewItem] {
        switch kind {
        case .namesAgree: items.namesAgree
        case .checksum: items.checksumSuggestions
        case .name: items.nameSuggestions
        case .noSuggestion: items.noSuggestion
        case .duplicateVersions, nil: []
        }
    }

    private func count(_ kind: Kind) -> Int {
        switch kind {
        case .namesAgree: items.namesAgree.count
        case .checksum: items.checksumSuggestions.count
        case .name: items.nameSuggestions.count
        case .noSuggestion: items.noSuggestion.count
        case .duplicateVersions: items.duplicateVersions.count
        }
    }

    private func reload() {
        do {
            items = try services.journal?.reviewQueue() ?? ReviewQueueItems()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func loadSuggestionNames() async {
        let ids = (items.namesAgree + items.checksumSuggestions + items.nameSuggestions).compactMap(\.suggestedIgdbGameId)
        guard let igdb = services.igdb, !ids.isEmpty, let games = try? await igdb.games(ids: ids.map(Int.init)) else { return }
        suggestionNames = games.reduce(into: [:]) { $0[Int64($1.key)] = $1.value.name }
    }

    private func confirmAll() {
        guard let queue = services.reviewQueue else { return }
        Task {
            do {
                _ = try await queue.confirmAll()
                error = nil
            } catch {
                self.error = "Confirm all stopped: \(error.localizedDescription)"
            }
            services.changes.changed()
        }
    }
}

/// A ROM item: why it's here, its suggestion, and Confirm / Search IGDB… / Assign to Game… / Make by hand….
private struct ReviewItemDetail: View {
    let services: Services
    let item: ReviewItem
    let failed: (String?) -> Void

    @State private var suggestion: IGDBGame?
    @State private var checksumGame: IGDBGame?
    @State private var platforms: [IGDBPlatform] = []
    /// Every IGDB platform, for Make by hand's "any other Platform".
    @State private var allPlatforms: [IGDBPlatform] = []
    @State private var searching = false
    @State private var assigning = false
    @State private var makingByHand = false
    @State private var duplicateWarning: (() -> Void)?

    var body: some View {
        Form {
            Section {
                Text(item.romName).font(.title2).bold()
                LabeledContent("Platform", value: platforms.map(\.name).joined(separator: " or "))
                Text(reason).foregroundStyle(.secondary)
                if item.missing { Text("Its file is missing from OpenEmu.").foregroundStyle(.orange) }
            }
            if item.suggestedIgdbGameId != nil {
                Section("Suggestion") {
                    if let checksumGame { Text(checksumGame.name ?? "").strikethrough().foregroundStyle(.secondary) }
                    HStack(alignment: .top) {
                        SuggestionCover(services: services, game: suggestion).frame(width: 60, height: 80)
                        VStack(alignment: .leading) {
                            Text(suggestion?.name ?? "IGDB #\(item.suggestedIgdbGameId!)").font(.headline)
                            if let type = suggestion?.record["game_type"]?.int, type != 0 { Text("game_type \(type)").font(.caption) }
                            Label(
                                item.namesAgree ? "Names agree" : "Names don't agree", systemImage: item.namesAgree ? "checkmark" : "xmark"
                            )
                            .font(.caption).foregroundStyle(item.namesAgree ? .green : .orange)
                        }
                    }
                    Button("Confirm", action: confirm).buttonStyle(.borderedProminent)
                }
            }
            Section {
                Button("Search IGDB…") { searching = true }.disabled(services.gameSearch == nil)
                Button("Assign to Game…") { assigning = true }
                Button("Make by hand…") { makingByHand = true }
            }
        }
        .formStyle(.grouped)
        .task(id: item.romId) { await load() }
        .sheet(isPresented: $searching) {
            if let search = services.gameSearch {
                ReviewSearchSheet(search: search, item: item, platforms: platforms) { result, platform in
                    act {
                        try await services.reviewQueue?.choose(item, igdbGameId: result.igdbGameId, name: result.name, platform: platform)
                    }
                }
            }
        }
        .sheet(isPresented: $assigning) {
            AssignToGameSheet(services: services) { game in
                let assign = { act { try services.journal?.assign(item, to: game) } }
                if (try? services.journal?.wouldHaveDuplicateVersions(game, adding: item.romId)) == true {
                    warnAfterSheetCloses(assign)
                } else {
                    assign()
                }
            }
        }
        .sheet(isPresented: $makingByHand) {
            MakeByHandSheet(name: cleanName(item.romName), platforms: platforms, allPlatforms: allPlatforms) { name, platform in
                act { _ = try services.journal?.makeByHand(item, name: name, platform: platform) }
            }
        }
        .confirmationDialog(
            "This gives the Game Duplicate Versions",
            isPresented: Binding(get: { duplicateWarning != nil }, set: { if !$0 { duplicateWarning = nil } })
        ) {
            Button("Match anyway") { duplicateWarning?() }
        } message: {
            Text("It's still Matched, but the Game shows under Duplicate Versions until you remove ROMs in OpenEmu.")
        }
    }

    private var reason: String {
        switch (item.suggestionKind, item.namesAgree, item.checksumIgdbGameId) {
        case (nil, _, _): "Nothing matched its checksum or name."
        case (.checksum, true, _?): "Its checksum's game has a related record whose name agrees."
        case (.checksum, true, nil): "Its checksum matched and the names agree."
        case (.checksum, false, _): "Its checksum matched, but the names don't agree."
        case (.name, true, _): "Found by name search, and the names agree."
        case (.name, false, _): "Found by name search, but the names don't agree."
        }
    }

    private func load() async {
        suggestion = nil
        checksumGame = nil
        let ids = openEmuSystemPlatforms[item.systemId] ?? []
        let all = (try? await services.igdb?.platforms()) ?? []
        allPlatforms = all
        platforms = ids.compactMap { id in all.first { $0.id == Int64(id) } }
        guard let igdb = services.igdb else { return }
        let wanted = [item.suggestedIgdbGameId, item.checksumIgdbGameId].compactMap { $0.map(Int.init) }
        let games = (try? await igdb.games(ids: wanted)) ?? [:]
        suggestion = item.suggestedIgdbGameId.flatMap { games[Int($0)] }
        checksumGame = item.checksumIgdbGameId.flatMap { games[Int($0)] }
    }

    /// A sheet that's closing can't present the warning, so it waits a moment.
    private func warnAfterSheetCloses(_ match: @escaping () -> Void) {
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            duplicateWarning = match
        }
    }

    private func confirm() {
        guard let queue = services.reviewQueue else { return }
        Task {
            if (try? await queue.confirmWouldGiveDuplicateVersions(item)) == true {
                duplicateWarning = { act { try await queue.confirm(item) } }
            } else {
                act { try await queue.confirm(item) }
            }
        }
    }

    private func act(_ answer: @escaping () async throws -> Void) {
        Task {
            do {
                try await answer()
                failed(nil)
            } catch {
                failed(journalErrorText(error))
            }
            services.changes.changed()
        }
    }
}

private struct SuggestionCover: View {
    let services: Services
    let game: IGDBGame?
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4).fill(.quaternary)
            if let image { Image(nsImage: image).resizable().scaledToFit() }
        }
        .task(id: game?.id) {
            guard let id = game?.record["cover"]?["image_id"]?.string, let file = try? await services.igdb?.cover(imageID: id) else {
                image = nil
                return
            }
            image = NSImage(contentsOf: file)
        }
    }
}

/// Search IGDB…: the shared search, its Platform filter pre-set to the ROM's platforms.
private struct ReviewSearchSheet: View {
    let search: GameSearch
    let item: ReviewItem
    let platforms: [IGDBPlatform]
    let choose: (GameSearchResult, IGDBPlatform) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Match \(item.romName)").font(.title2)
            IGDBSearchView(
                search: search, platforms: platforms, usedPlatforms: Set(platforms.map(\.id)), query: $query,
                platformFilter: platforms.first
            ) {
                result, platform in
                choose(result, platform)
                dismiss()
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
            }
        }
        .padding()
        .frame(width: 640, height: 520)
        .onAppear { query = cleanName(item.romName) }
    }
}

/// Assign to Game…: pick an existing Game, e.g. for a fan translation.
private struct AssignToGameSheet: View {
    let services: Services
    let choose: (GameID) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var filter = ""
    @State private var rows: [LibraryRow] = []

    var body: some View {
        VStack(alignment: .leading) {
            Text("Assign to Game").font(.title2)
            TextField("Filter Games", text: $filter).textFieldStyle(.roundedBorder)
            List(rows.filter { filter.isEmpty || $0.name.localizedCaseInsensitiveContains(filter) }) { row in
                Button {
                    choose(row.id)
                    dismiss()
                } label: {
                    HStack {
                        Text(row.name)
                        Spacer()
                        Text(row.platformName).foregroundStyle(.secondary)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
            }
        }
        .padding()
        .frame(width: 480, height: 480)
        .onAppear { rows = (try? services.journal?.library(LibraryFilter(), sort: .name, ascending: true)) ?? [] }
    }
}

/// Make by hand…: a Game with no IGDB link, its Platform pre-selected from the ROM's system.
private struct MakeByHandSheet: View {
    @State var name: String
    /// The ROM's system's platforms, offered first.
    let platforms: [IGDBPlatform]
    let allPlatforms: [IGDBPlatform]
    let make: (String, IGDBPlatform) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var platform: IGDBPlatform?

    var body: some View {
        Form {
            TextField("Name", text: $name)
            LabeledContent("Platform") {
                HStack {
                    if !platforms.isEmpty {
                        Picker("Platform", selection: $platform) {
                            ForEach(platforms) { Text($0.name).tag(IGDBPlatform?.some($0)) }
                            if let platform, !platforms.contains(platform) { Text(platform.name).tag(IGDBPlatform?.some(platform)) }
                        }
                        .labelsHidden()
                    }
                    PlatformMenu(title: "Other…", platforms: allPlatforms, used: Set(platforms.map(\.id))) { platform = $0 }
                }
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Make Game") {
                    if let platform { make(name, platform) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || platform == nil)
            }
        }
        .padding()
        .frame(width: 400)
        .onAppear { platform = platforms.first }
    }
}

/// A Duplicate Versions item: the Game and its present ROMs. It's resolved only by removing ROMs in OpenEmu.
private struct DuplicateVersionsDetail: View {
    let item: DuplicateVersionsGame
    let checkAgain: () -> Void

    var body: some View {
        Form {
            Section {
                Text(item.game.name).font(.title2).bold()
                Text("Remove all but one Version in OpenEmu, then Check again. Real exceptions need a code change.")
                    .foregroundStyle(.secondary)
            }
            Section("Present ROMs") {
                ForEach(item.roms) { rom in
                    VStack(alignment: .leading) {
                        Text(rom.version.isEmpty ? rom.fileName : rom.version).bold()
                        Text(rom.fileName).font(.caption)
                        Text("Played \(rom.playCount) times, \(Int(rom.playTimeSeconds / 60)) min").font(.caption).foregroundStyle(
                            .secondary)
                    }
                }
            }
            Button("Check again", action: checkAgain)
            Text("Check again uses the last Import. Run an Import after removing ROMs in OpenEmu.").font(.caption).foregroundStyle(
                .secondary)
        }
        .formStyle(.grouped)
    }
}
