import AppKit
import LudeumCore
import SwiftUI

/// What's been picked to Add as a ROM, and the Platforms whose ROM folders read it.
struct PickedROM: Identifiable {
    let source: ROMSource
    let platforms: [Int64]
    var id: [URL] { source.urls }
}

/// Asks for a ROM to Add: its file, an archive of it, its folder, or each of its Discs. `folders` picks only folders
/// (a Platform whose ROMs are kept in subfolders), false only one file, nil anything. Nil when cancelled.
@MainActor func pickROM(folders: Bool?) -> [URL]? {
    let panel = NSOpenPanel()
    panel.canChooseFiles = folders != true
    panel.canChooseDirectories = folders != false
    panel.allowsMultipleSelection = folders == nil
    panel.prompt = "Choose"
    panel.message =
        switch folders {
        case true?: "Choose the ROM's folder."
        case false?: "Choose the ROM's file, or an archive of it."
        case nil:
            "Choose a ROM: its file, an archive of it, its folder, or each of its Discs. Choose several ROMs to add them all, for an Import to Match."
        }
    return panel.runModal() == .OK && !panel.urls.isEmpty ? panel.urls : nil
}

/// Reads what was picked: the Platforms that can take it, or why none can.
func readPicked(_ urls: [URL]) async throws -> PickedROM {
    let source = ROMSource(urls)
    let platforms = try await source.platforms(sevenZip: SevenZip.find())
    guard !platforms.isEmpty else { throw AddROMError.noPlatformReadsIt }
    return PickedROM(source: source, platforms: platforms)
}

/// Adds the ROM as a Background task. Once it has run, the screens see what it did, and `added` gets its Game if it's in.
@MainActor func startAddingROM(
    _ source: ROMSource, on platformId: Int64, match: AddROMMatch, keepingOriginals: Bool, services: Services,
    added: @escaping (GameID) -> Void = { _ in }
) {
    guard let journal = services.journal,
        let folder = services.settings.romFolders.first(where: { $0.platformId == platformId })
    else { return }
    let adder = AddROM(journal: journal, libretro: services.libretro)
    let name = source.romName
    services.tasks.enqueue("Adding \(name)") { progress in
        try await adder.add(source, to: folder, match: match, keepingOriginals: keepingOriginals, progress: progress)
    } ended: { [changes = services.changes] in
        // Recorded only once it's all in place, so a ROM of its name Matched to a Game means it worked.
        if let rom = try? journal.romID(named: name, on: platformId), let game = try? journal.game(ofROM: rom) { added(game) }
        changes.coverChanged()  // its Box art
    }
}

/// Add ROM, from the toolbar: search IGDB for the picked ROM's game, then Add it on the Platform chosen.
struct AddROMSheet: View {
    let services: Services
    let picked: PickedROM
    let added: (GameID) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var chosen: (result: GameSearchResult, platform: IGDBPlatform)?
    @State private var error: String?

    /// Only the Platforms whose ROM folders read it can be chosen.
    private var platforms: [IGDBPlatform] {
        picked.platforms.map { IGDBPlatform(id: $0, name: ROMPlatform.all[$0]?.name ?? "Platform \($0)") }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let chosen {
                AddROMConfirmation(
                    services: services, source: picked.source, platformId: chosen.platform.id,
                    gameName: chosen.result.name,
                    existing: try? services.journal?.gameID(
                        igdbGameId: chosen.result.igdbGameId, platformId: chosen.platform.id),
                    back: { self.chosen = nil }
                ) { keepingOriginals, _ in
                    let match = AddROMMatch.igdb(gameId: chosen.result.igdbGameId, name: chosen.result.name, platform: chosen.platform)
                    startAddingROM(
                        picked.source, on: chosen.platform.id, match: match, keepingOriginals: keepingOriginals, services: services,
                        added: added)
                    dismiss()
                }
            } else {
                Text("Add \(picked.source.romName)").font(.title2)
                Text("Choose its game, and the Platform it goes on.").foregroundStyle(.secondary)
                if let search = services.gameSearch {
                    IGDBSearchView(
                        search: search, platforms: platforms, usedPlatforms: Set(picked.platforms), query: $query,
                        platformFilter: platforms.count == 1 ? platforms[0] : nil
                    ) { result, platform in
                        if picked.platforms.contains(platform.id) {
                            error = nil
                            chosen = (result, platform)
                        } else {
                            error = AddROMError.platformWontReadIt(platform.name).localizedDescription
                        }
                    }
                } else {
                    Text("Set IGDB credentials in Settings to search IGDB.").foregroundStyle(.secondary)
                }
                if let error { Text(error).foregroundStyle(.red) }
                HStack {
                    Spacer()
                    Button("Cancel", role: .cancel) { dismiss() }
                }
            }
        }
        .padding()
        .frame(width: 640, height: chosen == nil ? 560 : nil)
        .onAppear { query = cleanName(picked.source.romName) }
    }
}

