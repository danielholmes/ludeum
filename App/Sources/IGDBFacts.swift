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

/// Screenshots in their Platform's shape, in two rows of the biggest that keep them at most 300 points tall, or a
/// Nintendo DS Game's in one (`ScreenshotShape`), then a tile to show the rest. Click one to see it full size.
struct ScreenshotsSection: View {
    let loader: ScreenshotLoader
    let screenshots: [ShownScreenshot]
    /// Its heading, as LaunchBox's have their own.
    var title = "Screenshots"
    var shape = ScreenshotShape.widescreen
    @State private var showingAll = false
    /// The tiles for the width it has; for a narrow Game detail panel's until that's known.
    @State private var layout: ScreenshotLayout?
    @State private var viewing: Screenshot?

    private nonisolated static let spacing: CGFloat = 12

    var body: some View {
        Section(title) {
            let tiles = layout ?? shape.layout(width: ScreenshotShape.narrowPanelWidth, spacing: Self.spacing)
            let limit = tiles.limit
            let collapsed = !showingAll && screenshots.count > limit
            let shown = collapsed ? Array(screenshots.prefix(limit - 1)) : screenshots
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: Self.spacing), count: tiles.columns), spacing: Self.spacing
            ) {
                ForEach(shown, id: \.self) { screenshot in
                    ScreenshotImage(loader: loader, screenshot: screenshot, original: !shape.fitsThumbnail)
                        .aspectRatio(shape.aspectRatio, contentMode: .fit)
                        .frame(minWidth: 0)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .onTapGesture { viewing = Screenshot(id: screenshot) }
                }
                if collapsed {
                    Button {
                        showingAll = true
                    } label: {
                        // The next screenshot, dimmed, under "+N more".
                        ScreenshotImage(loader: loader, screenshot: screenshots[shown.count], original: !shape.fitsThumbnail)
                            .aspectRatio(shape.aspectRatio, contentMode: .fit)
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
            .onGeometryChange(for: ScreenshotLayout.self) { [shape] in
                shape.layout(width: $0.size.width, spacing: Self.spacing)
            } action: {
                layout = $0
            }
        }
        .onChange(of: screenshots) { showingAll = false }
        .sheet(item: $viewing) { shot in
            ScreenshotGallery(loader: loader, screenshots: screenshots, showing: shot.id, shape: shape)
        }
    }
}

/// Screenshots one at a time, whole, over a strip of them all. ← and → or the arrows on the image go
/// back and on, round from the last to the first; click one in the strip to see it.
struct ScreenshotGallery: View {
    let loader: ScreenshotLoader
    let screenshots: [ShownScreenshot]
    /// The strip's thumbnails are its shape: its Platform's screen.
    let shape: ScreenshotShape
    @State private var index: Int
    @Environment(\.dismiss) private var dismiss

    private nonisolated static let thumbnailHeight: CGFloat = 63

    init(loader: ScreenshotLoader, screenshots: [ShownScreenshot], showing screenshot: ShownScreenshot, shape: ScreenshotShape) {
        self.loader = loader
        self.screenshots = screenshots
        self.shape = shape
        _index = State(initialValue: screenshots.firstIndex(of: screenshot) ?? 0)
    }

    var body: some View {
        let stage = stageSize
        VStack(spacing: 12) {
            WholeScreenshot(loader: loader, screenshot: screenshots[index])
                // A spinner while the next one downloads, not the last one.
                .id(screenshots[index])
                .frame(width: stage.width, height: stage.height)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                .overlay(alignment: .leading) { arrow(-1) }
                .overlay(alignment: .trailing) { arrow(1) }
            thumbnails(width: stage.width)
            HStack {
                Text("\(index + 1) of \(screenshots.count)").monospacedDigit().foregroundStyle(.secondary)
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
    }

    /// Where each screenshot is shown, the same size for all of them: 16:9, as big as the screen leaves room for
    /// beside the strip and buttons, up to 1920 × 1080 (IGDB's biggest).
    private var stageSize: CGSize {
        let screen = (NSApp.keyWindow?.screen ?? NSScreen.main)?.visibleFrame.size ?? CGSize(width: 1440, height: 900)
        let width = max(640, min(1920, screen.width - 80, (screen.height - 240) * 16 / 9))
        return CGSize(width: width, height: width * 9 / 16)
    }

    /// A chevron over the image's edge: back one (←) or on one (→).
    private func arrow(_ step: Int) -> some View {
        Button {
            go(step)
        } label: {
            Image(systemName: step < 0 ? "chevron.left" : "chevron.right")
                .font(.title2.weight(.semibold))
                .frame(width: 40, height: 40)
                .background(.regularMaterial, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(step < 0 ? .leftArrow : .rightArrow, modifiers: [])
        .help(step < 0 ? "Previous (←)" : "Next (→)")
        .padding(12)
        .disabled(screenshots.count < 2)
    }

    private func go(_ step: Int) {
        index = (index + step + screenshots.count) % screenshots.count
    }

    /// Every screenshot small, the one showing outlined and kept in view.
    private func thumbnails(width: CGFloat) -> some View {
        ScrollViewReader { scroller in
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(screenshots.indices, id: \.self) { i in
                        ScreenshotImage(loader: loader, screenshot: screenshots[i], original: !shape.fitsThumbnail)
                            .frame(width: Self.thumbnailHeight * shape.aspectRatio, height: Self.thumbnailHeight)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                            .overlay {
                                RoundedRectangle(cornerRadius: 3)
                                    .strokeBorder(Color.accentColor, lineWidth: i == index ? 3 : 0)
                            }
                            .opacity(i == index ? 1 : 0.6)
                            .contentShape(Rectangle())
                            .onTapGesture { index = i }
                    }
                }
                .padding(.vertical, 2)
                // Centred when they don't fill the width.
                .frame(minWidth: width)
            }
            .onAppear { scroller.scrollTo(index, anchor: .center) }
            .onChange(of: index) { withAnimation { scroller.scrollTo(index, anchor: .center) } }
        }
        .frame(width: width)
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

    var body: some View {
        let shown = showingAll ? keywords.count : PillRow.fittingOneLine(keywords, rowWidth: width)
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
}
