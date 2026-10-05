import AppKit
import JournalCore
import SwiftUI

/// Game detail: the editable right-hand pane. Every change is saved straight away.
struct GameDetailView: View {
    let services: Services
    let id: GameID
    /// Opens the Library with a filter, e.g. every Game in this one's series.
    let browse: (LibraryFilter) -> Void
    /// Called after the Game is deleted.
    let deleted: () -> Void

    @State private var game: Game?
    @State private var platform: IGDBPlatform?
    @State private var history: [RatingEntry] = []
    @State private var playthroughs: [Playthrough] = []
    @State private var allLists: [GameList] = []
    @State private var memberOf: Set<Int64> = []
    @State private var roms: [JournalROM] = []
    @State private var showingHistory = false
    @State private var pins: Set<Pin> = []
    @State private var allScreenshots = false
    @State private var allCompanies = false
    /// Each present ROM file's created and modified dates, by ROM id, read from disk.
    @State private var fileDates: [Int64: (created: Date?, modified: Date?)] = [:]
    @State private var facts = GameFacts.none
    @State private var editing: PlaythroughEdit?
    @State private var linking = false
    @State private var editingGame = false
    @State private var viewing: Screenshot?
    @State private var deletion: DeletionSummary?
    @State private var deletingPlaythrough: Playthrough?
    @State private var error: String?

    var body: some View {
        if let game {
            form(game)
        } else {
            ContentUnavailableView(
                error == nil ? "Game not found" : "Couldn't read this Game", systemImage: "gamecontroller",
                description: error.map(Text.init)
            )
            .task(id: id) { load() }
        }
    }

