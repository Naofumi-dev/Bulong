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
    @Bindable private var uiState = AppComposition.uiState

    var body: some View {
        NavigationSplitView {
            List(MainSection.allCases, selection: $uiState.mainSection) { item in
                Label(item.rawValue, systemImage: item.icon)
                    .tag(item)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 168, ideal: 188)
            .safeAreaInset(edge: .top) {
                brandHeader
            }
            .scrollContentBackground(.hidden)
            .background(Theme.ink0)
        } detail: {
            ZStack {
                Theme.ink0.ignoresSafeArea()
                switch uiState.mainSection {
                case .history:
                    HistoryView(history: model.history)
                case .settings:
                    SettingsView(model: model, modelManager: modelManager)
                }
            }
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
                Text("Bulong")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Private input")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        .background(Theme.ink0)
    }
}
