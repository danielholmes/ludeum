import Foundation

/// 7-Zip's command line, `7zz` (Homebrew's `sevenzip`). Ludeum doesn't bundle it.
public struct SevenZip: Sendable {
    let executable: URL

    /// One file in an archive.
    public struct Entry: Sendable, Equatable {
        /// Its path inside the archive.
        public let path: String
        public let size: Int64

        public var fileName: String { (path as NSString).lastPathComponent }
    }

    /// `7zz` where Homebrew puts it, if it's installed.
    public static func find() -> SevenZip? {
        ["/opt/homebrew/bin/7zz", "/usr/local/bin/7zz"].first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { SevenZip(executable: URL(filePath: $0)) }
    }

    /// What's in the archive, read from its index without unpacking it: quick when the archive is
    /// on disk, but an online-only one is downloaded first (check `isOnDisk(_:)`).
    public func contents(of archive: URL) async throws -> [Entry] { try await list(archive) }

    /// False for a cloud file (Dropbox, iCloud) that's online-only: reading it would download it all.
    public static func isOnDisk(_ file: URL) -> Bool {
        guard let values = try? file.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]),
            values.isUbiquitousItem == true
        else { return true }
        return values.ubiquitousItemDownloadingStatus != .notDownloaded
    }

    /// The archive's files (not its folders).
    func list(_ archive: URL) async throws -> [Entry] {
        let output = try await run(["l", "-slt", "-ba", archive.path(percentEncoded: false)])
        // One block of "Key = Value" lines per entry, separated by blank lines.
        return output.components(separatedBy: "\n\n").compactMap { block in
            var fields: [String: String] = [:]
            for line in block.split(separator: "\n") {
                let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                if parts.count == 2 { fields[parts[0]] = parts[1] }
            }
            guard let path = fields["Path"], fields["Folder"] != "+", !(fields["Attributes"] ?? "").hasPrefix("D") else { return nil }
            return Entry(path: path, size: Int64(fields["Size"] ?? "") ?? 0)
        }
    }

    /// Extracts `paths` from the archive into `folder`, keeping their paths inside it.
    func extract(_ archive: URL, paths: [String], to folder: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        _ = try await run(
            ["x", "-y", "-bsp1", archive.path(percentEncoded: false), "-o\(folder.path(percentEncoded: false))"] + paths,
            progress: progress)
    }

    /// A new archive at maximum compression, holding `files` (names in `folder`) without any folder.
    func create(_ archive: URL, files: [String], in folder: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        _ = try await run(
            ["a", "-t7z", "-mx=9", "-bsp1", archive.path(percentEncoded: false)] + files, in: folder, progress: progress)
    }

    /// Throws unless every file in the archive tests as intact.
    func test(_ archive: URL) async throws {
        _ = try await run(["t", archive.path(percentEncoded: false)])
    }

    /// Runs `7zz`, reporting the percentages it prints with `-bsp1`. Cancelling the task stops it.
    private func run(_ arguments: [String], in folder: URL? = nil, progress: (@Sendable (Double) -> Void)? = nil) async throws -> String {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = folder
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        let collected = Collected()
        let errors = Collected()
        // Both pipes drain as 7zz writes: a full pipe would stop it.
        err.fileHandleForReading.readabilityHandler = { errors.append(String(decoding: $0.availableData, as: UTF8.self)) }
        out.fileHandleForReading.readabilityHandler = { handle in
            let text = String(decoding: handle.availableData, as: UTF8.self)
            collected.append(text)
            if let progress, let percent = text.matches(of: /(\d{1,3})%/).last.flatMap({ Int($0.output.1) }) {
                progress(Double(percent) / 100)
            }
        }
        try Task.checkCancellation()
        let running = RunningProcess(process)
        let status: Int32 = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
                do { try running.launch() } catch { continuation.resume(throwing: error) }
            }
        } onCancel: {
            running.stop()
        }
        out.fileHandleForReading.readabilityHandler = nil
        err.fileHandleForReading.readabilityHandler = nil
        collected.append(String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
        errors.append(String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
        try Task.checkCancellation()
        guard status == 0 else { throw ArchiveError.sevenZipFailed(errors.text.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return collected.text
    }
}

/// A process that can be stopped from any thread, before or after it launches: stopping one that
/// hasn't launched yet means it never does.
private final class RunningProcess: @unchecked Sendable {
    private let lock = NSLock()
    private let process: Process
    private var stopped = false

    init(_ process: Process) { self.process = process }

    func launch() throws {
        try lock.withLock {
            if stopped { throw CancellationError() }
            try process.run()
        }
    }

    func stop() {
        lock.withLock {
            stopped = true
            if process.isRunning { process.terminate() }
        }
    }
}

/// Output gathered from a pipe's handler, which runs on its own queue.
private final class Collected: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = ""

    func append(_ text: String) { lock.withLock { buffer += text } }
    var text: String { lock.withLock { buffer } }
}