    private func form(_ game: Game) -> some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: 16) {
                    // The Cover in its own shape (SNES boxes are wide), at the top of its column.
                    CoverView(services: services, game: id, name: game.name, fitsImage: true)
                        .frame(width: 150).frame(maxHeight: 200, alignment: .top)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(game.name).font(.title).bold()
                            Spacer()
                            if !roms.isEmpty, !roms.allSatisfy(\.missing) {
                                Button("Play in OpenEmu", systemImage: "play.fill", action: playInOpenEmu)
                                    .labelStyle(.iconOnly).buttonStyle(.hover).help("Play in OpenEmu")
                            }
                            Button("Edit Game", systemImage: "pencil") { editingGame = true }
                                .labelStyle(.iconOnly).buttonStyle(.hover).help("Name, Cover, IGDB link and deleting")
                        }
                        if let platform {
                            Text([platform.name, facts.releaseYear.map(String.init)].compactMap { $0 }.joined(separator: " · "))
                                .foregroundStyle(.secondary)
                        }
                        RatingEditor(
                            rating: game.rating, imported: game.ratingImported, hasHistory: !history.isEmpty,
                            set: { rating in save { try $0.setRating(id, rating) } }, showHistory: { showingHistory = true })
                        CommunityScores(players: facts.playerScore, critics: facts.criticScore)
                        if !facts.genres.isEmpty { PillRow(title: "Genre", items: facts.genres, open: { browse(LibraryFilter(genre: $0)) }) }
                        if !facts.themes.isEmpty { pinnable("Theme", .theme, facts.themes) }
                        if !facts.franchises.isEmpty { pinnable("Franchise", .franchise, facts.franchises) }
                        if !facts.series.isEmpty { pinnable("Series", .series, facts.series) }
                        if !facts.credits.isEmpty { companies }
                        if !facts.links.isEmpty {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text("Links").font(.caption).foregroundStyle(.secondary).frame(width: 66, alignment: .leading)
                                FlowLayout(spacing: 8) {
                                    ForEach(facts.links, id: \.title) { link in
                                        Link(link.title, destination: link.url).font(.caption).help(link.url.absoluteString)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Section("Intent and Lists") {
                HStack {
                    Picker("Intent", selection: Binding(get: { game.intent }, set: { new in save { try $0.setIntent(id, new) } })) {
                        Text("None").tag(Intent?.none)
                        Text("Backlog").tag(Intent?.some(.backlog))
                        Text("Up next").tag(Intent?.some(.upNext))
                    }
                    .pickerStyle(.segmented)
                    .help(game.intentSetAt.map { "Set \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "")
                    Toggle("Childhood", isOn: Binding(get: { game.childhood }, set: { new in save { try $0.setChildhood(id, new) } }))
                        .toggleStyle(.checkbox).fixedSize()
                }
                LabeledContent("Lists") {
                    // Current Lists as removable pills, then a menu of the rest.
                    FlowLayout(spacing: 6) {
                        ForEach(allLists.filter { memberOf.contains($0.id) }, id: \.id) { list in
                            HStack(spacing: 4) {
                                Text(list.name)
                                Button("Remove from \(list.name)", systemImage: "xmark") {
                                    save { try $0.removeFromList(list.id, id) }
                                }
                                .labelStyle(.iconOnly).buttonStyle(.hover).imageScale(.small)
                            }
                            .padding(.leading, 8).padding(.vertical, 2)
                            .background(.quaternary, in: .capsule)
                        }
                        let others = allLists.filter { !memberOf.contains($0.id) }
                        if !others.isEmpty {
                            Menu("Add to List") {
                                ForEach(others, id: \.id) { list in
                                    Button(list.name) { save { try $0.addToList(list.id, id) } }
                                }
                            }
                            .menuStyle(.borderlessButton).fixedSize().controlSize(.small)
                        }
                    }
                }
            }

            Section {
                ForEach(playthroughs, id: \.id) { p in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(playthroughTitle(p.draft))
                            if let details = playthroughDetails(p.draft) { Text(details).font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        Button("Edit") { editing = PlaythroughEdit(id: p.id, draft: p.draft) }.buttonStyle(.hover)
                        Button("Delete", systemImage: "trash") { deletingPlaythrough = p }.labelStyle(.iconOnly).buttonStyle(.hover)
                    }
                }
                Button("Add Playthrough…") { editing = PlaythroughEdit(id: nil, draft: PlaythroughDraft()) }
            } header: {
                Text("Playthroughs")
            }

            if !facts.screenshots.isEmpty, let igdb = services.igdb {
                Section("Screenshots") {
                    // Two rows of three, then a tile to show the rest.
                    let limit = 6
                    let all = facts.screenshots
                    let collapsed = !allScreenshots && all.count > limit
                    let shown = collapsed ? Array(all.prefix(limit - 1)) : all
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        ForEach(shown, id: \.self) { imageID in
                            ScreenshotImage(igdb: igdb, imageID: imageID, large: false)
                                .aspectRatio(16 / 9, contentMode: .fit)
                                .frame(minWidth: 0)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .onTapGesture { viewing = Screenshot(id: imageID) }
                        }
                        if collapsed {
                            Button { allScreenshots = true } label: {
                                Label("\(all.count - shown.count) more", systemImage: "plus")
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                            }
                            .buttonStyle(.plain)
                            .aspectRatio(16 / 9, contentMode: .fit)
                        }
                    }
                }
            }

            Section("ROMs") {
                if roms.isEmpty {
                    Text("No ROMs").foregroundStyle(.secondary)
                } else {
                    if roms.allSatisfy(\.missing) { Text("No ROM in OpenEmu").foregroundStyle(.orange) }
                    ForEach(roms) { rom in
                        HStack {
                        VStack(alignment: .leading) {
                            // Without its extension; GoodTools region codes spelled out.
                            Text((rom.fileName as NSString).deletingPathExtension).strikethrough(rom.missing)
                            Text(
                                [readableVersion(rom.version), rom.disc.map { "Disc \($0)" }, rom.missing ? "missing" : nil]
                                    .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
                            )
                            .font(.caption).foregroundStyle(.secondary)
                            if let dates = fileDates[rom.id] {
                                Text(
                                    [
                                        dates.created.map { "Created \($0.formatted(date: .abbreviated, time: .omitted))" },
                                        dates.modified.map { "Modified \($0.formatted(date: .abbreviated, time: .omitted))" },
                                    ].compactMap { $0 }.joined(separator: " · ")
                                )
                                .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if !rom.missing {
                            Button("Show in Finder", systemImage: "folder") { showInFinder(rom) }
                                .labelStyle(.iconOnly).buttonStyle(.hover).help("Show in Finder")
                        }
                        }
                    }
                }
            }

            if let error { Text(error).foregroundStyle(.red) }
        }
        .formStyle(.grouped)
        .task(id: services.changes.revision) { load() }
        .task(id: roms.map(\.id)) {
            // Off the main thread: it reads OpenEmu's library and the files' attributes.
            let library = services.settings.openEmuLibrary
            let present = roms.filter { !$0.missing }.map { ($0.id, $0.openEmuPk) }
            fileDates = await Task.detached(priority: .utility) {
                var out: [Int64: (created: Date?, modified: Date?)] = [:]
                for (id, pk) in present {
                    guard let file = try? OpenEmuLibrary.romFile(library: library, openEmuPk: pk),
                        let values = try? file.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
                    else { continue }
                    out[id] = (values.creationDate, values.contentModificationDate)
                }
                return out
            }.value
        }
        .task(id: game.igdbGameId) {
            facts = .none
            allScreenshots = false
            allCompanies = false
            if let link = game.igdbGameId, let igdb = services.igdb { facts = (try? await igdb.facts(igdbGameId: link)) ?? .none }
        }
        .sheet(isPresented: $editingGame) {
            EditGameSheet(
                services: services, game: game,
                canLink: services.gameSearch != nil && platform != nil,
                link: { linking = true },
                delete: {
                    do { deletion = try services.journal?.deletionSummary(id) } catch { self.error = journalErrorText(error) }
                })
        }
        .sheet(isPresented: $showingHistory) {
            RatingHistorySheet(history: history) { entry in save { try $0.deleteRatingEntry(entry.id) } }
        }
        .sheet(item: $viewing) { shot in
            if let igdb = services.igdb {
                // IGDB's full size (1280 × 720), shrinking to fit a smaller screen. Click to close.
                ScreenshotImage(igdb: igdb, imageID: shot.id, large: true)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .frame(minWidth: 640, idealWidth: 1280, maxWidth: 1280)
                    .onTapGesture { viewing = nil }
            }
        }
        .sheet(item: $editing) { edit in
            PlaythroughSheet(services: services, game: id, edit: edit) {
                editing = nil
                services.changes.changed()
            }
        }
        .sheet(isPresented: $linking) {
            if let search = services.gameSearch, let platform {
                LinkGameSheet(search: search, game: game, platform: platform, canChangePlatform: roms.isEmpty) {
                    // The new link can bring IGDB's Cover art.
                    services.changes.coverChanged()
                }
            }
        }
        .confirmationDialog(
            "Delete this Playthrough?",
            isPresented: Binding(get: { deletingPlaythrough != nil }, set: { if !$0 { deletingPlaythrough = nil } })
        ) {
            Button("Delete Playthrough", role: .destructive) {
                if let p = deletingPlaythrough { save { try $0.deletePlaythrough(p.id) } }
            }
        } message: {
            Text("Its dates, Outcome and notes go with it. There's no undo; a backup is taken first.")
        }
        .alert(
            deletion?.canDelete == false ? "Can't delete \(game.name)" : "Delete \(game.name)?",
            isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } }), presenting: deletion
        ) { summary in
            if summary.canDelete {
                Button("Delete Game", role: .destructive, action: deleteGame)
                Button("Cancel", role: .cancel) {}
            } else {
                Button("OK", role: .cancel) {}
            }
        } message: { summary in
            Text(deletionMessage(summary))
        }
    }

    private func load() {
        guard let journal = services.journal else { return }
        error = nil
        do {
            let game = try journal.game(id)
            self.game = game
            platform = try journal.platform(game.platformId)
            history = try journal.ratingHistory(id)
            playthroughs = try journal.playthroughs(id)
            allLists = try journal.lists()
            memberOf = Set(try journal.lists(containing: id).map(\.id))
            roms = try journal.roms(of: id)
            pins = Set(try journal.pins())
        } catch JournalError.gameNotFound {
            self.game = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Each company once, its roles in brackets: "Capcom (Developer, Publisher)". Developers and the
    /// first publisher show; the rest (often regional publishers) wait behind "+N more".
    @ViewBuilder private var companies: some View {
        let roles = Dictionary(facts.credits.map { ($0.name, $0.roles) }, uniquingKeysWith: { a, _ in a })
        let key = facts.credits.filter { $0.roles.contains(.developer) }.map(\.name)
            + facts.credits.filter { !$0.roles.contains(.developer) && $0.roles.contains(.publisher) }.prefix(1).map(\.name)
        let all = facts.credits.map(\.name)
        let shown = allCompanies || key.isEmpty ? all : all.filter(key.contains)
        pinnable(
            "Companies", .company, shown,
            more: shown.count < all.count ? (all.count - shown.count, { allCompanies = true }) : nil
        ) { name in
            let r = roles[name] ?? []
            return r.isEmpty ? name : "\(name) (\(r.map(\.rawValue.capitalized).joined(separator: ", ")))"
        }
    }

    /// Franchise, Series or Theme pills: each opens the Library filtered to it, and can be pinned to the sidebar.
    private func pinnable(
        _ title: String, _ kind: Pin.Kind, _ names: [String], more: (count: Int, show: () -> Void)? = nil,
        label: @escaping (String) -> String = { $0 }
    ) -> some View {
        PillRow(
            title: title, items: names, label: label, more: more, open: { browse(Pin(kind: kind, name: $0).filter) },
            pinned: Set(pins.filter { $0.kind == kind }.map(\.name)),
            togglePin: { name in
                let pin = Pin(kind: kind, name: name)
                save { pins.contains(pin) ? try $0.unpin(pin) : try $0.pin(pin) }
            })
    }

    /// Runs a journal change, then reloads every screen showing the journal.
    private func save(_ change: (JournalStore) throws -> Void) {
        guard let journal = services.journal else { return }
        do {
            try change(journal)
            error = nil
            services.changes.changed()
        } catch {
            self.error = journalErrorText(error)
        }
    }

    /// Opens the Game's ROM in OpenEmu, which plays it: the playlist of a multi-disc Version, else
    /// the first present ROM.
    private func playInOpenEmu() {
        let present = roms.filter { !$0.missing }
        guard let rom = present.first(where: { $0.fileName.lowercased().hasSuffix(".m3u") }) ?? present.first else { return }
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "org.openemu.OpenEmu") else {
            error = "OpenEmu isn't installed."
            return
        }
        do {
            guard let file = try OpenEmuLibrary.romFile(library: services.settings.openEmuLibrary, openEmuPk: rom.openEmuPk) else {
                error = "Couldn't find \(rom.fileName) in OpenEmu's library. Run an Import, then try again."
                return
            }
            NSWorkspace.shared.open([file], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
        } catch {
            self.error = "Couldn't read OpenEmu's library: \(error.localizedDescription)"
        }
    }


    /// Reveals the ROM's file in OpenEmu's library folder.
    private func showInFinder(_ rom: JournalROM) {
        do {
            guard let file = try OpenEmuLibrary.romFile(library: services.settings.openEmuLibrary, openEmuPk: rom.openEmuPk) else {
                error = "Couldn't find \(rom.fileName) in OpenEmu's library. Run an Import, then try again."
                return
            }
            NSWorkspace.shared.activateFileViewerSelecting([file])
        } catch {
            self.error = "Couldn't read OpenEmu's library: \(error.localizedDescription)"
        }
    }

    private func deleteGame() {
        save { try $0.deleteGame(id) }
        if error == nil { deleted() }
    }
}

/// "9.5" → 95 tenths. Nil for anything else, including a second decimal place.
func parseRating(_ text: String) -> Rating? {
    let text = text.trimmed
    guard text.wholeMatch(of: /\d{1,2}(\.\d)?/) != nil, let value = Double(text) else { return nil }
    return Rating(tenths: Int((value * 10).rounded()))
}

private func deletionMessage(_ s: DeletionSummary) -> String {
    guard s.canDelete else {
        return "It has \(s.presentROMs) ROM\(s.presentROMs == 1 ? "" : "s") in OpenEmu. Remove them in OpenEmu first, then Import."
    }
    var parts: [String] = []
    if s.ratingEntries > 0 { parts.append("its Rating history (\(s.ratingEntries))") }
    if s.playthroughs > 0 { parts.append("\(s.playthroughs) Playthrough\(s.playthroughs == 1 ? "" : "s")") }
    if s.lists > 0 { parts.append("its place in \(s.lists) List\(s.lists == 1 ? "" : "s")") }
    if s.missingROMs > 0 { parts.append("\(s.missingROMs) missing ROM\(s.missingROMs == 1 ? "" : "s") and their Activity") }
    parts.append("its Intent, Childhood, IGDB link and any uploaded Cover")
    return "This deletes " + parts.joined(separator: ", ") + ". There's no undo; a backup is taken first."
}

private func playthroughTitle(_ d: PlaythroughDraft) -> String {
    let outcome = d.outcome.map { $0 == .finished ? "Finished" : "Dropped" } ?? "In progress"
    // The same start and end shows once: "Finished, 2021", not "2021 – 2021".
    let dates = (d.start == d.end ? [d.start?.text] : [d.start?.text, d.end?.text]).compactMap { $0 }.joined(separator: " – ")
    return dates.isEmpty ? outcome : "\(outcome), \(dates)"
}

private func playthroughDetails(_ d: PlaythroughDraft) -> String? {
    let parts = [d.version, d.playedVia.map { "via \($0)" }, d.notes].compactMap { $0 }.filter { !$0.isEmpty }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
}

/// Messages for the journal's rules, as the UI says them.
func journalErrorText(_ error: Error) -> String {
    switch error as? JournalError {
    case .inProgressNeedsStart: "A Playthrough in progress needs a start date: add one, or choose an Outcome."
    case .endBeforeStart: "The end date can't come before the start date."
    case .listNameTaken: "There's already a List with that name."
    case .gameHasPresentROMs: "This Game has ROMs in OpenEmu. Remove them in OpenEmu first."
    case .igdbLinkTaken: "Another Game already has that IGDB link."
    case .alreadyLinked: "This Game already has an IGDB link. Use Change IGDB link… to replace it."
    case .gameHasROMs: "This Game has ROMs, so its Platform can't change."
    case .nameRequired: "A name is required."
    case .gameNotFound: "That Game no longer exists."
    case nil: error.localizedDescription
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

struct PlaythroughEdit: Identifiable {
    /// Nil for a new Playthrough.
    let id: Int64?
    let draft: PlaythroughDraft
}

/// Adding or editing a Playthrough. Every field is optional, except that one in progress needs a start.
struct PlaythroughSheet: View {
    let services: Services
    let game: GameID
    let edit: PlaythroughEdit
    let done: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var start = ""
    @State private var end = ""
    @State private var outcome: Outcome?
    @State private var notes = ""
    @State private var version = ""
    @State private var playedVia = ""
    @State private var versions: [String] = []
    @State private var vias: [String] = []
    @State private var error: String?

    var body: some View {
        Form {
            TextField("Start", text: $start, prompt: Text("YYYY, YYYY-MM or YYYY-MM-DD"))
            TextField("End", text: $end, prompt: Text("YYYY, YYYY-MM or YYYY-MM-DD"))
            Picker("Outcome", selection: $outcome) {
                Text("In progress").tag(Outcome?.none)
                Text("Finished").tag(Outcome?.some(.finished))
                Text("Dropped").tag(Outcome?.some(.dropped))
            }
            suggestedField("Version", text: $version, suggestions: versions)
            suggestedField("Played via", text: $playedVia, suggestions: vias)
            TextField("Notes", text: $notes, axis: .vertical).lineLimit(3...8)
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save", action: save).keyboardShortcut(.defaultAction)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .onAppear {
            let d = edit.draft
            start = d.start?.text ?? ""
            end = d.end?.text ?? ""
            outcome = d.outcome
            notes = d.notes ?? ""
            version = d.version ?? ""
            playedVia = d.playedVia ?? ""
            versions = (try? services.journal?.versionSuggestions(for: game)) ?? []
            vias = (try? services.journal?.playedViaSuggestions(for: game)) ?? []
        }
    }

    private func suggestedField(_ title: String, text: Binding<String>, suggestions: [String]) -> some View {
        HStack {
            TextField(title, text: text)
            if !suggestions.isEmpty {
                Menu("Suggestions") { ForEach(suggestions, id: \.self) { s in Button(s) { text.wrappedValue = s } } }
                    .fixedSize()
            }
        }
    }

    private func save() {
        guard let journal = services.journal else { return }
        func date(_ text: String, _ label: String) throws -> PartialDate? {
            guard !text.trimmed.isEmpty else { return nil }
            guard let d = PartialDate(text.trimmed) else { throw DateError(label: label) }
            return d
        }
        do {
            let draft = PlaythroughDraft(
                start: try date(start, "start"), end: try date(end, "end"), outcome: outcome, notes: notes.trimmed.nilIfEmpty,
                version: version.trimmed.nilIfEmpty, playedVia: playedVia.trimmed.nilIfEmpty)
            if let id = edit.id { try journal.updatePlaythrough(id, draft) } else { try journal.addPlaythrough(game, draft) }
            done()
        } catch let e as DateError {
            error = "The \(e.label) date should look like 1996, 1996-03 or 1996-03-17."
        } catch {
            self.error = journalErrorText(error)
        }
    }

    private struct DateError: Error { let label: String }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
