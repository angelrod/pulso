// Pulso: the app delegate and status item, building the bar from every Collector update.
import Cocoa
import Sparkle
import PulsoCore
import PulsoUI

// How often the bar re-reads the Collector: three seconds, matching the spec.
let refreshInterval: TimeInterval = 3

// The app delegate, a subclass so it can hold the status item it must outlive.
final class AppDelegate: NSResponder, NSApplicationDelegate {
    private var collector: Collector
    private let debug: Bool
    private let debugPanel: Bool
    let debugExit: Bool
    private var statusItem: NSStatusItem
    private(set) var lastSnapshot: Snapshot?
    private var didDebugPrint = false
    private var didDebugPanelPrint = false
    var didDebugLogin = false
    var didDebugQuit = false
    var didDebugFront = false
    var didDebugUpdate = false
    let updaterController: SPUStandardUpdaterController
    private var panel: PanelWindow

    init(collector: Collector, debug: Bool, debugPanel: Bool, debugExit: Bool) {
        self.collector = collector
        self.debug = debug
        self.debugPanel = debugPanel
        self.debugExit = debugExit
        // The updater is stored so it outlives the app; created before super.init().
        self.updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        // A variableLength item kept in a stored property so it never leaves the bar.
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.panel = PanelWindow(statusItem: statusItem) { action in
            NSLog("Pulso: action \(action)")
        }
        super.init()
        panel.onAction = { [weak self] action in self?.handle(action) }
        setStatusItemView()
    }

    // NSResponder is subclassed so this class never has to be decoded from a nib.
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // The timer runs on the main loop; hop to the main actor to touch the UI.
    func start() {
        // The first-launch login default, before the first reading refreshes the bar.
        applyLoginDefault()
        collect()
        RunLoop.current.add(
            Timer(timeInterval: refreshInterval, repeats: true) { [weak self] _ in
                let self_ = self
                DispatchQueue.main.async { self_?.collect() }
            },
            forMode: .common)
    }

    // One refresh: collect, log a failure but keep the last good view, then rebuild the bar.
    func collect() {
        let snapshot: Snapshot
        do {
            snapshot = try collector.collect()
        } catch {
            NSLog("Pulso: collect failed: \(error)")
            return
        }
        lastSnapshot = snapshot
        setStatusItemView()
        if debug, !didDebugPrint {
            didDebugPrint = true
            printDebug(lastSnapshot!)
        }
        // The debug open is deferred so the button's window exists when it runs.
        if debugPanel, !didDebugPanelPrint {
            didDebugPanelPrint = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.panel.debugPanel(exitNow: self?.debugExit ?? false)
            }
        }
        // Fire PULSO_DEBUG_QUIT once, after the first good collect, so the bar exists.
        runDebugQuitIfAsked()
        // Fire PULSO_DEBUG_FRONT once, right after, so the snapshot exists to plan against.
        runDebugFrontIfAsked()
        // Fire PULSO_DEBUG_LOGIN once, after the first good collect, so the app is running.
        runDebugLoginIfCalled()
        // Fire PULSO_DEBUG_UPDATER once, after, so the updater exists to inspect.
        runDebugUpdateIfCalled()
    }

    // Build the button from the latest snapshot's image, title and tooltip.
    private func setStatusItemView() {
        guard let snapshot = lastSnapshot else { return }
        let icon = trayIcon(snapshot)
        let image = NSImage(named: icon.rawValue)
        guard let image else {
            NSLog("Pulso: missing tray icon \(icon.rawValue)")
            return
        }
        // isTemplate is an image property; only the plain icon is a template.
        image.isTemplate = icon == .template
        let button = statusItem.button
        guard let button else {
            NSLog("Pulso: status item has no button")
            return
        }
        button.image = image
        button.imagePosition = .imageLeading
        button.title = trayTitle(snapshot)
        button.toolTip = trayTooltip(snapshot)
        // The click toggles the panel; statusItem.menu is left nil by design.
        button.target = panel
        button.action = #selector(PanelWindow.toggle)
        // The panel shows the same snapshot; the debug hook opens the panel once.
        panel.update(snapshot)
    }
}

// The debug hook: print one line from the button, then exit if asked.
extension AppDelegate {
    private func printDebug(_ snapshot: Snapshot) {
        let button = statusItem.button
        guard let button else {
            print("PULSO_DEBUG {\"error\":\"no status item button\"}")
            if debugExit { exit(0) }
            return
        }
        // The template flag is read from the button's image, since isTemplate lives on the image.
        let template = button.image?.isTemplate ?? false
        let tooltip = button.toolTip ?? ""
        print("PULSO_DEBUG {\"title\":\(json(button.title)),\"icon\":\(json(trayIcon(snapshot).rawValue)),\"template\":\(template),\"tooltip\":\(json(tooltip))}")
        if debugExit { exit(0) }
    }

    // Wrap a string as a JSON string literal, escaping the backslash and quote.
    private func json(_ s: String) -> String {
        let escaped = s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
