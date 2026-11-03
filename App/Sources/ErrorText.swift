import AppKit
import SwiftUI

/// An error, refusal or problem shown in place, in red. Every one the app shows as text goes through here, so what can be
/// done with one is in one place: its text is selectable, and Copy in its context menu copies the whole message. An
/// error shown as an alert goes through `errorAlert` for the same reason.
struct ErrorText: View {
    let message: String
    /// The view's own body size unless given.
    var font: Font?
    /// An SF Symbol before the message, for a status in a table.
    var systemImage: String?

    init(_ message: String, font: Font? = nil, systemImage: String? = nil) {
        self.message = message
        self.font = font
        self.systemImage = systemImage
    }

    var body: some View {
        Group {
            if let systemImage {
                Label(message, systemImage: systemImage)
            } else {
                Text(message)
            }
        }
        .font(font)
        .foregroundStyle(.red)
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
        .contextMenu {
            Button("Copy") { ErrorText.copy(message) }
        }
    }

    /// Puts the message on the pasteboard as plain text.
    static func copy(_ message: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message, forType: .string)
    }
}

extension View {
    /// An alert showing `problem` while there is one, cleared when it's dismissed, with a Copy button that puts its
    /// title and message on the pasteboard: an alert's text can't be selected.
    func errorAlert(_ problem: Binding<(title: String, message: String)?>) -> some View {
        alert(
            problem.wrappedValue?.title ?? "",
            isPresented: Binding(get: { problem.wrappedValue != nil }, set: { if !$0 { problem.wrappedValue = nil } })
        ) {
            Button("OK", role: .cancel) {}
            Button("Copy") {
                if let problem = problem.wrappedValue { ErrorText.copy("\(problem.title)\n\(problem.message)") }
            }
        } message: {
            Text(problem.wrappedValue?.message ?? "")
        }
    }

    /// As `errorAlert(_:)`, for a message under a fixed title.
    func errorAlert(_ title: String, message: Binding<String?>) -> some View {
        errorAlert(
            Binding(
                get: { message.wrappedValue.map { (title: title, message: $0) } },
                set: { if $0 == nil { message.wrappedValue = nil } }))
    }
}
