import JournalCore
import SwiftUI

/// Year in review: one year at a time, with the Library's filters.
struct YearInReviewScreen: View {
    let services: Services
    @Binding var selection: GameID?
    /// Opens the Library with a filter (the "no dates" footer).
    let openLibrary: (LibraryFilter) -> Void

    @State private var filter = LibraryFilter()
    @State private var years: [Int] = []
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
                ContentUnavailableView(
                    "Nothing to review", systemImage: "calendar",
                    description: Text(
                        filter == LibraryFilter()
                            ? "Playthroughs with dates and tracked OpenEmu play time show up here." : "Try fewer filters."))
            }
        }
        .navigationTitle("Year in review")
        .toolbar {
            if !years.isEmpty {
                Picker("Year", selection: $year) {
                    ForEach(years, id: \.self) { y in Text(yearTitle(y)).tag(Int?.some(y)) }
                }
            }
            LibraryFilterMenu(filter: $filter, platforms: platforms, lists: lists)
        }
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
            Text(r.isCurrentYear ? "\(String(r.year)) so far" : String(r.year)).font(.largeTitle.bold())
            summary(r.summary)
            playthroughSection("Finished", r.finished)
            playthroughSection("Dropped", r.dropped)
            playthroughSection("Also played", r.alsoPlayed)
            playTimeSection(r)
            if r.undatedPlaythroughs > 0 {
                Button(
                    "\(r.undatedPlaythroughs) Playthrough\(r.undatedPlaythroughs == 1 ? " has" : "s have") no dates"
                ) {
                    var f = filter
                    f.undatedPlaythroughs = true
                    openLibrary(f)
                }
                .buttonStyle(.link)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func summary(_ s: YearSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 24) {
                stat("Finished", "\(s.finished)")
                stat("Dropped", "\(s.dropped)")
                stat("Started", "\(s.started)")
                stat("Tracked", hoursText(s.playTimeSeconds))
            }
            if !s.platforms.isEmpty {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 2) {
                    ForEach(s.platforms, id: \.name) { p in
                        GridRow {
                            Text(p.name)
                            Text("\(p.playthroughs) Playthrough\(p.playthroughs == 1 ? "" : "s")").foregroundStyle(.secondary)
                            Text(p.playTimeSeconds > 0 ? hoursText(p.playTimeSeconds) : "").foregroundStyle(.secondary)
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
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), alignment: .top)], alignment: .leading, spacing: 16) {
                    ForEach(entries) { entry in
                        Button {
                            selection = entry.game.id
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                CoverView(services: services, game: entry.game.id, name: entry.game.name)
                                    .frame(width: 130, height: 174)
                                Text(entry.game.name).lineLimit(2)
                                Text(entry.game.platformName).font(.caption).foregroundStyle(.secondary)
                                HStack(spacing: 4) {
                                    if let rating = entry.game.rating { Text(ratingText(rating)).monospacedDigit() }
                                    if entry.endDateUnknown { Text("end date unknown").foregroundStyle(.secondary) }
                                }
                                .font(.caption)
                            }
                            .frame(width: 130, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder private func playTimeSection(_ r: YearInReview) -> some View {
        if !r.playTime.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("OpenEmu play time").font(.title2)
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                    ForEach(r.playTime) { entry in
                        GridRow {
                            Button(entry.game.name) { selection = entry.game.id }.buttonStyle(.link)
                            Text(entry.game.platformName).foregroundStyle(.secondary)
                            Text(hoursText(entry.seconds)).monospacedDigit().gridColumnAlignment(.trailing)
                        }
                    }
                    Divider()
                    GridRow {
                        Text("Total").bold()
                        Text("")
                        Text(hoursText(r.summary.playTimeSeconds)).bold().monospacedDigit()
                    }
                }
            }
        }
    }
}

/// Play time as "12 h 30 m", or "45 m" under an hour.
func hoursText(_ seconds: Double) -> String {
    let minutes = Int(seconds.rounded()) / 60
    return minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) m" : "\(minutes) m"
}
