import Foundation

/// A copy of a file that may be slow to read, kept out of the way until it's whole. Dropbox downloads a file it keeps
/// online only when it's read, which can take minutes, so that's done here, before the journal is touched: the journal's
/// `DatabaseQueue` makes every read wait for a write, and the main thread reads it, so doing it in a write locks up the app.
enum LocalCopy {
    /// Hands `use` a copy of `file`, in a temporary folder on the volume of `folder`, which must exist: moving it from there
    /// into `folder` is only a rename, and outside the Data folder Dropbox never sees it part-copied. It's gone afterwards
    /// unless `use` moved it. Throws `CancellationError`, without calling `use`, when the task was cancelled as it copied.
    static func with<T>(
        of file: URL, onVolumeOf folder: URL,
        copy: (URL, URL) throws -> Void = { try FileManager.default.copyItem(at: $0, to: $1) },
        _ use: (URL) throws -> T
    ) throws -> T {
        let work = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: folder, create: true)
        defer { try? FileManager.default.removeItem(at: work) }
        let local = work.appending(path: file.lastPathComponent, directoryHint: .notDirectory)
        try copy(file, local)
        try Task.checkCancellation()
        return try use(local)
    }
}
