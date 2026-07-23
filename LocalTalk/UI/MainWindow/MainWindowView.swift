import SwiftUI
@preconcurrency import AVFoundation

enum MainSection: String, CaseIterable, Identifiable {
    case history = "History"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .history:
            return "clock.arrow.circlepath"
        case .settings:
            return "slider.horizontal.3"
        }
    }
}

struct MainWindowView: View {
    var model: AppModel
    var modelManager: ModelManager
    var license: LicenseService
    @Bindable private var uiState = AppComposition.uiState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    @State private var axTrusted = PasteService.isAccessibilityTrusted

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(MainSection.allCases) { item in
                    let selected = uiState.mainSection == item
                    Button {
                        uiState.mainSection = item
                    } label: {
                        HStack(spacing: 8) {
                            Capsule()
                                .fill(selected ? Theme.accent : .clear)
                                .frame(width: 2, height: 16)
                            Image(systemName: item.icon)
                            Text(item.rawValue)
                            Spacer()
                        }
                        .font(Theme.Fonts.body)
                        .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: Theme.radiusControl)
                            .fill(selected ? Theme.ink2 : .clear))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? [.isSelected] : [])
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .navigationSplitViewColumnWidth(min: 168, ideal: 188)
            .safeAreaInset(edge: .top) {
                brandHeader
            }
            .safeAreaInset(edge: .bottom) {
                sidebarStatus
            }
            .background(Theme.ink0)
            .task {
                // Live health readout: cheap synchronous checks, only while
                // the window is open (the task cancels on disappear).
                while !Task.isCancelled {
                    micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
                    axTrusted = PasteService.isAccessibilityTrusted
                    modelManager.refresh()
                    try? await Task.sleep(for: .seconds(2))
                }
            }
        } detail: {
            ZStack {
                Theme.ink0.ignoresSafeArea()
                switch uiState.mainSection {
                case .history:
                    HistoryView(model: model)
                        .transition(.opacity)
                case .settings:
                    SettingsView(model: model, modelManager: modelManager, license: license)
                        .transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : Theme.easeFast, value: uiState.mainSection)
            .navigationTitle(uiState.mainSection.rawValue)
        }
        .frame(minWidth: 680, minHeight: 460)
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
        .background(Theme.ink0)
    }

    /// At-a-glance health: the armed trigger key plus the three things that
    /// must be true for dictation to work. Anything red deep-links to Settings.
    private var sidebarStatus: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text("Trigger")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textTertiary)
                HotkeyChip(text: triggerLabel)
            }
            statusRow("Microphone", ok: micGranted)
            statusRow("Accessibility", ok: axTrusted)
            statusRow("Speech model", ok: modelReady)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .overlay(Rectangle().fill(Theme.hairline).frame(height: 1), alignment: .top)
        .background(Theme.ink0)
    }

    private func statusRow(_ label: String, ok: Bool) -> some View {
        Button {
            if !ok { uiState.mainSection = .settings }
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(ok ? Theme.accent : Theme.failure)
                    .frame(width: 5, height: 5)
                Text(label)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(ok ? Theme.textSecondary : Theme.textPrimary)
                if !ok {
                    Text("Fix")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.accentText)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label): \(ok ? "ready" : "needs attention")")
    }

    private var triggerLabel: String {
        model.settings.activeTriggerLabel
    }

    private var modelReady: Bool {
        let route = EngineSelector.route(
            language: model.settings.language,
            task: model.settings.task,
            override: model.settings.engineOverride
        )
        switch route.engine {
        case .whisperKit:
            return modelManager.whisperLargeTurbo == .ready
        case .parakeet:
            return (route.parakeetVersion == .v3 ? modelManager.parakeetV3 : modelManager.parakeetV2) == .ready
        }
    }

    private var brandHeader: some View {
        HStack(spacing: 10) {
            Image("MenuIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 30, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Theme.hairlineStrong, lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 1) {
                // Rebrand: rounded capitalized wordmark, matching the logo lockup.
                Text("Bulong")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text("Private, on-device dictation")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        .background(Theme.ink0)
    }
}
