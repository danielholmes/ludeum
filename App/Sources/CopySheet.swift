import LudeumCore
import SwiftUI

/// What the Copy sheet edits: a new hand-recorded Copy, an existing one, or a ROM's Copy details.
enum CopyEdit: Identifiable {
    case new
    case copy(Copy)
    case rom(LudeumROM)

    var id: String {
        switch self {
        case .new: "new"
        case .copy(let c): "copy \(c.id)"
        case .rom(let r): "rom \(r.id)"
        }
    }
}

/// Adding or editing a Copy. Every field is optional but the Kind; a ROM has no Kind to choose and is never Gone.
struct CopySheet: View {
    let services: Services
    let game: GameID
    let edit: CopyEdit
    let done: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var kind = CopyKind.physical
    @State private var regions: [String] = []
    @State private var acquiredOn = ""
    @State private var acquiredFrom = ""
    @State private var price = ""
    @State private var currency = Price.homeCurrency
    @State private var gone = false
    @State private var goneOn = ""
    @State private var goneTo = ""
    @State private var regionSuggestions: [String] = []
    @State private var error: String?
    @State private var confirmingDelete = false
    @State private var deleteRunning = false

    private var rom: LudeumROM? { if case .rom(let r) = edit { r } else { nil } }
    private var existingCopy: Copy? { if case .copy(let c) = edit { c } else { nil } }
    private static let datePrompt = Text("YYYY, YYYY-MM or YYYY-MM-DD")