/// The last step of Add ROM: where it goes and what's done to it, and whether the picked files are copied or moved.
struct AddROMConfirmation: View {
    let services: Services
    let source: ROMSource
    let platformId: Int64
    let gameName: String
    /// The Game it joins, when the journal has it already.
    let existing: GameID?
    /// Offered when the Game has missing ROMs: forget them once the new one is in.
    var missingROMs = 0
    var back: (() -> Void)? = nil
    /// Whether to keep the picked files, and to forget the Game's missing ROMs.
    let add: (_ keepingOriginals: Bool, _ forgettingMissing: Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @AppStorage("addROMKeepsOriginals") private var keepingOriginals = true
    @State private var forgettingMissing = true

    private var platform: ROMPlatform? { ROMPlatform.all[platformId] }
    private var folder: ROMFolder? { services.settings.romFolders.first { $0.platformId == platformId } }

    var body: some View {
        Form {
            Section {
                Text("Add \(source.romName)").font(.title2).bold()
                LabeledContent("Game", value: gameName)
                LabeledContent("Platform", value: platform?.name ?? "Platform \(platformId)")
                if let folder {
                    LabeledContent("Goes in", value: "ROMs/\(folder.url.lastPathComponent)/\(AddROM.fileName(of: source, in: folder))")
                }
                Text(what).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if existing != nil, missingROMs == 0 {
                    Text("It's already in the Library, so the ROM joins that Game.").foregroundStyle(.secondary)
                }
            }
            Section {
                Picker("Picked files", selection: $keepingOriginals) {
                    Text("Copy them").tag(true)
                    Text("Move them").tag(false)
                }
                .pickerStyle(.radioGroup)
                Text(keepingOriginals ? "They stay where they are." : "They go to the Trash once the ROM is in.")
                    .font(.caption).foregroundStyle(.secondary)
                if missingROMs > 0 {
                    Toggle("Forget its \(missingROMs == 1 ? "missing ROM" : "\(missingROMs) missing ROMs")", isOn: $forgettingMissing)
                        .help("A missing ROM of the same name comes back instead, whatever this says.")
                }
            }
            HStack {
                if let back { Button("Back", action: back) }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Add ROM") { add(keepingOriginals, missingROMs > 0 && forgettingMissing) }.keyboardShortcut(.defaultAction)
            }
        }
        .formStyle(.grouped)
    }

    private var what: String {
        let unpacked = source.archive.map { "\($0.lastPathComponent) is unpacked, then " } ?? ""
        if source.isFolder || source.urls.count > 1 || platform?.archiving == .intoFolder {
            return "It's kept in a folder of its name, with a playlist for its Discs if they have none."
        }
        if let compact = platform?.compactExtension {
            if source.archive?.pathExtension.lowercased() == compact { return "It goes in as it is: its Emulator opens it directly." }
            return unpacked.isEmpty
                ? "It's Compacted into a .\(compact) its Emulator opens directly."
                : unpacked + "its game is Compacted into a .\(compact) its Emulator opens directly."
        }
        return unpacked.isEmpty ? "It's kept as one file named after it." : unpacked + "its game is kept as one file named after it."
    }
}

/// A Missing ROMs item's Add ROM: pick a file (or a folder, where the Platform keeps its ROMs in subfolders), then Add it
/// to the Game.
struct AddROMToGameSheet: View {
    let services: Services
    let game: Game
    let picked: PickedROM
    let missingROMs: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        AddROMConfirmation(
            services: services, source: picked.source, platformId: game.platformId, gameName: game.name, existing: game.id,
            missingROMs: missingROMs
        ) { keepingOriginals, forgetting in
            startAddingROM(
                picked.source, on: game.platformId, match: .game(game.id, forgettingMissing: forgetting),
                keepingOriginals: keepingOriginals, services: services)
            dismiss()
        }
        .padding()
        .frame(width: 560)
    }
}

