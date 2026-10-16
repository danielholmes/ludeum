import Foundation

/// The boundary to the network. Production uses URLSession; tests use a fake.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
    /// The body written to `file` rather than held in memory, for a large download.
    func download(_ request: URLRequest, to file: URL) async throws -> HTTPURLResponse
}

extension HTTPTransport {
    public func download(_ request: URLRequest, to file: URL) async throws -> HTTPURLResponse {
        let (data, response) = try await send(request)
        try data.write(to: file)
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
}

public struct HTTPStatusError: Error, CustomStringConvertible {
    public let status: Int
    public let url: URL?
    public var description: String { "HTTP \(status) from \(url?.absoluteString ?? "?")" }
}