    var body: some View {
        Form {
            if let rom {
                Section {
                    Text(rom.fileName).font(.headline)
                    Text("A ROM is a Copy: these are what it shares with the others.").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Picker("Kind", selection: $kind) {
                    ForEach(CopyKind.allCases, id: \.self) { Text(copyKindText($0)).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            RegionsEditor(regions: $regions, suggestions: regionSuggestions)
            TextField("Acquired on", text: $acquiredOn, prompt: Self.datePrompt)
            TextField("Acquired from", text: $acquiredFrom)
            LabeledContent("Price") {
                HStack {
                    TextField("Price", text: $price, prompt: Text("0.00")).labelsHidden()
                    TextField("Currency", text: $currency, prompt: Text(Price.homeCurrency)).labelsHidden().frame(width: 60)
                        .help("A 3-letter code, e.g. AUD, USD, JPY")
                }
            }
            if rom == nil {
                Toggle("No longer owned", isOn: $gone)
                if gone {
                    TextField("Gone on", text: $goneOn, prompt: Self.datePrompt)
                    TextField("Gone to", text: $goneTo, prompt: Text("Sold on eBay, given to a friend, lost…"))
                }
            }
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                if existingCopy != nil { Button("Delete…", role: .destructive) { confirmingDelete = true } }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save", action: save).keyboardShortcut(.defaultAction)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .disabled(deleteRunning)
        .confirmationDialog("Delete this Copy?", isPresented: $confirmingDelete) {
            Button("Delete Copy", role: .destructive, action: delete)
        } message: {
            Text("It leaves the journal for good, unlike marking it no longer owned. There's no undo; a backup is taken first.")
        }
        .onAppear {
            let details: CopyDetails
            switch edit {
            case .new: details = CopyDetails()
            case .copy(let c):
                details = c.draft.details
                kind = c.draft.kind
                gone = c.draft.gone != nil
                goneOn = c.draft.gone?.on?.text ?? ""
                goneTo = c.draft.gone?.to ?? ""
            case .rom(let r): details = r.details
            }
            regions = details.regions
            acquiredOn = details.acquiredOn?.text ?? ""
            acquiredFrom = details.acquiredFrom ?? ""
            price = details.price.map { "\($0.amount)" } ?? ""
            currency = details.price?.currency ?? Price.homeCurrency
            regionSuggestions = (try? services.journal?.regionSuggestions()) ?? Regions.suggested
        }
    }

    private func save() {
        guard let journal = services.journal else { return }
        func date(_ text: String, _ label: String) throws -> PartialDate? {
            guard !text.trimmed.isEmpty else { return nil }
            guard let d = PartialDate(text.trimmed) else {
                throw FieldError(message: "The \(label) date should look like 1996, 1996-03 or 1996-03-17.")
            }
            return d
        }
        do {
            let details = CopyDetails(
                regions: regions, acquiredOn: try date(acquiredOn, "acquired"), acquiredFrom: acquiredFrom.trimmed.nilIfEmpty,
                price: try parsedPrice())
            switch edit {
            case .rom(let r): try journal.setROMDetails(r.id, details)
            case .new, .copy:
                let draft = CopyDraft(
                    kind: kind, details: details,
                    gone: gone ? Gone(on: try date(goneOn, "gone"), to: goneTo.trimmed.nilIfEmpty) : nil)
                if let c = existingCopy { try journal.updateCopy(c.id, draft) } else { try journal.addCopy(game, draft) }
            }
            done()
        } catch let e as FieldError {
            error = e.message
        } catch {
            self.error = journalErrorText(error)
        }
    }

    /// The price typed, in its currency: nothing typed is no price.
    private func parsedPrice() throws -> Price? {
        let amount = price.trimmed
        guard !amount.isEmpty else { return nil }
        guard let value = Decimal(string: amount, locale: Locale(identifier: "en_US_POSIX")), value >= 0 else {
            throw FieldError(message: "The price should be a number, like 45 or 45.50.")
        }
        let code = currency.trimmed.uppercased()
        guard code.count == 3, code.allSatisfy(\.isLetter) else {
            throw FieldError(message: "The currency should be a 3-letter code, like AUD.")
        }
        return Price(amount: value, currency: code)
    }

    /// Off the main thread, as a backup of the whole journal is taken first.
    private func delete() {
        guard let journal = services.journal, let copy = existingCopy, !deleteRunning else { return }
        deleteRunning = true
        Task {
            defer { deleteRunning = false }
            do {
                try await offMain { try journal.deleteCopy(copy.id) }
                done()
            } catch {
                self.error = journalErrorText(error)
            }
        }
    }

    private struct FieldError: Error { let message: String }
}

/// A Copy's Regions: each as a chip with ×, and a field to add one, typed or picked from the suggestions.
struct RegionsEditor: View {
    @Binding var regions: [String]
    let suggestions: [String]
    @State private var typed = ""

    var body: some View {
        LabeledContent("Regions") {
            VStack(alignment: .leading, spacing: 6) {
                if !regions.isEmpty {
                    FlowLayout(spacing: 4) {
                        ForEach(regions, id: \.self) { region in
                            HStack(spacing: 4) {
                                Text(region)
                                Button("Remove", systemImage: "xmark") { regions.removeAll { $0 == region } }
                                    .labelStyle(.iconOnly).buttonStyle(.hover).imageScale(.small)
                            }
                            .padding(.leading, 8).padding(.vertical, 2)
                            .background(.quaternary, in: .capsule)
                        }
                    }
                }
                HStack {
                    TextField("Add a Region", text: $typed, prompt: Text("Add a Region")).labelsHidden().onSubmit(addTyped)
                    let offered = suggestions.filter { !regions.contains($0) }
                    if !offered.isEmpty {
                        Menu("Suggestions") { ForEach(offered, id: \.self) { s in Button(s) { add(s) } } }.fixedSize()
                    }
                }
            }
        }
    }

    private func addTyped() {
        add(typed)
        typed = ""
    }

    private func add(_ region: String) {
        let region = region.trimmed
        guard !region.isEmpty, !regions.contains(where: { $0.caseInsensitiveCompare(region) == .orderedSame }) else { return }
        regions = Regions.ordered(regions + [region])
    }
}

func copyKindText(_ kind: CopyKind) -> String {
    switch kind {
    case .physical: "Physical"
    case .digital: "Digital"
    case .physicalAndDigital: "Physical + digital"
    }
}

/// "A$45.50", "¥3,200", or "45.50 XYZ" for a currency the system can't format.
func priceText(_ price: Price) -> String {
    price.amount.formatted(.currency(code: price.currency))
}

/// What a Copy says about itself on one line: "USA, Europe · Acquired 2019-03 from eBay for A$45.50". Nil when it says
/// nothing.
func copyDetailsText(_ d: CopyDetails) -> String? {
    var parts: [String] = []
    if !d.regions.isEmpty { parts.append(d.regions.joined(separator: ", ")) }
    let acquired = [
        d.acquiredOn.map { "Acquired \($0.text)" } ?? (d.acquiredFrom != nil || d.price != nil ? "Acquired" : nil),
        d.acquiredFrom.map { "from \($0)" }, d.price.map { "for \(priceText($0))" },
    ].compactMap { $0 }
    if !acquired.isEmpty { parts.append(acquired.joined(separator: " ")) }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
}

/// "Gone 2021 to a friend", "Gone".
func goneText(_ g: Gone) -> String {
    ["Gone", g.on?.text, g.to.map { "to \($0)" }].compactMap { $0 }.joined(separator: " ")
}
