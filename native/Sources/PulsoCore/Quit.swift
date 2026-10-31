// What Quit on a row does before any dialog: refuse, ask the app to quit, or signal a lone process.
import Darwin

// The plan for Quit on one row, in the order the checks must run.
public enum QuitPlan: Equatable, Sendable {
    case refuse(String)      // the message to show; nothing is quit
    case app(pid: Int32)     // ask this app process to quit, as ⌘Q does
    case signal(pid: Int32)  // send SIGTERM to this lone process
}

// What Quit on a row does: first matching rule wins, otherwise signal the lone process.
public func quitPlan(rowPid: Int32, groups: [AppGroup], ownPid: Int32) -> QuitPlan {
    guard rowPid >= 2 else {
        return .refuse("PID \(rowPid) is this app or a core system process you cannot quit.")
    }
    guard let group = groups.first(where: { $0.pids.contains(rowPid) }) else {
        return .signal(pid: rowPid)
    }
    guard !group.pids.contains(ownPid) else {
        return .refuse("PID \(rowPid) is this app or a core system process you cannot quit.")
    }
    guard let bundlePath = group.bundlePath else {
        return .signal(pid: rowPid)
    }
    guard let mainPid = group.mainPid else {
        return .refuse("\(group.name) has no main process running to ask. Quit it from its own window.")
    }
    return .app(pid: mainPid)
}

// Why a SIGTERM failed, in the words the menu once showed.
public func signalFailure(_ code: Int32) -> String {
    guard code != EPERM, code != ESRCH else {
        return code == EPERM ? "You do not have permission to quit it; it belongs to another user or the system." : "It has already exited."
    }
    return "It could not be quit: error \(code)."
}
