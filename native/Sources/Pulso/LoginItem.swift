// Open at Login: the LaunchAgent file is the state, plus first-launch default and debug hook.
import Foundation
import PulsoCore

// The UserDefaults key that records that Pulso applied its first-launch default.
let loginDecidedKey = "openAtLoginDecided"

// The login item's state read from the LaunchAgent file, via the core enum.
func currentLoginStatus() -> LoginItemStatus {
    let path = loginAgentPath(home: NSHomeDirectory())
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
        return .notRegistered
    }
    // No parseable ProgramArguments reads as off; an unparseable file is logged.
    guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
        NSLog("Pulso: login agent at \(path) does not parse")
        return .notRegistered
    }
    guard let first = plist["ProgramArguments"] as? [String],
          let agentExecutable = first.first else {
        return .notRegistered
    }
    return loginAgentStatus(agentExecutable: agentExecutable, executable: Bundle.main.executablePath ?? "")
}

// The login item's status as a plain word, for the debug line.
func loginStatusString(_ status: LoginItemStatus) -> String {
    switch status {
    case .enabled: return "enabled"
    case .requiresApproval: return "requiresApproval"
    case .notRegistered: return "notRegistered"
    case .notFound: return "notFound"
    }
}

// Apply one step; log and report a failure so the default stays undecided.
func applyLoginStep(_ step: LoginStep) -> Bool {
    switch step {
    case .none:
        return true
    case .register:
        // Ensure the per-user directory before writing the agent that runs at login.
        let agents = URL(fileURLWithPath: NSHomeDirectory() + "/Library/LaunchAgents")
        do {
            try FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
        } catch {
            NSLog("Pulso: cannot create \(agents.path): \(error)")
            return false
        }
        let executable = Bundle.main.executablePath
        guard let executable else {
            NSLog("Pulso: no executable path to register at login")
            return false
        }
        guard let data = loginAgentPlist(executable: executable) else {
            NSLog("Pulso: cannot build the launch agent plist")
            return false
        }
        // nil means serialization failed and there is nothing to write.
        do {
            try data.write(to: URL(fileURLWithPath: loginAgentPath(home: NSHomeDirectory())))
        } catch {
            NSLog("Pulso: cannot write login agent: \(error)")
            return false
        }
        return true
    case .unregister:
        let path = loginAgentPath(home: NSHomeDirectory())
        // No launchctl stop: it would kill this running Pulso. An absent file counts as success.
        guard FileManager.default.fileExists(atPath: path) else { return true }
        do {
            try FileManager.default.removeItem(atPath: path)
        } catch {
            NSLog("Pulso: cannot remove login agent: \(error)")
            return false
        }
        return true
    }
}

extension AppDelegate {

    // The first-launch default: turn on login once, from /Applications only, else skip it.
    func applyLoginDefault() {
        guard Bundle.main.bundlePath.hasPrefix("/Applications/") else {
            NSLog("Pulso: login default skipped outside /Applications")
            return
        }
        let decided = UserDefaults.standard.bool(forKey: loginDecidedKey)
        // On register and it worked, record the decision; a failure leaves it false to retry.
        let step = loginStepAtLaunch(decided: decided)
        if step == .register, applyLoginStep(step) {
            UserDefaults.standard.set(true, forKey: loginDecidedKey)
        }
    }

    // Fire once from PULSO_DEBUG_LOGIN, then exit when the exit flag is set.
    func runDebugLoginIfCalled() {
        guard !didDebugLogin else { return }
        didDebugLogin = true
        guard ProcessInfo.processInfo.environment["PULSO_DEBUG_LOGIN"] == "1" else { return }
        let status = loginStatusString(currentLoginStatus())
        let decided = UserDefaults.standard.bool(forKey: loginDecidedKey)
        // Escape the bundle path so the printed line stays valid JSON.
        let bundle = Bundle.main.bundlePath
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        print("PULSO_DEBUG_LOGIN {\"status\":\"\(status)\",\"decided\":\(decided),\"bundle\":\"\(bundle)\"}")
        if debugExit { exit(0) }
    }
}
