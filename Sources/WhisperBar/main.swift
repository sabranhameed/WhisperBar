import AppKit

// MARK: - Entry point

// We use main.swift instead of @main so that the SPM executable target
// boots cleanly without conflicting with AppKit's own initialisation.

let app      = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
