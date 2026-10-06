import Foundation

/// A command-line tool Ludeum runs but doesn't bundle, checked for at launch. Each is optional:
/// without it, only what needs it fails, saying why.
public enum SystemTool: CaseIterable, Sendable {
    /// 7-Zip's `7zz`.
    case sevenZip

    public var name: String {
        switch self {
        case .sevenZip: "7-Zip"
        }
    }

    /// What can't be done without it.
    public var neededFor: String {
        switch self {
        case .sevenZip: "Archive, Unarchive and Compact, and seeing what's inside an Archived ROM"
        }
    }

    /// The command that installs it.
    public var install: String {
        switch self {
        case .sevenZip: "brew install sevenzip"
        }
    }

    public var isInstalled: Bool {
        switch self {
        case .sevenZip: SevenZip.find() != nil
        }
    }

    /// The tools that aren't installed. Only checks files exist, so it's quick.
    public static func missing() -> [SystemTool] { allCases.filter { !$0.isInstalled } }

    /// The launch warning about the `missing` tools, or nil when none are.
    public static func warning(missing: [SystemTool]) -> (title: String, message: String)? {
        guard let first = missing.first else { return nil }
        let title = missing.count == 1 ? "\(first.name) isn't installed" : "Some tools Ludeum uses aren't installed"
        let lines = missing.map { "\($0.name) is needed for \($0.neededFor). Install it with `\($0.install)`." }
        let rest = "Everything else works without \(missing.count == 1 ? "it" : "them")."
        return (title, (lines + [rest]).joined(separator: "\n\n"))
    }
}
