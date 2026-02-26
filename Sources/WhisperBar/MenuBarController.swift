import AppKit
import SwiftUI
import Combine

// MARK: - Menu Bar Controller

/// Central coordinator: owns every service object and drives the recording flow.
final class MenuBarController: NSObject {

    // MARK: - Services
    let appState    = AppState()
    let recorder    = AudioRecorder()
    let transcriber = WhisperTranscriber()
    let inserter    = TextInserter()
    var hotkeyManager: HotkeyManager?

    // MARK: - Waveform data  (shared between FloatingRecordingWindow and the level callback)
    let levelData = AudioLevelData()

    // MARK: - UI
    private var statusItem:       NSStatusItem!
    private var popover:          NSPopover!
    private var floatingWindow:   FloatingRecordingWindow?

    // MARK: - Recording context
    /// App that was in front when the hotkey was pressed — text gets pasted back here.
    private var previousApp: NSRunningApplication?

    // MARK: - Settings observer
    private var settingsCancellables = Set<AnyCancellable>()

    // MARK: - Menu-bar icon pulse timer
    private var pulseTimer: Timer?
    private var pulseState  = false

    // MARK: - Init

    override init() {
        super.init()
        setupStatusItem()
        setupPopover()
        setupHotkeys()
        observeSettings()
        loadModelInBackground()
    }

