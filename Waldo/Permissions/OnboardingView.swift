import SwiftUI

/// Explains why Waldo needs Accessibility access and sends the user to the right pane.
struct OnboardingView: View {
    @ObservedObject var permission: AccessibilityPermission
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Waldo needs Accessibility access", systemImage: "hand.raised")
                .font(.system(size: 18, weight: .semibold))

            Text("macOS asks you to approve this once. Waldo uses it to:")
            VStack(alignment: .leading, spacing: 6) {
                Text("• Show the Translate/Correct popup when you select text in another app (it reads the selected text and where it is on screen).")
                Text("• Run the hotkeys ⌥⌘T and ⌥⇧⌘T (it presses ⌘A, ⌘C and ⌘V for you).")
            }
            .fixedSize(horizontal: false, vertical: true)
            Text("Your text never leaves this Mac.")
                .foregroundStyle(Theme.secondaryText)

            if permission.isGranted {
                Label("Accessibility access is on. You're all set.", systemImage: "checkmark.circle")
                    .foregroundStyle(Theme.text)
                HStack {
                    Spacer()
                    Button("Done", action: close)
                        .buttonStyle(.monoPrimary)
                        .keyboardShortcut(.defaultAction)
                }
            } else {
                Text("Click the button, then turn on Waldo in Privacy & Security › Accessibility. This window updates by itself.")
                    .font(.callout)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Later", action: close)
                        .buttonStyle(.monoGhost)
                    Spacer()
                    Button("Open System Settings") { permission.request() }
                        .buttonStyle(.monoPrimary)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .foregroundStyle(Theme.text)
        .padding(28)
        .frame(width: 440)
        .background(Theme.background)
    }
}
