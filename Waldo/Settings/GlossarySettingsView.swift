import SwiftUI

/// Terms Waldo keeps exactly as written, in every app and mode.
struct GlossarySettingsView: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        SettingsPage(title: "Glossary") {
            SettingsCaption("Product names, team jargon, people's names: Waldo never translates or corrects these, and always writes them as you do here. One per line. Matches whole words, ignoring case.")

            VStack(alignment: .leading, spacing: 6) {
                TextEditor(text: $settings.glossaryText)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(height: 260)
                    .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.radius))
                    .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.border))
                let count = settings.glossary.count
                Text(count == 1 ? "1 term" : "\(count) terms")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.tertiaryText)
            }
        }
    }
}
