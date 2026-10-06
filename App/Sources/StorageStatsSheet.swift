import LudeumCore
import SwiftUI

/// How much room each Platform's ROM folder takes, then the rest of the Data folder, the journal and the cache. Measured
/// from the files each time it opens, and again on Refresh.
struct StorageStatsSheet: View {
    let services: Services
    @Environment(\.dismiss) private var dismiss
    @State private var stats: StorageStats?
    @State private var measuring = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Storage Stats").font(.title2.bold())
            if let stats {
                table(stats)
            } else {
                ProgressView("Measuring…").frame(maxWidth: .infinity, minHeight: 200)
            }
            Text(
                "Sizes are of the files themselves, so one Dropbox keeps online-only counts in full. "
                    + "Not a ROM is what's in a ROM folder that no ROM is made of."
            )
            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                if measuring, stats != nil { ProgressView().controlSize(.small) }
                Spacer()
                Button("Refresh") { Task { await measure() } }.disabled(measuring)
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 860)
        .task { await measure() }
    }

    private func measure() async {
        measuring = true
        let folder = services.settings.folder
        let journal = services.journal
        stats = await Task.detached(priority: .userInitiated) {
            StorageStats.measure(folder, journal: journal, cache: CacheStore.defaultDirectory)
        }.value
        measuring = false
    }

    private func table(_ stats: StorageStats) -> some View {
        ScrollView {
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                GridRow {
                    Text("")
                    Text("Total").gridColumnAlignment(.trailing)
                    Text("ROMs").gridColumnAlignment(.trailing)
                    Text("Playable").gridColumnAlignment(.trailing)
                    Text("Archived").gridColumnAlignment(.trailing)
                    Text("Not compacted").gridColumnAlignment(.trailing)
                    Text("Not a ROM").gridColumnAlignment(.trailing)
                }
                .font(.callout.bold()).foregroundStyle(.secondary)
                Divider()
                ForEach(stats.platforms) { row in
                    GridRow {
                        platformName(row)
                        if row.unreadable, row.total == 0 {
                            Label("Couldn't read", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                                .gridCellColumns(6)
                        } else {
                            sizeText(row.total)
                            roms(row)
                            tally(row.playable)
                            tally(row.archived)
                            Text(row.notCompacted == 0 ? "" : "\(row.notCompacted)").monospacedDigit()
                            sizeText(row.notAROM)
                        }
                    }
                }
                totalRow(Text("Backups"), stats.backups)
                totalRow(Text("Battery saves"), stats.batterySaves)
                Divider()
                totalRow(Text("Data folder \(Text("in Dropbox").foregroundStyle(.secondary))"), stats.dataFolder).font(.headline)
                totalRow(Text("Journal"), stats.journal)
                totalRow(Text("Cache"), stats.cache)
                Divider()
                totalRow(Text("Total"), stats.total).bold()
            }
        }
        .frame(minHeight: 200, maxHeight: 560)
    }

    private func platformName(_ row: PlatformStorage) -> some View {
        HStack(spacing: 4) {
            PlatformIcon(platformId: row.id)
            Text(row.name)
            if row.unreadable {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    .help("One of its ROM folders couldn't be read, so it's left out")
            }
            if row.inBothForms > 0 {
                Image(systemName: "doc.on.doc.fill").foregroundStyle(.orange)
                    .help("\(row.inBothForms) ROM\(row.inBothForms == 1 ? " is" : "s are") kept in both forms, wasting room")
            }
        }
    }

    @ViewBuilder private func roms(_ row: PlatformStorage) -> some View {
        if row.missing == 0 {
            Text(row.roms == 0 ? "" : "\(row.roms)").monospacedDigit()
        } else {
            Text("\(row.roms) \(Text("+\(row.missing) missing").foregroundStyle(.secondary))").monospacedDigit()
        }
    }

    /// A count and its size, or nothing when there are none.
    @ViewBuilder private func tally(_ tally: ROMTally) -> some View {
        if tally.count == 0 {
            Text("")
        } else {
            Text("\(bytes(tally.bytes)) \(Text("(\(tally.count))").foregroundStyle(.secondary))").monospacedDigit()
        }
    }

    /// A size, or nothing when it's zero.
    private func sizeText(_ count: Int64) -> some View { Text(count == 0 ? "" : bytes(count)).monospacedDigit() }

    /// A row after the Platforms, with only a total.
    private func totalRow(_ name: Text, _ total: Int64) -> some View {
        GridRow {
            name
            sizeText(total)
        }
    }

    private func bytes(_ count: Int64) -> String { ByteCountFormatter.string(fromByteCount: count, countStyle: .file) }
}
