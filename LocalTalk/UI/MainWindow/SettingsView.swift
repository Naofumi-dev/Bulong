import AppKit
import AVFoundation
import ServiceManagement
import SwiftUI
import FluidAudio

struct SettingsView: View {
    var model: AppModel
    var modelManager: ModelManager
    var license: LicenseService
    @State private var recordingHotkey = false
    @State private var licenseKeyField = ""
    @State private var licenseMessage: String?
    @State private var micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    @State private var axTrusted = PasteService.isAccessibilityTrusted
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @FocusState private var keyFieldFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum SettingsTab: Hashable { case setup, advanced }
    @State private var tab: SettingsTab = .setup

    private let languages: [(code: String, name: String)] = [
        ("en", "English"), ("tl", "Filipino (Tagalog)"), ("es", "Spanish"), ("fr", "French"),
        ("de", "German"), ("it", "Italian"), ("pt", "Portuguese"), ("ja", "Japanese"),
        ("ko", "Korean"), ("zh", "Chinese"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SegmentedChoice(options: [(label: "Set up", value: SettingsTab.setup),
                                          (label: "Advanced", value: .advanced)],
                                selection: $tab)
                    .frame(maxWidth: .infinity, alignment: .center)
                if tab == .setup {
                    setupHero
                    permissionsCard
                    hotkeyCard
                    modelsCard
                } else {
                    dictationCard
                    recordingPillCard
                    generalCard
                    licenseCard
                }
                footerNote
            }
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(20)
        }
        .background(Theme.ink0)
        .onAppear { modelManager.refresh() }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.5))
                micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
                axTrusted = PasteService.isAccessibilityTrusted
                launchAtLogin = SMAppService.mainApp.status == .enabled
                // Self-arm the single-key monitor once Accessibility is granted
                // while it's the active trigger (no need to re-toggle the picker).
                if axTrusted,
                   model.settings.triggerKind == .singleKey,
                   AppComposition.hotkey.singleKeyError != nil {
                    AppComposition.applyTrigger(for: model)
                }
            }
        }
    }

    // MARK: - Set up hero

    private var recommendedModel: RecommendedModel {
        ModelRecommendation.model(forLanguage: model.settings.language)
    }

    private var currentLanguageName: String {
        languages.first(where: { $0.code == model.settings.language })?.name ?? "your language"
    }

    private var recommendedReady: Bool {
        switch recommendedModel {
        case .parakeetV2: return modelManager.parakeetV2 == .ready
        case .parakeetV3: return modelManager.parakeetV3 == .ready
        case .whisper:    return modelManager.whisperLargeTurbo == .ready
        }
    }

    private var setupComplete: Bool { micGranted && axTrusted && recommendedReady }

    /// Prerequisites still missing before dictation can work — mic, Accessibility,
    /// and the model for the chosen language (dictation hard-fails without it).
    private var remainingSteps: Int {
        [micGranted, axTrusted, recommendedReady].filter { !$0 }.count
    }

    private var setupHero: some View {
        VStack(alignment: .leading, spacing: 10) {
            if setupComplete {
                Label("You're ready", systemImage: "checkmark.circle.fill")
                    .font(Theme.Fonts.title)
                    .foregroundStyle(Theme.accent)
                HStack(spacing: 6) {
                    Text("Press")
                        .font(Theme.Fonts.body)
                        .foregroundStyle(Theme.textSecondary)
                    if model.settings.triggerKind == .combo {
                        HotkeyChip(text: model.settings.hotkey.displayString)
                    } else {
                        Text("tap \(model.settings.singleKeyChoice.displayName)")
                            .font(Theme.Fonts.mono(11))
                            .foregroundStyle(Theme.accentText)
                    }
                    Text("anywhere to dictate")
                        .font(Theme.Fonts.body)
                        .foregroundStyle(Theme.textSecondary)
                }
            } else {
                Text(remainingSteps == 1 ? "One step left to start dictating:"
                                         : "\(remainingSteps) steps to start dictating:")
                    .font(Theme.Fonts.bodyStrong)
                    .foregroundStyle(Theme.textPrimary)
                heroStep(done: micGranted, label: "Microphone", hint: "grant it below")
                heroStep(done: axTrusted, label: "Accessibility", hint: "grant it below")
                heroStep(done: recommendedReady,
                         label: "Speech model for \(currentLanguageName)",
                         hint: "download it in Speech models below")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.radiusCard).fill(Theme.ink1))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusCard).stroke(Theme.hairline, lineWidth: 1))
    }

    /// One prerequisite line in the setup hero. Status only — the actual Grant /
    /// Download control lives in the card directly below, so each action has a
    /// single home (no duplicate buttons on the same tab).
    private func heroStep(done: Bool, label: String, hint: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(Theme.Fonts.body)
                .foregroundStyle(done ? Theme.accent : Theme.textTertiary)
            Text(label)
                .font(Theme.Fonts.body)
                .foregroundStyle(done ? Theme.textSecondary : Theme.textPrimary)
            if !done {
                Text("— \(hint)")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer()
        }
    }

    // MARK: - Section cards

    private var generalCard: some View {
        SectionCard(title: "General") {
            Toggle("Launch at login", isOn: launchAtLoginBinding)
                .toggleStyle(MintToggleStyle())
            divider
            row("Version") {
                Text(appVersion)
                    .font(Theme.Fonts.mono(11))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private var dictationCard: some View {
        SectionCard(title: "Dictation") {
            row("Language") {
                MenuPicker(options: languages.map { (label: $0.name, value: $0.code) },
                           selection: bind(\.language))
                    .frame(width: 190)
            }
            divider
            row("Mode") {
                MenuPicker(options: [(label: "Transcribe", value: DictationTask.transcribe),
                                     (label: "Translate to English", value: .translate)],
                           selection: bind(\.task))
                    .frame(width: 190)
            }
            divider
            Toggle("Paste into the focused app", isOn: bind(\.pasteAfterTranscription))
                .toggleStyle(MintToggleStyle())
            if !axTrusted && model.settings.pasteAfterTranscription {
                Text("Needs Accessibility — grant it in Set up")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }
            divider
            Toggle("Play sounds", isOn: bind(\.playSounds))
                .toggleStyle(MintToggleStyle())
        }
    }

    private var hotkeyCard: some View {
        SectionCard(title: "Hotkey",
                    footer: AppComposition.hotkey.registrationError,
                    footerIsError: AppComposition.hotkey.registrationError != nil) {
            row("Trigger") {
                SegmentedChoice(options: [(label: "Key combo", value: TriggerKind.combo),
                                          (label: "Single key", value: .singleKey)],
                                selection: triggerKindBinding)
            }
            divider
            if model.settings.triggerKind == .combo {
                row("Shortcut") {
                    Button { recordingHotkey = true } label: {
                        HotkeyChip(text: recordingHotkey ? "Press keys…" : model.settings.hotkey.displayString,
                                   pulsing: recordingHotkey)
                    }
                    .buttonStyle(.plain)
                    .background(HotkeyRecorder(isRecording: $recordingHotkey) { spec in
                        model.settings.hotkey = spec
                        AppComposition.hotkey.register(spec)
                    })
                }
                if recordingHotkey {
                    Text("Use ⌘ ⌥ ⌃ ⇧ + a key · Esc cancels")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.top, 4)
                }
                divider
                row("Behavior") {
                    SegmentedChoice(options: [(label: "Toggle", value: HotkeyMode.toggle),
                                              (label: "Push to talk", value: .pushToTalk)],
                                    selection: bind(\.hotkeyMode))
                }
            } else {
                row("Key") {
                    MenuPicker(options: SingleKeyChoice.allCases.map { (label: $0.displayName, value: $0) },
                               selection: singleKeyChoiceBinding)
                        .frame(width: 190)
                }
                divider
                Text("Tap \(model.settings.singleKeyChoice.displayName) to toggle · hold to talk")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if model.settings.singleKeyChoice == .fn {
                    Text("macOS may also act on the Fn key — check System Settings → Keyboard if it double-triggers.")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }
                if let singleKeyError = AppComposition.hotkey.singleKeyError {
                    Text(singleKeyError)
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.failure)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }
            }
        }
    }

    private var recordingPillCard: some View {
        SectionCard(title: "Recording pill",
                    footer: "The small pill shown while you talk — choose where it sits.") {
            HStack(spacing: 10) {
                ForEach(HUDPosition.allCases, id: \.self) { pos in
                    Button {
                        model.settings.hudPosition = pos
                        AppComposition.hud.clearSavedPositions()
                    } label: {
                        HUDPositionPreview(position: pos, selected: model.settings.hudPosition == pos)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var modelsCard: some View {
        SectionCard(title: "Speech models",
                    footer: "English is ready — download another only if you dictate in other languages.") {
            modelRow("English — fast", descriptor: "Parakeet", size: "~600 MB",
                     state: modelManager.parakeetV2,
                     recommended: recommendedModel == .parakeetV2) {
                Task { await modelManager.downloadParakeet(.v2) }
            }
            divider
            modelRow("European languages", descriptor: "Parakeet", size: "~1 GB",
                     state: modelManager.parakeetV3,
                     recommended: recommendedModel == .parakeetV3) {
                Task { await modelManager.downloadParakeet(.v3) }
            }
            divider
            modelRow("All languages + translate", descriptor: "Whisper", size: "~600 MB",
                     state: modelManager.whisperLargeTurbo,
                     recommended: recommendedModel == .whisper) {
                Task { await modelManager.downloadWhisper() }
            }
        }
    }

    private var permissionsCard: some View {
        SectionCard(title: "Permissions", accentStroke: !(micGranted && axTrusted)) {
            permissionRow("Microphone",
                          granted: micGranted,
                          grantedHint: "Granted ✓ — Bulong can hear you",
                          pendingHint: "Bulong needs your mic to hear you") {
                Task { micGranted = await AudioService.requestMicPermission() }
            }
            divider
            permissionRow("Accessibility",
                          granted: axTrusted,
                          grantedHint: "Granted ✓ — pastes into any app",
                          pendingHint: "Lets Bulong type the result where you're working") {
                PasteService.requestAccessibility()
            }
        }
    }

    private var licenseCard: some View {
        SectionCard(title: "License") {
            switch license.state {
            case .licensed(let l):
                row("Licensed to") {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(l.name)
                            .font(Theme.Fonts.mono(12))
                            .foregroundStyle(Theme.textSecondary)
                        Text(l.order)
                            .font(Theme.Fonts.mono(10.5))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                divider
                row("") {
                    Button("Remove license") {
                        license.removeLicense()
                        licenseMessage = nil
                    }
                    .buttonStyle(HoverButtonStyle())
                }
            case .trial(let d):
                row("Trial") {
                    Text(d == 1 ? "1 day left" : "\(d) days left")
                        .font(Theme.Fonts.mono(12))
                        .foregroundStyle(Theme.textSecondary)
                }
                divider
                buyRow
                divider
                activateRow
            case .trialExpired:
                HStack {
                    Text("Your 14-day trial has ended")
                        .font(Theme.Fonts.body)
                        .foregroundStyle(Theme.failure)
                    Spacer()
                }
                divider
                buyRow
                divider
                activateRow
            }
        }
    }

    private var footerNote: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Everything runs on this Mac. The only network use is downloading models above.")
                .font(Theme.Fonts.caption).foregroundStyle(Theme.textSecondary)
            Text("Bulong is Tagalog for a soft whisper. Includes NVIDIA Parakeet — © NVIDIA, CC-BY-4.0.")
                .font(Theme.Fonts.caption).foregroundStyle(Theme.textTertiary)
        }
        .padding(.horizontal, 4)
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return "Version \(version ?? "—")"
    }

    /// Registers/unregisters with SMAppService and reflects the real status
    /// (System Settings can flip it behind our back; the 1.5 s poll re-syncs).
    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { enable in
                do {
                    if enable {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    // Fall through to reading the real status below.
                }
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        )
    }

    private var divider: some View {
        Rectangle().fill(Theme.hairline).frame(height: 1).padding(.vertical, 8)
    }

    private var buyRow: some View {
        row("Full version") {
            Button("Buy — $29") {
                if let url = URL(string: "https://bulong.app/#pricing") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(BorderedActionButtonStyle(emphasized: true))
        }
    }

    private var activateRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Paste your license key", text: $licenseKeyField)
                    .textFieldStyle(.plain)
                    .font(Theme.Fonts.mono(11))
                    .foregroundStyle(Theme.textPrimary)
                    .focused($keyFieldFocused)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: Theme.radiusControl).fill(Theme.ink1))
                    .overlay(RoundedRectangle(cornerRadius: Theme.radiusControl)
                        .stroke(keyFieldFocused ? Theme.accent : Theme.hairline, lineWidth: 1))
                    .animation(reduceMotion ? nil : Theme.easeFast, value: keyFieldFocused)
                Button("Activate") {
                    switch license.activate(licenseKeyField.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    case .success:
                        // The card flips to "Licensed to {name}" — that IS the
                        // confirmation; no success line to leave behind.
                        licenseMessage = nil
                        licenseKeyField = ""
                    case .failure(let e):
                        licenseMessage = Self.message(for: e)
                    }
                }
                .buttonStyle(BorderedActionButtonStyle())
                .disabled(licenseKeyField.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            // Only ever an error now (success flips the card), so always failure red.
            if let m = licenseMessage {
                Text(m)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.failure)
            }
        }
    }

    private static func message(for e: LicenseError) -> String {
        switch e {
        case .malformed: return "That key looks malformed. Copy the whole key from your email."
        case .badSignature: return "That key didn't verify — check for a copy/paste slip."
        case .unreadablePayload: return "That key isn't for Bulong."
        }
    }

    private func row(_ title: String, @ViewBuilder control: () -> some View) -> some View {
        HStack {
            Text(title).font(Theme.Fonts.body).foregroundStyle(Theme.textPrimary)
            Spacer()
            control().accessibilityLabel(title)
        }
    }

    private func modelRow(_ name: String, descriptor: String, size: String,
                          state: ModelManager.DownloadState,
                          recommended: Bool,
                          download: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(name).font(Theme.Fonts.mono()).foregroundStyle(Theme.textPrimary)
                    if recommended {
                        Text("Recommended")
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(Theme.accent)
                    }
                }
                Text(descriptor).font(Theme.Fonts.caption).foregroundStyle(Theme.textSecondary)
            }
            .layoutPriority(1)
            Spacer()
            switch state {
            case .ready:
                Label("Ready", systemImage: "checkmark.circle.fill")
                    .font(Theme.Fonts.caption).foregroundStyle(Theme.accent)
            case .notDownloaded:
                HStack(spacing: 8) {
                    Text(size).font(Theme.Fonts.mono(10.5)).foregroundStyle(Theme.textTertiary)
                    Button("Download", action: download).buttonStyle(BorderedActionButtonStyle())
                }
            case .downloading(let p):
                HStack(spacing: 8) {
                    ProgressView(value: p).frame(width: 90)
                    Text("\(Int(p * 100))%").font(Theme.Fonts.mono(10.5)).foregroundStyle(Theme.textSecondary)
                }
            case .failed(let msg):
                VStack(alignment: .trailing, spacing: 4) {
                    Text(msg).font(Theme.Fonts.caption).foregroundStyle(Theme.failure).lineLimit(1)
                        .help(msg)
                    Button("Retry", action: download).buttonStyle(BorderedActionButtonStyle())
                }
            }
        }
    }

    private func permissionRow(_ title: String, granted: Bool, grantedHint: String,
                               pendingHint: String, request: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.Fonts.body).foregroundStyle(Theme.textPrimary)
                Text(granted ? grantedHint : pendingHint)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(granted ? Theme.accent : Theme.textTertiary)
            }
            Spacer()
            if !granted {
                Button("Grant", action: request)
                    .buttonStyle(BorderedActionButtonStyle(emphasized: true))
            }
        }
    }

    private func bind<T>(_ keyPath: ReferenceWritableKeyPath<SettingsStore, T>) -> Binding<T> {
        Binding(get: { model.settings[keyPath: keyPath] }, set: { model.settings[keyPath: keyPath] = $0 })
    }

    /// Persists the choice, then re-applies the live trigger so combo↔single-key
    /// swaps take effect immediately (no relaunch).
    private var triggerKindBinding: Binding<TriggerKind> {
        Binding(
            get: { model.settings.triggerKind },
            set: { newValue in
                model.settings.triggerKind = newValue
                AppComposition.applyTrigger(for: model)
            }
        )
    }

    /// Persists the chosen key, then re-arms the monitor on the new device mask.
    private var singleKeyChoiceBinding: Binding<SingleKeyChoice> {
        Binding(
            get: { model.settings.singleKeyChoice },
            set: { newValue in
                model.settings.singleKeyChoice = newValue
                AppComposition.applyTrigger(for: model)
            }
        )
    }
}

