import AppKit
import Carbon.HIToolbox

// MARK: - Text Inserter

/// Pastes transcribed text into whichever app was frontmost when recording began.
///
/// Strategy:
///   1. Write text to the system clipboard.
///   2. Re-activate the previously focused app.
///   3. Synthesise a Cmd+V key event so the text lands at the cursor.
///   4. Restore the original clipboard contents after a short delay.
final class TextInserter {

    // MARK: - Accessibility check

    /// Returns `true` when the app has been granted Accessibility permission.
    /// Passing `prompt: true` opens the System Settings permission sheet.
    func isAccessibilityGranted(prompt: Bool = false) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Main insertion

    /// Copies `text` to the clipboard and simulates Cmd+V in `targetApp`.
    /// - Parameters:
    ///   - text:      The string to insert.
    ///   - targetApp: The `NSRunningApplication` that should receive the paste.
    ///                Pass `nil` to send the event to whichever app is currently active.
    func insertText(_ text: String, into targetApp: NSRunningApplication?) {
        let pasteboard = NSPasteboard.general

        // Save current clipboard so we can restore it afterwards
        let savedItems = pasteboard.pasteboardItems?.compactMap { item -> (types: [NSPasteboard.PasteboardType], data: [NSPasteboard.PasteboardType: Data])? in
            let dataByType = item.types.reduce(into: [NSPasteboard.PasteboardType: Data]()) { dict, type in
                if let d = item.data(forType: type) { dict[type] = d }
            }
            return dataByType.isEmpty ? nil : (types: item.types, data: dataByType)
        }

        // Put our text on the clipboard
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Reactivate the target app, then send Cmd+V
        if let app = targetApp, app.bundleIdentifier != Bundle.main.bundleIdentifier {
            app.activate(options: .activateIgnoringOtherApps)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                self.simulatePaste()
                self.restoreClipboard(after: 0.5, savedItems: savedItems)
            }
        } else {
            simulatePaste()
            restoreClipboard(after: 0.5, savedItems: savedItems)
        }
    }

    // MARK: - Private helpers

    private func simulatePaste() {
        let source = CGEventSource(stateID: .hidSystemState)
        let vKey: CGKeyCode = 0x09  // 'v'

        let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        down?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)

        let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        up?.flags = .maskCommand
        up?.post(tap: .cghidEventTap)
    }

    private func restoreClipboard(
        after delay: TimeInterval,
        savedItems: [(types: [NSPasteboard.PasteboardType], data: [NSPasteboard.PasteboardType: Data])]?
    ) {
        guard let items = savedItems, !items.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            for saved in items {
                let item = NSPasteboardItem()
                for type in saved.types {
                    if let data = saved.data[type] {
                        item.setData(data, forType: type)
                    }
                }
                pasteboard.writeObjects([item])
            }
        }
    }
}
