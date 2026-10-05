import JournalCore
import SwiftUI

/// Counts changes to the journal. Views reload with `.task(id: changes.revision)`.
@Observable @MainActor final class JournalChanges {
    private(set) var revision = 0
    /// Bumped only when a Cover changes, so the covers view doesn't refetch on every edit.
    private(set) var coverRevision = 0
    func changed() { revision += 1 }
    func coverChanged() {
        coverRevision += 1
        revision += 1
    }
}

/// What the app's screens work with: the journal, and IGDB when credentials are set.
@MainActor struct Services {
    let settings: AppSettings
    let journal: JournalStore?
    /// Bumped after every change to the journal, so the screens showing it reload.
    let changes = JournalChanges()
    /// Decoded Covers and genres, shared by every screen.
    let memory = MemoryCache()
    /// The launch refresh, Import and Sync exclusivity, and the journal's edit lock.
    let work = BackgroundWork()
    /// Opened once; nil if it couldn't be.
    let cache: CacheStore?

    init(settings: AppSettings, journal: JournalStore?) {
        self.settings = settings
        self.journal = journal
        cache = try? CacheStore(directory: CacheStore.defaultDirectory)
    }

    /// Nil until IGDB credentials are set in Settings. Cheap to make: the token lives in the Keychain.
    var igdb: IGDBClient? {
        guard let credentials = settings.igdbCredentials, let cache else { return nil }
        return IGDBClient(credentials: credentials, cache: cache, tokenStore: settings.secrets)
    }

    var hasheous: HasheousClient? { cache.map { HasheousClient(cache: $0, apiKey: settings.hasheousKey) } }

    var reviewQueue: ReviewQueue? {
        guard let igdb, let journal else { return nil }
        return ReviewQueue(journal: journal, igdb: igdb)
    }

    var gameSearch: GameSearch? {
        guard let igdb, let journal else { return nil }
        return GameSearch(igdb: igdb, journal: journal)
    }

    var libretro: LibretroThumbnails? { cache.map { LibretroThumbnails(cache: $0) } }

    var covers: Covers? { journal.map { Covers(journal: $0, cache: cache, igdb: igdb, libretro: libretro) } }
}

/// The one IGDB search component: a search box, an optional Platform filter, and results with
/// their platforms as chips. What a chip does is up to the caller (add a Game, or link one).
struct IGDBSearchView: View {
    let search: GameSearch
    let platforms: [IGDBPlatform]
    let usedPlatforms: Set<Int64>
    @Binding var query: String
    @State var platformFilter: IGDBPlatform?
    /// Linking a Game: the Platform filter is fixed and each result has one Link button instead of chips.
    var linking = false
    /// Browsing (the IGDB screen): results are selectable and list their platforms; a selected one is shown in full.
    var browse: ((GameSearchResult?) -> Void)? = nil
    /// The journal's change count: browsing re-reads which results are in the Library when it changes.
    var revision = 0
    /// A chip was chosen: the result and the platform (a listed one, or one from "Different platform…").
    let choose: (GameSearchResult, IGDBPlatform) -> Void

