import AppKit
import Foundation
import LudeumCore

/// `migrate-openemu [--dry-run] [--journal <folder>] [--library <folder>] [--roms <folder>]`: run once, by hand,
/// with OpenEmu closed. Folders default to the app's own settings: its journal, OpenEmu library, ROM folders
/// root and backup folder. `--dry-run` prints what would happen and changes nothing.
func migrateOpenEmuRun(_ arguments: [String]) async throws {
    func option(_ name: String) -> URL? {
        arguments.firstIndex(of: name).flatMap { i in
            arguments.indices.contains(i + 1) ? URL(filePath: arguments[i + 1], directoryHint: .isDirectory) : nil
        }
    }
    let settings = AppSettings(defaults: UserDefaults(suiteName: "org.danielholmes.Ludeum") ?? .standard)
    if let roms = option("--roms") { settings.romFoldersRoot = roms }
    let journalFolder = option("--journal") ?? AppSettings.appFolder
    let journal = try LudeumStore(directory: journalFolder)
    let migration = OpenEmuMigration(
        journal: journal, library: option("--library") ?? settings.openEmuLibrary,
        romFolder: { settings.romFolder(platform: $0) }, backups: settings.backups(),
        isOpenEmuRunning: { !NSRunningApplication.runningApplications(withBundleIdentifier: "org.openemu.OpenEmu").isEmpty },
        libretro: LibretroThumbnails(cache: try CacheStore(directory: cacheDirectory)))

    let plan: OpenEmuMigrationPlan
    do {
        plan = try migration.plan()
    } catch OpenEmuMigrationError.openEmuRunning {
        fail("OpenEmu is running. Quit it, then run migrate-openemu again.")
    }
    print(describe(plan))
    guard plan.isRunnable else { fail("nothing was changed: fix the problems above, then run migrate-openemu again") }
    guard !arguments.contains("--dry-run") else {
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
    section("ROMs on a Platform with no ROM folder", plan.noROMFolder)
    section("File name clashes", plan.clashes)
    section("Folders that can't be written to", plan.unwritableFolders.map { $0.path(percentEncoded: false) })
    section("OpenEmu ROM files with no journal entry, left where they are", plan.leftInOpenEmu.map { $0.path(percentEncoded: false) })
    return lines.joined(separator: "\n")
}