/// One of several ROMs picked at once: the Platforms whose ROM folders read it, or why none can.
struct PickedROMsRow: Identifiable {
    let source: ROMSource
    let platforms: [Int64]
    let problem: String?
    var id: [URL] { source.urls }
}

/// Several ROMs picked at once, for the Add ROMs sheet.
struct PickedROMs: Identifiable {
    let id = UUID()
    let rows: [PickedROMsRow]
}

/// Reads each of several ROMs picked at once, as `readPicked` reads one. Only Platforms with a ROM folder can take one,
/// and not where that folder has a ROM of its name already.
func readPicked(several sources: [ROMSource], romFolders: [ROMFolder]) async -> PickedROMs {
    let sevenZip = SevenZip.find()
    let folders = Dictionary(romFolders.map { ($0.platformId, $0) }) { first, _ in first }
    var rows: [PickedROMsRow] = []
    for source in sources {
        do {
            let reading = try await source.platforms(sevenZip: sevenZip).filter { folders[$0] != nil }
            guard !reading.isEmpty else { throw AddROMError.noPlatformReadsIt }
            let platforms = reading.filter { (try? folders[$0]?.rom(named: source.romName)) == nil }
            guard !platforms.isEmpty else { throw AddROMError.alreadyInROMFolder(source.romName) }
            rows.append(PickedROMsRow(source: source, platforms: platforms, problem: nil))
        } catch {
            rows.append(PickedROMsRow(source: source, platforms: [], problem: journalErrorText(error)))
        }
    }
    return PickedROMs(rows: rows)
}

/// "1 ROM", "3 ROMs".
func romCount(_ count: Int) -> String { count == 1 ? "1 ROM" : "\(count) ROMs" }

/// Adds several ROMs as one Background task, unmatched. Once it has run (also when some failed or it was cancelled, as
/// the ones before went in), `then` runs, for the Import that Matches them.
@MainActor func startAddingROMs(
    _ roms: [(source: ROMSource, platformId: Int64)], keepingOriginals: Bool, services: Services, then: @escaping () -> Void
) {
    guard let journal = services.journal else { return }
    let folders = services.settings.romFolders
    let items = roms.compactMap { rom in folders.first { $0.platformId == rom.platformId }.map { (source: rom.source, folder: $0) } }
    let adder = AddROM(journal: journal, libretro: services.libretro)
    services.tasks.enqueue("Adding \(romCount(items.count))") { progress in
        try await adder.add(items, keepingOriginals: keepingOriginals, progress: progress)
    } ended: {
        then()
    }
}

/// Add ROM with several ROMs picked: each goes into its Platform's ROM folder unmatched, then an Import Matches them,
/// automatically where the checksum and name agree, else in the Review queue. Each needs a Platform, chosen for me
/// where it's clear.
struct AddROMsSheet: View {
    let services: Services
    let picked: PickedROMs
    /// Runs the Import once they're in.
    let thenImport: () -> Void
    @Environment(\.dismiss) private var dismiss
    @AppStorage("addROMKeepsOriginals") private var keepingOriginals = true
    /// Each ROM's Platform, by its row: nil until chosen.
    @State private var platforms: [[URL]: Int64] = [:]
    /// Rows I've left out.
    @State private var skipped: Set<[URL]> = []

