import Foundation
import AppKit
import Carbon.HIToolbox

// MARK: - Hotkey Manager

/// Manages two global hotkeys:
///
/// **Toggle mode** (Carbon `RegisterEventHotKey`)
///   - Works without Accessibility permission.
///   - Press once → start recording; press again → stop.
///
/// **Push-to-Talk mode** (NSEvent global monitor)
///   - Requires Accessibility permission (already requested for paste).
///   - Hold key → record; release → stop.
///
/// Call `configure(appState:)` once after init, then call `reconfigure()`
/// whenever the user changes a hotkey or recording mode in Settings.
final class HotkeyManager {

    // MARK: - Callbacks

    var onToggleRecording: (() -> Void)?   // start/stop toggle
    var onStartRecording:  (() -> Void)?   // push-to-talk: key down
    var onStopRecording:   (() -> Void)?   // push-to-talk: key up

    // MARK: - Private state

    // Carbon toggle hotkey
    private var hotKeyRef:        EventHotKeyRef?
    private var eventHandlerRef:  EventHandlerRef?

    // NSEvent push-to-talk monitors
    private var pttDownMonitor: Any?
    private var pttUpMonitor:   Any?

    // We keep a static weak back-reference so the Carbon callback can reach us
    private static weak var current: HotkeyManager?

    // Escape-cancel monitor (active while recording)
    private var escMonitor: Any?

    // MARK: - Current configuration

    private var currentMode:         RecordingMode = .toggle
    private var currentToggleCombo:  KeyCombo      = .defaultToggle
    private var currentPttCombo:     KeyCombo      = .defaultPushToTalk

    // MARK: - Init / deinit

    init() {
        HotkeyManager.current = self
    }

    deinit {
        unregisterAll()
    }

    // MARK: - Public API

    /// Apply the current settings from AppState and register hotkeys.
    func configure(mode: RecordingMode, toggleCombo: KeyCombo, pttCombo: KeyCombo) {
        currentMode        = mode
        currentToggleCombo = toggleCombo
        currentPttCombo    = pttCombo
        unregisterAll()
        registerForCurrentMode()
    }

    /// Re-read settings and re-register.  Call after user changes a setting.
    func reconfigure(mode: RecordingMode, toggleCombo: KeyCombo, pttCombo: KeyCombo) {
        configure(mode: mode, toggleCombo: toggleCombo, pttCombo: pttCombo)
    }

    /// Start monitoring Escape so the user can cancel a recording.
    func startEscapeMonitor(onEscape: @escaping () -> Void) {
        stopEscapeMonitor()
        escMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                DispatchQueue.main.async { onEscape() }
            }
        }
    }

    func stopEscapeMonitor() {
        if let m = escMonitor { NSEvent.removeMonitor(m); escMonitor = nil }
    }

    // MARK: - Toggle mode (Carbon)

    private func registerToggleHotkey(_ combo: KeyCombo) {
        unregisterCarbonHotkey()

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind:  UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, _, _) -> OSStatus in
                DispatchQueue.main.async {
                    HotkeyManager.current?.onToggleRecording?()
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )

        let hotKeyID = EventHotKeyID(signature: fourCharCode("WBHK"), id: 1)

        RegisterEventHotKey(
            UInt32(combo.keyCode),
            combo.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    private func unregisterCarbonHotkey() {
        if let ref = hotKeyRef        { UnregisterEventHotKey(ref);  hotKeyRef        = nil }
        if let ref = eventHandlerRef  { RemoveEventHandler(ref);      eventHandlerRef  = nil }
    }

    // MARK: - Push-to-Talk mode (NSEvent)

    private func registerPushToTalk(_ combo: KeyCombo) {
        removePushToTalkMonitors()

        pttDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return }
            if combo.matches(event: event) {
                DispatchQueue.main.async { self.onStartRecording?() }
            }
        }

        pttUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyUp) { [weak self] event in
            guard let self else { return }
            // Release fires when the primary key (not modifier) is lifted
            if Int(event.keyCode) == combo.keyCode {
                DispatchQueue.main.async { self.onStopRecording?() }
            }
        }
    }

    private func removePushToTalkMonitors() {
        if let m = pttDownMonitor { NSEvent.removeMonitor(m); pttDownMonitor = nil }
        if let m = pttUpMonitor   { NSEvent.removeMonitor(m); pttUpMonitor   = nil }
    }

    // MARK: - Helpers

    private func registerForCurrentMode() {
        switch currentMode {
        case .toggle:
            registerToggleHotkey(currentToggleCombo)
        case .pushToTalk:
            registerPushToTalk(currentPttCombo)
        }
    }

    private func unregisterAll() {
        unregisterCarbonHotkey()
        removePushToTalkMonitors()
        stopEscapeMonitor()
    }
}

// MARK: - FourCharCode helper

private func fourCharCode(_ string: String) -> FourCharCode {
    precondition(string.count == 4)
    return string.utf8.reduce(0) { ($0 << 8) | FourCharCode($1) }
}
