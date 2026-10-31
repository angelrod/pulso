// Pulso: a row's Quit, wired to dialogs and to the system as the task asks.
import Cocoa
import Darwin
import PulsoCore
import PulsoUI

extension AppDelegate {

    // Every menu action, wired as one case each so a later case fails to build.
    func handle(_ action: PanelAction) {
        switch action {
        case .refresh: collect()
        case .activityMonitor:
            let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                if let error { NSLog("Pulso: opening Activity Monitor failed: \(error)") }
            }
        case .help:
            let help = helpDialog()
            showAlert(help.message, help.detail, show: true)
        case .about:
            NSApp.activate(ignoringOtherApps: true)
            NSApp.orderFrontStandardAboutPanel(options: [
                .credits: NSAttributedString(string: "Memory and CPU at a glance, in the menu bar."),
            ])
        case .checkForUpdates:
            // Pulso has no Dock icon, so activate first to bring Sparkle's window to the front.
            NSApp.activate(ignoringOtherApps: true)
            updaterController.checkForUpdates(nil)
        case .quitPulso: NSApp.terminate(nil)
        case .quitRow(let pid): _ = quitRow(pid, confirm: true)
        case .front(let pid): _ = bringToFront(pid)
        // Toggle the login item, record the choice, then refresh so the ✓ updates.
        case .toggleLogin:
            if applyLoginStep(loginStepOnToggle(currentLoginStatus())) {
                UserDefaults.standard.set(true, forKey: loginDecidedKey)
            }
            collect()
        }
    }

    // Plan the quit, confirm it, then ask the app or signal the process, then refresh.
    func quitRow(_ pid: Int32, confirm: Bool) -> String {
        let groups = groupByApp(lastSnapshot?.processes ?? [])
        // The row's group is the one holding the pid, else invent it as a lone process.
        let row = groups.first(where: { $0.pids.contains(pid) })
            ?? AppGroup(name: "\(pid)", bundlePath: nil, pids: [pid], mainPid: pid, memoryBytes: 0, cpu: 0)
        var result = ""
        switch quitPlan(rowPid: pid, groups: groups, ownPid: getpid()) {
        case .refuse(let message):
            showAlert("Cannot quit", message, show: confirm)
            result = "refused: \(message)"
        case .app(let mainPid):
            if confirm, !confirmQuit(row) { result = "cancelled" }
            else if let app = NSRunningApplication(processIdentifier: mainPid) {
                if !app.terminate() {
                    showAlert(row.name, "\(row.name) did not accept the request to quit.", show: confirm)
                    result = "declined"
                } else { result = "asked app \(mainPid) to quit" }
            } else {
                showAlert("It has already exited.", "", show: confirm)
                result = "gone"
            }
        case .signal(let p):
            if confirm, !confirmQuit(row) { result = "cancelled" }
            else if kill(p, SIGTERM) != 0 {
                // Read errno once; the message is built from it, twice.
                let code = errno
                showAlert("Signal failed", signalFailure(code), show: confirm)
                result = "failed: \(signalFailure(code))"
            } else { result = "sent SIGTERM to \(p)" }
        }
        // Refresh the list after any outcome, so it no longer shows the quit one.
        collect()
        return result
    }

    // A row's click: bring what the row represents to the front, or report it has none.
    func bringToFront(_ pid: Int32) -> String {
        let groups = groupByApp(lastSnapshot?.processes ?? [])
        let row = groups.first(where: { $0.pids.contains(pid) })
            ?? AppGroup(name: "\(pid)", bundlePath: nil, pids: [pid], mainPid: pid, memoryBytes: 0, cpu: 0)
        switch frontPlan(row, host: frontHost(for: row)) {
        case .app(let p), .host(let p, _):
            guard let app = NSRunningApplication(processIdentifier: p) else { NSLog("Pulso: \(p) no longer runs"); return "gone" }
            if !app.activate(options: [.activateAllWindows]) { NSLog("Pulso: \(p) refused to activate"); return "refused" }
            return "activated \(p)"
        case .none:
            NSLog("Pulso: no window for \(pid)")
            return "none"
        }
    }

    // Confirm a quit: raise the app, ask, and put Cancel first so Return cancels.
    func confirmQuit(_ group: AppGroup) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let prompt = quitPrompt(group)
        let alert = NSAlert()
        alert.messageText = prompt.message
        alert.informativeText = prompt.detail
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: prompt.button)
        return alert.runModal() == .alertSecondButtonReturn
    }

    // Log every alert, and only show one when asked, so a debug run stays silent.
    func showAlert(_ title: String, _ text: String, show: Bool) {
        NSLog("Pulso: \(title): \(text)")
        guard show else { return }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.runModal()
    }

    // Fire once from PULSO_DEBUG_QUIT, then exit when the exit flag is set.
    func runDebugQuitIfAsked() {
        guard !didDebugQuit else { return }
        didDebugQuit = true
        guard let raw = ProcessInfo.processInfo.environment["PULSO_DEBUG_QUIT"] else { return }
        guard let pid = Int32(raw) else { NSLog("Pulso: PULSO_DEBUG_QUIT is not a pid: \(raw)"); if debugExit { exit(1) }; return }
        let result = quitRow(pid, confirm: false)
        print("PULSO_DEBUG_QUIT {\"pid\":\(pid),\"result\":\(Self.json(result))}")
        if debugExit { exit(0) }
    }

    // Fire once from PULSO_DEBUG_FRONT, then exit when the exit flag is set.
    func runDebugFrontIfAsked() {
        guard !didDebugFront else { return }
        didDebugFront = true
        guard let raw = ProcessInfo.processInfo.environment["PULSO_DEBUG_FRONT"] else { return }
        guard let pid = Int32(raw) else { NSLog("Pulso: PULSO_DEBUG_FRONT is not a pid: \(raw)"); if debugExit { exit(1) }; return }
        // Capture values that must not be read inside the deferred block.
        let debugExit = self.debugExit
        let result = Self.json(bringToFront(pid))
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            // frontmostApplication is read after the wait, so it reflects the app brought up.
            let front = Self.json(NSWorkspace.shared.frontmostApplication?.localizedName ?? "")
            print("PULSO_DEBUG_FRONT {\"pid\":\(pid),\"result\":\(result),\"front\":\(front)}")
            if debugExit { exit(0) }
        }
    }

    // Fire once from PULSO_DEBUG_UPDATER, then exit when the exit flag is set.
    func runDebugUpdateIfCalled() {
        guard !didDebugUpdate else { return }
        didDebugUpdate = true
        guard ProcessInfo.processInfo.environment["PULSO_DEBUG_UPDATER"] == "1" else { return }
        let updater = updaterController.updater
        let feed = updater.feedURL?.absoluteString ?? ""
        print("PULSO_DEBUG_UPDATER {\"feed\":\(Self.json(feed)),\"automatic\":\(updater.automaticallyChecksForUpdates),\"canCheck\":\(updater.canCheckForUpdates)}")
        if debugExit { exit(0) }
    }

    // Wrap a string as a JSON string literal, escaping the backslash and quote.
    private static func json(_ s: String) -> String {
        let escaped = s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

// The app a lone process runs in: the one macOS holds responsible, when that is an app.
func frontHost(for group: AppGroup) -> FrontHost? {
    guard group.bundlePath == nil, let pid = group.mainPid,
          let responsible = responsiblePid(pid), responsible != pid,
          let app = NSRunningApplication(processIdentifier: responsible),
          let name = app.localizedName else { return nil }
    return FrontHost(pid: responsible, name: name)
}
