import Foundation
import Combine

// MARK: - App Status

enum AppStatus: Equatable {
    case idle
    case recording
    case transcribing
    case downloadingModel
    case error(String)

    static func == (lhs: AppStatus, rhs: AppStatus) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle),
             (.recording, .recording),
             (.transcribing, .transcribing),
             (.downloadingModel, .downloadingModel):
            return true
        case (.error(let a), .error(let b)):
            return a == b
        default:
            return false
        }
    }
}

// MARK: - App State

final class AppState: ObservableObject {

    // ── Runtime state ──────────────────────────────────────────────────────
    @Published var status:                AppStatus = .idle
    @Published var lastTranscription:     String    = ""
    @Published var modelDownloadProgress: Double    = 0
    @Published var isModelLoaded:         Bool      = false

    // ── Persisted user settings ────────────────────────────────────────────

    @Published var selectedModel: String {
        didSet { UserDefaults.standard.set(selectedModel, forKey: "selectedModel") }
    }

    @Published var autoPaste: Bool {
        didSet { UserDefaults.standard.set(autoPaste, forKey: "autoPaste") }
    }

    @Published var launchAtStartup: Bool {
        didSet { UserDefaults.standard.set(launchAtStartup, forKey: "launchAtStartup") }
    }

    /// Whether the floating waveform widget is shown while recording.
    @Published var showFloatingWidget: Bool {
        didSet { UserDefaults.standard.set(showFloatingWidget, forKey: "showFloatingWidget") }
    }

    /// Toggle: press once → start, press again → stop.
    /// Push-to-Talk: hold key → recording, release → stop.
    @Published var recordingMode: RecordingMode {
        didSet {
            if let data = try? JSONEncoder().encode(recordingMode) {
                UserDefaults.standard.set(data, forKey: "recordingMode")
            }
        }
    }

    /// Hotkey for Toggle mode (registered via Carbon – no Accessibility needed).
    @Published var toggleHotkey: KeyCombo {
        didSet { UserDefaults.standard.set(toggleHotkey, forKey: "toggleHotkey") }
    }

    /// Hotkey for Push-to-Talk mode (uses NSEvent global monitor).
    @Published var pushToTalkHotkey: KeyCombo {
        didSet { UserDefaults.standard.set(pushToTalkHotkey, forKey: "pushToTalkHotkey") }
    }

    // MARK: - Init

    init() {
        self.selectedModel = UserDefaults.standard.string(forKey: "selectedModel") ?? "base"

        if UserDefaults.standard.object(forKey: "autoPaste") == nil {
            self.autoPaste = true
        } else {
            self.autoPaste = UserDefaults.standard.bool(forKey: "autoPaste")
        }

        self.launchAtStartup = UserDefaults.standard.bool(forKey: "launchAtStartup")

        if UserDefaults.standard.object(forKey: "showFloatingWidget") == nil {
            self.showFloatingWidget = true
        } else {
            self.showFloatingWidget = UserDefaults.standard.bool(forKey: "showFloatingWidget")
        }

        if let data = UserDefaults.standard.data(forKey: "recordingMode"),
           let mode = try? JSONDecoder().decode(RecordingMode.self, from: data) {
            self.recordingMode = mode
        } else {
            self.recordingMode = .toggle
        }

        self.toggleHotkey     = UserDefaults.standard.keyCombo(forKey: "toggleHotkey")     ?? .defaultToggle
        self.pushToTalkHotkey = UserDefaults.standard.keyCombo(forKey: "pushToTalkHotkey") ?? .defaultPushToTalk
    }
}

// MARK: - Available Whisper Models

struct WhisperModel: Identifiable, Hashable {
    let id: String
    let displayName: String
    let sizeDescription: String
    let note: String

    var fullDescription: String { "\(displayName) (\(sizeDescription)) – \(note)" }
}

extension AppState {
    static let availableModels: [WhisperModel] = [
        WhisperModel(id: "tiny",   displayName: "Tiny",   sizeDescription: "~39 MB",  note: "Fastest, less accurate"),
        WhisperModel(id: "base",   displayName: "Base",   sizeDescription: "~74 MB",  note: "Recommended – good balance"),
        WhisperModel(id: "small",  displayName: "Small",  sizeDescription: "~244 MB", note: "Better accuracy"),
        WhisperModel(id: "medium", displayName: "Medium", sizeDescription: "~769 MB", note: "High accuracy, slower"),
    ]
}
