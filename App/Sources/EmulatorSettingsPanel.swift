import LudeumCore
import SwiftUI

/// One Emulator setting a Game can change: what it's called, what it does, its choices and how it
/// reads in a summary. Adding a setting is adding one of these to `rows(for:)`.
struct EmulatorSettingRow: Identifiable {
    let title: String
    let explanation: String
    let value: WritableKeyPath<EmulatorSettings, Int?>
    /// The choices besides Default, as (label, value).
    let choices: [(label: String, value: Int)]
    /// What Default means, e.g. "0 frames".
    let defaultLabel: String
    /// How a chosen value reads in the button's summary, e.g. "Run-ahead 2".
    let summary: (Int) -> String
    var id: String { title }

    static func rows(for emulator: Emulator) -> [EmulatorSettingRow] {
        switch emulator {
        case .mesenCE, .duckStation:
            [
                EmulatorSettingRow(
                    title: "Run-ahead",
                    explanation: "Frames \(emulator.name) runs ahead to hide the game's own input lag. Set it to the game's lag "
                        + "in frames; too high makes sprites jitter.",
                    value: \.runAheadFrames,
                    choices: EmulatorSettings.runAheadRange.map { ("\($0) frame\($0 == 1 ? "" : "s")", $0) },
                    defaultLabel: "0 frames", summary: { "Run-ahead \($0)" })
            ]
        case .ares:
            [
                EmulatorSettingRow(
                    title: "Run-ahead",
                    explanation: "ares runs one frame ahead to hide the game's own input lag. It can't run further "
                        + "ahead than one frame.",
                    value: \.runAheadFrames,
                    choices: [("Off", 0), ("On (1 frame)", 1)],
                    defaultLabel: "off", summary: { $0 > 0 ? "Run-ahead on" : "Run-ahead off" })
            ]
        default: []
        }
    }
}

/// Next to Play: "MesenCE · Run-ahead 2" (or "Default settings"), opening this Game's settings
/// for its Emulator.
struct EmulatorSettingsButton: View {
    let emulator: Emulator
    let settings: EmulatorSettings
    let save: (EmulatorSettings) -> Void
    @State private var showing = false

    private var rows: [EmulatorSettingRow] { EmulatorSettingRow.rows(for: emulator) }

    private var summary: String {
        let changed = rows.compactMap { row in settings[keyPath: row.value].map(row.summary) }
        return changed.isEmpty ? "Default settings" : changed.joined(separator: " · ")
    }

    var body: some View {
        Button {
            showing = true
        } label: {
            Label("\(emulator.name) · \(summary)", systemImage: "slider.horizontal.3")
        }
        .buttonStyle(.hover)
        .help("This Game's \(emulator.name) settings")
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(emulator.name) settings").font(.headline)
                    Text("For this Game, applied every time you Play it.").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        Picker(row.title, selection: binding(row.value)) {
                            Text("Default (\(row.defaultLabel))").tag(Int?.none)
                            ForEach(row.choices, id: \.value) { choice in Text(choice.label).tag(Int?.some(choice.value)) }
                        }
                        Text(row.explanation).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Divider()
                Button("Reset to defaults") { save(EmulatorSettings()) }
                    .disabled(settings == EmulatorSettings())
            }
            .padding()
            .frame(width: 340)
        }
    }

    private func binding(_ value: WritableKeyPath<EmulatorSettings, Int?>) -> Binding<Int?> {
        Binding(
            get: { settings[keyPath: value] },
            set: { new in
                var changed = settings
                changed[keyPath: value] = new
                save(changed)
            })
    }
}
