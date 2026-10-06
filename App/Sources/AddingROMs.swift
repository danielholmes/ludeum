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
        case nil: "Choose a ROM: its file, an archive of it, its folder, or each of its Discs."
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
