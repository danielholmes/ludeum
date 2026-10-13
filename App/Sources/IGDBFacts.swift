import LudeumCore
import SwiftUI

/// What IGDB says about a game, as rows of pills: community scores, genres, themes, franchises,
/// series, companies, links and keywords. Shared by Game detail and the IGDB screen's game detail.
struct IGDBFactsRows: View {
    let services: Services
    let facts: GameFacts
    /// Opens the Library with a filter (a genre, a franchise…).
    let browse: (LibraryFilter) -> Void
    /// Game detail shows the scores beside my Rating instead.
    var showsScores = true
    @State private var pins: Set<Pin> = []
    @State private var allCompanies = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let summary = facts.summary { SummaryText(text: summary) }
            if showsScores { CommunityScores(players: facts.playerScore, critics: facts.criticScore) }
            if !facts.genres.isEmpty { PillRow(title: "Genre", items: facts.genres, open: { browse(LibraryFilter(genre: $0)) }) }
            if !facts.themes.isEmpty { pinnable("Theme", .theme, facts.themes) }
            // A franchise that only repeats the series (Metroid and Metroid) says nothing new.
            let franchises = facts.franchises.filter { !facts.series.contains($0) }
            if !franchises.isEmpty { pinnable("Franchise", .franchise, franchises) }
            if !facts.series.isEmpty { pinnable("Series", .series, facts.series) }
            if !facts.credits.isEmpty { companies }
            if let t = facts.timeToBeat, let text = timeToBeatText(t) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("Time to beat").font(FactStyle.label).foregroundStyle(.secondary).frame(
                        width: FactStyle.labelWidth, alignment: .leading)
                    Text(text).font(FactStyle.value)
                }
            }
            if !facts.links.isEmpty || facts.trailer != nil {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("Links").font(FactStyle.label).foregroundStyle(.secondary).frame(width: FactStyle.labelWidth, alignment: .leading)
                    FlowLayout(spacing: 8) {
                        if let trailer = facts.trailer {
                            Link("▶ Trailer", destination: trailer).font(FactStyle.value).help(trailer.absoluteString)
                        }
                        ForEach(facts.links, id: \.title) { link in
                            Link(link.title, destination: link.url).font(FactStyle.value).help(link.url.absoluteString)
                        }
                    }
                }
            }
            if !facts.keywords.isEmpty { KeywordsRow(keywords: facts.keywords) }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .task(id: services.changes.revision) { pins = Set((try? services.journal?.pins()) ?? []) }
    }

    /// Each company once, its roles in brackets: "Capcom (Developer, Publisher)". Developers and the
    /// first publisher show; the rest (often regional publishers) wait behind "+N more".
    @ViewBuilder private var companies: some View {
        let roles = Dictionary(facts.credits.map { ($0.name, $0.roles) }, uniquingKeysWith: { a, _ in a })
        let key =
            facts.credits.filter { $0.roles.contains(.developer) }.map(\.name)
            + facts.credits.filter { !$0.roles.contains(.developer) && $0.roles.contains(.publisher) }.prefix(1).map(\.name)
        let all = facts.credits.map(\.name)
        let shown = allCompanies || key.isEmpty ? all : all.filter(key.contains)
        pinnable(
            "Companies", .company, shown,
            more: shown.count < all.count ? (all.count - shown.count, { allCompanies = true }) : nil
        ) { name in
            let r = roles[name] ?? []
            return r.isEmpty ? name : "\(name) (\(r.map(\.rawValue.capitalized).joined(separator: ", ")))"
        }
    }

    /// Franchise, Series or Theme pills: each opens the Library filtered to it, and can be pinned to the sidebar.
    private func pinnable(
        _ title: String, _ kind: Pin.Kind, _ names: [String], more: (count: Int, show: () -> Void)? = nil,
        label: @escaping (String) -> String = { $0 }
    ) -> some View {
        PillRow(
            title: title, items: names, label: label, more: more, open: { browse(Pin(kind: kind, name: $0).filter) },
            pinned: Set(pins.filter { $0.kind == kind }.map(\.name)),
            togglePin: { name in
                guard let journal = services.journal else { return }
                let pin = Pin(kind: kind, name: name)
                do {
                    try pins.contains(pin) ? journal.unpin(pin) : journal.pin(pin)
                    error = nil
                    services.changes.changed()
                } catch {
                    self.error = journalErrorText(error)
                }
            })
    }
}

/// IGDB's screenshots in two rows of three (three rows of two in a narrow panel), then a tile to show the rest. Click
/// one to see it full size.
struct ScreenshotsSection: View {
    let igdb: IGDBClient
    let screenshots: [String]
    @State private var showingAll = false
    /// Three across while each gets at least `narrowest` points (in Game detail, a panel of about 400 points), else two.
    @State private var columns = 3
    @State private var viewing: Screenshot?

