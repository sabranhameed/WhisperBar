import AppKit
import SwiftUI

// MARK: - Silent Hosting View

/// NSHostingView subclass that silently discards key events so the floating
/// window never triggers the system alert beep.
private final class SilentHostingView<T: View>: NSHostingView<T> {
    override var acceptsFirstResponder: Bool { false }
    override func keyDown(with event: NSEvent) { /* swallow */ }
    override func keyUp(with event: NSEvent) { /* swallow */ }
    override func performKeyEquivalent(with event: NSEvent) -> Bool { true }
}

// MARK: - Floating Recording Window

/// A borderless, always-on-top NSPanel that hosts the waveform visualiser.
/// The window appears when recording begins and dismisses after transcription.
final class FloatingRecordingWindow: NSPanel {

    private var hostingView: SilentHostingView<FloatingRecordingView>?

    // Called when the user clicks the × button inside the window
    var onCancel: (() -> Void)?

    init(appState: AppState, levelData: AudioLevelData) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 120),
            styleMask:   [.borderless, .nonactivatingPanel],
            backing:     .buffered,
            defer:       false
        )

        isOpaque                = false
        backgroundColor         = .clear
        level                   = .floating
        collectionBehavior      = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = true
        hasShadow               = true

        let rootView = FloatingRecordingView(
            appState:  appState,
            levelData: levelData,
            onCancel:  { [weak self] in self?.onCancel?() }
        )
        let hv = SilentHostingView(rootView: rootView)
        hv.frame = NSRect(x: 0, y: 0, width: 300, height: 120)
        contentView = hv
        hostingView = hv
    }

    override var canBecomeKey:  Bool { false }
    override var canBecomeMain: Bool { false }

    // MARK: - Positioning

    /// Place the window centred horizontally, 15 % up from the bottom of the main screen.
    func positionOnScreen() {
        guard let screen = NSScreen.main else { return }
        let x = screen.visibleFrame.midX - frame.width  / 2
        let y = screen.visibleFrame.minY + screen.visibleFrame.height * 0.12
        setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: - Show / Hide with animation

    func showAnimated() {
        positionOnScreen()
        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            animator().alphaValue = 1
        }
    }

    func hideAnimated(completion: (() -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.3
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.orderOut(nil)
            completion?()
        })
    }
}

// MARK: - Floating Recording SwiftUI View

struct FloatingRecordingView: View {

    @ObservedObject var appState:  AppState
    @ObservedObject var levelData: AudioLevelData
    let onCancel: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // ── Glass card ──────────────────────────────────────
            RoundedRectangle(cornerRadius: 22)
                .fill(.black.opacity(0.78))
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(borderColour, lineWidth: 1)
                )

            // ── Content ─────────────────────────────────────────
            VStack(spacing: 10) {

                // Status row
                HStack(spacing: 8) {
                    if appState.status == .recording {
                        PulsingDot(color: .red)
                    } else if appState.status == .transcribing {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 12, height: 12)
                    }
                    Text(statusText)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                }

                // Waveform bars
                WaveformBarsView(
                    levels:         recentLevels,
                    isTranscribing: appState.status == .transcribing
                )

                // Hint text
                Text(hintText)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            // ── Cancel (×) button ────────────────────────────────
            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.45))
            }
            .buttonStyle(.plain)
            .padding(10)
            .help("Cancel recording")
        }
        .frame(width: 300, height: 120)
        .shadow(color: .black.opacity(0.4), radius: 24, x: 0, y: 8)
    }

    // MARK: - Computed

    private var recentLevels: [Float] {
        let count = 30
        let src   = levelData.levels
        if src.count >= count { return Array(src.suffix(count)) }
        return Array(repeating: 0, count: count - src.count) + src
    }

    private var statusText: String {
        switch appState.status {
        case .recording:    return "Recording…"
        case .transcribing: return "Transcribing…"
        default:            return "Ready"
        }
    }

    private var hintText: String {
        switch appState.status {
        case .recording:    return "Press hotkey again or × to stop"
        case .transcribing: return "Please wait…"
        default:            return ""
        }
    }

    private var borderColour: Color {
        switch appState.status {
        case .recording:    return .red.opacity(0.5)
        case .transcribing: return .orange.opacity(0.4)
        default:            return .white.opacity(0.15)
        }
    }
}

// MARK: - Waveform Bars

struct WaveformBarsView: View {

    let levels:         [Float]
    var isTranscribing: Bool = false

    private let barWidth:  CGFloat = 3.5
    private let barSpacing: CGFloat = 2.5
    private let maxHeight: CGFloat = 42
    private let minHeight: CGFloat = 3

    var body: some View {
        HStack(alignment: .center, spacing: barSpacing) {
            ForEach(Array(levels.enumerated()), id: \.offset) { idx, level in
                Capsule()
                    .fill(barGradient(for: idx))
                    .frame(width: barWidth,
                           height: isTranscribing
                                ? idleHeight(idx: idx)
                                : barHeight(for: level))
                    .animation(
                        .spring(response: 0.12, dampingFraction: 0.55),
                        value: level
                    )
            }
        }
        .frame(height: maxHeight + 6)
    }

    private func barHeight(for level: Float) -> CGFloat {
        minHeight + CGFloat(level) * (maxHeight - minHeight)
    }

    /// Gentle idle sine-wave when transcribing (no audio input)
    private func idleHeight(idx: Int) -> CGFloat {
        let phase = Double(idx) / Double(levels.count) * .pi * 2
        let sine  = (sin(phase + .pi / 2) + 1) / 2   // 0…1
        return minHeight + CGFloat(sine) * 14
    }

    private func barGradient(for index: Int) -> LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: [
                Color(red: 0.35, green: 0.85, blue: 1.00),
                Color(red: 0.20, green: 0.50, blue: 1.00),
            ]),
            startPoint: .top,
            endPoint:   .bottom
        )
    }
}

// MARK: - Pulsing Dot

struct PulsingDot: View {
    let color: Color
    @State private var pulsing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.3))
                .frame(width: 16, height: 16)
                .scaleEffect(pulsing ? 1.6 : 1)
                .opacity(pulsing ? 0 : 0.6)
                .animation(.easeOut(duration: 1).repeatForever(autoreverses: false), value: pulsing)

            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
        }
        .onAppear { pulsing = true }
    }
}
