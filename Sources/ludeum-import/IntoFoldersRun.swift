import AppKit
import Foundation
import LudeumCore

let intoFoldersUsage = "into-folders [--dry-run] [--journal <folder>] [--data <folder>]"

/// `into-folders [--dry-run] [--journal <folder>] [--data <folder>]`: run once, by hand, with Ludeum closed. Moves each
/// loose ROM of a disc Platform into a subfolder named after it. Folders default to the app's own; `--data` stands in
/// for the Data folder for this run only. `--dry-run` prints what would happen and changes nothing.
func intoFoldersRun(_ arguments: [String]) async throws {
    var options: [String: URL] = [:]
    var dryRun = false
    var rest = arguments[...]
    while let argument = rest.popFirst() {
        switch argument {
        case "--dry-run": dryRun = true
        case "--journal", "--data":
            guard let value = rest.popFirst() else { fail("\(argument) needs a folder. usage: ludeum-import \(intoFoldersUsage)") }
            options[argument] = URL(filePath: value, directoryHint: .isDirectory)
        default: fail("unknown option \(argument). usage: ludeum-import \(intoFoldersUsage)")
        }
    }
    if !NSRunningApplication.runningApplications(withBundleIdentifier: "org.danielholmes.Ludeum").isEmpty {
        fail("Ludeum is running. Quit it, then run into-folders again.")
    }
    let folder = LudeumFolder(
        url: options["--journal"] ?? LudeumFolder.standard.url, data: options["--data"] ?? LudeumFolder.standard.data)
    let data = requireDataFolder(folder)
    let journal = try LudeumStore(directory: folder.url, backups: Backups(folder: folder.backups))
    let intoFolders = IntoFolders(
        journal: journal, folder: folder, libretro: LibretroThumbnails(cache: try CacheStore(directory: cacheDirectory)))

    print("Data folder: \(folder.data.path(percentEncoded: false)), which is \(data.path(percentEncoded: false))")
    let plan: IntoFoldersPlan
    do {
        plan = try intoFolders.plan()
    } catch ImportError.openEmuMigrationNeeded {
        fail("This journal still has OpenEmu ROMs: run migrate-openemu first.")
    }
    print(describe(plan))
    guard plan.isRunnable else { fail("nothing was changed: fix the problems above, then run into-folders again") }
    guard !dryRun else {
        print("Dry run: nothing was changed.")
        return
    }
    let result = try await intoFolders.run()
    print("Done. Backup: \(result.backup.path(percentEncoded: false))")
    print("Move log: \(result.log.path(percentEncoded: false))")
}

private func describe(_ plan: IntoFoldersPlan) -> String {
    var lines: [String] = []
    lines.append("\(plan.folders.count) folders to make (\(plan.folders.map(\.moves.count).reduce(0, +)) files move)")
    for (platform, folders) in Dictionary(grouping: plan.folders, by: \.platformId).sorted(by: { $0.key < $1.key }) {
        lines.append("  \(ROMPlatform.all[platform]?.name ?? "Platform \(platform)"): \(folders.count)")
    }
    func section(_ title: String, _ items: [String]) {
        guard !items.isEmpty else { return }
        lines.append("\(title) (\(items.count)):")
        lines += items.map { "  \($0)" }
    }
    let multiDisc = plan.folders.filter { !$0.forgottenROMs.isEmpty || $0.needsPlaylist }
    section(
        "Multi-disc Versions becoming one ROM",
        multiDisc.map { f in
            var line = "\(f.name): \(f.forgottenROMs.count + (f.keptROM == nil ? 0 : 1)) ROMs become one"
            if f.renamed { line += ", renamed from its first Disc" }
            if f.needsPlaylist { line += "; no playlist, so it waits in the Review queue" }
            return line
        })
    section("Left where they are", plan.leftLoose)
    section("Problems", plan.clashes)
    return lines.joined(separator: "\n")
}
