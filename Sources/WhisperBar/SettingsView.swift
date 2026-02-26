import SwiftUI
import ServiceManagement
import AppKit
import AVFoundation
import Carbon.HIToolbox

// MARK: - Settings View

struct SettingsView: View {

    @ObservedObject var appState: AppState
    let onDone: () -> Void

    @State private var accessibilityGranted    = false
    @State private var showModelChangeWarning  = false

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ─────────────────────────────────────────────────────
            HStack {
                Button(action: onDone) {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
                Spacer()
                Text("Settings")
                    .font(.headline)
                Spacer()
                Text("Back").opacity(0)  // balancer
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // ── Whisper Model ──────────────────────────────────────
                    settingsSection("Whisper Model") {
                        VStack(alignment: .leading, spacing: 6) {
                            Picker("", selection: $appState.selectedModel) {
                                ForEach(AppState.availableModels) { model in
                                    Text(model.fullDescription).tag(model.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()

                            Text("Downloaded once, runs fully offline after that.")
                                .font(.caption).foregroundStyle(.secondary)

                            if showModelChangeWarning {
                                Label("Restart the app to use the new model.", systemImage: "info.circle")
                                    .font(.caption).foregroundStyle(.orange)
                            }
                        }
                    }

                    // ── Recording Mode ─────────────────────────────────────
                    settingsSection("Recording Mode") {
                        VStack(alignment: .leading, spacing: 8) {
                            Picker("", selection: $appState.recordingMode) {
                                ForEach(RecordingMode.allCases, id: \.self) { mode in
                                    Text(mode.displayName).tag(mode)
                                }
                            }
                            .pickerStyle(.radioGroup)
                            .labelsHidden()

                            if appState.recordingMode == .pushToTalk {
                                Label("Requires Accessibility permission.", systemImage: "hand.raised")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }

                    // ── Hotkeys ────────────────────────────────────────────
                    settingsSection("Keyboard Shortcuts") {
                        VStack(spacing: 10) {
                            if appState.recordingMode == .toggle || true {
                                HotkeyRow(
                                    label:    "Toggle recording",
                                    subtitle: "Press once to start, press again to stop",
                                    combo:    $appState.toggleHotkey
                                )
                            }
                            Divider()
                            HotkeyRow(
                                label:    "Push-to-talk",
                                subtitle: "Hold to record, release to transcribe",
                                combo:    $appState.pushToTalkHotkey
                            )
                        }
                    }

                    // ── Output ─────────────────────────────────────────────
                    settingsSection("Output") {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("Auto-paste into active app", isOn: $appState.autoPaste)
                            Text("Types transcription where your cursor was before recording.")
                                .font(.caption).foregroundStyle(.secondary)
                            Divider()
                            Toggle("Show floating waveform widget", isOn: $appState.showFloatingWidget)
                            Text("Displays an animated microphone widget on screen while recording.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }

                    // ── Permissions ────────────────────────────────────────
                    settingsSection("Permissions") {
                        VStack(alignment: .leading, spacing: 10) {
                            permissionRow(
                                title:    "Accessibility",
                                subtitle: "Required for auto-paste and push-to-talk.",
                                granted:  accessibilityGranted
                            ) {
                                let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
                                let opts = [key: true] as CFDictionary
                                _ = AXIsProcessTrustedWithOptions(opts)
                                refreshAccessibility()
                            }

                            permissionRow(
                                title:    "Microphone",
                                subtitle: "Required to record your voice.",
                                granted:  AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
                            ) {
                                NSWorkspace.shared.open(
                                    URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
                                )
                            }
                        }
                    }

                    // ── Startup ────────────────────────────────────────────
                    settingsSection("Startup") {
                        Toggle("Launch at login", isOn: $appState.launchAtStartup)
                            .onChange(of: appState.launchAtStartup) { newValue in
                                toggleLaunchAtLogin(newValue)
                            }
                    }
                }
                .padding(14)
            }
        }
        .onAppear { refreshAccessibility() }
        .onChange(of: appState.selectedModel) { _ in showModelChangeWarning = true }
    }

    // MARK: - Section builder

    @ViewBuilder
    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
        }
    }

    // MARK: - Permission row

    @ViewBuilder
    private func permissionRow(
        title: String, subtitle: String, granted: Bool,
        onGrant: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(granted ? .green : .red)
                .font(.system(size: 16))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !granted {
                Button("Grant") { onGrant() }
                    .buttonStyle(.bordered).controlSize(.small)
            }
        }
    }

    // MARK: - Helpers

    private func refreshAccessibility() {
        accessibilityGranted = AXIsProcessTrusted()
    }

    private func toggleLaunchAtLogin(_ enable: Bool) {
        if #available(macOS 13, *) {
            try? enable ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
        }
    }
}

// MARK: - Hotkey Row

struct HotkeyRow: View {
    let label:    String
    let subtitle: String
    @Binding var combo: KeyCombo

    @State private var isRecording = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(.subheadline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                KeyComboButton(combo: $combo, isRecording: $isRecording)
            }
        }
    }
}

// MARK: - Key Combo Button

struct KeyComboButton: View {
    @Binding var combo:       KeyCombo
    @Binding var isRecording: Bool

    var body: some View {
        ZStack {
            Button(isRecording ? "⌨ Press keys…" : combo.displayString) {
                isRecording = true
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .foregroundColor(isRecording ? .orange : .primary)

            // Invisible capture overlay — becomes first responder when isRecording
            KeyCaptureView(isRecording: $isRecording) { captured in
                if let c = captured { combo = c }
                isRecording = false
            }
            .frame(width: 1, height: 1)
            .opacity(0)
            .allowsHitTesting(false)
        }
    }
}

// MARK: - Key Capture View (NSViewRepresentable)

/// An invisible NSView that becomes first responder while `isRecording` is true
/// and delivers the captured KeyCombo (or nil for Escape-cancel) via `onCapture`.
struct KeyCaptureView: NSViewRepresentable {

    @Binding var isRecording: Bool
    var onCapture: (KeyCombo?) -> Void

    func makeNSView(context: Context) -> KeyCaptureNSView {
        let v = KeyCaptureNSView()
        v.onCapture = { [self] combo in
            DispatchQueue.main.async { self.onCapture(combo) }
        }
        return v
    }

    func updateNSView(_ nsView: KeyCaptureNSView, context: Context) {
        if isRecording {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        } else {
            DispatchQueue.main.async {
                if nsView.window?.firstResponder === nsView {
                    nsView.window?.makeFirstResponder(nsView.window)
                }
            }
        }
    }
}

final class KeyCaptureNSView: NSView {

    var onCapture: ((KeyCombo?) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Escape = cancel
        if event.keyCode == UInt16(kVK_Escape) {
            onCapture?(nil)
            return
        }

        // Must have at least one modifier, OR be a Function key (F1–F12)
        let isFunctionKey = event.keyCode >= 96 && event.keyCode <= 122
        if mods.isEmpty && !isFunctionKey { return }

        let combo = KeyCombo(
            keyCode:   Int(event.keyCode),
            modifiers: Int(mods.rawValue)
        )
        onCapture?(combo)
    }

    override func flagsChanged(with event: NSEvent) {
        // Don't consume modifier-only presses
        super.flagsChanged(with: event)
    }

    /// Silence any selector-based commands (copy, paste, etc.) that would
    /// otherwise bubble up and trigger the system alert beep.
    override func doCommand(by selector: Selector) { /* swallow */ }
}
