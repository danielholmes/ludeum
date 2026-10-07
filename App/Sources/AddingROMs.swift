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
            "Choose a ROM: its file, an archive of it, its folder, or each of its Discs. Choose several ROMs to add them one after another."
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

    var body: some View {
        AddROMFlow(services: services, picked: picked) { chosen, platform, keepingOriginals in
            let match = AddROMMatch.igdb(gameId: chosen.igdbGameId, name: chosen.name, platform: platform)
            startAddingROM(
                picked.source, on: platform.id, match: match, keepingOriginals: keepingOriginals, services: services, added: added)
            dismiss()
        } buttons: {
            EmptyView()
        }
        .padding()
        .frame(width: 640)
    }
}

/// One ROM's Add ROM, as the toolbar's sheet and each step of Add ROMs show it: the IGDB search, already run on the ROM's
/// name, its Platform filter limited to the Platforms that read it (set when one is clear); then where it goes, and
/// whether the picked files are copied or moved. `buttons` go beside the search's Cancel.
struct AddROMFlow<Buttons: View>: View {
    let services: Services
    let picked: PickedROM
    /// Why the Platform can't take it, beyond its ROM folder not reading it: nil when it can.
    let refused: (IGDBPlatform) -> String?
    let add: (_ game: GameSearchResult, _ platform: IGDBPlatform, _ keepingOriginals: Bool) -> Void
    @ViewBuilder let buttons: () -> Buttons
    @Environment(\.dismiss) private var dismiss
    @State private var query: String
    @State private var chosen: (result: GameSearchResult, platform: IGDBPlatform)?
    @State private var error: String?

    init(
        services: Services, picked: PickedROM, refused: @escaping (IGDBPlatform) -> String? = { _ in nil },
        add: @escaping (_ game: GameSearchResult, _ platform: IGDBPlatform, _ keepingOriginals: Bool) -> Void,
        @ViewBuilder buttons: @escaping () -> Buttons
    ) {
        self.services = services
        self.picked = picked
        self.refused = refused
        self.add = add
        self.buttons = buttons
        _query = State(initialValue: cleanName(picked.source.romName))
    }

    /// Only the Platforms whose ROM folders read it can be chosen.
    private var platforms: [IGDBPlatform] {
        picked.platforms.map { IGDBPlatform(id: $0, name: ROMPlatform.all[$0]?.name ?? "Platform \($0)") }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let chosen {
                AddROMConfirmation(
                    services: services, source: picked.source, platformId: chosen.platform.id, gameName: chosen.result.name,
                    existing: try? services.journal?.gameID(igdbGameId: chosen.result.igdbGameId, platformId: chosen.platform.id),
                    back: { self.chosen = nil }
                ) { keepingOriginals, _ in
                    add(chosen.result, chosen.platform, keepingOriginals)
                }
            } else {
                Text("Add \(picked.source.romName)").font(.title2)
                Text("Choose its game, and the Platform it goes on.").foregroundStyle(.secondary)
                if let search = services.gameSearch {
                    let likeliest = picked.source.likeliestPlatform(of: picked.platforms)
                    IGDBSearchView(
                        search: search, platforms: platforms, usedPlatforms: Set(picked.platforms), query: $query,
                        platformFilter: platforms.first { $0.id == likeliest }
                    ) { result, platform in
                        if !picked.platforms.contains(platform.id) {
                            error = AddROMError.platformWontReadIt(platform.name).localizedDescription
                        } else if let refusal = refused(platform) {
                            error = refusal
                        } else {
                            error = nil
                            chosen = (result, platform)
                        }
                    }
                } else {
                    Text("Set IGDB credentials in Settings to search IGDB.").foregroundStyle(.secondary)
                }
                if let error { Text(error).foregroundStyle(.red) }
                HStack {
                    buttons()
                    Spacer()
                    Button("Cancel", role: .cancel) { dismiss() }
                }
            }
        }
        .frame(height: chosen == nil ? 540 : nil)
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

/// Add ROM with several ROMs picked: each in turn, as Add ROM does one, with the IGDB search already run on its name.
/// One whose game IGDB doesn't have can go in without a Match instead, for an Import to Match automatically or send to
/// the Review queue, or be skipped. Those without a Match go in together from a last step, where I choose whether their
/// files are copied or moved; cancelling leaves them out.
struct AddROMsSheet: View {
    let services: Services
    let picked: PickedROMs
    /// Runs the Import once those without a Match are in.
    let thenImport: () -> Void
    @Environment(\.dismiss) private var dismiss
    @AppStorage("addROMKeepsOriginals") private var keepingOriginals = true
    @State private var step = 0
    /// What became of each ROM done with, by its place in `picked.rows`.
    @State private var done: [Int: Fate] = [:]
    /// Why Add without a Match was refused, until another ROM is shown.
    @State private var clashMessage: String?
    /// Every ROM is done with, and the last step adds those without a Match.
    @State private var finishing = false

