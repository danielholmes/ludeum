import Foundation

/// Sending a file or folder to the Trash. One Dropbox keeps online only, or a folder holding one, can't go there (macOS
/// says the volume has no Trash), so a cloud item that can't is deleted in Dropbox instead, which keeps it recoverable on
/// dropbox.com for a while. Anything else that can't go to the Trash stays, and the error says why.
public enum Trash {
    public static func move(_ item: URL) throws {
        try move(
            item, trash: { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) },
            remove: { try FileManager.default.removeItem(at: $0) }, isCloud: isCloud)
    }

    static func move(
        _ item: URL, trash: (URL) throws -> Void, remove: (URL) throws -> Void, isCloud: (URL) -> Bool
    ) throws {
        do {
            try trash(item)
        } catch let error as CocoaError where error.code == .featureUnsupported && isCloud(item) {
            try remove(item)
        }
    }

    /// Whether it's in a cloud folder (Dropbox, iCloud).
    static func isCloud(_ item: URL) -> Bool {
        (try? item.resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem) == true
    }
}
