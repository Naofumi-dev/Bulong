import SwiftUI

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
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .navigationSplitViewColumnWidth(min: 168, ideal: 188)
            .safeAreaInset(edge: .top) {
                brandHeader
            }
            .background(Theme.ink0)
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
                // The wordmark is always lowercase mono; capitalized "Bulong"
                // lives only in prose.
                Text("bulong")
                    .font(Theme.Fonts.mono(15, weight: .semibold))
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