    enum Fate: Equatable {
        /// Queued to be Added and Matched to this game, on this Platform.
        case added(game: String, platform: Int64)
        /// To go in without a Match on this Platform, from the last step.
        case unmatched(platform: Int64)
        case skipped

        /// Queued already, so it can't be undone here.
        var queued: Bool { if case .added = self { true } else { false } }

        var platform: Int64? {
            switch self {
            case .added(_, let platform), .unmatched(let platform): platform
            case .skipped: nil
            }
        }
    }

    private var row: PickedROMsRow { picked.rows[step] }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            stepper
            Divider()
            if finishing {
                lastStep
            } else if let fate = done[step] {
                doneView(fate)
            } else if let problem = row.problem {
                Text("Add \(row.source.romName)").font(.title2)
                Text(problem).foregroundStyle(.red)
                Spacer()
                HStack {
                    Spacer()
                    Button("Cancel", role: .cancel) { dismiss() }
                    Button(nextLabel) { goOn() }.keyboardShortcut(.defaultAction)
                }
            } else {
                AddROMFlow(
                    services: services, picked: PickedROM(source: row.source, platforms: row.platforms), refused: clash
                ) { game, platform, keepingOriginals in
                    let match = AddROMMatch.igdb(gameId: game.igdbGameId, name: game.name, platform: platform)
                    startAddingROM(row.source, on: platform.id, match: match, keepingOriginals: keepingOriginals, services: services)
                    finish(.added(game: game.name, platform: platform.id))
                } buttons: {
                    Button("Skip") { finish(.skipped) }.help("Leave this ROM out")
                    withoutAMatch
                }
                .id(step)
                if let clashMessage { Text(clashMessage).foregroundStyle(.red) }
            }
        }
        .padding()
        .frame(width: 640, height: 640, alignment: .top)
        .onAppear { step = picked.rows.indices.first(where: isPending) ?? 0 }
        .onChange(of: step) { clashMessage = nil }
    }

    /// The ROMs to go in without a Match, in order.
    private var unmatchedROMs: [(source: ROMSource, platformId: Int64)] {
        picked.rows.indices.compactMap { i in
            guard case .unmatched(let platform) = done[i] else { return nil }
            return (picked.rows[i].source, platform)
        }
    }

    /// Once every ROM is done with: those without a Match, and whether their files are copied or moved.
    @ViewBuilder private var lastStep: some View {
        let roms = unmatchedROMs
        Text("Add \(romCount(roms.count)) without a Match").font(.title2)
        Text(
            "Each goes into its Platform's ROM folder, ready to Play. Then an Import Matches them automatically where the checksum and name agree, else they wait in the Review queue."
        )
        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        List(roms, id: \.source.urls) { rom in
            LabeledContent(rom.source.romName, value: platformName(rom.platformId))
        }
        .listStyle(.bordered(alternatesRowBackgrounds: true))
        Picker("Picked files", selection: $keepingOriginals) {
            Text("Copy them").tag(true)
            Text("Move them").tag(false)
        }
        .pickerStyle(.radioGroup)
        Text(keepingOriginals ? "They stay where they are." : "They go to the Trash once each ROM is in.")
            .font(.caption).foregroundStyle(.secondary)
        HStack {
            Spacer()
            Button("Cancel", role: .cancel) { dismiss() }
                .help("Close without adding these: the ROMs already queued are still Added")
            Button("Add \(romCount(roms.count))") {
                startAddingROMs(roms, keepingOriginals: keepingOriginals, services: services, then: thenImport)
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    /// Which ROM this is, a strip of every ROM showing what became of it, and the way between them.
    private var stepper: some View {
        HStack(spacing: 8) {
            Button("Previous", systemImage: "chevron.left") { show(step - 1) }.disabled(step == 0)
            Text("ROM \(step + 1) of \(picked.rows.count)").monospacedDigit()
            Button("Next", systemImage: "chevron.right") { show(step + 1) }.disabled(step == picked.rows.count - 1)
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(picked.rows.indices, id: \.self) { i in
                            Button {
                                show(i)
                            } label: {
                                stepMark(i)
                            }
                            .buttonStyle(.plain)
                            .help(picked.rows[i].source.romName)
                            .id(i)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .onChange(of: step) { withAnimation { proxy.scrollTo(step, anchor: .center) } }
            }
        }
        .labelStyle(.iconOnly)
    }

    private func stepMark(_ i: Int) -> some View {
        let (symbol, colour): (String, Color) =
            switch done[i] {
            case .added?: ("checkmark.circle.fill", .green)
            case .unmatched?: ("tray.circle.fill", .blue)
            case .skipped?: ("minus.circle.fill", .gray)
            case nil: picked.rows[i].problem == nil ? ("\(i + 1).circle", .secondary) : ("exclamationmark.circle.fill", .red)
            }
        return Image(systemName: symbol).font(.title3).foregroundStyle(colour)
            .padding(2)
            .background(i == step ? Color.accentColor.opacity(0.25) : .clear, in: .circle)
    }

    /// A ROM already done with: what's to become of it, with Undo for one not yet queued.
    @ViewBuilder private func doneView(_ fate: Fate) -> some View {
        Text(row.source.romName).font(.title2)
        switch fate {
        case .added(let game, let platform):
            Text("It's being Added to \(game) on \(platformName(platform)): see Background tasks.").foregroundStyle(.secondary)
        case .unmatched(let platform):
            Text(
                "It goes into \(platformName(platform))'s ROM folder without a Match, from the last step once every ROM is done with. Then an Import Matches it automatically, or it waits in the Review queue."
            )
            .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        case .skipped:
            Text("Skipped: it isn't added.").foregroundStyle(.secondary)
        }
        Spacer()
        HStack {
            if !fate.queued {
                Button("Undo") { done[step] = nil }
            }
            Spacer()
            Button(nextLabel) { goOn() }.keyboardShortcut(.defaultAction)
        }
    }

    /// Add without a Match: on its likeliest Platform, or the one chosen from those that read it.
    @ViewBuilder private var withoutAMatch: some View {
        let help = "It goes into its ROM folder, and an Import Matches it automatically or sends it to the Review queue"
        if let platform = row.source.likeliestPlatform(of: row.platforms) {
            Button("Add without a Match") { unmatched(on: platform) }.help(help)
        } else {
            Menu("Add without a Match") {
                ForEach(row.platforms, id: \.self) { platform in
                    Button(platformName(platform)) { unmatched(on: platform) }
                }
            }
            .fixedSize()
            .help(help)
        }
    }

    private func unmatched(on platform: Int64) {
        if let refusal = clash(IGDBPlatform(id: platform, name: platformName(platform))) {
            clashMessage = refusal
        } else {
            finish(.unmatched(platform: platform))
        }
    }

    /// Two picked ROMs can't go in under one name on one Platform.
    private func clash(_ platform: IGDBPlatform) -> String? {
        let name = row.source.romName
        let taken = done.contains { i, fate in i != step && fate.platform == platform.id && picked.rows[i].source.romName == name }
        return taken ? "Another ROM picked goes in under this name on \(platform.name): skip one of them." : nil
    }

    private func finish(_ fate: Fate) {
        done[step] = fate
        goOn()
    }

    /// Still to be done with: not yet Added, put without a Match or skipped, and able to go in at all.
    private func isPending(_ i: Int) -> Bool { done[i] == nil && picked.rows[i].problem == nil }

    /// The next ROM still to be done with, after this one, else before it.
    private var nextPending: Int? {
        let order = Array(picked.rows.indices[(step + 1)...]) + Array(picked.rows.indices[..<step])
        return order.first(where: isPending)
    }

    private var nextLabel: String { nextPending != nil ? "Next ROM" : unmatchedROMs.isEmpty ? "Done" : "Continue" }

    /// On to the next ROM still to be done with; once there's none, the last step if any go in without a Match, else
    /// closes.
    private func goOn() {
        if let next = nextPending {
            step = next
        } else if !unmatchedROMs.isEmpty {
            finishing = true
        } else {
            dismiss()
        }
    }

    /// Shows the `i`th ROM, leaving the last step.
    private func show(_ i: Int) {
        step = i
        finishing = false
    }

    private func platformName(_ platform: Int64) -> String { ROMPlatform.all[platform]?.name ?? "Platform \(platform)" }
}