    @State private var results: [GameSearchResult] = []
    @State private var error: String?
    @State private var searching = false
    @State private var choosingPlatformFor: GameSearchResult?
    /// Bumped by each search, so only the latest one's answer is shown.
    @State private var generation = 0
    @State private var selected: Int64?
    /// Browsing: each result's chips as the Library is now.
    @State private var current: [Int64: [PlatformChip]] = [:]
    @State private var sort = GameSearchSort.name
    @State private var ascending = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Search IGDB", text: $query).textFieldStyle(.roundedBorder).onSubmit(run)
                if linking {
                    Text(platformFilter?.name ?? "").foregroundStyle(.secondary)
                } else {
                    PlatformMenu(title: platformFilter?.name ?? "Any platform", platforms: platforms, used: usedPlatforms, allowsAny: true)
                    {
                        platformFilter = $0
                        run()
                    }
                    .frame(maxWidth: 200)
                }
                if browse != nil {
                    Menu("Sort", systemImage: "arrow.up.arrow.down") {
                        // Choosing a sort also sets its usual order; Order can still flip it.
                        Picker(
                            "Sort by",
                            selection: Binding(
                                get: { sort },
                                set: {
                                    sort = $0
                                    ascending = $0.defaultAscending
                                })
                        ) {
                            Text("Name").tag(GameSearchSort.name)
                            Text("Release date").tag(GameSearchSort.releaseDate)
                        }
                        Picker("Order", selection: $ascending) {
                            Text("Ascending").tag(true)
                            Text("Descending").tag(false)
                        }
                    }
                    .fixedSize()
                }
                if searching { ProgressView().controlSize(.small) }
            }
            if let error { Text(error).foregroundStyle(.red) }
            List(
                browse == nil ? results : sort.sorted(results, ascending: ascending), selection: browse == nil ? .constant(nil) : $selected
            ) { result in
                HStack(alignment: .top, spacing: 8) {
                    ResultCover(search: search, result: result)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(result.name).font(.headline)
                            if let year = result.year { Text(String(year)).foregroundStyle(.secondary) }
                            if let type = result.gameType {
                                Text(type).font(.caption).padding(.horizontal, 4).background(.quaternary, in: .capsule)
                            }
                        }
                        if linking, let platform = platformFilter {
                            Button("Link") { choose(result, platform) }.controlSize(.small)
                        } else if browse != nil {
                            let chips = current[result.id] ?? result.chips
                            HStack(spacing: 6) {
                                if chips.contains(where: { $0.game != nil }) {
                                    Label("In Library", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
                                }
                                Text(chips.map { chipText($0) }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                            }
                        } else {
                            PlatformChips(
                                result: result, choose: { choose(result, $0) }, differentPlatform: { choosingPlatformFor = result })
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .sheet(item: $choosingPlatformFor) { result in
            PlatformPickerSheet(platforms: platforms, used: usedPlatforms) { choice in
                choosingPlatformFor = nil
                if case .platform(let platform) = choice { choose(result, platform) }
            }
        }
        .onAppear { if !query.isEmpty { run() } }
        .onChange(of: selected) { browse?(results.first { $0.id == selected }) }
        .task(id: CurrentChipsKey(results: results.map(\.id), revision: revision)) {
            guard browse != nil else { return }
            current = Dictionary(uniqueKeysWithValues: results.map { ($0.id, (try? search.currentChips(for: $0)) ?? $0.chips) })
        }
    }

    private func run() {
        let query = query
        let platform = platformFilter?.id
        generation += 1
        let mine = generation
        searching = true
        Task {
            do {
                let found = try await search.search(query, platform: platform)
                guard mine == generation else { return }
                results = found
                error = nil
            } catch {
                guard mine == generation else { return }
                self.error = "Search failed: \(error.localizedDescription)"
            }
            searching = false
        }
    }
}

private struct CurrentChipsKey: Equatable {
    let results: [Int64]
    let revision: Int
}

/// A platform's short name, ticked when it's in the Library.
private func chipText(_ chip: PlatformChip) -> String {
    let name = chip.platform.abbreviation ?? chip.platform.name
    return chip.game == nil ? name : "\(name) ✓"
}

/// A result's IGDB cover, from the cache (downloaded once).
private struct ResultCover: View {
    let search: GameSearch
    let result: GameSearchResult
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: 3).fill(.quaternary)
            }
        }
        .frame(width: 36, height: 48)
        .task(id: result.coverImageID) {
            guard let url = try? await search.cover(for: result) else { return }
            image = NSImage(contentsOf: url)
        }
    }
}

private struct PlatformChips: View {
    let result: GameSearchResult
    let choose: (IGDBPlatform) -> Void
    let differentPlatform: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(result.chips, id: \.platform.id) { chip in
                Button {
                    choose(chip.platform)
                } label: {
                    Text(
                        chip.game == nil
                            ? chip.platform.abbreviation ?? chip.platform.name
                            : "\(chip.platform.abbreviation ?? chip.platform.name) · In Library")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(chip.game == nil ? nil : .green)
            }
            Button("Different platform…", action: differentPlatform).buttonStyle(.hover).controlSize(.small)
        }
    }
}

/// A menu of Platforms, mine first.
struct PlatformMenu: View {
    let title: String
    let platforms: [IGDBPlatform]
    let used: Set<Int64>
    var allowsAny = false
    let choose: (IGDBPlatform?) -> Void
    @State private var picking = false

    var body: some View {
        Button(title) { picking = true }
            .sheet(isPresented: $picking) {
                PlatformPickerSheet(platforms: platforms, used: used, allowsAny: allowsAny) { choice in
                    picking = false
                    switch choice {
                    case .platform(let platform): choose(platform)
                    case .any: choose(nil)
                    case .cancel: break
                    }
                }
            }
    }
}

/// Every IGDB platform, type to filter, with the Platforms my Games use listed first.
struct PlatformPickerSheet: View {
    enum Choice {
        case platform(IGDBPlatform)
        /// "Any platform", offered only when `allowsAny`.
        case any
        case cancel
    }

    let platforms: [IGDBPlatform]
    let used: Set<Int64>
    var allowsAny = false
    let done: (Choice) -> Void
    @State private var filter = ""

