import AppKit
import SwiftUI

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var menuBarController: MenuBarController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide from the Dock — this is a pure menu-bar app
        NSApp.setActivationPolicy(.accessory)

        menuBarController = MenuBarController()

        // Prompt for Accessibility permission on first run so auto-paste works
        // (non-blocking — user can dismiss and still use manual copy)
        promptAccessibilityIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        menuBarController.cleanup()
    }

    // MARK: - Accessibility prompt

    private func promptAccessibilityIfNeeded() {
        guard !AXIsProcessTrusted() else { return }

        // Show a friendly one-time alert explaining why we need it
        let defaults = UserDefaults.standard
        let key = "hasShownAccessibilityPrompt"
        guard !defaults.bool(forKey: key) else { return }
        defaults.set(true, forKey: key)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let alert             = NSAlert()
            alert.messageText     = "Enable Auto-Paste"
            alert.informativeText =
                "WhisperBar can automatically paste transcribed text into any app.\n\n" +
                "To enable this, grant Accessibility permission when prompted — or do it later " +
                "via Settings → Permissions."
            alert.addButton(withTitle: "Grant Permission")
            alert.addButton(withTitle: "Skip for Now")

            if alert.runModal() == .alertFirstButtonReturn {
                let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
                AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
            }
        }
    }
}
