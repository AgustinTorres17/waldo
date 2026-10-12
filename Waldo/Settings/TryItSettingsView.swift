import SwiftUI

/// Debug field to run the pipeline without hotkeys or the clipboard.
struct TryItSettingsView: View {
    let model: AppModel
    @ObservedObject var settings: SettingsStore

    @State private var input = ""
    @State private var output = ""
    @State private var status = ""
    @State private var isError = false
    @State private var isRunning = false

    var body: some View {
        SettingsPage(title: "Try It",
                     subtitle: "Run Waldo on any text, without hotkeys or the clipboard. Into \(settings.targetLanguage.displayName).") {
            VStack(alignment: .leading, spacing: 14) {
                fieldLabel("Text")
                TextEditor(text: $input)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(height: 110)
                    .fieldBox()

                HStack(spacing: 10) {
                    Button("Process") { run(.automatic) }
                        .buttonStyle(.monoPrimary)
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(isRunning || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Rephrase") { run(.rephrase) }
                        .buttonStyle(.monoSecondary)
                        .keyboardShortcut(.return, modifiers: [.command, .shift])
                        .disabled(isRunning || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    HStack(spacing: 4) {
                        KeyCap("⌘↩")
                        KeyCap("⇧⌘↩")
                    }
                    Spacer()
                    if isRunning { ProgressView().controlSize(.small).scaleEffect(0.8) }
                }

                fieldLabel("Result")
                ScrollView {
                    Text(output)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.text)
                        .lineSpacing(2)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .frame(height: 110)
                .fieldBox()

                if !status.isEmpty {
                    Text(status)
                        .font(.system(size: 12))
                        .foregroundStyle(isError ? Theme.danger : Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.secondaryText)
    }

    private func run(_ mode: ProcessingMode) {
        isRunning = true
        output = ""
        status = ""
        let text = input
        Task {
            let start = ContinuousClock.now
            do {
                let result = try await model.process(text, mode: mode)
                output = result.text
                isError = false
                status = "\(result.summary) \(formatted(ContinuousClock.now - start))"
            } catch {
                isError = true
                status = error.localizedDescription
            }
            isRunning = false
        }
    }

    private func formatted(_ duration: Duration) -> String {
        let ms = duration.components.seconds * 1000 + duration.components.attoseconds / 1_000_000_000_000_000
        return "(\(ms) ms)"
    }
}