    var body: some View {
        VStack(alignment: .leading) {
            TextField("Filter platforms", text: $filter).textFieldStyle(.roundedBorder)
            List(platformPickerOrder(platforms, used: used, filter: filter)) { platform in
                Button {
                    done(.platform(platform))
                } label: {
                    HStack {
                        Text(platform.name)
                        Spacer()
                        if used.contains(platform.id) { Text("Mine").font(.caption).foregroundStyle(.secondary) }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            HStack {
                if allowsAny { Button("Any platform") { done(.any) } }
                Spacer()
                Button("Cancel", role: .cancel) { done(.cancel) }
            }
        }
        .padding()
        .frame(width: 360, height: 420)
    }
}

/// A Game with no IGDB link: name and Platform required, with a warning (never a block) when
/// a Game on that Platform has a name that agrees.
struct AddByHandSheet: View {
    let journal: JournalStore
    let platforms: [IGDBPlatform]
    let used: Set<Int64>
    @State var name: String
    let done: (GameID?) -> Void
    @State private var platform: IGDBPlatform?
    @State private var similar: [Game] = []
    @State private var error: String?

    init(journal: JournalStore, platforms: [IGDBPlatform], used: Set<Int64>, name: String, done: @escaping (GameID?) -> Void) {
        self.journal = journal
        self.platforms = platforms
        self.used = used
        _name = State(initialValue: name)
        self.done = done
    }

    var body: some View {
        Form {
            TextField("Name", text: $name)
            LabeledContent("Platform") {
                PlatformMenu(title: platform?.name ?? "Choose…", platforms: platforms, used: used) { platform = $0 }
            }
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { done(nil) }
                Button("Add", action: add).keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || platform == nil)
            }
        }
        .padding()
        .frame(width: 420)
        .confirmationDialog(
            "A Game with this name is already on \(platform?.name ?? "this Platform")",
            isPresented: Binding(get: { !similar.isEmpty }, set: { if !$0 { similar = [] } })
        ) {
            ForEach(similar, id: \.id) { game in Button("Open \(game.name)") { done(game.id) } }
            Button("Add anyway") { insert() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Two games on one platform can share a name, so this is only a warning.")
        }
    }

    private func add() {
        guard let platform else { return }
        do {
            similar = try journal.gamesWhoseNamesAgree(with: name, platformId: platform.id)
            if similar.isEmpty { insert() }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func insert() {
        guard let platform else { return }
        do {
            try journal.addPlatform(id: platform.id, name: platform.name)
            done(try journal.addGameByHand(name: name, platformId: platform.id))
        } catch {
            self.error = "Couldn't add it: \(error.localizedDescription)"
        }
    }
}

/// Linking a hand-made Game later: the same search, filtered to its Platform.
struct LinkGameSheet: View {
    let search: GameSearch
    let game: Game
    let platform: IGDBPlatform
    /// A Game with no ROMs can move to another Platform with its new link: each result offers its platforms.
    let canChangePlatform: Bool
    let linked: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query: String
    @State private var error: String?
    @State private var allPlatforms: [IGDBPlatform] = []

    init(search: GameSearch, game: Game, platform: IGDBPlatform, canChangePlatform: Bool = false, linked: @escaping () -> Void) {
        self.search = search
        self.game = game
        self.platform = platform
        self.canChangePlatform = canChangePlatform
        self.linked = linked
        _query = State(initialValue: game.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(game.igdbGameId == nil ? "Link \(game.name) to IGDB" : "Change \(game.name)'s IGDB link").font(.title2)
            if canChangePlatform {
                Text("It has no ROMs, so it can move to another Platform: choose the platform on a result.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            IGDBSearchView(
                search: search, platforms: canChangePlatform && !allPlatforms.isEmpty ? allPlatforms : [platform],
                usedPlatforms: [platform.id], query: $query, platformFilter: platform, linking: !canChangePlatform
            ) {
                result, chosen in
                do {
                    try search.link(
                        game.id, to: result, replacing: game.igdbGameId != nil,
                        platform: canChangePlatform && chosen.id != platform.id ? chosen : nil)
                    linked()
                    dismiss()
                } catch JournalError.igdbLinkTaken {
                    let holder = (try? search.journalGame(igdbGameId: result.igdbGameId, platformId: platform.id))?.name ?? "another Game"
                    error = "Already linked to \(holder)."
                } catch {
                    self.error = "Couldn't link it: \(error.localizedDescription)"
                }
            }
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
            }
        }
        .padding()
        .frame(width: 640, height: 520)
        .task { if canChangePlatform { allPlatforms = (try? await search.platforms()) ?? [] } }
    }
}
