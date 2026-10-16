import AppKit
import Foundation
import LudeumCore

let intoBundlesUsage = "into-bundles [--dry-run] [--journal <folder>] [--data <folder>]"

/// `into-bundles [--dry-run] [--journal <folder>] [--data <folder>]`: run once, by hand, with Ludeum closed. Makes the
/// Games that were really Bundles into Bundles of the Games IGDB lists for them, and the boxes recorded as one Copy per
/// Game into Bundles made by hand (`IntoBundles.mine`). Folders default to the app's own. `--dry-run` prints what would
/// happen and changes nothing.
func intoBundlesRun(_ arguments: [String]) async throws {
    var options: [String: URL] = [:]
    var dryRun = false
    var rest = arguments[...]
    while let argument = rest.popFirst() {
        switch argument {
        case "--dry-run": dryRun = true
        case "--journal", "--data":
            guard let value = rest.popFirst() else { fail("\(argument) needs a folder. usage: ludeum-import \(intoBundlesUsage)") }
            options[argument] = URL(filePath: value, directoryHint: .isDirectory)
        default: fail("unknown option \(argument). usage: ludeum-import \(intoBundlesUsage)")
        }
    }
    if !NSRunningApplication.runningApplications(withBundleIdentifier: "org.danielholmes.Ludeum").isEmpty {
        fail("Ludeum is running. Quit it, then run into-bundles again.")
    }
    let folder = LudeumFolder(
        url: options["--journal"] ?? LudeumFolder.standard.url, data: options["--data"] ?? LudeumFolder.standard.data)
    requireDataFolder(folder)
    let backups = Backups(folder: folder.backups)
    let journal = try LudeumStore(directory: folder.url, backups: backups)
    let (igdb, _) = try clients()
    let intoBundles = IntoBundles(journal: journal, igdb: igdb, backups: backups)

    let plan = try await intoBundles.plan()
    print(describe(plan, journal))
    guard plan.isRunnable else { fail("nothing was changed: fix the problems above, then run into-bundles again") }
    guard !dryRun else {
        print("Dry run: nothing was changed.")
        return
    }
    if let backup = try await intoBundles.run(plan) {
        print("Done. Backup: \(backup.url.path(percentEncoded: false))")
    } else {
        print("Nothing to do.")
    }
}

private func describe(_ plan: IntoBundles.Plan, _ journal: LudeumStore) -> String {
    var lines: [String] = ["\(plan.bundles.count) Bundles to make"]
    for bundle in plan.bundles {
        let platform = (try? journal.platform(bundle.platformId))?.name ?? "Platform \(bundle.platformId)"
        var line = "  \(bundle.name) (\(platform), \(bundle.game == nil ? "made by hand" : "from its Game"))"
        if let rating = bundle.droppedRating { line += ", dropping its Rating \(String(format: "%.1f", Double(rating.tenths) / 10))" }
        if !bundle.replacedCopies.isEmpty { line += ", one Copy for the \(bundle.replacedCopies.count) it replaces" }
        lines.append(line)
        for game in bundle.contents {
            lines.append("    \(game.game == nil ? "+" : "=") \(game.name)\(game.igdbGameId == nil ? " (by hand)" : "")")
        }
    }
    if !plan.done.isEmpty { lines.append("Already Bundles: \(plan.done.joined(separator: ", "))") }
    if !plan.problems.isEmpty {
        lines.append("Problems (\(plan.problems.count)):")
        lines += plan.problems.map { "  \($0)" }
    }
    lines.append("(+ is a Game to add, = one already in the journal)")
    return lines.joined(separator: "\n")
}