/// Miniature screen showing where the HUD pill sits for a preset.
struct HUDPositionPreview: View {
    let position: HUDPosition
    let selected: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: alignment) {
                RoundedRectangle(cornerRadius: 6).fill(Theme.ink2)
                    .overlay(RoundedRectangle(cornerRadius: 6)
                        .stroke(selected ? Theme.accent : Theme.hairlineStrong, lineWidth: selected ? 1.5 : 1))
                Capsule().fill(selected ? Theme.accent : Theme.waveInactive)
                    .frame(width: 26, height: 7)
                    .padding(6)
            }
            .frame(width: 92, height: 58)
            Text(position.label)
                .font(Theme.Fonts.caption)
                .foregroundStyle(selected ? Theme.textPrimary : Theme.textTertiary)
        }
        .contentShape(Rectangle())
        .animation(reduceMotion ? nil : Theme.easeFast, value: selected)
    }

    private var alignment: Alignment {
        switch position {
        case .bottomCenter: .bottom
        case .topRight: .topTrailing
        case .nearNotch: .top
        }
    }
}

struct HotkeyRecorder: NSViewRepresentable {
    @Binding var isRecording: Bool
    var onCapture: (HotkeySpec) -> Void

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ view: NSView, context: Context) {
        if isRecording && context.coordinator.monitor == nil {
            context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                let carbonMods = Self.carbonFlags(from: event.modifierFlags)
                if carbonMods != 0 || event.keyCode == 53 {
                    if event.keyCode != 53 {
                        onCapture(HotkeySpec(keyCode: UInt32(event.keyCode), carbonModifiers: carbonMods))
                    }
                    Task { @MainActor in
                        isRecording = false
                    }
                    context.coordinator.stop()
                    return nil
                }
                return event
            }
        } else if !isRecording {
            context.coordinator.stop()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    final class Coordinator {
        var monitor: Any?

        func stop() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    static func carbonFlags(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= 0x0100 }
        if flags.contains(.shift) { carbon |= 0x0200 }
        if flags.contains(.option) { carbon |= 0x0800 }
        if flags.contains(.control) { carbon |= 0x1000 }
        return carbon
    }
}