    // MARK: - Status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let btn = statusItem.button else { return }
        btn.image             = icon(for: .idle)
        btn.image?.isTemplate = true
        btn.action            = #selector(handleBarClick)
        btn.target            = self
    }

    @objc private func handleBarClick(_ sender: NSStatusBarButton) {
        if let event = NSApp.currentEvent, event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover(sender)
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(
            withTitle: "Toggle Recording",
            action:    #selector(toggleRecording),
            keyEquivalent: ""
        ).target = self
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Quit WhisperBar",
            action:    #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    // MARK: - Popover

    private func setupPopover() {
        popover          = NSPopover()
        popover.behavior = .transient
        popover.animates = true

        let content = PopoverView(
            appState:          appState,
            onToggleRecording: { [weak self] in self?.toggleRecording() },
            onOpenSettings:    { },
            onQuit:            { NSApp.terminate(nil) }
        )
        popover.contentViewController = SilentKeyHostingController(rootView: content)
        popover.contentSize           = NSSize(width: 310, height: 340)
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        if popover.isShown {
            popover.performClose(sender)
        } else if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: - Hotkey setup

    private func setupHotkeys() {
        let hm = HotkeyManager()

        // Toggle mode
        hm.onToggleRecording = { [weak self] in self?.toggleRecording() }

        // Push-to-talk mode
        hm.onStartRecording  = { [weak self] in
            guard let self, self.appState.status == .idle else { return }
            self.startRecording()
        }
        hm.onStopRecording   = { [weak self] in
            guard let self, self.appState.status == .recording else { return }
            self.stopRecording()
        }

        hm.configure(
            mode:        appState.recordingMode,
            toggleCombo: appState.toggleHotkey,
            pttCombo:    appState.pushToTalkHotkey
        )

        hotkeyManager = hm
    }

    /// Re-register hotkeys when the user changes settings.
    private func observeSettings() {
        Publishers.MergeMany(
            appState.$recordingMode.map     { _ in () }.eraseToAnyPublisher(),
            appState.$toggleHotkey.map      { _ in () }.eraseToAnyPublisher(),
            appState.$pushToTalkHotkey.map  { _ in () }.eraseToAnyPublisher()
        )
        .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
        .sink { [weak self] in
            guard let self else { return }
            self.hotkeyManager?.reconfigure(
                mode:        self.appState.recordingMode,
                toggleCombo: self.appState.toggleHotkey,
                pttCombo:    self.appState.pushToTalkHotkey
            )
        }
        .store(in: &settingsCancellables)
    }

    // MARK: - Recording toggle

    @objc func toggleRecording() {
        switch appState.status {
        case .idle:      startRecording()
        case .recording: stopRecording()
        case .error:
            appState.status = .idle
            updateIcon()
        default:
            break
        }
    }

    // MARK: - Start recording

    private func startRecording() {
        guard appState.isModelLoaded else {
            showAlert(title: "Model not ready",
                      message: "WhisperBar is still loading the Whisper model. Please wait a moment.")
            return
        }

        previousApp = NSWorkspace.shared.frontmostApplication

        recorder.requestPermission { [weak self] granted in
            guard let self else { return }
            if granted {
                do {
                    try self.recorder.startRecording()
                    self.appState.status = .recording
                    self.updateIcon()
                    self.startPulse()

                    // Wire level callbacks → waveform data
                    self.levelData.reset()
                    self.recorder.onLevel = { [weak self] level in
                        self?.levelData.push(level)
                    }

                    // Show floating widget
                    if self.appState.showFloatingWidget {
                        self.showFloatingWindow()
                    }

                    // Escape key cancels recording
                    self.hotkeyManager?.startEscapeMonitor { [weak self] in
                        self?.cancelRecording()
                    }
                } catch {
                    self.appState.status = .error("Mic error: \(error.localizedDescription)")
                    self.updateIcon()
                }
            } else {
                self.showMicPermissionAlert()
            }
        }
    }

    // MARK: - Stop recording

    private func stopRecording() {
        hotkeyManager?.stopEscapeMonitor()
        stopPulse()
        recorder.onLevel = nil

        guard let audioURL = recorder.stopRecording() else {
            appState.status = .idle
            updateIcon()
            hideFloatingWindow()
            return
        }

        appState.status = .transcribing
        updateIcon()

        let capturedApp = previousApp

        Task {
            do {
                let text = try await transcriber.transcribe(audioURL: audioURL)
                await MainActor.run {
                    self.appState.lastTranscription = text
                    self.appState.status            = .idle
                    self.updateIcon()
                    self.hideFloatingWindow()
                    if self.appState.autoPaste {
                        self.inserter.insertText(text, into: capturedApp)
                    }
                }
            } catch TranscriptionError.noSpeechDetected {
                await MainActor.run {
                    self.appState.status = .idle
                    self.updateIcon()
                    self.hideFloatingWindow()
                }
            } catch {
                await MainActor.run {
                    self.appState.status = .error(error.localizedDescription)
                    self.updateIcon()
                    self.hideFloatingWindow()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                        if case .error = self.appState.status {
                            self.appState.status = .idle
                            self.updateIcon()
                        }
                    }
                }
            }
        }
    }

    /// Aborts an in-progress recording without transcribing.
    private func cancelRecording() {
        hotkeyManager?.stopEscapeMonitor()
        stopPulse()
        recorder.onLevel = nil
        _ = recorder.stopRecording()
        levelData.reset()
        appState.status = .idle
        updateIcon()
        hideFloatingWindow()
    }

    // MARK: - Floating waveform window

    private func showFloatingWindow() {
        if floatingWindow == nil {
            let win = FloatingRecordingWindow(appState: appState, levelData: levelData)
            win.onCancel = { [weak self] in self?.cancelRecording() }
            floatingWindow = win
        }
        floatingWindow?.showAnimated()
    }

    private func hideFloatingWindow() {
        floatingWindow?.hideAnimated { [weak self] in
            self?.floatingWindow = nil
        }
    }

    // MARK: - Model loading

    private func loadModelInBackground() {
        appState.status = .downloadingModel
        updateIcon()

        Task {
            do {
                try await transcriber.loadModel(
                    appState.selectedModel,
                    onProgress: { [weak self] p in
                        DispatchQueue.main.async { self?.appState.modelDownloadProgress = p }
                    }
                )
                await MainActor.run {
                    self.appState.isModelLoaded = true
                    self.appState.status        = .idle
                    self.updateIcon()
                }
            } catch {
                await MainActor.run {
                    self.appState.status = .error("Failed to load model: \(error.localizedDescription)")
                    self.updateIcon()
                }
            }
        }
    }

    // MARK: - Menu-bar icon

    private func updateIcon() {
        DispatchQueue.main.async {
            let img = self.icon(for: self.appState.status)
            self.statusItem.button?.image             = img
            self.statusItem.button?.image?.isTemplate = true
        }
    }

    private func icon(for status: AppStatus) -> NSImage? {
        let name: String
        switch status {
        case .idle:             name = "mic"
        case .recording:        name = "mic.fill"
        case .transcribing:     name = "waveform"
        case .downloadingModel: name = "arrow.down.circle"
        case .error:            name = "exclamationmark.circle"
        }
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)
    }

    private func startPulse() {
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, case .recording = self.appState.status else { return }
            self.pulseState.toggle()
            let name = self.pulseState ? "mic.fill" : "mic"
            self.statusItem.button?.image             = NSImage(systemSymbolName: name, accessibilityDescription: nil)
            self.statusItem.button?.image?.isTemplate = true
        }
    }

    private func stopPulse() {
        pulseTimer?.invalidate()
        pulseTimer = nil
    }

    // MARK: - Alerts

    private func showMicPermissionAlert() {
        let alert = NSAlert()
        alert.messageText     = "Microphone Access Required"
        alert.informativeText = "Open System Settings → Privacy & Security → Microphone and enable WhisperBar."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(
                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
            )
        }
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText     = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // MARK: - Cleanup

    func cleanup() {
        stopPulse()
        recorder.cleanup()
        hotkeyManager = nil
        floatingWindow?.orderOut(nil)
    }
}

// MARK: - Silent Key Hosting Controller

/// NSHostingController subclass that silently consumes all key events so the
/// popover never triggers the system alert beep when keys are pressed.
final class SilentKeyHostingController<T: View>: NSHostingController<T> {
    override func keyDown(with event: NSEvent) { /* swallow */ }
    override func keyUp(with event: NSEvent) { /* swallow */ }
    override func performKeyEquivalent(with event: NSEvent) -> Bool { true }
}
