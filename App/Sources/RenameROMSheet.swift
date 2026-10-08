import LudeumCore
import SwiftUI

/// The name Rename offers a ROM, and whether another ROM already has it.
struct RenameOffer: Identifiable {
    let rom: LudeumROM
    let standard: ROMRename.StandardName
    let taken: Bool

    var id: Int64 { rom.id }
    var name: String { standard.name() }
}

/// Confirming a Rename: the name it gets, with a choice to drop each tag Rename can't place (a scene group's, or an
/// edition's), which is otherwise kept.
struct RenameROMSheet: View {
    let offer: RenameOffer
    /// Whether another ROM has the name, as it changes with the tags dropped.
    let isTaken: (String) -> Bool
    let rename: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var dropping: Set<String> = []

    private var name: String { offer.standard.name(dropping: dropping) }

    var body: some View {
        Form {
            Section {
                LabeledContent("Now", value: offer.rom.folderName)
                LabeledContent("Renamed") { Text(name).textSelection(.enabled) }
                if isTaken(name) { Text("Another ROM has this name.").foregroundStyle(.red) }
            } footer: {
                Text(
                    "Named as No-Intro (or Redump, on disc Platforms) would name it, with its Regions, in every form it's kept in. "
                        + "What's inside its folder or archive keeps its names.")
            }
            if !offer.standard.unplacedTags.isEmpty {
                UnplacedTagsChoice(tags: offer.standard.unplacedTags, dropping: $dropping)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Rename") {
                    rename(name)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isTaken(name))
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
    }
}

/// A checkbox for each tag Rename can't place, ticked to keep it.
struct UnplacedTagsChoice: View {
    let tags: [String]
    @Binding var dropping: Set<String>

    var body: some View {
        Section {
            ForEach(tags, id: \.self) { tag in
                Toggle(
                    "Keep \(tag)",
                    isOn: Binding(
                        get: { !dropping.contains(tag) },
                        set: { keep in if keep { dropping.remove(tag) } else { dropping.insert(tag) } }))
            }
        } footer: {
            Text("Tags it can't place: a scene group's, or an edition's.")
        }
    }
}
