import SwiftUI

/// Terms Waldo keeps exactly as written, in every app and mode.
struct GlossarySettingsView: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        SettingsPage(title: "Glossary", subtitle: "Words Waldo always leaves exactly as you write them.") {
            let count = settings.glossary.count
            SettingsSection(title: count == 1 ? "1 term" : "\(count) terms",
                            footer: "Product names, team jargon, people's names: Waldo never translates or corrects these, and always writes them as you do here. One per line. Matches whole words, ignoring case.") {
                TextEditor(text: $settings.glossaryText)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Theme.text)
                    .lineSpacing(3)
                    .scrollContentBackground(.hidden)
                    .padding(.vertical, 10)
                    .frame(height: 280)
            }
        }
    }
}
