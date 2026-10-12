import SwiftUI

struct EngineSettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var models: ModelDownloader

    private static let idleChoices = [30, 60, 120, 300, 600, 1_800]

    var body: some View {
        SettingsPage(title: "Engine") {
            SettingsSection(title: "Inference") {
                SettingsRow(title: "Engine", detail: settings.engineMode.detail) {
                    MonoMenuPicker(selection: $settings.engineMode, options: EngineMode.allCases) { $0.title }
                }
            }

            SettingsSection(title: "llama.cpp models") {
                ForEach(Array(ModelCatalog.all.enumerated()), id: \.element.id) { index, model in
                    if index > 0 {
                        Rectangle().fill(Theme.divider).frame(height: 1)
                    }
                    ModelRow(model: model, state: models.state(of: model),
                             isChosen: settings.llamaModelID == model.id,
                             isRecommended: model == ModelCatalog.recommended,
                             downloadDisabled: models.isBusy,
                             choose: { settings.llamaModelID = model.id },
                             download: { models.download(model) },
                             cancel: models.cancel,
                             delete: { models.delete(model) })
                }
            }

            SettingsSection(title: "Memory") {
                SettingsRow(title: "Unload after",
                            detail: "The model stays in memory for this long after its last use, so the next request starts fast.") {
                    MonoMenuPicker(selection: $settings.llamaIdleUnloadSeconds, options: Self.idleChoices, title: Self.idleTitle)
                }
            }
        }
        .onAppear(perform: models.refresh)
    }

    private static func idleTitle(_ seconds: Int) -> String {
        seconds < 60 ? "\(seconds) seconds" : seconds == 60 ? "1 minute" : "\(seconds / 60) minutes"
    }
}

private struct ModelRow: View {
    let model: ModelInfo
    let state: ModelDownloader.State
    let isChosen: Bool
    let isRecommended: Bool
    let downloadDisabled: Bool
    let choose: () -> Void
    let download: () -> Void
    let cancel: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: choose) {
                ZStack {
                    Circle().strokeBorder(isChosen ? Theme.solid : Theme.border, lineWidth: isChosen ? 5 : 1.5)
                }
                .frame(width: 15, height: 15)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(.top, 1)
            .accessibilityLabel(isChosen ? "Chosen" : "Choose \(model.name)")
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(model.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.text)
                    if isRecommended {
                        Text("Recommended")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.secondaryText)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Theme.hover, in: RoundedRectangle(cornerRadius: 4))
                    }
                }
                SettingsCaption("\(model.summary) \(model.formattedSize).")
                status
            }
            Spacer(minLength: 12)
            actions
        }
        .padding(.vertical, 12)
    }

    @ViewBuilder private var status: some View {
        switch state {
        case .downloading(let fraction):
            VStack(alignment: .leading, spacing: 4) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.divider)
                        Capsule().fill(Theme.solid).frame(width: proxy.size.width * fraction)
                    }
                }
                .frame(height: 3)
                Text("Downloading… \(Int(fraction * 100))%")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.secondaryText)
            }
            .padding(.top, 4)
        case .verifying:
            Text("Verifying download…")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.secondaryText)
        case .failed(let message):
            Text(message)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.danger)
        case .installed, .notInstalled:
            EmptyView()
        }
    }

    @ViewBuilder private var actions: some View {
        switch state {
        case .downloading:
            Button("Cancel", action: cancel).buttonStyle(.monoSecondary)
        case .verifying:
            ProgressView().controlSize(.small).scaleEffect(0.8)
        case .installed:
            Button("Delete", role: .destructive, action: delete).buttonStyle(.monoDestructive)
        case .notInstalled, .failed:
            Button("Download", action: download)
                .buttonStyle(.monoPrimary)
                .disabled(downloadDisabled)
        }
    }
}
