import JournalCore
import SwiftUI

/// The ⌘, Settings window: IGDB credentials with "Test connection", the optional Hasheous key,
/// the OpenEmu library and the backup folder. Backing up and restoring arrive with Backups.
struct SettingsView: View {
    let settings: AppSettings

    @State private var clientID = ""
    @State private var clientSecret = ""
    @State private var hasheousKey = ""
    @State private var openEmuLibrary: URL?
    @State private var backupFolder: URL?
    @State private var check: CheckState = .idle
    @State private var saveError: String?
    @State private var choosingFolder: Folder?

    enum CheckState: Equatable {
        case idle, running
        case passed(String)
        case failed(String)
    }

    enum Folder: Identifiable {
        case openEmuLibrary, backups
        var id: Self { self }
    }

    var body: some View {
        Form {
            Section {
                if settings.needsCredentials {
                    Text(
                        "Games Journal needs IGDB credentials: register an app in the [Twitch developer console](https://dev.twitch.tv/console/apps) and paste its client ID and secret here."
                    )
                    .font(.callout)
                }
                TextField("Client ID", text: $clientID)
                SecureField("Client secret", text: $clientSecret)
                HStack {
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

            Section("Folders") {
                folderRow("OpenEmu library", openEmuLibrary, .openEmuLibrary)
                folderRow("Backups", backupFolder, .backups)
            }

            if let saveError {
                Text(saveError).foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear(perform: load)
        .onChange(of: clientID) { save() }
        .onChange(of: clientSecret) { save() }
        .onChange(of: hasheousKey) { save() }
        .fileImporter(
            isPresented: Binding(get: { choosingFolder != nil }, set: { if !$0 { choosingFolder = nil } }),
            allowedContentTypes: [.folder]
        ) { result in
            guard case .success(let url) = result, let folder = choosingFolder else { return }
            switch folder {
            case .openEmuLibrary: settings.openEmuLibrary = url
            case .backups: settings.backupFolder = url
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
        openEmuLibrary = settings.openEmuLibrary
        backupFolder = settings.backupFolder
    }

    private func save() {
        check = .idle
        do {
            try settings.setIGDBCredentials(IGDBCredentials(clientID: clientID, clientSecret: clientSecret))
            try settings.setHasheousKey(hasheousKey)
            saveError = nil
        } catch {
            saveError = "Couldn't save to the Keychain: \(error)"
        }
    }

    private func testConnection() {
        check = .running
        let credentials = IGDBCredentials(clientID: clientID, clientSecret: clientSecret)
        let key = hasheousKey.isEmpty ? nil : hasheousKey
        Task {
            do {
                let cache = try CacheStore(directory: AppDirectories.cache)
                let igdb = IGDBClient(credentials: credentials, cache: cache, tokenStore: settings.secrets)
                let hasheous = HasheousClient(cache: cache, apiKey: key)
                check = .passed(try await ConnectionCheck.run(igdb: igdb, hasheous: hasheous).summary)
            } catch {
                check = .failed(String(describing: error))
            }
        }
    }
}

enum AppDirectories {
    /// Shared with `journal-import`.
    static let cache = URL.applicationSupportDirectory.appending(path: "GamesJournal/cache", directoryHint: .isDirectory)
}
