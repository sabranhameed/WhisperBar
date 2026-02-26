import SwiftUI
import AppKit

// MARK: - Main Popover View

struct PopoverView: View {

    @ObservedObject var appState: AppState

    /// Callbacks wired up by MenuBarController
    let onToggleRecording: () -> Void
    let onOpenSettings:    () -> Void
    let onQuit:            () -> Void

    @State private var showSettings = false
    @State private var copiedFeedback = false

    var body: some View {
        Group {
            if showSettings {
                SettingsView(appState: appState) {
                    showSettings = false
                }
            } else {
                mainView
            }
        }
        .frame(width: 310)
    }

    // MARK: - Main view

    private var mainView: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            recordSection
            Divider()
            transcriptionSection
            Divider()
            footerBar
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform.badge.mic")
                .foregroundStyle(.tint)
                .font(.system(size: 16, weight: .semibold))
            Text("WhisperBar")
                .font(.headline)
            Spacer()
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gear")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Record section

    private var recordSection: some View {
        VStack(spacing: 10) {
            // Big record / stop button
            Button(action: onToggleRecording) {
                HStack(spacing: 10) {
                    Image(systemName: recordButtonIcon)
                        .font(.system(size: 17, weight: .semibold))
                    Text(recordButtonLabel)
                        .font(.system(size: 14, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(recordButtonColor)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
            .disabled(!canRecord)

            // Download progress
            if case .downloadingModel = appState.status {
                VStack(spacing: 4) {
                    ProgressView(value: max(0.05, appState.modelDownloadProgress))
                        .tint(.accentColor)
                    Text("Downloading \(appState.selectedModel) model…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Hotkey hint
            if appState.status == .idle || appState.status == .recording {
                Text("Global hotkey: ⌘ ⇧ Space")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
    }

    // MARK: - Transcription section

    @ViewBuilder
    private var transcriptionSection: some View {
        if appState.status == .transcribing {
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(width: 16, height: 16)
                Text("Transcribing…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(16)
        } else if appState.lastTranscription.isEmpty {
            Text("Your transcription will appear here")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(16)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("Last transcription")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ScrollView {
                    Text(appState.lastTranscription)
                        .font(.subheadline)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 80)

                HStack {
                    Spacer()
                    Button(copiedFeedback ? "Copied!" : "Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(appState.lastTranscription, forType: .string)
                        withAnimation {
                            copiedFeedback = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            copiedFeedback = false
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(14)
        }
    }

    // MARK: - Footer

    private var footerBar: some View {
        HStack {
            // Error message or auto-paste indicator
            if case .error(let msg) = appState.status {
                Label(msg, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            } else {
                HStack(spacing: 4) {
                    Image(systemName: appState.autoPaste ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(appState.autoPaste ? .green : .secondary)
                        .font(.caption)
                    Text("Auto-paste")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Quit") { onQuit() }
                .font(.caption)
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Computed helpers

    private var recordButtonIcon: String {
        switch appState.status {
        case .recording:        return "stop.circle.fill"
        case .transcribing:     return "waveform"
        case .downloadingModel: return "arrow.down.circle"
        default:                return "mic.circle.fill"
        }
    }

    private var recordButtonLabel: String {
        switch appState.status {
        case .idle:             return "Start Recording"
        case .recording:        return "Stop Recording"
        case .transcribing:     return "Transcribing…"
        case .downloadingModel: return "Loading Model…"
        case .error:            return "Try Again"
        }
    }

    private var recordButtonColor: Color {
        switch appState.status {
        case .recording:    return .red
        case .transcribing: return .orange
        case .error:        return .gray
        default:            return .accentColor
        }
    }

    private var canRecord: Bool {
        switch appState.status {
        case .transcribing, .downloadingModel: return false
        default: return true
        }
    }
}
