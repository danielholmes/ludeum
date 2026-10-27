import LudeumCore
import SwiftUI

/// After an Import that changed something: what was sent to review, what's gone missing and the new Stray files (and,
/// after Add ROMs, what it Matched automatically), linking to their Games. Dismissible; an Import that changed nothing
/// shows nothing.
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
                        section("Matched automatically", summary.matched)
                        section("Back on their Game", summary.returned)
                        section("Sent to the Review queue", summary.sentToReview)
                        section("Gone missing", summary.goneMissing)
                        if !summary.strayFiles.isEmpty {
                            Text("Stray files, not ROMs").font(.caption).foregroundStyle(.secondary)
                            ForEach(Array(summary.strayFiles.enumerated()), id: \.offset) { _, name in Text(name) }
                        }
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
            summary.matched.isEmpty ? nil : "\(romCount(summary.matched.count)) Matched automatically",
            summary.returned.isEmpty ? nil : "\(romCount(summary.returned.count)) back on their Game",
            added > 0 ? "\(added) ROM\(added == 1 ? "" : "s") added to review" : nil,
            summary.goneMissing.isEmpty ? nil : "\(summary.goneMissing.count) gone missing",
            summary.strayFiles.isEmpty
                ? nil : "\(summary.strayFiles.count) Stray file\(summary.strayFiles.count == 1 ? "" : "s") in the ROM folders",
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

/// The main window's Import banners: the last Import's failure and summary at the bottom.
struct ImportBanners: ViewModifier {
    @Bindable var model: ImportModel
    let open: (GameID) -> Void

    func body(content: Content) -> some View {
        content
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