    private nonisolated static let spacing: CGFloat = 12
    private nonisolated static let narrowest: CGFloat = 105

    var body: some View {
        Section("Screenshots") {
            let limit = 6
            let collapsed = !showingAll && screenshots.count > limit
            let shown = collapsed ? Array(screenshots.prefix(limit - 1)) : screenshots
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Self.spacing), count: columns), spacing: Self.spacing) {
                ForEach(shown, id: \.self) { imageID in
                    ScreenshotImage(igdb: igdb, imageID: imageID, large: false)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .frame(minWidth: 0)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .onTapGesture { viewing = Screenshot(id: imageID) }
                }
                if collapsed {
                    Button {
                        showingAll = true
                    } label: {
                        // The next screenshot, dimmed, under "+N more".
                        ScreenshotImage(igdb: igdb, imageID: screenshots[shown.count], large: false)
                            .aspectRatio(16 / 9, contentMode: .fit)
                            .frame(minWidth: 0)
                            .overlay(Color.black.opacity(0.55))
                            .overlay {
                                Label("\(screenshots.count - shown.count) more", systemImage: "plus")
                                    .font(.headline).foregroundStyle(.white)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                }
            }
            .onGeometryChange(for: Int.self) {
                $0.size.width >= 3 * Self.narrowest + 2 * Self.spacing ? 3 : 2
            } action: {
                columns = $0
            }
        }
        .onChange(of: screenshots) { showingAll = false }
        .sheet(item: $viewing) { shot in
            // IGDB's full size (1280 × 720), shrinking to fit a smaller screen. Click to close.
            ScreenshotImage(igdb: igdb, imageID: shot.id, large: true)
                .aspectRatio(16 / 9, contentMode: .fit)
                .frame(minWidth: 640, idealWidth: 1280, maxWidth: 1280)
                .onTapGesture { viewing = nil }
        }
    }
}

/// IGDB's summary: a few lines, with More to read the rest.
private struct SummaryText: View {
    let text: String
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(text).lineLimit(expanded ? nil : 4).fixedSize(horizontal: false, vertical: true)
            if !expanded, text.count > 280 {
                Button("More") { expanded = true }.buttonStyle(.link).font(.caption)
            }
        }
    }
}

/// "Rushed 3.5 h · Normally 10 h · 100% 12 h", leaving out what IGDB doesn't know.
func timeToBeatText(_ t: TimeToBeat) -> String? {
    func hours(_ seconds: Int?) -> String? {
        guard let seconds, seconds > 0 else { return nil }
        let h = Double(seconds) / 3600
        return h < 10 ? String(format: "%.1f h", h) : "\(Int(h.rounded())) h"
    }
    let parts = [
        hours(t.hastily).map { "Rushed \($0)" }, hours(t.normally).map { "Normally \($0)" },
        hours(t.completely).map { "100% \($0)" },
    ].compactMap { $0 }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
}

/// IGDB's keywords: one row of pills, then "+N more" for the ones that wouldn't fit.
private struct KeywordsRow: View {
    let keywords: [String]
    @State private var width: CGFloat = 0
    @State private var showingAll = false

    /// PillRow's, between its pills.
    private static let spacing: CGFloat = 4

    var body: some View {
        // The pills get the row less the label column and the gap after it.
        let shown = showingAll ? keywords.count : Self.fitting(keywords, in: width - FactStyle.labelWidth - 6)
        PillRow(
            title: "Keywords", items: Array(keywords.prefix(shown)),
            more: shown < keywords.count ? (keywords.count - shown, { showingAll = true }) : nil
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) {
            $0.size.width
        } action: {
            width = $0
        }
        .onChange(of: keywords) { showingAll = false }
    }

    /// How many of the keywords' pills fit in `width`, leaving room for "+N more" after them when not all do.
    private static func fitting(_ keywords: [String], in width: CGFloat) -> Int {
        let widths = keywords.map(pillWidth)
        if widths.reduce(0, +) + spacing * CGFloat(widths.count - 1) <= width { return keywords.count }
        var x: CGFloat = 0
        var count = 0
        for w in widths {
            let more = pillWidth("+\(keywords.count - count - 1) more")
            guard x + w + spacing + more <= width else { break }
            x += w + spacing
            count += 1
        }
        return count
    }

    /// A pill's width: its text in the body font, and 8 points either side.
    private static func pillWidth(_ text: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        return (text as NSString).size(withAttributes: [.font: font]).width.rounded(.up) + 16
    }
}
