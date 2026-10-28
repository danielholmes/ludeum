import Foundation

/// The boundary to the network. Production uses URLSession; tests use a fake.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
    /// The body written to `file` rather than held in memory, for a large download.
    func download(_ request: URLRequest, to file: URL) async throws -> HTTPURLResponse
    /// As `download(_:to:)`, telling `progress` how far it's got (0–1) when the server says how big the body is.
    func download(_ request: URLRequest, to file: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> HTTPURLResponse
}

extension HTTPTransport {
    public func download(_ request: URLRequest, to file: URL) async throws -> HTTPURLResponse {
        let (data, response) = try await send(request)
        try data.write(to: file)
        return response
    }

    public func download(_ request: URLRequest, to file: URL, progress: @escaping @Sendable (Double) -> Void) async throws
        -> HTTPURLResponse
    {
        let response = try await download(request, to: file)
        progress(1)
        return response
    }
}

public struct URLSessionTransport: HTTPTransport {
    let session: URLSession

    public init(session: URLSession = .shared) { self.session = session }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }

    public func download(_ request: URLRequest, to file: URL) async throws -> HTTPURLResponse {
        let (downloaded, response) = try await session.download(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        try FileManager.default.moveItem(at: downloaded, to: file)
        return http
    }

    /// Streamed into `file` a chunk at a time, so a big download (an Emulator) can say how far it's got.
    public func download(_ request: URLRequest, to file: URL, progress: @escaping @Sendable (Double) -> Void) async throws
        -> HTTPURLResponse
    {
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard http.statusCode == 200 else { return http }
        FileManager.default.createFile(atPath: file.path(percentEncoded: false), contents: nil)
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        let expected = http.expectedContentLength
        var buffer = Data()
        var written: Int64 = 0
        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= 1 << 20 {
                try handle.write(contentsOf: buffer)
                written += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                if expected > 0 { progress(Double(written) / Double(expected)) }
            }
        }
        try handle.write(contentsOf: buffer)
        progress(1)
        return http
    }
}

public struct HTTPStatusError: Error, CustomStringConvertible {
    public let status: Int
    public let url: URL?
    public var description: String { "HTTP \(status) from \(url?.absoluteString ?? "?")" }
}
