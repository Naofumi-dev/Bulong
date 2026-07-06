import AVFoundation
import FluidAudio
import SwiftUI

struct OnboardingView: View {
    var model: AppModel
    var modelManager: ModelManager
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0
    @State private var micGranted = AVCaptureAuthHelper.isGranted
    @State private var testText = ""

    var body: some View {
        VStack(spacing: 20) {
            Image("MenuIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(spacing: 7) {
                Text(titles[step])
                    .font(.system(size: 22, weight: .bold))
                Text(subtitles[step])
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 390)
            }

            stepContent
                .frame(minHeight: 74)

            HStack {
                if step > 0 {
                    Button("Back") {
                        step -= 1
                    }
                }

                Spacer()

                Button(step == titles.count - 1 ? "Finish" : "Continue") {
                    if step == titles.count - 1 {
                        model.settings.hasCompletedOnboarding = true
                        dismiss()
                    } else {
                        step += 1
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(step == 3 && modelManager.parakeetV2 != .ready)
            }
            .padding(.top, 8)
        }
        .padding(32)
        .frame(width: 520, height: 380)
        .background(Theme.ink0)
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
        .onAppear {
            modelManager.refresh()
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case 1:
            Button(micGranted ? "Microphone granted" : "Allow microphone") {
                Task { micGranted = await AudioService.requestMicPermission() }
            }
            .disabled(micGranted)
        case 2:
            VStack(spacing: 8) {
                Button(PasteService.isAccessibilityTrusted ? "Accessibility granted" : "Open Accessibility settings") {
                    PasteService.requestAccessibility()
                }
                .disabled(PasteService.isAccessibilityTrusted)

                Text("Optional: without it, transcripts go to your clipboard instead of pasting.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        case 3:
            modelDownloadControl
        case 4:
            TextField("Click here, press \(model.settings.hotkey.displayString), and speak", text: $testText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 380)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var modelDownloadControl: some View {
        switch modelManager.parakeetV2 {
        case .ready:
            Label("English model ready", systemImage: "checkmark.circle.fill")
                .foregroundStyle(Theme.accent)
        case .downloading(let progress):
            ProgressView(value: progress) {
                Text("Downloading the English model, about 600 MB")
            }
            .frame(width: 320)
        case .notDownloaded:
            Button("Download English model") {
                Task { await modelManager.downloadParakeet(.v2) }
            }
        case .failed(let message):
            VStack(spacing: 8) {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(Theme.failure)
                    .lineLimit(2)
                Button("Retry") {
                    Task { await modelManager.downloadParakeet(.v2) }
                }
            }
        }
    }

    private let titles = [
        "Welcome to Bulong",
        "Microphone",
        "Auto-paste",
        "Speech model",
        "Try it",
    ]

    private let subtitles = [
        "Dictation that never leaves your Mac. Four quick steps and you are talking.",
        "Bulong needs your microphone to hear you. Audio is processed on this Mac and never uploaded.",
        "Accessibility permission lets Bulong type the result straight into whatever app you are using.",
        "The on-device English model is a one-time download. Other languages can be added later in Settings.",
        "Focus the field below, press your hotkey, say something, and press it again.",
    ]
}

struct OnboardingWindowView: View {
    var model: AppModel
    var modelManager: ModelManager

    var body: some View {
        OnboardingView(model: model, modelManager: modelManager)
            .onChange(of: model.settings.hasCompletedOnboarding) { _, done in
                if done {
                    AppComposition.onboardingWindow?.close()
                    AppComposition.onboardingWindow = nil
                }
            }
    }
}

enum AVCaptureAuthHelper {
    static var isGranted: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }
}
