import AppKit
import LudeumCore
import SwiftUI

/// The Review queue, Mail-style: item kinds with counts, that kind's items, and the selected item.
struct ReviewQueueScreen: View {
    let services: Services
    /// Re-reads the ROM folders (an Import).
    let checkAgain: () -> Void
    /// The Game shown in the detail column: set to the Game an answer gave the ROM.
    @Binding var shownGame: GameID?

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
                    DuplicateVersionsDetail(item: d, checkAgain: checkAgain)
                } else if let item = romItems.first(where: { $0.romId == selection }) {
                    ReviewItemDetail(services: services, item: item, failed: { error = $0 }, answered: { shownGame = $0 })
                } else {
                    ContentUnavailableView(items.count == 0 ? "Nothing to review" : "Choose an item", systemImage: "tray")
                }
            }
            .frame(minWidth: 646, idealWidth: 823, maxWidth: .infinity, maxHeight: .infinity)
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

    /// The ids listed in the middle column, in order.
    private var listedIDs: [Int64] { kind == .duplicateVersions ? items.duplicateVersions.map(\.id) : romItems.map(\.romId) }

    private func reload() {
        do {
            let before = listedIDs
            items = try services.journal?.reviewQueue() ?? ReviewQueueItems()
            // The selected item was answered: move to the next one (else the one before), for quick review.
            let after = Set(listedIDs)
            if let selected = selection, !after.contains(selected), let index = before.firstIndex(of: selected) {
                selection = before[(index + 1)...].first(where: after.contains) ?? before[..<index].last(where: after.contains)
            }
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
    /// The Game the ROM now belongs to, to show in the detail column.
    let answered: (GameID) -> Void

    @State private var suggestion: IGDBGame?
    /// A Search IGDB result I picked: shown as the suggestion until I Confirm it.
    @State private var picked: (igdbGameId: Int64, name: String, platform: IGDBPlatform)?
    @State private var checksumGame: IGDBGame?
    @State private var platforms: [IGDBPlatform] = []
    /// Every IGDB platform, for Make by hand's "any other Platform".
    @State private var allPlatforms: [IGDBPlatform] = []
    @State private var searching = false
    @State private var assigning = false
    @State private var makingByHand = false
    @State private var duplicateWarning: (() -> Void)?

    /// This ROM beside the suggestion, row by row: name, platform (shared ones highlighted), region and year.
    @ViewBuilder private var comparison: some View {
        let rom = ROMName(item.romName)
        let romPlatforms = Set(platforms.map(\.id))
        let suggested = (suggestion?.record["platforms"]?.array ?? []).compactMap { p -> (id: Int64, name: String)? in
            guard let id = p["id"]?.int, let name = p["name"]?.string else { return nil }
            return (Int64(id), name)
        }
        let releases = suggestion?.releases(onPlatform: item.platformId) ?? []
        Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                Text("")
                Text("This ROM").font(.caption.bold()).foregroundStyle(.secondary)
                Text("Suggestion").font(.caption.bold()).foregroundStyle(.secondary)
            }
            Divider().gridCellUnsizedAxes(.horizontal)
            GridRow {
                label("Name")
                Text(cleanName(item.romName)).fontWeight(.semibold).fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(suggestion?.name ?? picked?.name ?? "IGDB #\(item.suggestedIgdbGameId ?? 0)").fontWeight(.semibold)
                        .fixedSize(horizontal: false, vertical: true)
                    if picked == nil {
                        Image(systemName: item.namesAgree ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(item.namesAgree ? .green : .orange)
                            .help(item.namesAgree ? "Names agree" : "Names don't agree")
                    }
                }
            }
            GridRow {
                label("Platform")
                Text(platforms.map(\.name).joined(separator: " or ")).fixedSize(horizontal: false, vertical: true)
                FlowLayout(spacing: 4) {
                    // The ROM's own platforms first, highlighted.
                    ForEach(suggested.sorted { romPlatforms.contains($0.id) && !romPlatforms.contains($1.id) }, id: \.id) { p in
                        let match = romPlatforms.contains(p.id)
                        Text(p.name).font(.caption).padding(.horizontal, 6).padding(.vertical, 1)
                            .foregroundStyle(match ? Color.white : Color.secondary)
                            .background(match ? AnyShapeStyle(Color.green) : AnyShapeStyle(.quaternary), in: .capsule)
                    }
                    if !suggested.isEmpty, !suggested.contains(where: { romPlatforms.contains($0.id) }) {
                        Label("Not on this platform", systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
                    }
                }
            }
            GridRow {
                label("Region")
                Text(rom.regions.map(regionText) ?? "Not in the name").foregroundStyle(rom.regions == nil ? .secondary : .primary)
                if releases.isEmpty {
                    Text("No releases listed").foregroundStyle(.secondary)
                } else {
                    // Green where a release matches the ROM's region; red when the ROM names a region none match.
                    let matching = Set(releases.map(\.region).filter { region in rom.regions.map { regionMatches(region, $0) } ?? false })
                    FlowLayout(spacing: 4) {
                        ForEach(releases, id: \.region) { r in
                            let match = matching.contains(r.region)
                            Text(r.year.map { "\(r.region) \($0)" } ?? r.region).font(.caption)
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .foregroundStyle(match ? Color.white : Color.secondary)
                                .background(match ? AnyShapeStyle(Color.green) : AnyShapeStyle(.quaternary), in: .capsule)
                        }
                        if rom.regions != nil, matching.isEmpty {
                            Label("No release in this ROM's region", systemImage: "xmark.octagon.fill").font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    .help("Releases on this ROM's platform")
                }
            }
            GridRow {
                label("Year")
                Text("–").foregroundStyle(.secondary)
                Text(suggestion?.facts.releaseYear.map(String.init) ?? "–")
            }
        }
    }

    private func label(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary).gridColumnAlignment(.leading)
    }

    /// Whether an IGDB release region covers any of the ROM's regions. Australia and New Zealand count as
    /// Europe (PAL releases).
    private func regionMatches(_ release: String, _ regions: Set<NameRegion>) -> Bool {
        switch release {
        case "Worldwide": true
        case "North America": regions.contains(.usa)
        case "Europe", "Australia", "New Zealand": regions.contains(.europe)
        case "Japan": regions.contains(.japan)
        case "Korea": regions.contains(.korea)
        default: false
        }
    }

    private func regionText(_ regions: Set<NameRegion>) -> String {
        [(NameRegion.usa, "USA"), (.europe, "Europe"), (.japan, "Japan"), (.korea, "Korea")].filter { regions.contains($0.0) }
            .map(\.1).joined(separator: ", ")
    }

    var body: some View {
        Form {
            Section {
                Text(item.romName).font(.title2).bold()
                LabeledContent("Platform", value: platforms.map(\.name).joined(separator: " or "))
                Text(reason).foregroundStyle(.secondary)
                if item.missing { Text("Its file is missing from its ROM folder.").foregroundStyle(.orange) }
            }
            if item.suggestedIgdbGameId != nil || picked != nil {
                Section(picked == nil ? "Suggestion" : "Picked from search") {
                    if picked == nil, let checksumGame { Text(checksumGame.name ?? "").strikethrough().foregroundStyle(.secondary) }
                    HStack(alignment: .top, spacing: 16) {
                        SuggestionCover(services: services, game: suggestion).frame(width: 180, height: 240)
                        VStack(alignment: .leading, spacing: 10) {
                            comparison
                            let developers = suggestion?.facts.credits.filter { $0.roles.contains(.developer) }.map(\.name) ?? []
                            if !developers.isEmpty {
                                Text("Developer: " + developers.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                            }
                            if let type = suggestion?.record["game_type"]?.int, type != 0 { Text("game_type \(type)").font(.caption) }
                        }
                    }
                    HStack {
                        Button("Confirm", action: confirm).buttonStyle(.borderedProminent)
                        if picked != nil {
                            Button(item.suggestedIgdbGameId == nil ? "Clear" : "Back to the suggestion") {
                                Task { await load() }
                            }
                        }
                    }
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
                    // Show it for comparison first; Confirm matches it.
                    picked = (result.igdbGameId, result.name, platform)
                    Task { await showPicked() }
                }
            }
        }
        .sheet(isPresented: $assigning) {
            AssignToGameSheet(services: services) { game in
                let assign = {
                    act {
                        try services.journal?.assign(item, to: game)
                        return game
                    }
                }
                if (try? services.journal?.wouldHaveDuplicateVersions(game, adding: item.romId)) == true {
                    warnAfterSheetCloses(assign)
                } else {
                    assign()
                }
            }
        }
        .sheet(isPresented: $makingByHand) {
            MakeByHandSheet(name: cleanName(item.romName), platforms: platforms, allPlatforms: allPlatforms) { name, platform in
                act { try services.journal?.makeByHand(item, name: name, platform: platform) }
            }
        }
        .confirmationDialog(
            "This gives the Game Duplicate Versions",
            isPresented: Binding(get: { duplicateWarning != nil }, set: { if !$0 { duplicateWarning = nil } })
        ) {
            Button("Match anyway") { duplicateWarning?() }
        } message: {
            Text("It's still Matched, but the Game shows under Duplicate Versions until you remove ROMs from its ROM folder.")
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

    /// Loads the picked search result's record into the suggestion.
    private func showPicked() async {
        guard let picked, let igdb = services.igdb else { return }
        suggestion = (try? await igdb.games(ids: [Int(picked.igdbGameId)]))?[Int(picked.igdbGameId)]
    }

    private func load() async {
        picked = nil
        suggestion = nil
        checksumGame = nil
        let ids = [item.platformId]
        let all = (try? await services.igdb?.platforms()) ?? []
        allPlatforms = all
        platforms = ids.compactMap { id in all.first { $0.id == id } }
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
        if let picked {
            act { try await queue.choose(item, igdbGameId: picked.igdbGameId, name: picked.name, platform: picked.platform) }
            return
        }
        Task {
            if (try? await queue.confirmWouldGiveDuplicateVersions(item)) == true {
                duplicateWarning = { act { try await queue.confirm(item) } }
            } else {
                act { try await queue.confirm(item) }
            }
        }
    }

    /// Runs an answer, then shows the Game the ROM went to.
    private func act(_ answer: @escaping () async throws -> GameID?) {
        Task {
            do {
                let game = try await answer()
                failed(nil)
                if let game { answered(game) }
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

/// Make by hand…: a Game with no IGDB link, its Platform pre-selected from the ROM's.
private struct MakeByHandSheet: View {
    @State var name: String
    /// The ROM's Platform, offered first.
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

/// A Duplicate Versions item: the Game and its present ROMs. It's resolved only by removing ROMs from its ROM folder.
private struct DuplicateVersionsDetail: View {
    let item: DuplicateVersionsGame
    let checkAgain: () -> Void

    var body: some View {
        Form {
            Section {
                Text(item.game.name).font(.title2).bold()
                Text("Remove all but one Version from its ROM folder, then Check again. Real exceptions need a code change.")
                    .foregroundStyle(.secondary)
            }
            Section("Present ROMs") {
                ForEach(item.roms) { rom in
                    VStack(alignment: .leading) {
                        Text(rom.version.isEmpty ? rom.fileName : rom.version).bold()
                        Text(rom.fileName).font(.caption)
                    }
                }
            }
            Button("Check again", action: checkAgain)
        }
        .formStyle(.grouped)
    }
}
