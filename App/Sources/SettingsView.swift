import SwiftUI

/// The ⌘, Settings window. Credentials, backups and OpenEmu arrive in later slices.
struct SettingsView: View {
    var body: some View {
        Form {
            Text("Settings coming soon.")
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 240)
    }
}
