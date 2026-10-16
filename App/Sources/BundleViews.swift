import AppKit
import LudeumCore
import SwiftUI

/// What a Bundle has that shows on each Game it contains (ADR 0016): its Copies, Attachments and Highlight note.
struct BundleShare: Identifiable, Equatable {
    let bundle: Game
    let roms: [LudeumROM]
    let copies: [Copy]
    let attachments: [Attachment]
    var id: GameID { bundle.id }

    /// Every Bundle containing `game`, first made first.
    @MainActor static func of(_ game: GameID, services: Services) throws -> [BundleShare] {
        guard let journal = services.journal else { return [] }
        return try journal.bundles(containing: game).map { bundle in
            BundleShare(
                bundle: bundle, roms: try journal.roms(of: bundle.id), copies: try journal.copies(of: bundle.id),
                attachments: (try? services.attachments?.attachments(of: bundle.id)) ?? [])
        }
    }
}

/// "Bundled in: Super Mario All-Stars", each a link to the Bundle.
struct BundledInLine: View {
    let bundles: [Game]
    let open: (GameID) -> Void

    var body: some View {
        FlowLayout(spacing: 4) {
            Text("Bundled in:").foregroundStyle(.secondary)
            ForEach(bundles, id: \.id) { bundle in
                Button(bundle.name) { open(bundle.id) }.buttonStyle(.link).help("Open this Bundle")
            }
        }
    }
}

/// A Game's Copies that are its Bundles': shown, not edited, here. Each Bundle's heading opens it, where they're edited.
struct BundleCopyRows: View {
    let shares: [BundleShare]
    let open: (GameID) -> Void

