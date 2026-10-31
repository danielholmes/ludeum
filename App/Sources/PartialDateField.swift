import LudeumCore
import SwiftUI

/// A Partial date typed as text, with a button that fills in today.
struct PartialDateField: View {
    let label: String
    @Binding var text: String

    init(_ label: String, text: Binding<String>) {
        self.label = label
        self._text = text
    }

    var body: some View {
        LabeledContent(label) {
            HStack {
                TextField(label, text: $text, prompt: Text("YYYY, YYYY-MM or YYYY-MM-DD")).labelsHidden()
                Button("Today") { text = PartialDate(day: .now).text }
            }
        }
    }
}
