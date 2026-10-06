import LudeumCore
import SwiftUI

/// The Import: reading the ROM folders into the journal, at launch and by hand (the Review queue's Check again).
/// One at a time; a request mid-Import runs once more after it.
@Observable @MainActor final class ImportModel {
    /// The last Import's changes, shown until dismissed. Nil when it changed nothing.
    var summary: ImportResult?
    /// Why the last Import failed, shown until dismissed.
    var error: String?
    private(set) var importing = false
    private var runAgain = false
    private let services: Services

    /// True while an Import runs: quitting asks first.
    static var isRunning = false

    init(services: Services) {
        self.services = services
    }

    func importNow() {
        guard let igdb = services.igdb, let hasheous = services.hasheous, let journal = services.journal else { return }
        guard !importing else {
            runAgain = true
            return
        }
        guard services.work.begin(.importing) else { return }
        importing = true
        Self.isRunning = true
        let run = Import(
            igdb: igdb, hasheous: hasheous, journal: journal, backups: services.settings.backups(), libretro: services.libretro)
        let romFolders = services.settings.romFolders
        Task {
            do {
                let work = services.work
                let result = try await run.run(romFolders: romFolders) {
                    await MainActor.run { work.lockJournal(true) }
                } wrote: {
                    await MainActor.run { work.lockJournal(false) }
                }
                if result.changedSomething { summary = result }
                error = nil
                services.changes.coverChanged()  // the Box art step can change Covers
            } catch {
                self.error = "Import failed: \(error.localizedDescription)"
            }
            importing = false
            Self.isRunning = false
            services.work.end(.importing)
            if runAgain {
                runAgain = false
                importNow()
            }
        }
    }
}

/// Runs an Import once at launch, not for every new main window.
struct ImportOnLaunch: ViewModifier {
    let model: ImportModel
    @MainActor private static var launched = false

    func body(content: Content) -> some View {
        content.task {
            guard !Self.launched else { return }
            Self.launched = true
            model.importNow()
        }
    }
}
