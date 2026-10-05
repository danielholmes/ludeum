import SwiftUI

/// A borderless button that shows it's clickable: a soft background on hover, darker while pressed.
struct HoverButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverBody(configuration: configuration)
    }

    private struct HoverBody: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .foregroundStyle(isEnabled ? .primary : .secondary)
                .padding(.horizontal, 4).padding(.vertical, 2)
                .background(
                    Color.primary.opacity(!isEnabled ? 0 : configuration.isPressed ? 0.16 : hovering ? 0.08 : 0),
                    in: .rect(cornerRadius: 4)
                )
                .contentShape(.rect)
                .onHover { hovering = $0 }
        }
    }
}

/// A link button: underlined on hover, dimmed while pressed.
struct HoverLinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        LinkBody(configuration: configuration)
    }

    private struct LinkBody: View {
        let configuration: Configuration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .foregroundStyle(Color.accentColor)
                .underline(hovering)
                .opacity(configuration.isPressed ? 0.6 : 1)
                .contentShape(.rect)
                .onHover { hovering = $0 }
                .pointerStyle(.link)
        }
    }
}

extension ButtonStyle where Self == HoverButtonStyle {
    static var hover: HoverButtonStyle { HoverButtonStyle() }
}

extension ButtonStyle where Self == HoverLinkButtonStyle {
    static var hoverLink: HoverLinkButtonStyle { HoverLinkButtonStyle() }
}
