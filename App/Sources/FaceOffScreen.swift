import LudeumCore
import SwiftUI

/// Face-off: two rated Games at a time, without their Ratings, and I pick the one I liked more. The Disagreements
/// its Battles find are one tab away at any point.
struct FaceOffScreen: View {
    let services: Services
    @Binding var selection: GameID?

    private enum Tab { case battles, disagreements }

    @State private var tab = Tab.battles
    @State private var pair: FaceOffPair?
    @State private var ratedGames = 0
    /// The last pick and the pair it was made on, for Undo: one level only.
    @State private var lastPick: (pick: FaceOffPick, pair: FaceOffPair)?
    @State private var battlesToday = 0
    @State private var disagreements: [Disagreement] = []
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $tab) {
                Text("Battles").tag(Tab.battles)
                Text(disagreements.isEmpty ? "Disagreements" : "Disagreements (\(disagreements.count))").tag(Tab.disagreements)
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
            .padding()
            if let error {
                Text(error).foregroundStyle(.red).font(.callout).padding(.bottom)
            }
            switch tab {
            case .battles: battles
            case .disagreements:
                DisagreementsList(services: services, disagreements: disagreements, selection: $selection, save: save)
            }
        }
        // Game detail would show a Rating beside the pair.
        .onChange(of: tab, initial: true) { if tab == .battles { selection = nil } }
        .navigationTitle("Face-off")
        .disabled(services.work.journalLocked)
        .task(id: services.changes.revision) { load() }
    }

    // MARK: Battles

    @ViewBuilder private var battles: some View {
        if ratedGames < 2 {
            ContentUnavailableView(
                "Not enough rated Games", systemImage: "star", description: Text("Rate at least two Games in their detail."))
        } else if let pair {
            VStack(spacing: 16) {
                Text("Which did you like more?").font(.title2.bold())
                HStack(alignment: .top, spacing: 24) {
                    fighter(pair.left) { pick(.a) }
                    Text("vs").font(.title3).foregroundStyle(.secondary).padding(.top, 160)
                    fighter(pair.right) { pick(.b) }
                }
                HStack {
                    Button("Left") { pick(.a) }.keyboardShortcut(.leftArrow, modifiers: [])
                    Button("About the same") { pick(.same) }.keyboardShortcut(.downArrow, modifiers: [])
                    Button("Right") { pick(.b) }.keyboardShortcut(.rightArrow, modifiers: [])
                    Button("Skip") { skip() }.keyboardShortcut(.space, modifiers: [])
                    Button("Undo") { undo() }.keyboardShortcut(.delete, modifiers: []).disabled(lastPick == nil)
                }
                Text("← → pick · ↓ About the same · Space skip · ⌫ undo · \(battlesToday) Battle\(battlesToday == 1 ? "" : "s") today")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            ContentUnavailableView(
                "No pair left today", systemImage: "checkmark.circle",
                description: Text("Every pair has been fought in the last two weeks or skipped today."))
        }
    }

    private func fighter(_ game: FaceOffGame, choose: @escaping () -> Void) -> some View {
        Button(action: choose) {
            VStack(spacing: 6) {
                CoverView(services: services, game: game.id, name: game.name)
                    .frame(width: 270, height: 360)
                Text(game.name).font(.callout).multilineTextAlignment(.center).lineLimit(2)
                Text(game.platformName).font(.caption).foregroundStyle(.secondary)
            }
            .frame(width: 280)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func pick(_ result: BattleResult) {
        guard let journal = services.journal, let shown = pair else { return }
        record(shown) { try journal.recordBattle(shown, result) }
    }

    private func skip() {
        guard let journal = services.journal, let shown = pair else { return }
        record(shown) { try journal.skip(shown) }
    }

    private func record(_ shown: FaceOffPair, _ make: () throws -> FaceOffPick) {
        do {
            lastPick = (try make(), shown)
            pair = nil
            services.changes.changed()
        } catch {
            self.error = journalErrorText(error)
        }
    }

    /// Takes back the last pick and shows its pair again.
    private func undo() {
        guard let journal = services.journal, let last = lastPick else { return }
        do {
            try journal.undo(last.pick)
            lastPick = nil
            pair = last.pair
            services.changes.changed()
        } catch {
            self.error = journalErrorText(error)
        }
    }

    // MARK: Loading

    private func save(_ change: (LudeumStore) throws -> Void) {
        guard let journal = services.journal else { return }
        do {
            try change(journal)
            error = nil
            services.changes.changed()
        } catch {
            self.error = journalErrorText(error)
        }
    }

    /// Reads the Disagreements and today's count, and chooses a pair when none is showing.
    private func load() {
        guard let journal = services.journal else { return }
        do {
            let rated = Set(try journal.faceOffGames().map(\.id))
            ratedGames = rated.count
            battlesToday = try journal.battlesToday()
            disagreements = try journal.disagreements()
            // One of them was unrated or deleted meanwhile.
            if let shown = pair, !rated.isSuperset(of: [shown.left.id, shown.right.id]) { pair = nil }
            if pair == nil {
                var rng = SystemRandomNumberGenerator()
                pair = try journal.nextFaceOffPair(using: &rng)
            }
            error = nil
        } catch {
            self.error = journalErrorText(error)
        }
    }
}

/// The Disagreements, biggest gap first, each with its placement, its Battles, and Set Rating or Keep.
private struct DisagreementsList: View {
    let services: Services
    let disagreements: [Disagreement]
    @Binding var selection: GameID?
    let save: ((LudeumStore) throws -> Void) -> Void

    var body: some View {
        if disagreements.isEmpty {
            ContentUnavailableView(
                "No Disagreements yet", systemImage: "rectangle.on.rectangle",
                description: Text("They show here once Battles consistently place a Game away from its Rating."))
        } else {
            List(disagreements, selection: $selection) { disagreement in
                DisagreementRow(services: services, disagreement: disagreement, save: save).tag(disagreement.game.id)
            }
        }
    }
}

private struct DisagreementRow: View {
    let services: Services
    let disagreement: Disagreement
    let save: ((LudeumStore) throws -> Void) -> Void
    @State private var text = ""
    @State private var invalid = false

    private var game: FaceOffGame { disagreement.game }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CoverView(services: services, game: game.id, name: game.name).frame(width: 60, height: 80)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(game.name).font(.headline)
                    Text(game.platformName).font(.caption).foregroundStyle(.secondary)
                }
                Text(summary)
                DisclosureGroup("\(disagreement.evidence.count) Battle\(disagreement.evidence.count == 1 ? "" : "s")") {
                    ForEach(Array(disagreement.evidence.enumerated()), id: \.offset) { _, evidence in
                        HStack {
                            Text(verdictText(evidence.verdict)).foregroundStyle(verdictColour(evidence.verdict)).frame(
                                width: 90, alignment: .leading)
                            Text(evidence.opponent.name)
                            Text(ratingText(evidence.opponent.rating)).monospacedDigit().foregroundStyle(.secondary)
                            Spacer()
                            Text("counts \(Int((evidence.counts * 100).rounded()))%").font(.caption).foregroundStyle(.secondary)
                        }
                        .font(.callout)
                    }
                }
                HStack {
                    TextField("Rating", text: $text, prompt: Text("0.0–10.0")).frame(width: 70).onSubmit(setRating)
                    Button("Set Rating", action: setRating)
                    Button("Keep \(ratingText(game.rating))") { save { try $0.keepRating(game.id) } }
                        .help("Stand by this Rating until it fights another Battle")
                    if invalid { Text("0.0 to 10.0, in steps of 0.1").font(.caption).foregroundStyle(.red) }
                }
            }
        }
        .padding(.vertical, 6)
        .onAppear { text = ratingText(suggested) }
    }

    private var summary: AttributedString {
        let direction = disagreement.direction == .tooHigh ? "too high" : "too low"
        let placement: String =
            switch disagreement.placement {
            case .around(let from, let to): "belongs around \(ratingText(from))–\(ratingText(to))"
            case .below(let rating): "belongs below \(ratingText(rating))"
            case .above(let rating): "belongs above \(ratingText(rating))"
            }
        return (try? AttributedString(markdown: "Rated **\(ratingText(game.rating))**, probably **\(direction)**: \(placement)"))
            ?? AttributedString()
    }

    /// The middle of its placement, or one step past a one-sided one.
    private var suggested: Rating {
        switch disagreement.placement {
        case .around(let from, let to): Rating(tenths: (from.tenths + to.tenths) / 2)!
        case .below(let rating): Rating(tenths: max(0, rating.tenths - 1))!
        case .above(let rating): Rating(tenths: min(100, rating.tenths + 1))!
        }
    }

    private func setRating() {
        guard let rating = parseRating(text.trimmed) else {
            invalid = true
            return
        }
        invalid = false
        save { try $0.setRating(game.id, rating) }
    }

    private func verdictText(_ verdict: Disagreement.Evidence.Verdict) -> String {
        switch verdict {
        case .won: "Beat"
        case .lost: "Lost to"
        case .same: "Same as"
        }
    }

    private func verdictColour(_ verdict: Disagreement.Evidence.Verdict) -> Color {
        switch verdict {
        case .won: .green
        case .lost: .red
        case .same: .secondary
        }
    }
}
