import AppKit
import LudeumCore
import SwiftUI

/// A Platform's icon: 16 px colour pixel art from App/Resources/PlatformIcons. Most are gamicons
/// (MIT, by Jason Wilson); the platforms it lacks are drawn for the journal in the same style.
/// Anything else gets a symbol.
struct PlatformIcon: View {
    let platformId: Int64

    var body: some View {
        Group {
            if let image = Self.image(platformId) {
                // Nearest-neighbour keeps pixel art crisp on a Retina screen.
                Image(nsImage: image).interpolation(.none).resizable().frame(width: 16, height: 16)
            } else {
                Image(systemName: "gamecontroller")
            }
        }
        .frame(width: 22, height: 16)
    }

    /// IGDB platform id → icon file in PlatformIcons.
    private static let files: [Int64: String] = [
        33: "gamicons-gb", 22: "gamicons-gbc", 24: "gamicons-gba", 20: "gamicons-ds", 18: "gamicons-nes", 99: "gamicons-nes",
        19: "gamicons-snes", 58: "gamicons-snes",
        4: "gamicons-n64", 21: "gamicons-gcn", 5: "gamicons-wii", 29: "gamicons-gen", 32: "gamicons-sat", 7: "gamicons-psx",
        38: "gamicons-psp",
        9: "gamicons-ps3",
        130: "ludeum-switch", 86: "ludeum-pce", 150: "ludeum-pce", 64: "ludeum-sms", 35: "ludeum-gg", 78: "ludeum-scd",
        8: "ludeum-ps2", 48: "ludeum-ps4", 49: "ludeum-xone", 11: "ludeum-xbox", 12: "ludeum-x360",
        6: "ludeum-pc",
        13: "ludeum-pc",
    ]

    @MainActor private static var loaded: [Int64: NSImage?] = [:]

    @MainActor private static func image(_ id: Int64) -> NSImage? {
        if let cached = loaded[id] { return cached }
        let image = files[id]
            .flatMap { Bundle.main.url(forResource: $0, withExtension: "png", subdirectory: "PlatformIcons") }
            .flatMap(NSImage.init(contentsOf:))
        loaded[id] = image
        return image
    }
}
