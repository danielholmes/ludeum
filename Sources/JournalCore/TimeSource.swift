import Foundation

/// The boundary to wall-clock time, so expiry and throttling can be tested.
public protocol TimeSource: Sendable {
    func now() -> Date
    func sleep(seconds: Double) async throws
}

public struct SystemTimeSource: TimeSource {
    public init() {}
    public func now() -> Date { Date() }
    public func sleep(seconds: Double) async throws {
        guard seconds > 0 else { return }
        try await Task.sleep(for: .seconds(seconds))
    }
}
