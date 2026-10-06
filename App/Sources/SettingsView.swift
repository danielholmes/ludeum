import LudeumCore
import SwiftUI

/// The ⌘, Settings window: IGDB credentials with "Test connection", the optional Hasheous key,
/// the ROM folders, and backups. Players and Emulators have sheets of their own.
struct SettingsView: View {
    let settings: AppSettings
    /// Nil if the journal couldn't be opened, so there's nothing to back up or restore into.
    let journal: LudeumStore?

    @State private var clientID = ""
    @State private var clientSecret = ""
    @State private var hasheousKey = ""
    @State private var backupFolder: URL?
    @State private var ps2Folder: URL?
    @State private var romFoldersRoot: URL?
    @State private var needsCredentials = false
    @State private var check: CheckState = .idle
    /// Bumped by every edit, so a test that finishes after one doesn't report on values no longer shown.
    @State private var checkGeneration = 0
    @State private var saveError: String?
    @State private var choosingFolder: Folder?

    enum CheckState: Equatable {
        case idle, running
        case passed(String)
        case failed(String)
    }

    enum Folder: Identifiable {
        case backups, ps2, romFoldersRoot
        var id: Self { self }
    }

    var body: some View {
        Form {
            Section {
                if needsCredentials {
                    Text(
                        "Ludeum needs IGDB credentials: register an app in the [Twitch developer console](https://dev.twitch.tv/console/apps) and paste its client ID and secret here."
                    )
                    .font(.callout)
                }
                TextField("Client ID", text: $clientID)
                SecureField("Client secret", text: $clientSecret)
                HStack {
                    Button("Save", action: save).keyboardShortcut(.defaultAction)
                    Button("Test connection", action: testConnection)
                        .disabled(clientID.isEmpty || clientSecret.isEmpty || check == .running)
                    checkStatus
                }
            } header: {
                Text("IGDB")
            } footer: {
                Text("Kept in the Keychain, along with the Twitch token.").foregroundStyle(.secondary)
            }

            Section {
                SecureField("API key (optional)", text: $hasheousKey)
            } header: {
                Text("Hasheous")
            } footer: {
                Text("Hash lookups don't need a key. Set one only if anonymous lookups get throttled.").foregroundStyle(.secondary)
            }

            Section {
                folderRow("PS2", ps2Folder, .ps2)
                folderRow("Every other Platform", romFoldersRoot, .romFoldersRoot)
            } header: {
                Text("ROM folders")
            } footer: {
                Text(
                    "Every other Platform's ROM folder is in there, named for the Platform (SNES, Game Boy Color…). A .7z in a ROM folder is Archived: Unarchive it in Game detail to play."
                )
                .foregroundStyle(.secondary)
            }

            BackupsSection(journal: journal, backups: settings.backups()) { choosingFolder = .backups }
                .id(backupFolder)

            if let saveError {
                Text(saveError).foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear(perform: load)
        .onSubmit(save)
        .onChange(of: clientID) { edited() }
        .onChange(of: clientSecret) { edited() }
        .onChange(of: hasheousKey) { edited() }
        .fileImporter(
            isPresented: Binding(get: { choosingFolder != nil }, set: { if !$0 { choosingFolder = nil } }),
            allowedContentTypes: [.folder]
        ) { result in
            guard case .success(let url) = result, let folder = choosingFolder else { return }
            switch folder {
            case .backups: settings.backupFolder = url
            case .ps2: settings.ps2Folder = url
            case .romFoldersRoot: settings.romFoldersRoot = url
            }
            load()
        }
    }

    @ViewBuilder private var checkStatus: some View {
        switch check {
        case .idle: EmptyView()
        case .running: ProgressView().controlSize(.small)
        case .passed(let summary): Label(summary, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed(let message): Label(message, systemImage: "xmark.octagon.fill").foregroundStyle(.red)
        }
    }

    private func folderRow(_ title: String, _ url: URL?, _ folder: Folder) -> some View {
        LabeledContent(title) {
            HStack {
                Text(url?.path(percentEncoded: false) ?? "").lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                Button("Choose…") { choosingFolder = folder }
            }
        }
    }

    private func load() {
        clientID = settings.igdbCredentials?.clientID ?? clientID
        clientSecret = settings.igdbCredentials?.clientSecret ?? clientSecret
        hasheousKey = settings.hasheousKey ?? hasheousKey
        backupFolder = settings.backupFolder
        ps2Folder = settings.ps2Folder
        romFoldersRoot = settings.romFoldersRoot
        needsCredentials = settings.needsCredentials
    }

    private func edited() {
        check = .idle
        checkGeneration += 1
    }

    private func save() {
        check = .idle
        do {
            try settings.setIGDBCredentials(IGDBCredentials(clientID: clientID, clientSecret: clientSecret))
            try settings.setHasheousKey(hasheousKey)
            saveError = nil
            needsCredentials = settings.needsCredentials
        } catch {
            saveError = "Couldn't save to the Keychain: \(error)"
        }
    }

    private func testConnection() {
        check = .running
        checkGeneration += 1
        let generation = checkGeneration
        let credentials = IGDBCredentials(clientID: clientID, clientSecret: clientSecret)
        let key = hasheousKey.isEmpty ? nil : hasheousKey
        Task {
            do {
                let cache = try CacheStore(directory: CacheStore.defaultDirectory)
                let igdb = IGDBClient(credentials: credentials, cache: cache, tokenStore: settings.secrets)
                let hasheous = HasheousClient(cache: cache, apiKey: key)
                let summary = try await ConnectionCheck.run(igdb: igdb, hasheous: hasheous).summary
                if generation == checkGeneration { check = .passed(summary) }
            } catch {
                if generation == checkGeneration { check = .failed(String(describing: error)) }
            }
        }
    }
}
