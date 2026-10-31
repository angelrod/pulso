// Pulso: the menu bar app entry point — create the collector, the app, run it.
import Cocoa
import PulsoCore

// The debug flags, read from the environment before the app starts.
let debug = ProcessInfo.processInfo.environment["PULSO_DEBUG"] == "1"
let debugPanel = ProcessInfo.processInfo.environment["PULSO_DEBUG_PANEL"] == "1"
let debugExit = ProcessInfo.processInfo.environment["PULSO_DEBUG_EXIT"] == "1"

// The one collector for the app; the app cannot run without it, so a launch failure is fatal.
var collector: Collector
do {
    collector = try Collector()
} catch {
    FileHandle.standardError.write(Data("Pulso: \(error)\n".utf8))
    exit(1)
}

let app = NSApplication.shared
let delegate = AppDelegate(collector: collector, debug: debug, debugPanel: debugPanel, debugExit: debugExit)
app.delegate = delegate
app.setActivationPolicy(.accessory)
// Start before run(): app.run() blocks, so the three-second timer lives on its run loop.
delegate.start()
app.run()
