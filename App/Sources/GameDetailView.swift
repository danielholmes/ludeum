import JournalCore
import SwiftUI

/// Game detail: the editable right-hand pane. Every change is saved straight away.
struct GameDetailView: View {
    let services: Services
    let id: GameID
    /// Called after the Game is deleted.
    let deleted: () -> Void

    @State private var game: Game?
    @State private var platform: IGDBPlatform?
    @State private var history: [RatingEntry] = []
    @State private var playthroughs: [Playthrough] = []
    @State private var allLists: [GameList] = []
    @State private var memberOf: Set<Int64> = []
    @State private var roms: [JournalROM] = []
    @State private var activity: Activity?
    @State private var nameOverride = ""
    @State private var ratingInput = ""
    @State private var editing: PlaythroughEdit?
    @State private var linking = false
    @State private var deletion: DeletionSummary?
    @State private var deletingPlaythrough: Playthrough?
    @State private var error: String?
    @FocusState private var focus: Field?

    private enum Field { case nameOverride, rating }

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
                Text(game.name).font(.title).bold()
                if let platform { Text(platform.name).foregroundStyle(.secondary) }
                if game.igdbGameId == nil, services.gameSearch != nil, platform != nil {
                    Button("Link to IGDB…") { linking = true }
                }
                TextField("Name override", text: $nameOverride, prompt: Text("Use IGDB's name"))
                    .focused($focus, equals: .nameOverride)
                    .onSubmit(saveNameOverride)
            }

            Section("Rating") {
                HStack {
                    TextField("Rating", text: $ratingInput, prompt: Text("0.0–10.0")).frame(width: 90)
                        .focused($focus, equals: .rating).onSubmit(setRating)
                    Button("Set", action: setRating)
                    Button("Clear") { save { try $0.setRating(id, nil) } }.disabled(game.rating == nil)
                    if game.ratingImported { Text("Imported from OpenEmu, approximate").font(.caption).foregroundStyle(.secondary) }
                }
                ForEach(history, id: \.id) { entry in
                    HStack {
                        Text(entry.day).monospacedDigit()
                        Text(entry.rating.map(ratingText) ?? "Unrated")
                        if entry.imported { Text("imported").font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        Button("Delete", systemImage: "trash") { save { try $0.deleteRatingEntry(entry.id) } }
                            .labelStyle(.iconOnly).buttonStyle(.borderless)
                    }
                }
            }

            Section("Intent and Lists") {
                Picker("Intent", selection: Binding(get: { game.intent }, set: { new in save { try $0.setIntent(id, new) } })) {
                    Text("None").tag(Intent?.none)
                    Text("Backlog").tag(Intent?.some(.backlog))
                    Text("Up next").tag(Intent?.some(.upNext))
                }
                if let setAt = game.intentSetAt { LabeledContent("Set", value: setAt.formatted(date: .abbreviated, time: .shortened)) }
                Toggle("Childhood", isOn: Binding(get: { game.childhood }, set: { new in save { try $0.setChildhood(id, new) } }))
                ForEach(allLists, id: \.id) { list in
                    Toggle(
                        list.name,
                        isOn: Binding(
                            get: { memberOf.contains(list.id) },
                            set: { on in save { on ? try $0.addToList(list.id, id) : try $0.removeFromList(list.id, id) } }))
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
                        Button("Edit") { editing = PlaythroughEdit(id: p.id, draft: p.draft) }.buttonStyle(.borderless)
                        Button("Delete", systemImage: "trash") { deletingPlaythrough = p }.labelStyle(.iconOnly).buttonStyle(.borderless)
                    }
                }
                Button("Add Playthrough…") { editing = PlaythroughEdit(id: nil, draft: PlaythroughDraft()) }
            } header: {
                Text("Playthroughs")
            }

            Section("ROMs and Activity") {
                if roms.isEmpty {
                    Text("No ROMs").foregroundStyle(.secondary)
                } else {
                    if roms.allSatisfy(\.missing) { Text("No ROM in OpenEmu").foregroundStyle(.orange) }
                    if let activity {
                        LabeledContent("Played", value: "\(activity.playCount) times, \(playTime(activity.playTimeSeconds))")
                        if let last = activity.lastPlayedAt {
                            LabeledContent("Last played", value: last.formatted(date: .abbreviated, time: .omitted))
                        }
                    }
                    ForEach(roms) { rom in
                        VStack(alignment: .leading) {
                            Text(rom.fileName).strikethrough(rom.missing)
                            Text(
                                [rom.version, rom.disc.map { "Disc \($0)" }, rom.missing ? "missing" : nil].compactMap { $0 }.filter {
                                    !$0.isEmpty
                                }.joined(separator: " · ")
                            )
                            .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {
                Button("Delete Game…", role: .destructive) {
                    do { deletion = try services.journal?.deletionSummary(id) } catch { self.error = journalErrorText(error) }
                }
            }

            if let error { Text(error).foregroundStyle(.red) }
        }
        .formStyle(.grouped)
        .task(id: services.changes.revision) { load() }
        .onChange(of: focus) { old, _ in
            // Leaving a field saves it, like pressing Return.
            if old == .nameOverride { saveNameOverride() }
            if old == .rating, ratingInput.trimmed != (game.rating.map(ratingText) ?? "") { setRating() }
        }
        .sheet(item: $editing) { edit in
            PlaythroughSheet(services: services, game: id, edit: edit) {
                editing = nil
                services.changes.changed()
            }
        }
        .sheet(isPresented: $linking) {
            if let search = services.gameSearch, let platform {
                LinkGameSheet(search: search, game: game, platform: platform) { services.changes.changed() }
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
            activity = try journal.activity(of: id)
            // Never overwrite what I'm typing.
            if focus != .nameOverride { nameOverride = try journal.nameOverride(id) ?? "" }
            if focus != .rating { ratingInput = game.rating.map(ratingText) ?? "" }
        } catch JournalError.gameNotFound {
            self.game = nil
        } catch {
            self.error = error.localizedDescription
        }
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

    private func saveNameOverride() {
        let name = nameOverride.trimmed
        guard name != ((try? services.journal?.nameOverride(id)) ?? nil ?? "") else { return }
        save { try $0.setNameOverride(id, name.isEmpty ? nil : name) }
    }

    private func setRating() {
        guard let rating = parseRating(ratingInput) else {
            error = "A Rating is 0.0 to 10.0, in steps of 0.1."
            return
        }
        save { try $0.setRating(id, rating) }
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
    let dates = [d.start?.text, d.end?.text].compactMap { $0 }.joined(separator: " – ")
    return dates.isEmpty ? outcome : "\(outcome), \(dates)"
}

private func playthroughDetails(_ d: PlaythroughDraft) -> String? {
    let parts = [d.version, d.playedVia.map { "via \($0)" }, d.notes].compactMap { $0 }.filter { !$0.isEmpty }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
}

private func playTime(_ seconds: Double) -> String {
    let hours = Int(seconds) / 3600
    let minutes = (Int(seconds) % 3600) / 60
    return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
}

/// Messages for the journal's rules, as the UI says them.
func journalErrorText(_ error: Error) -> String {
    switch error as? JournalError {
    case .inProgressNeedsStart: "A Playthrough in progress needs a start date: add one, or choose an Outcome."
    case .endBeforeStart: "The end date can't come before the start date."
    case .listNameTaken: "There's already a List with that name."
    case .gameHasPresentROMs: "This Game has ROMs in OpenEmu. Remove them in OpenEmu first."
    case .igdbLinkTaken: "Another Game already has that IGDB link."
    case .alreadyLinked: "This Game already has an IGDB link, which can't be changed."
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
