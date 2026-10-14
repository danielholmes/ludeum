import Foundation

/// A command-line tool Ludeum runs, or points me to, but doesn't bundle, checked for at launch. Each is optional:
/// without it, only what needs it fails, saying why.
public enum SystemTool: CaseIterable, Sendable {
    /// 7-Zip's `7zz`.
    case sevenZip
    /// xdvdfs, which makes an XISO of a full Redump Xbox image.
    case xdvdfs

    public var name: String {
        switch self {
        case .sevenZip: "7-Zip"
        case .xdvdfs: "xdvdfs"
        }
    }

    /// What can't be done without it.
    public var neededFor: String {
        switch self {
        case .sevenZip: "Archive, Unarchive and Compact, and seeing what's inside an Archived ROM"
        case .xdvdfs: "making an XISO of an Xbox ROM that's a full Redump image, which xemu can't Play"
        }
    }

    /// The command that installs it.
    public var install: String {
        switch self {
        case .sevenZip: "brew install sevenzip"
        // Not in Homebrew, and its releases have no Mac build.
        case .xdvdfs: "cargo install xdvdfs-cli"
        }
    }

    /// The Emulator it's only needed alongside, if any: without that Emulator installed, it isn't looked for.
    var neededWith: Emulator? {
        switch self {
        case .sevenZip: nil
        case .xdvdfs: .xemu
        }
    }

    public var isInstalled: Bool {
        switch self {
        case .sevenZip: SevenZip.find() != nil
        case .xdvdfs: XDVDFS.find() != nil
        }
    }

    /// The tools that aren't installed, of those needed with the Emulators that are. Only checks files exist, so it's quick.
    public static func missing(
        installed: (SystemTool) -> Bool = \.isInstalled, emulatorInstalled: (Emulator) -> Bool
    ) -> [SystemTool] {
        allCases.filter { tool in (tool.neededWith.map(emulatorInstalled) ?? true) && !installed(tool) }
    }

    /// The launch warning about the `missing` tools, or nil when none are.
    public static func warning(missing: [SystemTool]) -> (title: String, message: String)? {
        guard let first = missing.first else { return nil }
        let title = missing.count == 1 ? "\(first.name) isn't installed" : "Some tools Ludeum uses aren't installed"
        let lines = missing.map { "\($0.name) is needed for \($0.neededFor). Install it with `\($0.install)`." }
        let rest = "Everything else works without \(missing.count == 1 ? "it" : "them")."
        return (title, (lines + [rest]).joined(separator: "\n\n"))
    }
}

/// xdvdfs, which I run myself to make an XISO for xemu.
enum XDVDFS {
    /// Where `cargo install` puts it (Cargo's own folder, or asdf's shims for an asdf Rust), else Homebrew's folders.
    static func find(home: URL = URL.homeDirectory) -> URL? {
        let paths =
            [".cargo/bin/xdvdfs", ".asdf/shims/xdvdfs"].map { home.appending(path: $0).path(percentEncoded: false) }
            + ["/opt/homebrew/bin/xdvdfs", "/usr/local/bin/xdvdfs"]
        return paths.first { FileManager.default.isExecutableFile(atPath: $0) }.map { URL(filePath: $0) }
    }
}
