import LudeumCore
import SwiftUI

/// What to play next: Playing, Up next and Backlog, each Game once. A plain view, no suggestions.
struct WhatToPlayNextScreen: View {
    let services: Services
    @Binding var selection: GameID?

    @State private var filter = LibraryFilter()
    /// Nil is each section's default order.
    @State private var sort: LibrarySort?
    @State private var ascending = true
    @State private var next = PlayNext<LibraryRow>(playing: [], upNext: [], backlog: [])
    /// How long the sections' Games take to beat normally: nil when none of them has a time (or none is read yet).
    @State private var estimates: PlayNextBeatEstimates?
    /// Every linked Game's IGDB facts, by IGDB game id, as last read: the times to beat come from them.
    @State private var facts: [Int64: GameFacts] = [:]
    @State private var platforms: [IGDBPlatform] = []
    @State private var players: [Player] = []
    @State private var error: String?
    // Shared with the Library: one choice of view and Cover size everywhere.
    @AppStorage("libraryShowsCovers") private var showCovers = false
    @AppStorage(CoverTileSize.widthKey) private var coverWidth = CoverTileSize.defaultWidth

    var body: some View {
        Group {
            if let error {
                ContentUnavailableView("Couldn't read the journal", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if next.playing.isEmpty, next.upNext.isEmpty, next.backlog.isEmpty {
                EmptyResults(
                    title: "Nothing to play next", systemImage: "play.circle",
                    description: filter == LibraryFilter() ? "Set a Game's Intent to Up next or Backlog." : "Try fewer filters.",
                    clearFilters: filter == LibraryFilter() ? nil : { filter = LibraryFilter() })
            } else if showCovers {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        // Each section's covers, a rule between sections.
                        let shown = sections.filter { !$0.rows.isEmpty }
                        ForEach(Array(shown.enumerated()), id: \.offset) { index, section in
                            if index > 0 { Divider() }
                            Text(section.heading).font(.headline)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: coverWidth), spacing: 24, alignment: .top)], spacing: 24) {
                                ForEach(section.rows) { row in
                                    CoverCell(services: services, row: row, width: coverWidth, selection: $selection)
                                        .contextMenu { if section.canStart { Button("Start playing") { startPlaying(row.id) } } }
                                }
                            }
                        }
                    }
                    .padding()
                }
            } else {
                List(selection: $selection) {
                    ForEach(sections, id: \.title) { listSection($0) }
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                FilterBar(
                    filter: $filter, kinds: FilterKind.library.subtracting([.genre, .theme]), platforms: platforms,
                    players: players
                ) {
                    LibrarySortMenu(
                        sort: $sort, ascending: $ascending, sorts: LibrarySort.allCases.filter { !$0.comesFromCache },
                        offersDefault: true)
                    ViewModeControls(showCovers: $showCovers, coverWidth: $coverWidth)
                }
                if let estimates, error == nil { totalLine(estimates) }
            }
        }
        .navigationTitle("What to play next")
        .viewShortcuts(showCovers: $showCovers)
        .task(id: Reload(revision: services.changes.revision, filter: filter, sort: sort, ascending: ascending)) { await load() }
    }

    private struct Reload: Equatable {
        let revision: Int
        let filter: LibraryFilter
        let sort: LibrarySort?
        let ascending: Bool
    }

    /// One of Playing, Up next and Backlog, with its Games and how long they take to beat.
    private struct NextSection {
        let title: String
        let rows: [LibraryRow]
        /// Start playing is offered: its Games aren't Playing already.
        let canStart: Bool
        let estimate: BeatEstimate?

        /// "Backlog (42) · 310 h".
        var heading: String {
            let counted = "\(title) (\(rows.count))"
            return estimate.flatMap { hours($0.seconds) }.map { "\(counted) · \($0)" } ?? counted
        }
    }

    private var sections: [NextSection] {
        [
            NextSection(title: "Playing", rows: next.playing, canStart: false, estimate: estimates?.playing),
            NextSection(title: "Up next", rows: next.upNext, canStart: true, estimate: estimates?.upNext),
            NextSection(title: "Backlog", rows: next.backlog, canStart: true, estimate: estimates?.backlog),
        ]
    }

    /// "About 1,234 h to beat them all", and how many Games had no time of their own.
    private func totalLine(_ estimates: PlayNextBeatEstimates) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("About \(hours(estimates.total.seconds) ?? "0 h") to beat them all")
            if estimates.total.atMedian > 0 {
                Text("· \(estimates.total.atMedian) without a time counted at the median, \(hours(estimates.medianSeconds) ?? "0 h")")
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .font(.callout)
        .help("From IGDB's \"Normally\" times to beat, not Rushed or 100%. A Game without one counts at the median of the others.")
        .padding(.horizontal, 12).padding(.bottom, 6)
        .background(.bar)
    }

    @ViewBuilder private func listSection(_ section: NextSection) -> some View {
        if !section.rows.isEmpty {
            Section(section.heading) {
                ForEach(section.rows) { row in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(row.name)
                            Text(detail(row)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if section.canStart {
                            Button("Start playing") { startPlaying(row.id) }
                                .help("Adds a Playthrough starting today and clears the Intent")
                        }
                    }
                    .tag(row.id)
                    .contextMenu {
                        if section.canStart { Button("Start playing") { startPlaying(row.id) } }
                    }
                }
            }
        }
    }

    private func detail(_ row: LibraryRow) -> String {
        var parts = [row.platformName]
        if let since = row.playingSince { parts.append("since \(since.text)") }
        if let rating = row.rating { parts.append(ratingText(rating)) }
        return parts.joined(separator: " · ")
    }

    private func startPlaying(_ game: GameID) {
        guard let journal = services.journal else { return }
        do {
            try journal.startPlaying(game)
            services.changes.changed()
        } catch {
            self.error = journalErrorText(error)
        }
    }

    private func load() async {
        guard let journal = services.journal else { return }
        do {
            next = try journal.whatToPlayNext(filter, sort: sort, ascending: ascending)
            (platforms, players) = try filterChoices(journal)
            error = nil
        } catch {
            self.error = error.localizedDescription
            estimates = nil
            return
        }
        // The times to beat live in IGDB's cache: from the facts held, so the hours never lag the Games, then again
        // once any newly linked Game's facts are read.
        estimates = next.beatEstimates(timeToBeat)
        facts = await services.memory.facts(services)
        guard !Task.isCancelled else { return }
        estimates = next.beatEstimates(timeToBeat)
    }

    /// A Game's IGDB time to beat normally, in seconds, when IGDB has one: neither rushed nor 100%.
    private func timeToBeat(_ row: LibraryRow) -> Int? {
        row.igdbGameId.flatMap { facts[$0] }?.timeToBeat?.normally
    }
}
