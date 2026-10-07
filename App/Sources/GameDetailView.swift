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
    /// What's inside each of those files that's an archive, by its file.
    @State private var archiveListings: [URL: ArchiveListing] = [:]
    /// ROMs whose files are shown.
    @State private var expandedROMs: Set<Int64> = []
    @State private var facts = GameFacts.none
    @State private var editing: PlaythroughEdit?
    @State private var linking = false
    @State private var editingGame = false
    @State private var deletion: DeletionSummary?
    @State private var deletingPlaythrough: Playthrough?
    /// A ROM about to be renamed after the Game, with its new name, for the confirmation.
    @State private var renaming: (rom: LudeumROM, name: String)?
    /// A delete is running: nothing here can be changed until it's done.
    @State private var deleteRunning = false
    @State private var error: String?
    /// Why the last Play didn't open, shown under Play.
    @State private var playError: String?
    /// An Emulator version problem found on Play: refused (too old), or a once-per-launch warning.
    @State private var versionAlert: (title: String, message: String)?

    var body: some View {
        if let game {
            form(game).disabled(deleteRunning)
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
                            if let message = playError ?? emulator.flatMap(services.versions.tooOldMessage) {
                                Text(message).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                            }
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
                        ForEach(Intent.allCases, id: \.self) { Text(intentText($0)).tag(Intent?.some($0)) }
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
        .alert(
            versionAlert?.title ?? "", isPresented: Binding(get: { versionAlert != nil }, set: { if !$0 { versionAlert = nil } })
        ) {
            Button("OK") {}
        } message: {
            Text(versionAlert?.message ?? "")
        }
        // Again when a ROM changes file (Archive, Compact), not only when the ROMs do.
        .task(id: roms) {
            // Off the main thread: it reads the ROM folders and the files' attributes.
            let locator = self.locator
            let present = roms.filter { !$0.missing }
            romFiles = await Task.detached(priority: .utility) {
                var out: [Int64: [ROMFileInfo]] = [:]
                for rom in present { out[rom.id] = locator.files(of: rom) }
                return out
            }.value
            // Then what's inside the archives, from their indexes, for the folded lines' savings.
            var listings: [URL: ArchiveListing] = [:]
            for file in romFiles.values.joined() where file.isArchive {
                listings[file.url] = await ArchiveListing.read(file.url)
                if Task.isCancelled { return }
            }
            archiveListings = listings
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
            "Rename it “\(renaming?.name ?? "")”?",
            isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } }), titleVisibility: .visible
        ) {
            Button("Rename") { if let renaming { rename(renaming.rom, to: renaming.name) } }
        } message: {
            Text(
                "\(renaming?.rom.folderName ?? "") is renamed after the Game, keeping its tags, in every form it's kept in. "
                    + "What's inside its folder or archive keeps its names.")
        }
        .confirmationDialog(
            "Delete this Playthrough?",
            isPresented: Binding(get: { deletingPlaythrough != nil }, set: { if !$0 { deletingPlaythrough = nil } })
        ) {
            Button("Delete Playthrough", role: .destructive) {
                if let p = deletingPlaythrough { delete { try $0.deletePlaythrough(p.id) } }
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

    /// Runs a delete, then reloads every screen showing the journal. Off the main thread, as a backup of the whole
    /// journal is taken first.
    private func delete(_ change: @escaping @Sendable (LudeumStore) throws -> Void, then done: @escaping () -> Void = {}) {
        guard let journal = services.journal, !deleteRunning else { return }
        deleteRunning = true
        Task {
            defer { deleteRunning = false }
            do {
                try await offMain { try change(journal) }
                error = nil
                services.changes.changed()
                done()
            } catch {
                self.error = journalErrorText(error)
            }
        }
    }

    /// ▶ Play in the Platform's Emulator, and beside it the Emulator's settings, or under it when the panel's too
    /// narrow for both. A Platform with no Emulator says so instead.
    @ViewBuilder private var playControls: some View {
        let refusal = playing.availability.refusal
        if refusal == .archived {
            SideBySideOrStacked {
                // Stacked and still too wide, it wraps rather than being cut short.
                Label(Play.Refusal.archived.message, systemImage: "archivebox").foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                if let rom = roms.first(where: { !$0.missing && $0.archived }) { archiveButton(rom) }
            }
        } else if let emulator, let platformId = game?.platformId {
            SideBySideOrStacked {
                Button {
                    play(in: emulator)
                } label: {
                    Label("Play", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(services.versions.tooOldMessage(emulator) == nil ? nil : .red)
                .disabled(refusal == .busy)
                .help(refusal?.message ?? "Play in \(emulator.name)")
                // Dolphin has no per-Game settings: every Game gets the same ones.
                if !EmulatorSettingRow.rows(for: emulator, platformId: platformId).isEmpty {
                    EmulatorSettingsButton(emulator: emulator, platformId: platformId, settings: emulatorSettings) { settings in
                        save { try $0.setEmulatorSettings(id, settings) }
                    }
                }
            }
        } else if let refusal {
            Text(refusal.message).foregroundStyle(.secondary)
        }
    }

    /// This Game's Play, with the ROMs a Background task is working on.
    private var playing: Play {
        Play(
            platformId: game?.platformId ?? 0, platformName: platform?.name ?? "", roms: roms, settings: emulatorSettings,
            busyROMs: Set(roms.map(\.id).filter { services.tasks.isActive(.rom($0)) }))
    }

    @ViewBuilder private var romRows: some View {
        if roms.isEmpty {
            Text("No ROMs").foregroundStyle(.secondary)
        } else {
            if roms.allSatisfy(\.missing) {
                Text("No ROM in its ROM folder").foregroundStyle(.orange)
            }
            ForEach(roms) { rom in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        VStack(alignment: .leading) {
                            // Its subfolder, whose files show when it's opened; else its file's full name, extension and all.
                            Group {
                                if let subfolder = rom.subfolder {
                                    Text("\(Image(systemName: "folder")) \(subfolder)")
                                } else {
                                    Text(rom.fileName)
                                }
                            }
                            .strikethrough(rom.missing)
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
                        if let name = newName(for: rom) {
                            Button("Rename…", systemImage: "character.cursor.ibeam") { renaming = (rom, name) }
                                .help("Rename it “\(name)”, after its Game")
                        }
                        if ROMArchiving.action(for: rom) != nil { archiveButton(rom) }
                        if rom.missing {
                            // Gone from its ROM folder for good, e.g. replaced by a renamed file Import found as a new ROM.
                            Button("Forget") { save { try $0.forgetROM(rom.id) } }
                                .help("Stop showing this missing ROM. If its file comes back, an Import finds it again.")
                        } else {
                            Button("Show in Finder", systemImage: "folder") { showInFinder(rom) }
                                .labelStyle(.iconOnly).buttonStyle(.hover).help("Show in Finder")
                        }
                    }
                    if let files = romFiles[rom.id], !files.isEmpty { fileList(rom, files) }
                }
            }
        }
    }

    /// The ROM's files, folded away: "3 files · 702 MB", or for an archive "1 file · 390 KB (57% smaller)", that in
    /// green, or red when the archive is bigger than what's inside. Opening it shows each file and its size; an
    /// archive's size is its compressed one, and it lists what's inside, each file at its uncompressed size.
    /// The whole line is the button, not just the chevron.
    private func fileList(_ rom: LudeumROM, _ files: [ROMFileInfo]) -> some View {
        let total = files.compactMap(\.size).reduce(0, +)
        let expanded = expandedROMs.contains(rom.id)
        let saving = SevenZip.saving(files: files, contents: archiveListings.compactMapValues(\.entries))
        // Its saving can't be read from an archive Dropbox keeps online-only.
        let onlineOnly = files.allSatisfy(\.isArchive) && files.contains { archiveListings[$0.url] == .onlineOnly }
        return VStack(alignment: .leading, spacing: 4) {
            Button {
                if expanded { expandedROMs.remove(rom.id) } else { expandedROMs.insert(rom.id) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right").rotationEffect(.degrees(expanded ? 90 : 0)).frame(width: 12)
                    Text(
                        "\(files.count) file\(files.count == 1 ? "" : "s") · \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))"
                    )
                    if let saving {
                        savingText(saving)
                    } else if onlineOnly {
                        Text("(online-only in Dropbox)").help("Download it to see how much room its archive saves.")
                    }
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
                        Text(file.name).fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        if let size = file.size {
                            Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file) + (file.isArchive ? " compressed" : ""))
                                .foregroundStyle(.secondary).monospacedDigit().fixedSize()
                        }
                    }
                    .font(.callout)
                    .padding(.leading, 18)
                    if file.isArchive { ArchiveContentsList(listing: archiveListings[file.url]) }
                }
            }
        }
    }

    /// "(57% smaller)" in green, or "(12% bigger)" in red when packing made it take more room.
    private func savingText(_ saving: Double) -> some View {
        // A few bytes either way reads "<1%", not "0%".
        let percent = abs(saving) < 0.005 ? "<1%" : abs(saving).formatted(.percent.precision(.fractionLength(0)))
        return Text("(\(percent) \(saving < 0 ? "bigger" : "smaller"))")
            .foregroundStyle(saving < 0 ? .red : .green).monospacedDigit()
            .help(saving < 0 ? "The archive takes more room than its files unpacked." : "How much room the archive saves.")
    }

    // MARK: Archive, Unarchive and Compact

    /// Archive, Unarchive or Compact, as a Background task; while it's queued or running, its progress.
    @ViewBuilder private func archiveButton(_ rom: LudeumROM) -> some View {
        if let task = services.tasks.active(.rom(rom.id)) {
            BackgroundTaskProgress(task: task, tasks: services.tasks)
        } else {
            switch ROMArchiving.action(for: rom) {
            case .unarchive:
                Button("Unarchive", systemImage: "archivebox") { startArchiving(rom) }
                    .help(
                        ROMArchiving.unarchivesToOneFile(rom)
                            ? "Unpack its file, so it can be Played. The .7z goes to the Trash."
                            : "Unpack it into a folder named after it, so it can be Played. The .7z goes to the Trash.")
            case .archive:
                Button("Archive", systemImage: "archivebox") { startArchiving(rom) }
                    .help("Pack it into a .7z at maximum compression. What it packed goes to the Trash.")
            case .compact:
                Button("Compact", systemImage: "archivebox") { startArchiving(rom) }
                    .help(
                        "Pack it into \(ROMArchiving.compactFileName(for: rom) ?? "an archive"), which its Emulator still opens. "
                            + "The file it replaces goes to the Trash.")
            case nil:
                EmptyView()
            }
        }
    }

    // MARK: Rename

    /// The name to offer a present ROM that isn't named after its Game, while no Background task is working on it.
    private func newName(for rom: LudeumROM) -> String? {
        guard let game, !rom.missing, !services.tasks.isActive(.rom(rom.id)) else { return nil }
        return ROMRename.newName(forROM: rom.folderName, gameName: game.name)
    }

    /// Renames the ROM in its ROM folder and the journal.
    private func rename(_ rom: LudeumROM, to name: String) {
        // A Background task may have started on it while the confirmation was up.
        guard let folder = locator.folder(of: rom), !services.tasks.isActive(.rom(rom.id)) else { return }
        save { try $0.renameROM(rom.id, to: name, in: folder) }
    }

    private var locator: ROMLocator {
        ROMLocator(romFolders: services.settings.romFolders)
    }

    /// Archive, Unarchive or Compact, whichever it needs. Once done, whichever screen is showing sees the change.
    private func startArchiving(_ rom: LudeumROM) {
        ROMArchiving(locator: locator, journal: services.journal, tasks: services.tasks).start(rom) {
            [changes = services.changes] in
            changes.changed()
        }
    }

    private var emulator: Emulator? { game.flatMap { Emulator.of(platformId: $0.platformId) } }

    /// Plays the Game in its Emulator, with every Emulator setting on the command line. A running
    /// Emulator gets the ROM in its open window.
    private func play(in emulator: Emulator) {
        playError = nil
        startPlay(playing, in: emulator, services: services, refused: { playError = $0 }, alert: { versionAlert = ($0, $1) })
    }

    /// Reveals the ROM's file in its ROM folder.
    private func showInFinder(_ rom: LudeumROM) {
        do {
            guard let file = try locator.file(of: rom) else {
                error = "Couldn't find \(rom.fileName). Run an Import, then try again."
                return
            }
            NSWorkspace.shared.activateFileViewerSelecting([file])
        } catch {
            self.error = "Couldn't look for \(rom.fileName): \(error.localizedDescription)"
        }
    }

    private func deleteGame() {
        delete({ [id] in try $0.deleteGame(id) }, then: deleted)
    }
}

