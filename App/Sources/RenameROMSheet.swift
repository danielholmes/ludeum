import LudeumCore
import SwiftUI

/// The name Rename offers a ROM, and whether another ROM already has it.
struct RenameOffer: Identifiable {
    let rom: LudeumROM
    let standard: ROMRename.StandardName
    let taken: Bool

    var id: Int64 { rom.id }
    var name: String { standard.name() }
    /// Whether its Standard name, with every tag kept, is a new name: when it isn't, Rename is offered only to drop tags.
    var changesName: Bool { name != rom.folderName }

    /// What Rename… does for it, or why it can't.
    var help: String {
        if !changesName { return "Drop its languages or tags it can't place from its name" }
        return taken ? "Another ROM has the name it would be given" : "Rename it “\(name)”"
    }
}

/// Confirming a Rename: the name it gets, with a choice to drop its languages and each tag Rename can't place (a scene
/// group's, or an edition's), which are otherwise kept.
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
                if isTaken(name) { ErrorText("Another ROM has this name.") }
            } footer: {
                Text(
                    "Named as No-Intro (or Redump, on disc Platforms) would name it, with its Regions, in every form it's kept in. "
                        + "What's inside its folder or archive keeps its names.")
            }
            if !offer.standard.droppableTags.isEmpty {
                DroppableTagsChoice(tags: offer.standard.droppableTags, dropping: $dropping)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Rename") {
                    rename(name)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isTaken(name) || name == offer.rom.folderName)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
    }
}

/// A checkbox for each tag that can be dropped from a Standard name, its languages and those it can't place, ticked to
/// keep it.
struct DroppableTagsChoice: View {
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
            Text("Its languages, and tags it can't place: a scene group's, or an edition's.")
        }
    }
}
