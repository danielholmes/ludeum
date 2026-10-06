import AppKit
import LudeumCore
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
    @State private var players: [Player] = []
    @State private var roms: [LudeumROM] = []
    @State private var emulatorSettings = EmulatorSettings()
    @State private var showingHistory = false
    /// Each present ROM file's created and modified dates, by ROM id, read from disk.
    /// Each present ROM's files on disk, read off the main thread.
    @State private var romFiles: [Int64: [ROMFileInfo]] = [:]
    /// ROMs whose files are shown.
    @State private var expandedROMs: Set<Int64> = []
    @State private var facts = GameFacts.none
    @State private var editing: PlaythroughEdit?
    @State private var linking = false
    @State private var editingGame = false
    @State private var deletion: DeletionSummary?
    @State private var deletingPlaythrough: Playthrough?
    @State private var error: String?
    /// Why the last Play didn't open, shown under Play.
    @State private var playError: String?

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
            // Identity and actions: what the Game is, and playing it.
            Section {
                HStack(alignment: .top, spacing: 16) {
                    // The Cover in its own shape (SNES boxes are wide), at the top of its column.
                    CoverView(services: services, game: id, name: game.name, fitsImage: true)
                        .frame(width: 150).frame(maxHeight: 200, alignment: .top)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(game.name).font(.title).bold()
                            Spacer()
                            Button("Edit Game", systemImage: "pencil") { editingGame = true }
                                .labelStyle(.iconOnly).buttonStyle(.hover).help("Name, Cover, IGDB link and deleting")
                        }
                        if let platform {
                            Text([platform.name, facts.releaseYear.map(String.init)].compactMap { $0 }.joined(separator: " · "))
                                .foregroundStyle(.secondary)
                        }
                        if !roms.isEmpty, !roms.allSatisfy(\.missing) {
                            playControls
                            if let playError { Text(playError).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
                        }
                    }
                }
            }

            // My journal: what I think of it and when I played it.
            Section("My journal") {
                // Mine, Players and Critics alike: a label above the value, lined up along the bottom.
                HStack(alignment: .lastTextBaseline, spacing: 28) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Mine").font(FactStyle.label).foregroundStyle(.secondary)
                        RatingEditor(
                            rating: game.rating, hasHistory: !history.isEmpty,
                            set: { rating in save { try $0.setRating(id, rating) } }, showHistory: { showingHistory = true })
                    }
                    CommunityScores(players: facts.playerScore, critics: facts.criticScore, stacked: true)
                }
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
                ForEach(playthroughs, id: \.id) { p in
                    // Click to edit; delete from the right-click menu or the edit sheet.
                    Button {
                        editing = PlaythroughEdit(id: p.id, draft: p.draft)
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(playthroughTitle(p.draft))
                                if let details = playthroughDetails(p.draft) {
                                    Text(details).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            PlayerBadges(ids: p.draft.players, players: players)
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .help("Edit this Playthrough")
                    .contextMenu {
                        Button("Edit…") { editing = PlaythroughEdit(id: p.id, draft: p.draft) }
                        Button("Delete…", role: .destructive) { deletingPlaythrough = p }
                    }
                }
                Button("Add Playthrough…", systemImage: "plus") { editing = PlaythroughEdit(id: nil, draft: nil) }
                    .buttonStyle(.hover)
            }

            // About: what IGDB says about it.
            if facts != .none {
                Section("About") {
                    IGDBFactsRows(services: services, facts: facts, browse: browse, showsScores: false)
                }
            }
            if !facts.screenshots.isEmpty, let igdb = services.igdb {
                ScreenshotsSection(igdb: igdb, screenshots: facts.screenshots)
            }
            if !facts.keywords.isEmpty { KeywordsSection(keywords: facts.keywords) }

            // Files: the ROMs, checked now and then.
            Section("Files") { romRows }

            if let error { Text(error).foregroundStyle(.red) }
        }
        .formStyle(.grouped)
        .task(id: services.changes.revision) { load() }
        .onChange(of: id) { playError = nil }
        .task(id: roms.map(\.id)) {
            // Off the main thread: it reads OpenEmu's library and the files' attributes.
            let library = services.settings.openEmuLibrary
            let folders = services.settings.romFolders
            let present = roms.filter { !$0.missing }
            romFiles = await Task.detached(priority: .utility) {
                var out: [Int64: [ROMFileInfo]] = [:]
                for rom in present { out[rom.id] = filesOnDisk(rom, library: library, folders: folders) }
                return out
            }.value
        }
        .task(id: game.igdbGameId) {
            facts = .none
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
            players = try journal.players()
            roms = try journal.roms(of: id)
            emulatorSettings = try journal.emulatorSettings(id)
        } catch LudeumError.gameNotFound {
            self.game = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Runs a journal change, then reloads every screen showing the journal.
    private func save(_ change: (LudeumStore) throws -> Void) {
        guard let journal = services.journal else { return }
        do {
            try change(journal)
            error = nil
            services.changes.changed()
        } catch {
            self.error = journalErrorText(error)
        }
    }

    /// ▶ Play in the Platform's Emulator, and beside it the Emulator's settings. A Platform with no
    /// Emulator says so instead.
    @ViewBuilder private var playControls: some View {
        if isArchived {
            HStack(spacing: 12) {
                Label("Archived: unarchive to play", systemImage: "archivebox").foregroundStyle(.orange)
                if let rom = roms.first(where: { !$0.missing && $0.archived }) { archiveButton(rom) }
            }
        } else if let emulator, let platformId = game?.platformId {
            HStack(spacing: 12) {
                Button {
                    play(in: emulator)
                } label: {
                    Label("Play", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isBeingArchived)
                .help(isBeingArchived ? "Waiting for Archive or Unarchive to finish" : "Play in \(emulator.name)")
                // Dolphin has no per-Game settings: every Game gets the same ones.
                if !EmulatorSettingRow.rows(for: emulator, platformId: platformId).isEmpty {
                    EmulatorSettingsButton(emulator: emulator, platformId: platformId, settings: emulatorSettings) { settings in
                        save { try $0.setEmulatorSettings(id, settings) }
                    }
                }
            }
        } else {
            Text("No \(platform?.name ?? "") emulator yet").foregroundStyle(.secondary)
        }
    }

    /// One of this Game's ROMs is queued or running in Background tasks: its files are about to change.
    private var isBeingArchived: Bool { roms.contains { services.tasks.active(Self.taskSubject($0)) != nil } }

    /// Every present ROM is archived, so there's nothing to Play until one is Unarchived.
    private var isArchived: Bool {
        let present = roms.filter { !$0.missing }
        return !present.isEmpty && present.allSatisfy(\.archived)
    }

    @ViewBuilder private var romRows: some View {
        if roms.isEmpty {
            Text("No ROMs").foregroundStyle(.secondary)
        } else {
            if roms.allSatisfy(\.missing) {
                Text(roms.contains { $0.folderName != nil } ? "No ROM in its ROM folder" : "No ROM in OpenEmu").foregroundStyle(.orange)
            }
            ForEach(roms) { rom in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        VStack(alignment: .leading) {
                            // Without its extension; GoodTools region codes spelled out.
                            Text((rom.fileName as NSString).deletingPathExtension).strikethrough(rom.missing)
                            Text(
                                [
                                    readableVersion(rom.version), rom.disc.map { "Disc \($0)" },
                                    rom.missing ? "missing" : rom.archived ? "archived" : nil,
                                ]
                                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
                            )
                            .font(.callout).foregroundStyle(.secondary)
                            if let main = romFiles[rom.id]?.first {
                                Text(
                                    [
                                        main.created.map { "Created \($0.formatted(date: .abbreviated, time: .omitted))" },
                                        main.modified.map { "Modified \($0.formatted(date: .abbreviated, time: .omitted))" },
                                    ].compactMap { $0 }.joined(separator: " · ")
                                )
                                .font(.callout).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if !rom.missing, rom.systemId == ROMFolder.ps2SystemId { archiveButton(rom) }
                        if !rom.missing {
                            Button("Show in Finder", systemImage: "folder") { showInFinder(rom) }
                                .labelStyle(.iconOnly).buttonStyle(.hover).help("Show in Finder")
                        }
                    }
                    if let files = romFiles[rom.id], !files.isEmpty { fileList(rom, files) }
                }
            }
        }
    }

    /// The ROM's files, folded away: "3 files · 702 MB", opening to each file and its size.
    /// The whole line is the button, not just the chevron.
    private func fileList(_ rom: LudeumROM, _ files: [ROMFileInfo]) -> some View {
        let total = files.compactMap(\.size).reduce(0, +)
        let expanded = expandedROMs.contains(rom.id)
        return VStack(alignment: .leading, spacing: 4) {
            Button {
                if expanded { expandedROMs.remove(rom.id) } else { expandedROMs.insert(rom.id) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right").rotationEffect(.degrees(expanded ? 90 : 0)).frame(width: 12)
                    Text(
                        "\(files.count) file\(files.count == 1 ? "" : "s") · \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))"
                    )
                    Spacer()
                }
                .font(.callout).foregroundStyle(.secondary)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(expanded ? "Hide its files" : "Show its files")
            if expanded {
                ForEach(files, id: \.url) { file in
                    HStack {
                        Text(file.name).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        if let size = file.size {
                            Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)).foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    .font(.callout)
                    .padding(.leading, 18)
                }
            }
        }
    }

    // MARK: Archive and Unarchive

    /// Archive or Unarchive, as a Background task; while it's queued or running, its progress.
    @ViewBuilder private func archiveButton(_ rom: LudeumROM) -> some View {
        if let task = services.tasks.active(Self.taskSubject(rom)) {
            if task.state == .running {
                HStack(spacing: 6) {
                    ProgressView(value: task.progress ?? 0).controlSize(.small).frame(width: 80)
                    Text(task.progress.map { "\(Int($0 * 100))%" } ?? "").font(.caption).monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .help(task.title)
            } else {
                Text("Queued").font(.caption).foregroundStyle(.secondary).help("Waiting in Background tasks")
            }
        } else if rom.archived {
            Button("Unarchive", systemImage: "archivebox") { unarchive(rom) }
                .help("Unpack it into a folder named after it, so it can be Played. The .7z goes to the Trash.")
        } else {
            Button("Archive", systemImage: "archivebox") { archive(rom) }
                .help("Pack it into a .7z at maximum compression. The image goes to the Trash.")
        }
    }

    private static func taskSubject(_ rom: LudeumROM) -> String { "rom \(rom.id)" }

    private func folder(of rom: LudeumROM) -> ROMFolder? { services.settings.romFolders.first { $0.systemId == rom.systemId } }

    private func unarchive(_ rom: LudeumROM) {
        guard let folder = folder(of: rom), let name = rom.folderName else { return }
        let archive = folder.url.appending(path: rom.fileName)
        services.tasks.enqueue("Unarchiving \(name)", subject: Self.taskSubject(rom)) { progress in
            try await ROMArchiver.installed().unarchive(archive, romName: name, in: folder, progress: progress)
        } finished: {
            checkROMsAgain()
        }
    }

    private func archive(_ rom: LudeumROM) {
        guard let folder = folder(of: rom), let name = rom.folderName else { return }
        services.tasks.enqueue("Archiving \(name)", subject: Self.taskSubject(rom)) { progress in
            try await ROMArchiver.installed().archive(name, in: folder, progress: progress)
        } finished: {
            checkROMsAgain()
        }
    }

    /// After a Background task: this Game's ROMs as they are now, whichever screen is showing.
    private func checkROMsAgain() {
        try? services.journal?.checkROMsAgain(id, in: services.settings.romFolders)
        services.changes.changed()
    }

    private var emulator: Emulator? { game.flatMap { Emulator.of(platformId: $0.platformId) } }

    /// The file a Play opens: the playlist of a multi-disc Version, else the first present ROM. Nil
    /// (with the error shown) when it can't be found.
    private func playFile() -> URL? {
        let present = roms.filter { !$0.missing && !$0.archived }
        guard let rom = present.first(where: { $0.fileName.lowercased().hasSuffix(".m3u") }) ?? present.first else { return nil }
        do {
            guard let file = try romFile(rom, library: services.settings.openEmuLibrary, folders: services.settings.romFolders, ready: true)
            else {
                playError = "Couldn't find \(rom.fileName). Run an Import, then try again."
                return nil
            }
            return file
        } catch {
            self.playError = "Couldn't look for \(rom.fileName): \(error.localizedDescription)"
            return nil
        }
    }

    /// Plays the Game in its Emulator, with every Emulator setting on the command line. A running
    /// Emulator gets the ROM in its open window.
    private func play(in emulator: Emulator) {
        playError = nil
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: emulator.bundleIdentifier) else {
            playError = "\(emulator.name) isn't installed."
            return
        }
        guard let file = playFile() else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        do {
            configuration.arguments = try emulator.arguments(rom: file, platformId: game?.platformId ?? 0, settings: emulatorSettings)
        } catch {
            self.playError = "Couldn't write \(emulator.name)'s settings: \(error.localizedDescription)"
            return
        }
        // A second MesenCE hands its arguments to the running one and quits; DuckStation opens another window.
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: app, configuration: configuration) { _, error in
            if let error { Task { @MainActor in self.playError = "Couldn't open \(emulator.name): \(error.localizedDescription)" } }
        }
    }

    /// Reveals the ROM's file in OpenEmu's library folder.
    private func showInFinder(_ rom: LudeumROM) {
        do {
            guard let file = try romFile(rom, library: services.settings.openEmuLibrary, folders: services.settings.romFolders) else {
                error = "Couldn't find \(rom.fileName). Run an Import, then try again."
                return
            }
            NSWorkspace.shared.activateFileViewerSelecting([file])
        } catch {
            self.error = "Couldn't look for \(rom.fileName): \(error.localizedDescription)"
        }
    }

    private func deleteGame() {
        save { try $0.deleteGame(id) }
        if error == nil { deleted() }
    }
}

/// One file of a ROM, as Game detail lists it.
struct ROMFileInfo: Sendable {
    let url: URL
    /// Its path from the ROM's own folder (the ROM folder, or the folder OpenEmu keeps it in).
    let name: String
    let size: Int64?
    let created: Date?
    let modified: Date?
}

/// Every file of a ROM on disk, the file a Play opens first. Empty when it can't be found.
private func filesOnDisk(_ rom: LudeumROM, library: URL, folders: [ROMFolder]) -> [ROMFileInfo] {
    let files: [URL]
    let base: URL
    if let pk = rom.openEmuPk {
        guard let main = try? OpenEmuLibrary.romFile(library: library, openEmuPk: pk) else { return [] }
        files = ROMFiles.files(of: main)
        base = main.deletingLastPathComponent()
    } else if let name = rom.folderName, let folder = folders.first(where: { $0.systemId == rom.systemId }) {
        files = (try? folder.files(named: name)) ?? []
        base = folder.url
    } else {
        return []
    }
    let basePath = base.standardizedFileURL.path(percentEncoded: false)
    return files.map { file in
        let values = try? file.resourceValues(forKeys: [.fileSizeKey, .creationDateKey, .contentModificationDateKey])
        let path = file.standardizedFileURL.path(percentEncoded: false)
        return ROMFileInfo(
            url: file,
            name: path.hasPrefix(basePath)
                ? String(path.dropFirst(basePath.count)).trimmingPrefix("/").description : file.lastPathComponent,
            size: values?.fileSize.map(Int64.init), created: values?.creationDate, modified: values?.contentModificationDate)
    }
}

/// Where a ROM's file is: in OpenEmu's library, or in its ROM folder. `ready` asks for the file a
/// Play opens, so an archived ROM has none.
private func romFile(_ rom: LudeumROM, library: URL, folders: [ROMFolder], ready: Bool = false) throws -> URL? {
    if let pk = rom.openEmuPk { return try OpenEmuLibrary.romFile(library: library, openEmuPk: pk) }
    guard let name = rom.folderName, let folder = folders.first(where: { $0.systemId == rom.systemId }) else { return nil }
    if ready { return try folder.readyFile(named: name) }
    let file = folder.url.appending(path: rom.fileName)
    return FileManager.default.fileExists(atPath: file.path(percentEncoded: false)) ? file : nil
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
    if s.missingROMs > 0 { parts.append("\(s.missingROMs) missing ROM\(s.missingROMs == 1 ? "" : "s")") }
    parts.append("its Intent, Childhood, IGDB link and any uploaded Cover")
    return "This deletes " + parts.joined(separator: ", ") + ". There's no undo; a backup is taken first."
}

private func playthroughTitle(_ d: PlaythroughDraft) -> String {
    let outcome = d.outcome.map { $0 == .finished ? "Finished" : "Dropped" } ?? "In progress"
    // The same start and end shows once: "Finished, 2021", not "2021 – 2021".
    let dates = [d.start.text, d.start == d.end ? nil : d.end?.text].compactMap { $0 }.joined(separator: " – ")
    return dates.isEmpty ? outcome : "\(outcome), \(dates)"
}

private func playthroughDetails(_ d: PlaythroughDraft) -> String? {
    let parts = [d.version, d.playedVia.map { "via \($0)" }, d.notes].compactMap { $0 }.filter { !$0.isEmpty }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
}

/// Messages for the journal's rules, as the UI says them.
func journalErrorText(_ error: Error) -> String {
    switch error as? LudeumError {
    case .endBeforeStart: "The end date can't come before the start date."
    case .listNameTaken: "There's already a List with that name."
    case .playerNameTaken: "There's already a Player with that name."
    case .gameHasPresentROMs: "This Game has ROMs in OpenEmu. Remove them in OpenEmu first."
    case .igdbLinkTaken: "Another Game already has that IGDB link."
    case .alreadyLinked: "This Game already has an IGDB link. Use Change IGDB link… to replace it."
    case .gameHasROMs: "This Game has ROMs, so its Platform can't change."
    case .nameRequired: "A name is required."
    case .gameNotFound: "That Game no longer exists."
    case .runAheadOutOfRange: "Run-ahead is 0 to 10 frames."
    case nil: error.localizedDescription
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

struct PlaythroughEdit: Identifiable {
    /// Both nil for a new Playthrough.
    let id: Int64?
    let draft: PlaythroughDraft?
}

/// Adding or editing a Playthrough. Every field is optional except the start date.
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
    @State private var players: [Player] = []
    @State private var selectedPlayers: Set<Int64> = []
    @State private var error: String?
    @State private var confirmingDelete = false

    var body: some View {
        Form {
            TextField("Start", text: $start, prompt: Text("YYYY, YYYY-MM or YYYY-MM-DD"))
            TextField("End", text: $end, prompt: Text("YYYY, YYYY-MM or YYYY-MM-DD"))
            Picker("Outcome", selection: $outcome) {
                Text("In progress").tag(Outcome?.none)
                Text("Finished").tag(Outcome?.some(.finished))
                Text("Dropped").tag(Outcome?.some(.dropped))
            }
            PlayerPicker(players: players, selected: $selectedPlayers)
            suggestedField("Version", text: $version, suggestions: versions)
            suggestedField("Played via", text: $playedVia, suggestions: vias)
            TextField("Notes", text: $notes, axis: .vertical).lineLimit(3...8)
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                if edit.id != nil { Button("Delete…", role: .destructive) { confirmingDelete = true } }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save", action: save).keyboardShortcut(.defaultAction)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .confirmationDialog("Delete this Playthrough?", isPresented: $confirmingDelete) {
            Button("Delete Playthrough", role: .destructive, action: delete)
        } message: {
            Text("Its dates, Outcome and notes go with it. There's no undo; a backup is taken first.")
        }
        .onAppear {
            if let d = edit.draft {
                start = d.start.text
                end = d.end?.text ?? ""
                outcome = d.outcome
                notes = d.notes ?? ""
                version = d.version ?? ""
                playedVia = d.playedVia ?? ""
                selectedPlayers = Set(d.players)
            }
            versions = (try? services.journal?.versionSuggestions(for: game)) ?? []
            vias = (try? services.journal?.playedViaSuggestions(for: game)) ?? []
            players = (try? services.journal?.players()) ?? []
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
        guard !start.trimmed.isEmpty else {
            error = "A start date is required."
            return
        }
        do {
            let draft = PlaythroughDraft(
                start: try date(start, "start")!, end: try date(end, "end"), outcome: outcome, notes: notes.trimmed.nilIfEmpty,
                version: version.trimmed.nilIfEmpty, playedVia: playedVia.trimmed.nilIfEmpty,
                players: selectedPlayers.sorted())
            if let id = edit.id { try journal.updatePlaythrough(id, draft) } else { try journal.addPlaythrough(game, draft) }
            done()
        } catch let e as DateError {
            error = "The \(e.label) date should look like 1996, 1996-03 or 1996-03-17."
        } catch {
            self.error = journalErrorText(error)
        }
    }

    private func delete() {
        guard let journal = services.journal, let id = edit.id else { return }
        do {
            try journal.deletePlaythrough(id)
            done()
        } catch {
            self.error = journalErrorText(error)
        }
    }

    private struct DateError: Error { let label: String }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
