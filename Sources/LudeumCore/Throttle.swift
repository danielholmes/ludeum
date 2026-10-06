import Foundation

/// Sends requests to one service no faster than its rate limit, and waits out
/// "429 Too Many Requests" replies (honouring Retry-After) before retrying.
final class Throttle: Sendable {
    private let transport: HTTPTransport
    private let clock: TimeSource
    private let slots: Slots
    private let maxRetries = 5

    init(requestsPerSecond: Double, transport: HTTPTransport, clock: TimeSource) {
        self.transport = transport
        self.clock = clock
        slots = Slots(interval: 1 / requestsPerSecond, clock: clock)
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var attempt = 0
        while true {
            try await slots.wait()
            let (data, response) = try await transport.send(request)
            guard response.statusCode == 429, attempt < maxRetries else { return (data, response) }
            attempt += 1
            let retryAfter = response.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init) ?? 1
            try await clock.sleep(seconds: retryAfter)
        }
    }

    /// Hands out send times at least `interval` apart. A caller waits until the next one is free and only then takes
    /// it, so concurrent callers queue up rather than bunching together, and one cancelled while it waits takes none.
    private actor Slots {
        let interval: TimeInterval
        let clock: TimeSource
        var next: Date?

        init(interval: TimeInterval, clock: TimeSource) {
            self.interval = interval
            self.clock = clock
        }

        func wait() async throws {
            // Another caller can take the time waited for, so look again after every sleep.
            while let next, next > clock.now() { try await clock.sleep(seconds: next.timeIntervalSince(clock.now())) }
            next = clock.now().addingTimeInterval(interval)
        }
    }
}
