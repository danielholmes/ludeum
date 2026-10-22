import LudeumCore
import SwiftUI
import os

/// The Import: reading the ROM folders against the journal, at launch and by hand (the Review queue's Check again, and
/// adding Stray files as ROMs, from there or after Add ROMs). One at a time; a request mid-Import runs once more after it.
@Observable @MainActor final class ImportModel {
    /// The last Import's changes, shown until dismissed. Nil when it changed nothing.
    var summary: ImportResult?
    /// Why the last Import failed, shown until dismissed.
    var error: String?
    private var runAgain = false
    private var runAgainShowingMatched = false
    private var runAgainAdding: Set<StrayFile.Key> = []
    private let services: Services

    /// True while an Import runs: quitting asks first. Static, as the app delegate has no `Services` to ask.
    static var isRunning = false
    private static let log = Logger(subsystem: "org.danielholmes.Ludeum", category: "import")

    init(services: Services) {
        self.services = services
    }

    /// `byHand` is false for the launch Import, which says nothing when it's refused: the main window's banner does.
    /// `showingMatched` has the summary list the ROMs it Matched automatically, and the missing ones that came back to
    /// their Game, too: as after Add ROMs, where I want to know where each went. `adding` names the Stray files it records
    /// as new ROMs.
    func importNow(byHand: Bool = true, showingMatched: Bool = false, adding: Set<StrayFile.Key> = []) {
        guard let igdb = services.igdb, let hasheous = services.hasheous, let journal = services.journal else { return }
        guard services.work.beginImport() else {
            runAgain = true
            runAgainShowingMatched = runAgainShowingMatched || showingMatched
            runAgainAdding.formUnion(adding)
            return
        }
        Self.isRunning = true
        let run = Import(
            igdb: igdb, hasheous: hasheous, journal: journal, backups: services.settings.backups())
        let romFolders = services.settings.romFolders
        Task {
            do {
                let work = services.work
                let result = try await run.run(romFolders: romFolders, adding: adding) {
                    await MainActor.run { work.lockJournal(true) }
                } wrote: {
                    await MainActor.run { work.lockJournal(false) }
                }
                // Attachments too: a Game's folder follows its name, and a file gone from it waits in the Review queue.
                // The Import has written by now, so a failure here is only logged, and tried again at the next one.
                if let attachments = services.attachments {
                    do {
                        try await offMain {
                            try attachments.followAll()
                            try attachments.checkFiles()
                        }
                    } catch {
                        Self.log.error("Attachments not checked: \(error, privacy: .public)")
                    }
                }
                var shown = result
                if !showingMatched {
                    shown.matched = []
                    shown.returned = []
                }
                if shown.changedSomething || !shown.matched.isEmpty || !shown.returned.isEmpty { summary = shown }
                error = nil
                // The launch Import has every Cover read again only when one may have changed. Check again always
                // does: it's also how a Cover left stale by something else (a Match by hand) is put right.
                if byHand || result.coversChanged { services.changes.coverChanged() } else { services.changes.changed() }
            } catch ImportError.openEmuMigrationNeeded {
                if byHand { error = OpenEmuMigrationBanner.message }
            } catch {
                self.error = "Import failed: \(error.localizedDescription)"
            }
            Self.isRunning = false
            services.work.endImport()
            if runAgain {
                let showing = runAgainShowingMatched
                let adding = runAgainAdding
                runAgain = false
                runAgainShowingMatched = false
                runAgainAdding = []
                importNow(showingMatched: showing, adding: adding)
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
            model.importNow(byHand: false)
        }
    }
}
