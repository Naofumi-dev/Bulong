import SwiftUI

struct HUDView: View {
    let state: DictationState
    let level: Float
    let partial: String
    let language: String
    var onCancel: () -> Void
    var onDragChanged: (CGSize) -> Void = { _ in }
    var onDragEnded: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isFailed: Bool {
        if case .failed = state { true } else { false }
    }

    private var accent: Color {
        isFailed ? Theme.failure : Theme.accent
    }

    var body: some View {
        HStack(spacing: 12) {
            brandMark
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer(minLength: 6)
            WaveformBars(state: state, level: level, accent: accent)
                .frame(width: 50)
            badge("ON DEVICE")
            badge(language.uppercased())
            if case .transcribing = state {
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Cancel")
            }
        }
        .padding(.horizontal, 12)
        .frame(width: 392, height: 74)
        .background(background)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.34), radius: 22, y: 12)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { onDragChanged($0.translation) }
                .onEnded { _ in onDragEnded() }
        )
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: state)
    }

    private var brandMark: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(0.045))
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color.white.opacity(0.11), lineWidth: 1)
            Image("MenuIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
        }
        .frame(width: 31, height: 31)
    }

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 10/255, green: 18/255, blue: 18/255),
                    Color(red: 7/255, green: 9/255, blue: 11/255),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [accent.opacity(0.22), .clear],
                center: .topLeading,
                startRadius: 10,
                endRadius: 250
            )
        }
    }

    private var border: Color {
        isFailed
            ? Theme.failure.opacity(0.55)
            : Color(red: 60/255, green: 104/255, blue: 96/255).opacity(0.95)
    }

    private var title: String {
        switch state {
        case .recording:
            "Listening"
        case .transcribing:
            "Transcribing"
        case .inserting:
            "Inserting"
        case .failed:
            "Needs attention"
        case .idle:
            "LocalTalk"
        }
    }

    private var detail: String {
        if case .failed(let message) = state {
            return message
        }
        if !partial.isEmpty {
            return partial
        }
        switch state {
        case .recording:
            return "Voice stays on this Mac"
        case .transcribing:
            return "Finalizing locally"
        case .inserting:
            return "Sending text to your app"
        case .idle:
            return "Private dictation"
        case .failed:
            return ""
        }
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(isFailed ? Theme.failure : Theme.accentText)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.045))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(accent.opacity(0.42), lineWidth: 1)
                    )
            )
    }
}

struct WaveformBars: View {
    let state: DictationState
    let level: Float
    let accent: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let heights: [CGFloat] = [0.34, 0.62, 1.0, 0.72, 0.48, 0.82, 0.38]

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.08)) { context in
            HStack(alignment: .center, spacing: 4) {
                ForEach(0..<heights.count, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(fill(for: index))
                        .frame(width: 4, height: barHeight(index, date: context.date))
                }
            }
        }
    }

    private func fill(for index: Int) -> Color {
        index >= 2 && index <= 4 ? accent : Color(red: 86/255, green: 102/255, blue: 116/255)
    }

    private func barHeight(_ index: Int, date: Date) -> CGFloat {
        let base = heights[index] * 24
        switch state {
        case .recording:
            return max(4, base * CGFloat(0.28 + 0.82 * level))
        case .transcribing, .inserting:
            guard !reduceMotion else { return max(4, base * 0.45) }
            let phase = date.timeIntervalSinceReferenceDate * 4.5 + Double(index) * 0.58
            return max(4, base * CGFloat(0.42 + 0.18 * sin(phase)))
        case .failed:
            return 4
        case .idle:
            return max(4, base * 0.3)
        }
    }
}
