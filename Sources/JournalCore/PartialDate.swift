import Foundation

/// A date known only to the year, month or day: `1996`, `1996-03` or `1996-03-17`.
/// Its text sorts as the Partial date sort (a less precise date before the dates within it),
/// so the journal stores and compares it as plain text.
public struct PartialDate: Hashable, Comparable, Sendable {
    public let text: String

    public init?(_ text: String) {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count),
            parts[0].count == 4, parts.dropFirst().allSatisfy({ $0.count == 2 }),
            parts.allSatisfy({ $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) })
        else { return nil }
        let numbers = parts.map { Int($0)! }
        if numbers.count > 1, !(1...12).contains(numbers[1]) { return nil }
        if numbers.count > 2 {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "UTC")!
            let components = DateComponents(year: numbers[0], month: numbers[1], day: numbers[2])
            guard let date = calendar.date(from: components),
                calendar.component(.day, from: date) == numbers[2]
            else { return nil }
        }
        self.text = text
    }

    /// Whether `other` falls within this date: `2024` contains `2024-03` and itself.
    public func contains(_ other: PartialDate) -> Bool {
        other.text.hasPrefix(text)
    }

    public static func < (lhs: PartialDate, rhs: PartialDate) -> Bool { lhs.text < rhs.text }
}