/// Its views in a row while they fit unwrapped, else one above the other, so a narrow panel doesn't squeeze each into
/// a column of wrapped words.
private struct SideBySideOrStacked<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { content }
            VStack(alignment: .leading, spacing: 8) { content }
        }
    }
}

/// What's inside an Archived or Compacted ROM's archive, read from its index when Game detail opens. An online-only
/// archive isn't read: that would download all of it just to list it.
private enum ArchiveListing: Equatable {
    case onlineOnly
    case listed([SevenZip.Entry])
    case failed(String)

    var entries: [SevenZip.Entry]? {
        if case .listed(let entries) = self { entries } else { nil }
    }

    static func read(_ archive: URL) async -> ArchiveListing {
        guard let sevenZip = SevenZip.find() else { return .failed("Install 7-Zip (`brew install sevenzip`) to see what's inside.") }
        guard SevenZip.isOnDisk(archive) else { return .onlineOnly }
        do {
            return .listed(try await sevenZip.contents(of: archive))
        } catch {
            return .failed("Couldn't read what's inside: \(error.localizedDescription)")
        }
    }
}

/// An archive's files, each at its uncompressed size; nil while it's still being read.
private struct ArchiveContentsList: View {
    let listing: ArchiveListing?

    var body: some View {
        Group {
            switch listing {
            case nil: ProgressView().controlSize(.small)
            case .onlineOnly:
                Text("Online-only in Dropbox: what's inside shows once it's downloaded.").foregroundStyle(.secondary)
            case .listed(let entries):
                ForEach(entries, id: \.path) { entry in
                    HStack {
                        Text(entry.path).fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file)).foregroundStyle(.secondary)
                            .monospacedDigit().fixedSize()
                    }
                }
            case .failed(let message): Text(message).foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .padding(.leading, 36)
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
        return "It has \(s.presentROMs) ROM\(s.presentROMs == 1 ? "" : "s") in its ROM folder. Move them out of the folder first."
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
    if let error = error as? ReviewError { return reviewErrorText(error) }
    return switch error as? LudeumError {
    case .endBeforeStart: "The end date can't come before the start date."
    case .listNameTaken: "There's already a List with that name."
    case .playerNameTaken: "There's already a Player with that name."
    case .gameHasPresentROMs: "This Game has ROMs in its ROM folder. Move them out first."
    case .romIsPresent: "That ROM is in its ROM folder, so there's nothing to forget."
    case .igdbLinkTaken: "Another Game already has that IGDB link."
    case .alreadyLinked: "This Game already has an IGDB link. Use Change IGDB link… to replace it."
    case .gameHasROMs: "This Game has ROMs, so its Platform can't change."
    case .nameRequired: "A name is required."
    case .gameNotFound: "That Game no longer exists."
    case .runAheadOutOfRange: "Run-ahead is 0 to 10 frames."
    case nil: error.localizedDescription
    }
}

private func reviewErrorText(_ error: ReviewError) -> String {
    switch error {
    case .alreadyMatched: "This ROM was already answered."
    case .suggestionGone: "IGDB no longer has the suggested game."
    case .notASiblingPlatform: "Confirm can only use this ROM's Platform or its sibling."
    case .alreadyInROMFolder: "That Platform's ROM folder already has a ROM by this name. Nothing was moved."
    case .romFilesNotFound: "A ROM's files aren't in its ROM folder, so nothing was changed. Check again first."
    case .noROMFolder: "That Platform has no ROM folder."
    case .siblingWontReadFile: "That Platform's ROM folder doesn't read this ROM's file type. Nothing was moved."
    case .noDiscsWithoutPlaylist: "This ROM's folder no longer has Discs without a playlist. Check again."
    case .bothFormsChanged: "This ROM's copies have changed in its ROM folder. Nothing went to the Trash."
    case .duplicateVersionsChanged: "This Game's ROMs have changed since they were shown. Nothing was changed."
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
    @State private var deleteRunning = false

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
        .disabled(deleteRunning)
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

    /// Off the main thread, as a backup of the whole journal is taken first.
    private func delete() {
        guard let journal = services.journal, let id = edit.id, !deleteRunning else { return }
        deleteRunning = true
        Task {
            defer { deleteRunning = false }
            do {
                try await offMain { try journal.deletePlaythrough(id) }
                done()
            } catch {
                self.error = journalErrorText(error)
            }
        }
    }

    private struct DateError: Error { let label: String }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
