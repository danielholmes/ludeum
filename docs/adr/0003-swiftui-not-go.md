# Build the app in SwiftUI + SQLite, not Go

I'd rather write Go, but no Go option in 2026 gives a native macOS app without hacks. Wails is a web UI inside a native window, Fyne draws its own non-native widgets, and darwinkit (the AppKit bindings) has been dormant since 2024. The app is SwiftUI with GRDB/SQLite, all in one language. We also rejected a Go CLI core with a SwiftUI shell: a one-person app doesn't justify two toolchains and the plumbing to connect them.