    private var addable: [PickedROMsRow] { picked.rows.filter { $0.problem == nil && !skipped.contains($0.id) } }
    private var undecided: [PickedROMsRow] { addable.filter { platforms[$0.id] == nil } }
    /// Rows that would go in under the same name as another on the same Platform: only one of them could.
    private var clashing: Set<[URL]> {
        let chosen = addable.compactMap { row in platforms[row.id].map { (row.id, "\($0) \(row.source.romName)") } }
        let counts = Dictionary(chosen.map { ($0.1, 1) }, uniquingKeysWith: +)
        return Set(chosen.filter { counts[$0.1, default: 0] > 1 }.map(\.0))
    }
    /// The Platforms some undecided ROM could go on, for Set Platform.
    private var undecidedPlatforms: [Int64] {
        Set(undecided.flatMap(\.platforms)).sorted { name(of: $0).localizedStandardCompare(name(of: $1)) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add \(picked.rows.count) ROMs").font(.title2).bold()
            Text(
                "Each goes into its Platform's ROM folder, ready to Play. Then an Import Matches them: automatically where the checksum and name agree, else they wait in the Review queue."
            )
            .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if services.igdb == nil || services.hasheous == nil {
                Text("Set IGDB and Hasheous credentials in Settings: until then no Import can read them, so they won't be Matched.")
                    .foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            List(picked.rows) { row in
                rowView(row)
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            .frame(minHeight: 200)
            HStack(alignment: .top) {
                Picker("Picked files", selection: $keepingOriginals) {
                    Text("Copy them").tag(true)
                    Text("Move them").tag(false)
                }
                .pickerStyle(.radioGroup)
                Text(keepingOriginals ? "They stay where they are." : "They go to the Trash once each ROM is in.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if !undecided.isEmpty {
                    Menu("Set Platform") {
                        ForEach(undecidedPlatforms, id: \.self) { platform in
                            Button(name(of: platform)) {
                                for row in undecided where row.platforms.contains(platform) { platforms[row.id] = platform }
                            }
                        }
                    }
                    .fixedSize()
                    .help("Choose the Platform of every ROM still without one that it can go on")
                }
            }
            HStack {
                if !undecided.isEmpty {
                    Text("Choose a Platform for each ROM, or leave it out.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Add \(romCount(addable.count))", action: add)
                    .keyboardShortcut(.defaultAction)
                    .disabled(addable.isEmpty || !undecided.isEmpty || !clashing.isEmpty)
            }
        }
        .padding()
        .frame(width: 720, height: 560)
        .onAppear {
            for row in picked.rows {
                if let likeliest = row.source.likeliestPlatform(of: row.platforms) { platforms[row.id] = likeliest }
            }
        }
    }

    @ViewBuilder private func rowView(_ row: PickedROMsRow) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Toggle(
                "Add",
                isOn: Binding(
                    get: { row.problem == nil && !skipped.contains(row.id) },
                    set: { if $0 { skipped.remove(row.id) } else { skipped.insert(row.id) } })
            )
            .labelsHidden()
            .disabled(row.problem != nil)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.source.romName).lineLimit(1).truncationMode(.middle)
                if let problem = row.problem {
                    Text(problem).font(.caption).foregroundStyle(.red)
                } else if clashing.contains(row.id) {
                    Text("Another ROM picked goes in under this name on this Platform: leave one out.")
                        .font(.caption).foregroundStyle(.red)
                } else if let platform = platforms[row.id],
                    let folder = services.settings.romFolders.first(where: { $0.platformId == platform })
                {
                    Text("ROMs/\(folder.url.lastPathComponent)/\(AddROM.fileName(of: row.source, in: folder))")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer()
            if row.problem == nil {
                if row.platforms.count == 1 {
                    Text(name(of: row.platforms[0])).foregroundStyle(.secondary)
                } else {
                    Picker("Platform", selection: Binding(get: { platforms[row.id] }, set: { platforms[row.id] = $0 })) {
                        Text("Choose…").tag(Int64?.none)
                        ForEach(row.platforms, id: \.self) { Text(name(of: $0)).tag(Int64?.some($0)) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
        }
        .opacity(row.problem == nil && skipped.contains(row.id) ? 0.5 : 1)
    }

    private func name(of platform: Int64) -> String { ROMPlatform.all[platform]?.name ?? "Platform \(platform)" }

    private func add() {
        let roms = addable.compactMap { row in platforms[row.id].map { (source: row.source, platformId: $0) } }
        startAddingROMs(roms, keepingOriginals: keepingOriginals, services: services, then: thenImport)
        dismiss()
    }
}