    var body: some View {
        ForEach(shares.filter { !$0.roms.isEmpty || !$0.copies.isEmpty }) { share in
            Button {
                open(share.bundle.id)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("From \(share.bundle.name)")
                        ForEach(share.roms) { rom in
                            Text(rom.subfolder ?? rom.fileName).strikethrough(rom.missing)
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        ForEach(share.copies) { copy in
                            Text(
                                [copyKindText(copy.draft.kind), copyDetailsText(copy.draft.details), copy.draft.gone.map(goneText)]
                                    .compactMap { $0 }.joined(separator: " · ")
                            )
                            .strikethrough(copy.draft.gone != nil).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help("A Copy of the Bundle, so of every Game in it. Open the Bundle to edit it.")
        }
    }
}

/// A Bundle's Attachments, on a Game it contains: opened from here, managed on the Bundle.
struct BundleAttachmentsSection: View {
    let share: BundleShare
    let open: (GameID) -> Void

    var body: some View {
        Section {
            ForEach(share.attachments) { attachment in
                Button {
                    NSWorkspace.shared.open(attachment.url)
                } label: {
                    Label(attachment.fileName, systemImage: attachment.isManual ? "book" : "paperclip")
                }
                .buttonStyle(.link).disabled(attachment.missing)
                .help(attachment.missing ? "Its file is missing" : "Open it")
            }
        } header: {
            HStack {
                Text("Attachments from \(share.bundle.name)")
                Spacer()
                Button("Open Bundle") { open(share.bundle.id) }.buttonStyle(.link).font(.callout)
            }
        }
    }
}

/// A Bundle's page lists the Games it contains, each a link, with Remove and Add Game….
struct BundleContentsSection: View {
    let services: Services
    let bundle: Game
    let open: (GameID) -> Void
    @State private var games: [Game] = []
    @State private var adding = false
    @State private var error: String?

    var body: some View {
        Section("Contains") {
            if games.isEmpty { Text("No Games yet").foregroundStyle(.secondary) }
            ForEach(games, id: \.id) { game in
                HStack {
                    Button(game.name) { open(game.id) }.buttonStyle(.link).help("Open this Game")
                    Spacer()
                    Button("Remove from Bundle", systemImage: "minus.circle") { change { try $0.removeFromBundle(bundle.id, game.id) } }
                        .labelStyle(.iconOnly).buttonStyle(.hover)
                        .help("Take it out of this Bundle. The Game stays in the Library.")
                }
            }
            Button("Add Game…", systemImage: "plus") { adding = true }.buttonStyle(.hover)
                .help("Add a Game from the Library, or one IGDB lists for this Bundle")
            if let error { Text(error).foregroundStyle(.red) }
        }
        .task(id: services.changes.revision) { games = (try? services.journal?.bundleGames(bundle.id)) ?? [] }
        .sheet(isPresented: $adding) { AddToBundleSheet(services: services, bundle: bundle, contained: Set(games.map(\.id))) }
    }

    private func change(_ body: (LudeumStore) throws -> Void) {
        guard let journal = services.journal else { return }
        do {
            try body(journal)
            error = nil
            services.changes.changed()
        } catch {
            self.error = journalErrorText(error)
        }
    }
}

/// Adding a Game to a Bundle: one IGDB lists for it, or any Game of its Platform in the Library.
struct AddToBundleSheet: View {
    let services: Services
    let bundle: Game
    let contained: Set<GameID>
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var library: [LibraryRow] = []
    @State private var fromIGDB: [BundleContent] = []
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add to \(bundle.name)").font(.headline)
            let missing = fromIGDB.filter { $0.game.map { !contained.contains($0) } ?? true }
            if !missing.isEmpty {
                Text("IGDB lists").foregroundStyle(.secondary)
                ForEach(missing) { content in
                    Button(content.game == nil ? "\(content.name) (adds it to the Library)" : content.name) { add(content) }
                        .buttonStyle(.link)
                }
                Divider()
            }
            TextField("Find a Game in the Library", text: $text).textFieldStyle(.roundedBorder)
            List(library.filter { !contained.contains($0.id) }) { row in
                Button(row.name) { add(row.id) }.buttonStyle(.link)
            }
            .frame(minHeight: 200)
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 420, height: 460)
        .task(id: text) {
            library =
                (try? services.journal?.library(LibraryFilter(platformId: bundle.platformId, name: text), sort: .name, ascending: true))
                ?? []
        }
        .task(id: services.changes.revision) {
            guard let search = services.gameSearch, let igdbGameId = bundle.igdbGameId,
                let result = try? await search.result(igdbGameId: igdbGameId),
                let platform = try? services.journal?.platform(bundle.platformId)
            else { return }
            fromIGDB = (try? await search.bundleContents(of: result, on: platform)) ?? []
        }
    }

    private func add(_ game: GameID) {
        guard let journal = services.journal else { return }
        do {
            try journal.addToBundle(bundle.id, game)
            services.changes.changed()
            dismiss()
        } catch {
            self.error = journalErrorText(error)
        }
    }

    private func add(_ content: BundleContent) {
        Task {
            guard let search = services.gameSearch, let igdbGameId = bundle.igdbGameId,
                let result = try await search.result(igdbGameId: igdbGameId),
                let platform = try services.journal?.platform(bundle.platformId)
            else { return }
            do {
                try search.addBundle(result, on: platform, contents: [content])
                services.changes.changed()
                dismiss()
            } catch {
                self.error = journalErrorText(error)
            }
        }
    }
}

/// Adding an IGDB bundle on a Platform: as a Bundle containing the games IGDB lists for it (each ticked, and each one
/// already in the Library linked rather than added again), or as a Game instead, for a release that's one game.
struct AddBundleSheet: View {
    let services: Services
    let result: GameSearchResult
    let platform: IGDBPlatform
    /// Adds it as a Game instead.
    let addAsGame: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var contents: [BundleContent] = []
    @State private var chosen: Set<Int64> = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add \(result.name) on \(platform.name)").font(.headline)
            Text("A Bundle contains Games, each in the Library, and its Copies count for every one of them.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if loading {
                ProgressView().controlSize(.small)
            } else if contents.isEmpty {
                Text("IGDB lists no games in it. Add them to the Bundle afterwards.").foregroundStyle(.secondary)
            }
            List(contents) { content in
                Toggle(
                    isOn: Binding(
                        get: { chosen.contains(content.id) },
                        set: { if $0 { chosen.insert(content.id) } else { chosen.remove(content.id) } })
                ) {
                    Text(content.game == nil ? content.name : "\(content.name) · In Library")
                }
                .toggleStyle(.checkbox)
            }
            .frame(minHeight: 180)
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Button("Add as a Game Instead") {
                    dismiss()
                    addAsGame()
                }
                .help("It's one game, whatever IGDB calls it (Kirby Super Star)")
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Add Bundle", action: add).keyboardShortcut(.defaultAction).disabled(loading)
            }
        }
        .padding()
        .frame(width: 460, height: 440)
        .task {
            defer { loading = false }
            do {
                contents = try await services.gameSearch?.bundleContents(of: result, on: platform) ?? []
                chosen = Set(contents.map(\.id))
            } catch {
                self.error = "Couldn't read what IGDB lists in it: \(error.localizedDescription)"
            }
        }
    }

    private func add() {
        guard let search = services.gameSearch else { return }
        do {
            try search.addBundle(result, on: platform, contents: contents.filter { chosen.contains($0.id) })
            services.changes.changed()
            dismiss()
        } catch {
            self.error = journalErrorText(error)
        }
    }
}
