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
        case noPlaylist = "No playlist"
        case missingROMs = "Missing ROMs"
        case oldMissingROMs = "Old missing ROMs"
        case bothForms = "In both forms"
        case notCompacted = "Not compacted"
        var id: Self { self }
    }

    @State private var items = ReviewQueueItems()
    @State private var kind: Kind? = .namesAgree
    @State private var selection: Int64?
    /// Selected once `kind` changes, which otherwise clears the selection.
    @State private var selectAfterKindChange: Int64?
    @State private var error: String?
    @State private var confirmingAll = false
    @State private var compactingAll = false
    /// Suggested IGDB games' names, for the middle column.
    @State private var suggestionNames: [Int64: String] = [:]

    /// The narrowest each column goes. The kinds and items columns stay near it; the item's detail takes the rest.
    private static let kindsMinWidth: CGFloat = 170
    private static let itemsMinWidth: CGFloat = 220
    private static let detailMinWidth: CGFloat = 320
    /// The narrowest the screen goes: each column at its narrowest, and the two dividers.
    static let minWidth = kindsMinWidth + itemsMinWidth + detailMinWidth + 2

    var body: some View {
        HSplitView {
            List(Kind.allCases, selection: $kind) { kind in
                Text(kind.rawValue).badge(count(kind)).tag(kind)
            }
            .frame(minWidth: Self.kindsMinWidth, idealWidth: 190, maxWidth: 200)

            VStack(alignment: .leading, spacing: 0) {
                if kind == .namesAgree, !items.namesAgree.isEmpty {
                    Button("Confirm all \(items.namesAgree.count)") { confirmingAll = true }.padding(8)
                }
                if kind == .notCompacted, !notCompactedIdle.isEmpty {
                    Button("Compact all \(notCompactedIdle.count)") { compactingAll = true }.padding(8)
                }
                List(selection: $selection) {
                    if kind == .notCompacted {
                        ForEach(items.notCompacted) { item in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(item.rom.name)
                                    Text("\(item.rom.fileName) → \(item.compactFileName)").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let task = services.tasks.active(.rom(item.id)) { BackgroundTaskProgress(task: task) }
                            }
                            .tag(item.id)
                        }
                    } else if kind == .bothForms {
                        ForEach(items.bothForms) { item in
                            VStack(alignment: .leading) {
                                Text(item.rom.name)
                                Text(item.rom.fileName).font(.caption).foregroundStyle(.secondary)
                            }
                            .tag(item.id)
                        }
                    } else if kind == .duplicateVersions {
                        ForEach(items.duplicateVersions) { d in
                            VStack(alignment: .leading) {
                                Text(d.game.name)
                                Text("\(d.roms.count) present ROMs").font(.caption).foregroundStyle(.secondary)
                            }
                            .tag(d.id)
                        }
                    } else if kind == .noPlaylist {
                        ForEach(items.noPlaylist) { item in
                            VStack(alignment: .leading) {
                                Text(item.romName)
                                Text("Discs with no playlist").font(.caption).foregroundStyle(.secondary)
                            }
                            .tag(item.romId)
                        }
                    } else if kind == .missingROMs {
                        ForEach(items.missingROMs) { m in
                            VStack(alignment: .leading) {
                                Text(m.game.name)
                                Text(m.roms.count == 1 ? "1 missing ROM" : "\(m.roms.count) missing ROMs")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            .tag(m.id)
                        }
                    } else if kind == .oldMissingROMs {
                        ForEach(items.oldMissingROMs) { m in
                            VStack(alignment: .leading) {
                                Text(m.game.name)
                                Text(
                                    "\(m.missing.count) old missing ROM\(m.missing.count == 1 ? "" : "s") · "
                                        + "\(m.present.count) present"
                                )
                                .font(.caption).foregroundStyle(.secondary)
                            }
                            .tag(m.id)
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
            .frame(minWidth: Self.itemsMinWidth, idealWidth: 260, maxWidth: 300)

            Group {
                if kind == .duplicateVersions, let d = items.duplicateVersions.first(where: { $0.id == selection }) {
                    DuplicateVersionsDetail(
                        services: services, item: d, checkAgain: checkAgain, showGame: { shownGame = d.id },
                        showSplitOff: { version in
                            // Straight to the split-off ROM, to Match it.
                            selectAfterKindChange = version.first?.id
                            kind = .noSuggestion
                        }, failed: { error = $0 })
                } else if kind == .missingROMs, let m = items.missingROMs.first(where: { $0.id == selection }) {
                    MissingROMsDetail(
                        services: services, item: m, checkAgain: checkAgain, showGame: { shownGame = m.id }, failed: { error = $0 })
                } else if kind == .oldMissingROMs, let m = items.oldMissingROMs.first(where: { $0.id == selection }) {
                    OldMissingROMsDetail(
                        services: services, item: m, checkAgain: checkAgain, showGame: { shownGame = m.id }, failed: { error = $0 })
                } else if kind == .noPlaylist, let item = items.noPlaylist.first(where: { $0.id == selection }) {
                    NoPlaylistDetail(services: services, item: item, failed: { error = $0 })
                } else if kind == .bothForms, let item = items.bothForms.first(where: { $0.id == selection }) {
                    BothFormsDetail(
                        services: services, item: item, checkAgain: checkAgain, showGame: { shownGame = $0 }, failed: { error = $0 })
                } else if kind == .notCompacted, let item = items.notCompacted.first(where: { $0.id == selection }) {
                    NotCompactedDetail(services: services, item: item, showGame: { shownGame = $0 })
                } else if let item = romItems.first(where: { $0.romId == selection }) {
                    ReviewItemDetail(services: services, item: item, failed: { error = $0 }, answered: { shownGame = $0 })
                } else {
                    ContentUnavailableView(items.count == 0 ? "Nothing to review" : "Choose an item", systemImage: "tray")
                }
            }
            .frame(minWidth: Self.detailMinWidth, maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Review queue")
        .overlay(alignment: .bottom) {
            if let error { Text(error).foregroundStyle(.white).padding(8).background(.red, in: .rect(cornerRadius: 6)).padding() }
        }
        .task(id: services.changes.revision) {
            reload()
            await loadSuggestionNames()
        }
        .onChange(of: kind) {
            selection = selectAfterKindChange
            selectAfterKindChange = nil
        }
        .confirmationDialog("Confirm all \(items.namesAgree.count) suggestions whose names agree?", isPresented: $confirmingAll) {
            Button("Confirm all") { confirmAll() }
        } message: {
            Text("Each ROM is Matched to its suggestion. To keep one out, answer it on its own first.")
        }
        .confirmationDialog("Compact all \(notCompactedIdle.count) ROMs?", isPresented: $compactingAll) {
            Button("Compact all") {
                for item in notCompactedIdle { compact(item, services: services) }
            }
        } message: {
            Text(
                "Each is packed into the archive its Emulator opens directly, one at a time in Background tasks. The files they "
                    + "replace go to the Trash. Online-only files download first.")
        }
    }

    /// The Not compacted items no Background task is working on yet.
    private var notCompactedIdle: [NotCompactedROM] { items.notCompacted.filter { services.tasks.active(.rom($0.id)) == nil } }

    private var romItems: [ReviewItem] {
        switch kind {
        case .namesAgree: items.namesAgree
        case .checksum: items.checksumSuggestions
        case .name: items.nameSuggestions
        case .noSuggestion: items.noSuggestion
        case .duplicateVersions, .noPlaylist, .missingROMs, .oldMissingROMs, .bothForms, .notCompacted, nil: []
        }
    }

    private func count(_ kind: Kind) -> Int {
        switch kind {
        case .namesAgree: items.namesAgree.count
        case .checksum: items.checksumSuggestions.count
        case .name: items.nameSuggestions.count
        case .noSuggestion: items.noSuggestion.count
        case .duplicateVersions: items.duplicateVersions.count
        case .noPlaylist: items.noPlaylist.count
        case .missingROMs: items.missingROMs.count
        case .oldMissingROMs: items.oldMissingROMs.count
        case .bothForms: items.bothForms.count
        case .notCompacted: items.notCompacted.count
        }
    }

    /// The ids listed in the middle column, in order.
    private var listedIDs: [Int64] {
        switch kind {
        case .duplicateVersions: items.duplicateVersions.map(\.id)
        case .noPlaylist: items.noPlaylist.map(\.id)
        case .missingROMs: items.missingROMs.map(\.id)
        case .oldMissingROMs: items.oldMissingROMs.map(\.id)
        case .bothForms: items.bothForms.map(\.id)
        case .notCompacted: items.notCompacted.map(\.id)
        default: romItems.map(\.romId)
        }
    }

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
    /// The ROM's Platform, once IGDB's list of platforms is loaded.
    @State private var romPlatform: IGDBPlatform?
    /// The Platform Confirm matches on: one of `item.platformChoices`, at first the one the suggestion is on.
    @State private var confirmPlatform: Int64 = 0
    /// Every IGDB platform, for Make by hand's "any other Platform".
    @State private var allPlatforms: [IGDBPlatform] = []
    @State private var searching = false
    @State private var assigning = false
    @State private var makingByHand = false
    @State private var deleting = false
    @State private var duplicateWarning: (() -> Void)?
    /// The ROM itself, for Play.
    @State private var rom: LudeumROM?
    @State private var playError: String?
    @State private var versionAlert: (title: String, message: String)?

    /// This ROM beside the suggestion, row by row: name, platform (shared ones highlighted), region and year.
    @ViewBuilder private var comparison: some View {
        let rom = ROMName(item.romName)
        let onROMPlatform = { (id: Int64) in id == item.platformId }
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
                Text(romPlatform?.name ?? "").fixedSize(horizontal: false, vertical: true)
                FlowLayout(spacing: 4) {
                    // The ROM's own Platform first, highlighted.
                    ForEach(suggested.sorted { onROMPlatform($0.id) && !onROMPlatform($1.id) }, id: \.id) { p in
                        let match = onROMPlatform(p.id)
                        Text(p.name).font(.caption).padding(.horizontal, 6).padding(.vertical, 1)
                            .foregroundStyle(match ? Color.white : Color.secondary)
                            .background(match ? AnyShapeStyle(Color.green) : AnyShapeStyle(.quaternary), in: .capsule)
                    }
                    if !suggested.isEmpty, !suggested.contains(where: { onROMPlatform($0.id) }) {
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

    /// The comparison, then the suggestion's developers and its IGDB game type.
    private var suggestionFacts: some View {
        VStack(alignment: .leading, spacing: 10) {
            comparison
            let developers = suggestion?.facts.credits.filter { $0.roles.contains(.developer) }.map(\.name) ?? []
            if !developers.isEmpty {
                Text("Developer: " + developers.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
            }
            if let type = suggestion?.record["game_type"]?.int, type != 0 { Text("game_type \(type)").font(.caption) }
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
                LabeledContent("Platform", value: romPlatform?.name ?? "")
                Text(reason).foregroundStyle(.secondary)
                if item.missing { Text("Its file is missing from its ROM folder.").foregroundStyle(.orange) }
                if let emulator = playableEmulator { playControls(emulator) }
            }
            if item.suggestedIgdbGameId != nil || picked != nil {
                Section(picked == nil ? "Suggestion" : "Picked from search") {
                    if picked == nil, let checksumGame { Text(checksumGame.name ?? "").strikethrough().foregroundStyle(.secondary) }
                    // The cover art beside the comparison while that leaves it room, else smaller and above it.
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 16) {
                            SuggestionCover(services: services, game: suggestion).frame(width: 180, height: 240)
                            suggestionFacts.frame(minWidth: 280, idealWidth: 280, maxWidth: .infinity, alignment: .leading)
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            SuggestionCover(services: services, game: suggestion).frame(width: 120, height: 160)
                            suggestionFacts
                        }
                    }
                    FlowLayout(spacing: 8) {
                        Button("Confirm", action: confirm).buttonStyle(.borderedProminent)
                        if picked == nil, item.platformChoices.count > 1 {
                            Picker("on", selection: $confirmPlatform) {
                                ForEach(item.platformChoices, id: \.self) { id in
                                    Text(ROMPlatform.all[id]?.name ?? "Platform \(id)").tag(id)
                                }
                            }
                            .fixedSize()
                            .help("Another Platform moves the ROM into its ROM folder")
                        }
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
                if item.suggestedIgdbGameId == nil {
                    Button("Delete ROM…", role: .destructive) { deleting = true }
                        .disabled(services.tasks.isActive(.rom(item.romId)))
                        .help(item.missing ? "Delete it: its file is gone already" : "Send its files to the Trash, and delete it")
                }
            }
        }
        .formStyle(.grouped)
        .task(id: item.romId) { await load() }
        .sheet(isPresented: $searching) {
            if let search = services.gameSearch {
                ReviewSearchSheet(search: search, item: item, romPlatform: romPlatform) { result, platform in
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
            MakeByHandSheet(name: cleanName(item.romName), romPlatform: romPlatform, allPlatforms: allPlatforms) { name, platform in
                act { try services.journal?.makeByHand(item, name: name, platform: platform) }
            }
        }
        .confirmationDialog(
            "This gives the Game Duplicate Versions",
            isPresented: Binding(get: { duplicateWarning != nil }, set: { if !$0 { duplicateWarning = nil } })
        ) {
            Button("Match anyway") { duplicateWarning?() }
        } message: {
            Text("It's still Matched, but the Game shows under Duplicate Versions until it's left with one Version.")
        }
        .confirmationDialog(item.missing ? "Delete \(item.romName)?" : "Send \(item.romName) to the Trash?", isPresented: $deleting) {
            Button("Delete ROM", role: .destructive, action: delete)
        } message: {
            Text(item.missing ? "It leaves the Review queue." : "Its files go to the Trash and it leaves the Review queue.")
        }
        .alert(
            versionAlert?.title ?? "", isPresented: Binding(get: { versionAlert != nil }, set: { if !$0 { versionAlert = nil } })
        ) {
            Button("OK") {}
        } message: {
            Text(versionAlert?.message ?? "")
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

    /// A No suggestion ROM's Emulator, to Play it and see what it is: none for a missing ROM, a Platform with no
    /// Emulator, or one the launch check found isn't installed.
    private var playableEmulator: Emulator? {
        guard item.suggestedIgdbGameId == nil, !item.missing, let emulator = Emulator.of(platformId: item.platformId),
            !services.versions.notInstalled.contains(emulator.bundleIdentifier)
        else { return nil }
        return emulator
    }

    /// The ROM's Play, with its default Emulator settings: settings are kept per Game, and it has none yet.
    private var playing: Play? {
        rom.map { rom in
            Play(
                platformId: item.platformId, platformName: ROMPlatform.all[item.platformId]?.name ?? "", roms: [rom],
                settings: EmulatorSettings(), busyROMs: services.tasks.isActive(.rom(rom.id)) ? [rom.id] : [])
        }
    }

    @ViewBuilder private func playControls(_ emulator: Emulator) -> some View {
        let refusal = playing?.availability.refusal
        Button {
            guard let playing else { return }
            playError = nil
            startPlay(playing, in: emulator, services: services, refused: { playError = $0 }, alert: { versionAlert = ($0, $1) })
        } label: {
            Label("Play", systemImage: "play.fill")
        }
        .buttonStyle(.borderedProminent)
        .tint(services.versions.tooOldMessage(emulator) == nil ? nil : .red)
        .disabled(playing == nil || refusal != nil)
        .help(refusal?.message ?? "Play in \(emulator.name), to see what it is")
        if let message = playError ?? refusal?.message ?? services.versions.tooOldMessage(emulator) {
            Text(message).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Loads the picked search result's record into the suggestion.
    private func showPicked() async {
        guard let picked, let igdb = services.igdb else { return }
        suggestion = (try? await igdb.games(ids: [Int(picked.igdbGameId)]))?[Int(picked.igdbGameId)]
    }

    private func load() async {
        picked = nil
        playError = nil
        rom = try? services.journal?.rom(item.romId)
        suggestion = nil
        checksumGame = nil
        confirmPlatform = item.platformId
        let all = (try? await services.igdb?.platforms()) ?? []
        allPlatforms = all
        romPlatform = all.first { $0.id == item.platformId }
        guard let igdb = services.igdb else { return }
        let wanted = [item.suggestedIgdbGameId, item.checksumIgdbGameId].compactMap { $0.map(Int.init) }
        let games = (try? await igdb.games(ids: wanted)) ?? [:]
        suggestion = item.suggestedIgdbGameId.flatMap { games[Int($0)] }
        checksumGame = item.checksumIgdbGameId.flatMap { games[Int($0)] }
        // The ROM's own Platform if the suggestion is on it, else the first sibling it is on.
        let listed = Set((suggestion?.record["platforms"]?.array ?? []).compactMap { $0["id"]?.int ?? $0.int }.map(Int64.init))
        if !listed.contains(item.platformId), let sibling = item.platformChoices.first(where: listed.contains) {
            confirmPlatform = sibling
        }
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
        let platform = confirmPlatform
        Task {
            if (try? await queue.confirmWouldGiveDuplicateVersions(item, on: platform)) == true {
                duplicateWarning = { act { try await queue.confirm(item, on: platform) } }
            } else {
                act { try await queue.confirm(item, on: platform) }
            }
        }
    }

    private func delete() {
        do {
            try services.journal?.deleteROM(item, romFolders: services.settings.romFolders)
            failed(nil)
        } catch {
            failed(journalErrorText(error))
        }
        services.changes.changed()
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

/// Search IGDB…: the shared search, its Platform filter pre-set to the ROM's Platform.
private struct ReviewSearchSheet: View {
    let search: GameSearch
    let item: ReviewItem
    let romPlatform: IGDBPlatform?
    let choose: (GameSearchResult, IGDBPlatform) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Match \(item.romName)").font(.title2)
            IGDBSearchView(
                search: search, platforms: romPlatform.map { [$0] } ?? [], usedPlatforms: Set(romPlatform.map { [$0.id] } ?? []),
                query: $query,
                platformFilter: romPlatform
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
    let romPlatform: IGDBPlatform?
    let allPlatforms: [IGDBPlatform]
    let make: (String, IGDBPlatform) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var platform: IGDBPlatform?

    var body: some View {
        Form {
            TextField("Name", text: $name)
            LabeledContent("Platform") {
                HStack {
                    if let romPlatform {
                        Picker("Platform", selection: $platform) {
                            Text(romPlatform.name).tag(IGDBPlatform?.some(romPlatform))
                            if let platform, platform != romPlatform { Text(platform.name).tag(IGDBPlatform?.some(platform)) }
                        }
                        .labelsHidden()
                    }
                    PlatformMenu(title: "Other…", platforms: allPlatforms, used: Set(romPlatform.map { [$0.id] } ?? [])) {
                        platform = $0
                    }
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
        .onAppear { platform = romPlatform }
    }
}

/// A Duplicate Versions item: the Game and its present ROMs by Version. I Keep only one Version (the rest go to the Trash),
/// or Split one into its own Game, to be Matched again; or remove ROMs from its ROM folder myself and Check again.
private struct DuplicateVersionsDetail: View {
    let services: Services
    let item: DuplicateVersionsGame
    let checkAgain: () -> Void
    let showGame: () -> Void
    /// Shows the Version's ROMs, Split off and waiting to be Matched.
    let showSplitOff: ([LudeumROM]) -> Void
    let failed: (String?) -> Void
    @State private var keeping: [LudeumROM]?

    var body: some View {
        Form {
            Section {
                Text(item.game.name).font(.title2).bold()
                Text(
                    "It has more than one Version. Keep only one, sending the rest to the Trash, or Split one into its own Game "
                        + "if it's a different game (a re-release IGDB lists apart, say). Real exceptions need a code change."
                )
                .foregroundStyle(.secondary)
            }
            ForEach(Array(item.versions.enumerated()), id: \.offset) { _, version in
                Section {
                    ForEach(version) { ROMRow(rom: $0) }
                    FlowLayout(spacing: 8) {
                        Button("Keep only this Version") { keeping = version }
                            .help("Sends the other Versions' ROMs to the Trash, and deletes them")
                        Button("Split into its own Game") { split(version) }
                            .help("Takes it off this Game, to be Matched again from No suggestion")
                    }
                    .disabled(busy)
                }
            }
            FlowLayout(spacing: 8) {
                Button("Show Game", action: showGame)
                Button("Check again", action: checkAgain)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "Send the other Versions to the Trash?", isPresented: Binding(get: { keeping != nil }, set: { if !$0 { keeping = nil } })
        ) {
            Button("Keep only this Version") { keeping.map(keepOnly) }
        } message: {
            Text("Their ROMs go to the Trash and \(item.game.name) keeps its journal data.")
        }
    }

    /// A Background task is queued or working on one of its ROMs.
    private var busy: Bool { item.roms.contains { services.tasks.isActive(.rom($0.id)) } }

    private func keepOnly(_ version: [LudeumROM]) {
        guard let journal = services.journal else { return }
        do {
            try journal.keepOnly(version, of: item, romFolders: services.settings.romFolders)
            failed(nil)
        } catch {
            failed(journalErrorText(error))
        }
        services.changes.coverChanged()
    }

    private func split(_ version: [LudeumROM]) {
        guard let journal = services.journal else { return }
        do {
            try journal.splitOff(version, from: item)
            failed(nil)
            showSplitOff(version)
        } catch {
            failed(journalErrorText(error))
        }
        services.changes.coverChanged()
    }
}

/// A No playlist item: the ROM's Discs, and Make playlist, which writes one into its subfolder.
private struct NoPlaylistDetail: View {
    let services: Services
    let item: NoPlaylistItem
    let failed: (String?) -> Void
    @State private var discs: [URL] = []

    var body: some View {
        Form {
            Section {
                Text(item.romName).font(.title2).bold()
                Text("Its folder holds its Discs but no playlist, so Play can't open them all. Make playlist writes one.")
                    .foregroundStyle(.secondary)
            }
            Section("Discs") {
                ForEach(discs, id: \.self) { Text($0.lastPathComponent) }
            }
            Button("Make playlist", action: makePlaylist)
        }
        .formStyle(.grouped)
        .task(id: item) { discs = (try? romFolder?.discsWithoutPlaylist(named: item.romName)) ?? [] }
    }

    private var romFolder: ROMFolder? { services.settings.romFolders.first { $0.platformId == item.platformId } }

    private func makePlaylist() {
        guard let journal = services.journal else { return }
        do {
            try journal.makePlaylist(item, romFolders: services.settings.romFolders)
            failed(nil)
        } catch {
            failed(journalErrorText(error))
        }
        services.changes.changed()
    }
}

/// A Missing ROMs item: a Game whose ROMs are all gone from its ROM folder. I Add a ROM, put a file back and Check
/// again, or delete its missing ROMs (and then, if I like, the Game).
private struct MissingROMsDetail: View {
    let services: Services
    let item: MissingROMsGame
    let checkAgain: () -> Void
    let showGame: () -> Void
    let failed: (String?) -> Void
    @State private var picked: PickedROM?

    /// Its Platform keeps each ROM in a subfolder, so a folder is picked.
    private var picksFolder: Bool { ROMPlatform.all[item.game.platformId]?.archiving == .intoFolder }

    var body: some View {
        Form {
            Section {
                HStack {
                    Text(item.game.name).font(.title2).bold()
                    Button("Copy name", systemImage: "doc.on.doc") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(item.game.name, forType: .string)
                    }
                    .labelStyle(.iconOnly).buttonStyle(.hover).help("Copy the Game's name, to search for its ROM")
                }
                Text(
                    "Its ROMs are all missing from its ROM folder. Add a ROM, put one back then Check again, or delete its missing "
                        + "ROMs: the Game stays, as a journal entry I can delete too."
                )
                .foregroundStyle(.secondary)
            }
            Section("Missing ROMs") { ForEach(item.roms) { ROMRow(rom: $0) } }
            FlowLayout(spacing: 8) {
                Button(picksFolder ? "Add ROM folder…" : "Add ROM file…", action: addROM)
                    .help("Choose a ROM for this Game: it goes into its ROM folder, ready to Play")
                Button(item.roms.count == 1 ? "Delete its missing ROM" : "Delete its \(item.roms.count) missing ROMs") {
                    guard let journal = services.journal else { return }
                    do {
                        try journal.deleteMissingROMs(of: item.game.id)
                        failed(nil)
                    } catch {
                        failed(journalErrorText(error))
                    }
                    services.changes.changed()
                }
                .help("They leave the journal with their Copy details. If a file comes back, an Import finds it again.")
                Button("Show Game", action: showGame)
                Button("Check again", action: checkAgain)
            }
        }
        .formStyle(.grouped)
        .sheet(item: $picked) { picked in
            AddROMToGameSheet(services: services, game: item.game, picked: picked, missingROMs: item.roms.count)
        }
    }

    private func addROM() {
        guard let urls = pickROM(folders: picksFolder) else { return }
        let platform = item.game.platformId
        Task {
            do {
                let read = try await readPicked(urls)
                guard read.platforms.contains(platform) else {
                    throw AddROMError.platformWontReadIt(ROMPlatform.all[platform]?.name ?? "Its Platform")
                }
                failed(nil)
                picked = read
            } catch {
                failed(journalErrorText(error))
            }
        }
    }
}

/// An Old missing ROMs item: a Game that still has a present ROM, with missing ones left over. Its files, present and
/// missing, side by side, so I can Delete the old ones (one at a time, or all), or put a file back and Check again.
private struct OldMissingROMsDetail: View {
    let services: Services
    let item: OldMissingROMsGame
    let checkAgain: () -> Void
    let showGame: () -> Void
    let failed: (String?) -> Void

    var body: some View {
        Form {
            Section {
                Text(item.game.name).font(.title2).bold()
                Text(
                    "It still has \(item.present.count == 1 ? "a ROM" : "ROMs") in its ROM folder, so these missing ones are "
                        + "likely old: a file renamed or replaced. Delete them, or put one back, then Check again."
                )
                .foregroundStyle(.secondary)
            }
            Section("Present") { ForEach(item.present) { ROMRow(rom: $0) } }
            Section("Missing") {
                ForEach(item.missing) { rom in
                    HStack {
                        ROMRow(rom: rom)
                        Spacer()
                        Button("Delete") { delete { try $0.deleteROM(rom.id, romFolders: []) } }
                            .help("Delete this missing ROM from the journal. If its file comes back, an Import finds it again.")
                    }
                }
            }
            FlowLayout(spacing: 8) {
                Button(item.missing.count == 1 ? "Delete it" : "Delete all \(item.missing.count)") {
                    delete { try $0.deleteMissingROMs(of: item.game.id) }
                }
                .help("Delete its missing ROMs from the journal. Its present ones stay.")
                Button("Show Game", action: showGame)
                Button("Check again", action: checkAgain)
            }
        }
        .formStyle(.grouped)
    }

    private func delete(_ write: (LudeumStore) throws -> Void) {
        guard let journal = services.journal else { return }
        do {
            try write(journal)
            failed(nil)
        } catch {
            failed(journalErrorText(error))
        }
        services.changes.changed()
    }
}

/// A ROM by its Version text, then its file name.
private struct ROMRow: View {
    let rom: LudeumROM

    var body: some View {
        VStack(alignment: .leading) {
            Text(rom.version.isEmpty ? rom.fileName : rom.version).bold()
            Text(rom.fileName).font(.caption).textSelection(.enabled)
        }
    }
}

/// An In both forms item: the copy of the ROM that's kept and what goes to the Trash, as its ROM folder has them now, and
/// Keep the Playable copy (or Keep the Compacted copy), which sends them there. Once that's done, the item leaves the
/// queue.
private struct BothFormsDetail: View {
    let services: Services
    let item: BothFormsROM
    let checkAgain: () -> Void
    let showGame: (GameID) -> Void
    let failed: (String?) -> Void
    /// Nil until it's read, and when its ROM folder no longer has it in both forms.
    @State private var forms: BothForms?
    @State private var sizes: [URL: Int64] = [:]

    private struct Key: Equatable {
        let item: BothFormsROM
        let revision: Int
    }

    var body: some View {
        Form {
            Section {
                Text(item.rom.name).font(.title2).bold()
                Text(explanation).foregroundStyle(.secondary)
            }
            if let forms {
                Section("Keep") { copy(forms.keep) }
                Section("To the Trash") { ForEach(forms.trash, id: \.self) { copy($0) } }
            }
            FlowLayout(spacing: 8) {
                if let forms {
                    Button(forms.keepsCompacted ? "Keep the Compacted copy" : "Keep the Playable copy") { keep(forms) }
                        .disabled(services.tasks.active(.rom(item.id)) != nil)
                        .help("Sends the rest to the Trash")
                }
                if let game = item.game { Button("Show Game") { showGame(game) } }
                Button("Check again", action: checkAgain)
            }
        }
        .formStyle(.grouped)
        .task(id: Key(item: item, revision: services.changes.revision)) {
            forms = try? romFolder?.bothForms(named: item.rom.folderName)
            sizes = ((forms.map { [$0.keep] + $0.trash }) ?? []).reduce(into: [:]) { $0[$1] = BothForms.size(of: $1) }
        }
    }

    private var romFolder: ROMFolder? { services.settings.romFolders.first { $0.platformId == item.rom.platformId } }

    private var explanation: String {
        guard let forms else { return "Its ROM folder doesn't have it in both forms now. Check again." }
        return forms.keepsCompacted
            ? "It's kept in more than one form at once, wasting room. Its Compacted copy is smaller and still Plays, so that's "
                + "the one to keep: the rest goes to the Trash."
            : "It's kept as a Playable copy and as an Archived .7z at once, wasting room. The Playable copy is the one to "
                + "keep: the .7z goes to the Trash."
    }

    /// A copy's file (or subfolder) and the room it takes.
    private func copy(_ url: URL) -> some View {
        LabeledContent(url.hasDirectoryPath ? url.lastPathComponent + "/" : url.lastPathComponent) {
            if let size = sizes[url] { Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)) }
        }
    }

    private func keep(_ forms: BothForms) {
        guard let journal = services.journal else { return }
        do {
            try journal.keepOneForm(item, as: forms, romFolders: services.settings.romFolders)
            failed(nil)
        } catch {
            failed(journalErrorText(error))
        }
        services.changes.changed()
    }
}

/// A Not compacted item: the ROM, and Compact, which packs it into the archive its Emulator opens directly as a
/// Background task. Once that's done, the item leaves the queue.
private struct NotCompactedDetail: View {
    let services: Services
    let item: NotCompactedROM
    let showGame: (GameID) -> Void

    var body: some View {
        Form {
            Section {
                Text(item.rom.name).font(.title2).bold()
                Text(explanation).foregroundStyle(.secondary)
            }
            Section("Files") {
                LabeledContent("Now", value: item.rom.fileName)
                LabeledContent("Compacted", value: item.compactFileName)
            }
            FlowLayout(spacing: 8) {
                if let task = services.tasks.active(.rom(item.id)) {
                    BackgroundTaskProgress(task: task)
                } else {
                    Button("Compact") { compact(item, services: services) }
                }
                if let game = item.game { Button("Show Game") { showGame(game) } }
            }
        }
        .formStyle(.grouped)
    }

    private var explanation: String {
        let emulator = Emulator.of(platformId: item.rom.platformId)?.name ?? "Its Emulator"
        return item.rom.archived
            ? "\(emulator) can't open its .7z. Compact repacks it as \(item.compactFileName), which \(emulator) opens directly, "
                + "and sends the .7z to the Trash once that checks out."
            : "\(emulator) opens \(item.compactFileName) directly. Compact packs it at maximum compression and sends "
                + "\(item.rom.fileName) to the Trash once the archive checks out."
    }
}

/// Compacts the ROM as a Background task. Once done, whichever screen is showing sees the change, and its Not
/// compacted item is gone.
@MainActor private func compact(_ item: NotCompactedROM, services: Services) {
    ROMArchiving(locator: ROMLocator(romFolders: services.settings.romFolders), journal: services.journal, tasks: services.tasks)
        .start(item.rom) { [changes = services.changes] in changes.changed() }
}
