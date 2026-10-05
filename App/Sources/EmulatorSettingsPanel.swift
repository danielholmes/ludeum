import LudeumCore
import SwiftUI

/// One Emulator setting a Game can change: what it's called, what it does, its choices and how it
/// reads in a summary. Adding a setting is adding one of these to `rows(for:platformId:)`.
struct EmulatorSettingRow: Identifiable {
    let title: String
    let explanation: String
    /// The setting as a choice's value; nil is Default.
    let value: WritableKeyPath<EmulatorSettings, Int?>
    /// The choices besides Default, as (label, value).
    let choices: [(label: String, value: Int)]
    /// What Default means, e.g. "0 frames".
    let defaultLabel: String
    /// How a chosen value reads in the button's summary, e.g. "Run-ahead 2".
    let summary: (Int) -> String
    var id: String { title }

    static func rows(for emulator: Emulator, platformId: Int64) -> [EmulatorSettingRow] {
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
                + (emulator == .mesenCE && GameBoyModel.applies(to: platformId) ? [gameBoyModel] : [])
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

    private static var gameBoyModel: EmulatorSettingRow {
        EmulatorSettingRow(
            title: "Game Boy Model",
            explanation: "The hardware MesenCE plays this Game as. Games made for only one model show a warning screen on the "
                + "others.",
            value: \.gameBoyModelChoice,
            choices: GameBoyModel.allCases.enumerated().map { ($1.label, $0) },
            defaultLabel: "Auto", summary: { GameBoyModel.allCases[$0].label })
    }
}

/// Next to Play: "MesenCE · Run-ahead 2" (or "Default settings"), opening this Game's settings
/// for its Emulator.
struct EmulatorSettingsButton: View {
    let emulator: Emulator
    let platformId: Int64
    let settings: EmulatorSettings
    let save: (EmulatorSettings) -> Void
    @State private var showing = false

    private var rows: [EmulatorSettingRow] { EmulatorSettingRow.rows(for: emulator, platformId: platformId) }

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

extension GameBoyModel {
    var label: String {
        switch self {
        case .gameBoy: "Game Boy"
        case .gameBoyColor: "Game Boy Color"
        case .superGameBoy: "Super Game Boy"
        }
    }
}

extension EmulatorSettings {
    /// The Game Boy Model as a row choice: its index in `GameBoyModel.allCases`.
    fileprivate var gameBoyModelChoice: Int? {
        get { gameBoyModel.flatMap { GameBoyModel.allCases.firstIndex(of: $0) } }
        set { gameBoyModel = newValue.map { GameBoyModel.allCases[$0] } }
    }
}
