import AppKit
import Foundation
import LudeumCore

let recoverOpenEmuRenamedUsage =
    "recover-openemu-renamed [--dry-run] [--journal <folder>] [--library <folder>] [--data <folder>] [--backup <before-migration.sqlite>]"

/// `recover-openemu-renamed [--dry-run] [--journal <folder>] [--library <folder>] [--data <folder>] [--backup <file>]`:
/// run once, by hand, after `migrate-openemu`, with OpenEmu closed. Folders default to the app's own, as for
/// `migrate-openemu`; `--backup` defaults to the newest `before-migration` Backup in the Data folder. `--dry-run` prints
/// what would happen and changes nothing.
func recoverOpenEmuRenamedRun(_ arguments: [String]) async throws {
    var options: [String: URL] = [:]
    var dryRun = false
    var rest = arguments[...]
    while let argument = rest.popFirst() {
        switch argument {
        case "--dry-run": dryRun = true
        case "--journal", "--library", "--data", "--backup":
            guard let value = rest.popFirst() else { fail("\(argument) needs a path. usage: ludeum-import \(recoverOpenEmuRenamedUsage)") }
            options[argument] = URL(filePath: value, directoryHint: argument == "--backup" ? .notDirectory : .isDirectory)
        default: fail("unknown option \(argument). usage: ludeum-import \(recoverOpenEmuRenamedUsage)")
        }
    }
    let settings = AppSettings(defaults: UserDefaults(suiteName: "org.danielholmes.Ludeum") ?? .standard)
    let folder = LudeumFolder(
        url: options["--journal"] ?? LudeumFolder.standard.url, data: options["--data"] ?? LudeumFolder.standard.data)
    let data = requireDataFolder(folder)
    guard let backup = try options["--backup"] ?? OpenEmuRecovery.beforeMigrationBackup(in: folder) else {
        fail("there's no before-migration Backup in \(folder.backups.path(percentEncoded: false)): give one with --backup")
    }
    let journal = try LudeumStore(directory: folder.url, backups: Backups(folder: folder.backups))
    let recovery = OpenEmuRecovery(
        journal: journal, library: options["--library"] ?? settings.openEmuLibrary, beforeMigration: backup, folder: folder,
        isOpenEmuRunning: { !NSRunningApplication.runningApplications(withBundleIdentifier: "org.openemu.OpenEmu").isEmpty })

    print("Data folder: \(folder.data.path(percentEncoded: false)), which is \(data.path(percentEncoded: false))")
    print("OpenEmu ids from: \(backup.path(percentEncoded: false))")
    let plan: OpenEmuRecoveryPlan
    do {
        plan = try recovery.plan()
    } catch OpenEmuRecoveryError.openEmuRunning {
        fail("OpenEmu is running. Quit it, then run recover-openemu-renamed again.")
    } catch OpenEmuRecoveryError.notMigrated {
        fail("This journal still uses OpenEmu: run migrate-openemu first.")
    } catch OpenEmuRecoveryError.notABeforeMigrationBackup(let file) {
        fail("\(file.path(percentEncoded: false)) has no OpenEmu ids: give the before-migration Backup with --backup")
    }
    print(describe(plan))
    guard plan.isRunnable else { fail("nothing was changed: fix the problems above, then run recover-openemu-renamed again") }
    guard !dryRun else {
        print("Dry run: nothing was changed.")
        return
    }
    let result = try await recovery.run()
    print("Recovered. Backup: \(result.backup.path(percentEncoded: false))")
    print("Move log: \(result.log.path(percentEncoded: false))")
    print("The next Import finds them.")
}

private func describe(_ plan: OpenEmuRecoveryPlan) -> String {
    var lines: [String] = []
    lines.append(
        "\(plan.roms.count) ROMs found and move (\(plan.roms.map(\.moves.count).reduce(0, +)) files); "
            + "\(plan.unmatched.count) not found and \(plan.ambiguous.count) ambiguous stay missing")
    for (platform, roms) in Dictionary(grouping: plan.roms, by: \.platformId).sorted(by: { $0.key < $1.key }) {
        lines.append("  \(ROMPlatform.all[platform]?.name ?? "Platform \(platform)"): \(roms.count)")
        lines += roms.map { rom in "    \(rom.fileName) ← \(rom.moves.first?.from.path(percentEncoded: false) ?? "")" }
    }
    func section(_ title: String, _ items: [String]) {
        guard !items.isEmpty else { return }
        lines.append("\(title) (\(items.count)):")
        lines += items.map { "  \($0)" }
    }
    for (playlist, discs) in Dictionary(grouping: plan.forgottenDiscs, by: \.playlist).sorted(by: { $0.key < $1.key }) {
        lines.append(
            "\(playlist) loads the discs already in its ROM folder; their own ROMs are forgotten: "
                + discs.map(\.name).joined(separator: ", "))
    }
    section("Playlists whose discs in the ROM folder differ, left missing", plan.playlistsLeftMissing)
    section("More than one file each could be, left missing", plan.ambiguous)
    section("No file found, left missing", plan.unmatched)
    section("ROMs on a Platform with no ROM folder", plan.noROMFolder)
    section("File name clashes", plan.clashes)
    section("Files their Platform's ROM folder won't read (convert them first)", plan.unreadableFiles)
    section("Folders that can't be written to", plan.unwritableFolders.map { $0.path(percentEncoded: false) })
    return lines.joined(separator: "\n")
}
