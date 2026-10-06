import AppKit
import Foundation
import LudeumCore

let migrateOpenEmuUsage = "migrate-openemu [--dry-run] [--journal <folder>] [--library <folder>] [--data <folder>]"

/// `migrate-openemu [--dry-run] [--journal <folder>] [--library <folder>] [--data <folder>]`: run once, by hand,
/// with OpenEmu closed. Folders default to the app's own: its journal, OpenEmu library and Data folder. `--data` stands
/// in for the Data folder for this run only (its ROMs, Backups and battery-save archive), so a rehearsal never touches
/// the real one. `--dry-run` prints what would happen and changes nothing.
func migrateOpenEmuRun(_ arguments: [String]) async throws {
    var options: [String: URL] = [:]
    var dryRun = false
    var rest = arguments[...]
    while let argument = rest.popFirst() {
        switch argument {
        case "--dry-run": dryRun = true
        case "--journal", "--library", "--data":
            guard let value = rest.popFirst() else { fail("\(argument) needs a folder. usage: ludeum-import \(migrateOpenEmuUsage)") }
            options[argument] = URL(filePath: value, directoryHint: .isDirectory)
        default: fail("unknown option \(argument). usage: ludeum-import \(migrateOpenEmuUsage)")
        }
    }
    let settings = AppSettings(defaults: UserDefaults(suiteName: "org.danielholmes.Ludeum") ?? .standard)
    // Each is the app's own unless given: `--journal` alone still uses the app's Data folder.
    let folder = LudeumFolder(
        url: options["--journal"] ?? LudeumFolder.standard.url, data: options["--data"] ?? LudeumFolder.standard.data)
    let data = requireDataFolder(folder)
    // Opening the journal may migrate its schema, so it's backed up first like the app's.
    let journal = try LudeumStore(directory: folder.url, backups: Backups(folder: folder.backups))
    let migration = OpenEmuMigration(
        journal: journal, library: options["--library"] ?? settings.openEmuLibrary, folder: folder,
        isOpenEmuRunning: { !NSRunningApplication.runningApplications(withBundleIdentifier: "org.openemu.OpenEmu").isEmpty },
        libretro: LibretroThumbnails(cache: try CacheStore(directory: cacheDirectory)))

    print("Data folder: \(folder.data.path(percentEncoded: false)), which is \(data.path(percentEncoded: false))")
    let plan: OpenEmuMigrationPlan
    do {
        plan = try migration.plan()
    } catch OpenEmuMigrationError.openEmuRunning {
        fail("OpenEmu is running. Quit it, then run migrate-openemu again.")
    } catch OpenEmuMigrationError.alreadyMigrated {
        print("This journal no longer uses OpenEmu: there's nothing to migrate.")
        return
    }
    print(describe(plan))
    guard plan.isRunnable else { fail("nothing was changed: fix the problems above, then run migrate-openemu again") }
    guard !dryRun else {
        print("Dry run: nothing was changed.")
        return
    }
    let result = try await migration.run()
    print("Migrated. Backup: \(result.backup.path(percentEncoded: false))")
    print("Move log: \(result.log.path(percentEncoded: false))")
    print("Battery saves archived in: \(result.batterySaveArchive.path(percentEncoded: false))")
}

private func describe(_ plan: OpenEmuMigrationPlan) -> String {
    var lines: [String] = []
    let moving = plan.roms.filter { !$0.missing }
    lines.append(
        "\(moving.count) ROMs move (\(moving.map(\.moves.count).reduce(0, +)) files); \(plan.roms.count - moving.count) missing ROMs are re-keyed"
    )
    for (platform, roms) in Dictionary(grouping: plan.roms, by: \.platformId).sorted(by: { $0.key < $1.key }) {
        lines.append("  Platform \(platform): \(roms.count)")
    }
    lines.append("Battery saves to archive: \(plan.batterySaves.map(\.path).joined(separator: ", "))")
    func section(_ title: String, _ items: [String]) {
        guard !items.isEmpty else { return }
        lines.append("\(title) (\(items.count)):")
        lines += items.map { "  \($0)" }
    }
    section("Games on a Platform their ROM's OpenEmu system can't hold", plan.platformMismatches)
    section("Journal ROMs OpenEmu no longer has, so their Platform isn't checked; they stay missing", plan.goneFromOpenEmu)
    section("ROMs on a Platform with no ROM folder", plan.noROMFolder)
    section("File name clashes", plan.clashes)
    section("Files their Platform's ROM folder won't read (convert them first)", plan.unreadableFiles)
    section("Folders that can't be written to", plan.unwritableFolders.map { $0.path(percentEncoded: false) })
    section("OpenEmu ROM files with no journal entry, left where they are", plan.leftInOpenEmu.map { $0.path(percentEncoded: false) })
    return lines.joined(separator: "\n")
}
