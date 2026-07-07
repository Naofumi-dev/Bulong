import AVFoundation
import FluidAudio
import SwiftUI

struct OnboardingView: View {
    var model: AppModel
    var modelManager: ModelManager
    @State private var step = 0
    @State private var micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    @State private var axTrusted = PasteService.isAccessibilityTrusted
    @State private var testText = ""
    @State private var payoff = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                switch step {
                case 0: promiseStep.transition(stepTransition)
                case 1: permissionsStep.transition(stepTransition)
                default: dictateStep.transition(stepTransition)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(reduceMotion ? nil : Theme.spring, value: step)

            HStack {
                if step > 0 {
                    Button("Back") { step -= 1 }.buttonStyle(HoverButtonStyle())
                }
                Spacer()
                StepDots(count: 3, index: step)
                Spacer()
                Button(step == 2 ? "Finish" : "Continue") {
                    if step == 2 { model.settings.hasCompletedOnboarding = true } else { step += 1 }
                }
                .buttonStyle(.plain)
                .font(Theme.Fonts.action)
                .foregroundStyle(continueEnabled ? Theme.ink0 : Theme.textTertiary)
                .padding(.horizontal, 16).padding(.vertical, 7)
                .background(Capsule().fill(continueEnabled ? Theme.accent : Theme.ink2))
                .disabled(!continueEnabled)
            }
            .padding(20)
        }
        .frame(width: 560, height: 420)
        .background(Theme.ink0)
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
        .onAppear { modelManager.refresh() }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.5))
                micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
                axTrusted = PasteService.isAccessibilityTrusted
            }
        }
        .onChange(of: model.lastTranscript) { _, new in
            if step == 2, !new.isEmpty { payoff = true }
        }
    }

    private var stepTransition: AnyTransition {
        .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity))
    }

    private var continueEnabled: Bool {
        switch step {
        case 1: micGranted            // accessibility stays optional
        case 2: modelManager.parakeetV2 == .ready
        default: true
        }
    }

    // Step 0 — the promise
    private var promiseStep: some View {
        VStack(spacing: 16) {
            HStack(spacing: 3) {
                ForEach(0..<7, id: \.self) { i in
                    Capsule().fill(Theme.accent)
                        .frame(width: 4, height: [12, 22, 34, 26, 36, 18, 10][i])
                }
            }
            .accessibilityHidden(true)
            Text("bulong").font(Theme.Fonts.mono(30, weight: .semibold)).foregroundStyle(Theme.textPrimary)
            Text("Tagalog for “whisper”")
                .font(Theme.Fonts.caption).foregroundStyle(Theme.textTertiary)
            Text("Press a hotkey. Speak. The words appear —\nand your voice never leaves this Mac.")
                .font(Theme.Fonts.body).foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center).lineSpacing(3)
        }
        .padding(32)
    }

    // Step 1 — permissions with live status
    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Two permissions").font(Theme.Fonts.display).foregroundStyle(Theme.textPrimary)
            permissionCard(icon: "mic.fill", title: "Microphone", granted: micGranted, required: true,
                           reason: "So Bulong can hear you. Audio is processed on this Mac and never uploaded.") {
                Task { micGranted = await AudioService.requestMicPermission() }
            }
            permissionCard(icon: "keyboard.fill", title: "Accessibility", granted: axTrusted, required: false,
                           reason: "Lets Bulong type the result into whatever app you're using. Optional — without it, transcripts go to your clipboard.") {
                PasteService.requestAccessibility()
            }
        }
        .padding(28)
    }

    private func permissionCard(icon: String, title: String, granted: Bool, required: Bool,
                                reason: String, request: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(Theme.Fonts.title)
                .foregroundStyle(granted ? Theme.accent : Theme.textSecondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title).font(Theme.Fonts.title).foregroundStyle(Theme.textPrimary)
                    if !required {
                        Text("optional").font(Theme.Fonts.mono(9)).foregroundStyle(Theme.textTertiary)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().stroke(Theme.hairlineStrong, lineWidth: 1))
                    }
                }
                Text(granted ? "Granted ✓" : reason)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(granted ? Theme.accent : Theme.textSecondary)
                    .lineSpacing(2)
            }
            Spacer()
            if !granted {
                Button("Grant", action: request).buttonStyle(HoverButtonStyle())
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Theme.radiusCard).fill(Theme.ink1))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusCard)
            .stroke(granted ? Theme.accentDim : Theme.hairline, lineWidth: 1))
        .animation(Theme.easeFast, value: granted)
    }

    // Step 2 — model + first dictation payoff
    private var dictateStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Say something").font(Theme.Fonts.display).foregroundStyle(Theme.textPrimary)
            switch modelManager.parakeetV2 {
            case .ready:
                HStack(spacing: 6) {
                    Text("Click the field, press").font(Theme.Fonts.body).foregroundStyle(Theme.textSecondary)
                    HotkeyChip(text: model.settings.hotkey.displayString)
                    Text("and speak.").font(Theme.Fonts.body).foregroundStyle(Theme.textSecondary)
                }
                TextField("", text: $testText, prompt: Text("Your words land here…")
                    .foregroundStyle(Theme.textTertiary))
                    .textFieldStyle(.plain)
                    .font(Theme.Fonts.mono(13))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: Theme.radiusCard).fill(Theme.ink1))
                    .overlay(RoundedRectangle(cornerRadius: Theme.radiusCard)
                        .stroke(payoff ? Theme.accent : Theme.hairlineStrong, lineWidth: 1))
                if payoff {
                    Label("It worked — that's Bulong. Same hotkey, any app.", systemImage: "checkmark.circle.fill")
                        .font(Theme.Fonts.body).foregroundStyle(Theme.accent)
                        .transition(.opacity)
                }
            case .downloading(let p):
                VStack(alignment: .leading, spacing: 6) {
                    Text("Downloading the English model — one time, ~600 MB.")
                        .font(Theme.Fonts.body).foregroundStyle(Theme.textSecondary)
                    HStack(spacing: 8) {
                        ProgressView(value: p).frame(width: 260)
                        Text("\(Int(p * 100))%").font(Theme.Fonts.mono(11)).foregroundStyle(Theme.textSecondary)
                    }
                }
            case .notDownloaded:
                Button("Download the speech model") { Task { await modelManager.downloadParakeet(.v2) } }
                    .buttonStyle(HoverButtonStyle())
            case .failed(let msg):
                VStack(alignment: .leading, spacing: 6) {
                    Text(msg).font(Theme.Fonts.caption).foregroundStyle(Theme.failure)
                    Button("Retry") { Task { await modelManager.downloadParakeet(.v2) } }
                        .buttonStyle(HoverButtonStyle())
                }
            }
            Spacer()
        }
        .padding(28)
        .animation(Theme.easeFast, value: payoff)
    }
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
