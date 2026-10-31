// Tests for deciding what Quit on a row does, before any dialog: refuse (Pulso itself, or
// a core process), ask the app to quit as ⌘Q does, or signal a lone process. And the words
// shown when a signal fails, ported from the 0.1 app.
import Darwin
import Testing
@testable import PulsoCore

private let chrome = "/Applications/Google Chrome.app"

private let groups: [AppGroup] = [
    AppGroup(name: "Google Chrome", bundlePath: chrome, pids: [760, 761], mainPid: 760, memoryBytes: 700, cpu: 0),
    AppGroup(name: "Google Chrome · Raycast", bundlePath: chrome, pids: [800, 801], mainPid: 800,
             memoryBytes: 150, cpu: 0, startedBy: "Raycast"),
    AppGroup(name: "Safari", bundlePath: "/Applications/Safari.app", pids: [11], mainPid: nil, memoryBytes: 50, cpu: 0),
    AppGroup(name: "node", bundlePath: nil, pids: [50], mainPid: 50, memoryBytes: 280, cpu: 0),
    AppGroup(name: "Pulso", bundlePath: "/Applications/Pulso.app", pids: [900, 901], mainPid: 900, memoryBytes: 9, cpu: 0),
]

@Suite("quitPlan")
struct QuitPlanTests {
    @Test("asks the row's own copy of an app to quit, through its main process")
    func app() {
        #expect(quitPlan(rowPid: 760, groups: groups, ownPid: 900) == .app(pid: 760))
        #expect(quitPlan(rowPid: 800, groups: groups, ownPid: 900) == .app(pid: 800))
    }

    @Test("finds the copy from any of its processes")
    func anyPid() {
        #expect(quitPlan(rowPid: 801, groups: groups, ownPid: 900) == .app(pid: 800))
    }

    @Test("signals a process outside any app")
    func signal() {
        #expect(quitPlan(rowPid: 50, groups: groups, ownPid: 900) == .signal(pid: 50))
    }

    @Test("signals a pid it cannot find in any group, as a lone process")
    func unknown() {
        #expect(quitPlan(rowPid: 4242, groups: groups, ownPid: 900) == .signal(pid: 4242))
    }

    @Test("refuses Pulso itself, through any of its pids")
    func refusesSelf() {
        #expect(quitPlan(rowPid: 901, groups: groups, ownPid: 900)
            == .refuse("PID 901 is this app or a core system process you cannot quit."))
    }

    @Test("refuses pid 0 and 1")
    func refusesCore() {
        #expect(quitPlan(rowPid: 1, groups: groups, ownPid: 900)
            == .refuse("PID 1 is this app or a core system process you cannot quit."))
        #expect(quitPlan(rowPid: 0, groups: groups, ownPid: 900)
            == .refuse("PID 0 is this app or a core system process you cannot quit."))
    }

    @Test("refuses an app whose main process is not running, saying why")
    func noMain() {
        #expect(quitPlan(rowPid: 11, groups: groups, ownPid: 900)
            == .refuse("Safari has no main process running to ask. Quit it from its own window."))
    }
}

@Suite("signalFailure")
struct SignalFailureTests {
    @Test("says why a signal failed, in plain words")
    func messages() {
        #expect(signalFailure(EPERM) == "You do not have permission to quit it; it belongs to another user or the system.")
        #expect(signalFailure(ESRCH) == "It has already exited.")
        #expect(signalFailure(EINVAL) == "It could not be quit: error \(EINVAL).")
    }
}
