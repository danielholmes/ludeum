import LudeumCore
import SwiftUI

/// Year in review: one year at a time, with the Library's filters.
struct YearInReviewScreen: View {
    let services: Services
    @Binding var selection: GameID?

    @State private var filter = LibraryFilter()
    @State private var years: [Int] = []
    /// Finished Playthroughs per year (with the filter), for the year menu.
    @State private var finished: [Int: Int] = [:]
    @State private var year: Int?
    @State private var review: YearInReview?
    @State private var platforms: [IGDBPlatform] = []
    @State private var lists: [GameList] = []
    @State private var error: String?

    var body: some View {
        Group {
            if let error {
                ContentUnavailableView("Couldn't read the journal", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if let review {
                ScrollView { content(review).padding() }
            } else {
                EmptyResults(
                    title: "Nothing to review", systemImage: "calendar",
                    description: filter == LibraryFilter() ? "Playthroughs show up here." : "Try fewer filters.",
                    clearFilters: filter == LibraryFilter() ? nil : { filter = LibraryFilter() })
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            FilterBar(filter: $filter, kinds: FilterKind.library.subtracting([.genre, .theme]), platforms: platforms, lists: lists)
        }
        .navigationTitle("Year in review")
        .task(id: Reload(revision: services.changes.revision, filter: filter, year: year)) { load() }
    }

    private struct Reload: Equatable {
        let revision: Int
        let filter: LibraryFilter
        let year: Int?
    }

    private func yearTitle(_ y: Int) -> String {
        y == Calendar.current.component(.year, from: Date()) ? "\(String(y)) so far" : String(y)
    }

    private func load() {
        guard let journal = services.journal else { return }
        do {
            years = try journal.yearsInReview(filter)
            finished = try Dictionary(uniqueKeysWithValues: years.map { ($0, try journal.yearInReview($0, filter).summary.finished) })
            if year == nil || !years.contains(year!) { year = years.first }
            review = try year.map { try journal.yearInReview($0, filter) }
            (platforms, lists) = try filterChoices(journal)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    @ViewBuilder private func content(_ r: YearInReview) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            // The heading is the year picker: a menu of the years with something in them.
            Menu {
                Picker("Year", selection: $year) {
                    ForEach(years, id: \.self) { y in Text("\(yearTitle(y)) (\(finished[y] ?? 0))").tag(Int?.some(y)) }
                }
                .pickerStyle(.inline).labelsHidden()
            } label: {
                HStack(spacing: 6) {
                    Text(yearTitle(r.year)).font(.largeTitle.bold())
                    Image(systemName: "chevron.down").font(.title3.bold()).foregroundStyle(.secondary)
                }
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            .help("Choose a year")
            summary(r.summary)
            playthroughSection("Finished", r.finished)
            playthroughSection("Dropped", r.dropped)
            playthroughSection("Also played", r.alsoPlayed)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func summary(_ s: YearSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 24) {
                stat("Finished", "\(s.finished)")
                stat("Dropped", "\(s.dropped)")
                stat("Started", "\(s.started)")
            }
            if !s.platforms.isEmpty {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 2) {
                    ForEach(s.platforms, id: \.name) { p in
                        GridRow {
                            Text(p.name)
                            Text("\(p.playthroughs) Playthrough\(p.playthroughs == 1 ? "" : "s")").foregroundStyle(.secondary)
                        }
                    }
                }
                .font(.callout).monospacedDigit()
            }
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading) {
            Text(value).font(.title.bold()).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func playthroughSection(_ title: String, _ entries: [YearPlaythrough]) -> some View {
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.title2)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 24, alignment: .top)], alignment: .leading, spacing: 24) {
                    ForEach(entries) { entry in
                        Button {
                            selection = entry.game.id
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                CoverTile(services: services, row: entry.game, width: 130)
                                Text(entry.game.name).lineLimit(2)
                                Text(entry.game.platformName).font(.caption).foregroundStyle(.secondary)
                                if entry.endDateUnknown { Text("end date unknown").font(.caption).foregroundStyle(.secondary) }
                            }
                            .frame(width: 130, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
