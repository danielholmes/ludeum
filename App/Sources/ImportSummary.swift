import LudeumCore
import SwiftUI

/// After an Import that changed something: what was added, matched, sent to review and gone
/// missing, linking to their Games. Dismissible; an Import that changed nothing shows nothing.
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
                        section("Matched", summary.matched)
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
        let added = summary.matched.count + summary.sentToReview.count
        return [
            added > 0
                ? "\(added) ROM\(added == 1 ? "" : "s") added (\(summary.matched.count) matched, \(summary.sentToReview.count) to review)"
                : nil,
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
