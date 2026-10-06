import LudeumCore
import SwiftUI

/// After an Import that changed something: what was sent to review and what's gone missing,
/// linking to their Games. Dismissible; an Import that changed nothing shows nothing.
struct ImportSummaryBanner: View {
    let summary: ImportResult
    let open: (GameID) -> Void
    let dismiss: () -> Void
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(headline, systemImage: "square.and.arrow.down").bold()
                Spacer()
                Button(expanded ? "Hide" : "Details") { expanded.toggle() }.buttonStyle(.hover)
                Button("Dismiss", systemImage: "xmark", action: dismiss).labelStyle(.iconOnly).buttonStyle(.hover)
            }
            if expanded {
                // An Import can touch a thousand ROMs: scroll rather than grow the window off-screen.
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        section("Sent to the Review queue", summary.sentToReview)
                        section("Gone missing", summary.goneMissing)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 300)
            }
        }
        .padding(10)
        .background(.regularMaterial, in: .rect(cornerRadius: 8))
        .padding(8)
    }

    private var headline: String {
        let added = summary.sentToReview.count
        return [
            added > 0 ? "\(added) ROM\(added == 1 ? "" : "s") added to review" : nil,
            summary.goneMissing.isEmpty ? nil : "\(summary.goneMissing.count) gone missing",
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }

    @ViewBuilder private func section(_ title: String, _ roms: [ImportedROM]) -> some View {
        if !roms.isEmpty {
            Text(title).font(.caption).foregroundStyle(.secondary)
            ForEach(Array(roms.enumerated()), id: \.offset) { _, rom in
                if let game = rom.game {
                    Button(rom.romName) { open(game) }.buttonStyle(.hoverLink)
                } else {
                    Text(rom.romName)
                }
            }
        }
    }
}

/// Until `migrate-openemu` has moved the journal's OpenEmu ROMs into ROM folders, the main window says to run it,
/// and Import is refused with the same words.
struct OpenEmuMigrationBanner: View {
    static let message =
        "This journal still uses OpenEmu. Quit Ludeum, run `ludeum-import migrate-openemu` (try `--dry-run` first), then reopen."

    var body: some View {
        Label(LocalizedStringKey(Self.message), systemImage: "exclamationmark.triangle.fill")
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.orange.opacity(0.15))
    }
}

/// Why the last Import failed. Dismissible.
struct ImportErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            Spacer()
            Button("Dismiss", systemImage: "xmark", action: dismiss).labelStyle(.iconOnly).buttonStyle(.hover)
        }
        .padding(10)
        .background(.regularMaterial, in: .rect(cornerRadius: 8))
        .padding(8)
    }
}

/// The main window's Import banners: `migrate-openemu` still to run across the top, and the last Import's
/// failure and summary at the bottom.
struct ImportBanners: ViewModifier {
    @Bindable var model: ImportModel
    let needsOpenEmuMigration: Bool
    let open: (GameID) -> Void

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                if needsOpenEmuMigration { OpenEmuMigrationBanner() }
            }
            .overlay(alignment: .bottom) {
                VStack(spacing: 0) {
                    if let error = model.error {
                        ImportErrorBanner(message: error) { model.error = nil }.frame(maxWidth: 520)
                    }
                    if let summary = model.summary {
                        ImportSummaryBanner(summary: summary, open: open, dismiss: { model.summary = nil }).frame(maxWidth: 520)
                    }
                }
            }
    }
}
