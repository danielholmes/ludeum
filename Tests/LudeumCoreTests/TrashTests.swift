import Foundation
import Testing

@testable import LudeumCore

/// Sending to the Trash: a cloud item macOS won't trash (Dropbox keeps it online only) is deleted in Dropbox instead.
@Suite struct TrashTests {
    let item = URL(fileURLWithPath: "/ROMs/PSP/Tomb Raider - Anniversary (USA).7z")
    let unsupported = CocoaError(.featureUnsupported)

    @Test func itGoesToTheTrashWhenItCan() throws {
        var trashed: [URL] = []
        var removed: [URL] = []
        try Trash.move(item, trash: { trashed.append($0) }, remove: { removed.append($0) }, isCloud: { _ in true })
        #expect(trashed == [item])
        #expect(removed.isEmpty)
    }

    @Test func aCloudItemTheTrashWontTakeIsDeleted() throws {
        var removed: [URL] = []
        try Trash.move(item, trash: { _ in throw unsupported }, remove: { removed.append($0) }, isCloud: { _ in true })
        #expect(removed == [item])
    }

    @Test func anItemOnAVolumeWithNoTrashStays() {
        var removed: [URL] = []
        #expect(throws: CocoaError.self) {
            try Trash.move(item, trash: { _ in throw unsupported }, remove: { removed.append($0) }, isCloud: { _ in false })
        }
        #expect(removed.isEmpty)
    }

    @Test func anyOtherFailureStays() {
        var removed: [URL] = []
        #expect(throws: CocoaError.self) {
            try Trash.move(
                item, trash: { _ in throw CocoaError(.fileWriteNoPermission) }, remove: { removed.append($0) },
                isCloud: { _ in true })
        }
        #expect(removed.isEmpty)
    }
}
