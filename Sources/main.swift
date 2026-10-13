import AppKit

// The top level of main.swift runs on the main thread; say so to the compiler.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()                 // NSApplication only keeps a weak reference; `run()` keeps this alive
    app.delegate = delegate
    app.setActivationPolicy(.accessory)          // menu bar only: no Dock icon, no app menu
    app.run()
}
